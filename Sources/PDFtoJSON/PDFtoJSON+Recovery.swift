import Foundation
import Spanker
import Hitch

// Reconstruction of damaged files: when the xref table is missing, points to the wrong
// place, or does not lead to a catalog, find objects by scanning for "N G obj".

private func isDigit(_ c: UInt8) -> Bool {
    return c >= .zero && c <= .nine
}

/// Offsets of every "N G obj" header in the file (later definitions win, as in
/// incremental updates). Built once and cached.
func scanObjectOffsets(_ context: PDFContext) -> [Int: Int] {
    if let cached = context.scannedOffsets {
        return cached
    }

    var offsets: [Int: Int] = [:]
    let start = context.start
    let end = context.end

    var ptr = start
    while ptr + 3 <= end {
        guard ptr[0] == .o, ptr[1] == .b, ptr[2] == .j else {
            ptr += 1
            continue
        }
        // must be followed by a delimiter or end of data
        if ptr + 3 < end, ptr[3].isDelimiter() == false && ptr[3] != .percentSign {
            ptr += 3
            continue
        }

        // walk backwards: whitespace, generation digits, whitespace, object digits
        var back = ptr - 1
        var sawSpace = false
        while back >= start, back[0].isWhitspace() { back -= 1; sawSpace = true }
        guard sawSpace else { ptr += 3; continue }
        var digits = 0
        while back >= start, isDigit(back[0]) { back -= 1; digits += 1 }
        guard digits > 0 else { ptr += 3; continue }
        sawSpace = false
        while back >= start, back[0].isWhitspace() { back -= 1; sawSpace = true }
        guard sawSpace else { ptr += 3; continue }
        digits = 0
        while back >= start, isDigit(back[0]) { back -= 1; digits += 1 }
        guard digits > 0, digits < 11 else { ptr += 3; continue }
        // the object number must start a token
        guard back < start || back[0].isDelimiter() || back[0] == .percentSign else { ptr += 3; continue }

        var idPtr = back + 1
        if let id = readInt(&idPtr, ptr) {
            offsets[id] = (back + 1) - start
        }
        ptr += 3
    }

    context.scannedOffsets = offsets
    return offsets
}

/// Does `needle` occur in the first `window` bytes at `offset`?
private func headerContains(_ context: PDFContext,
                            offset: Int,
                            _ needle: HalfHitch,
                            window: Int = 512) -> Bool {
    guard let ptr = context.pointer(offset: offset) else { return false }
    let count = min(window, context.end - ptr)
    let header = HalfHitch(sourceObject: nil, raw: ptr, count: count, from: 0, to: count)
    return header.contains(needle)
}

/// Rebuild the xref table and trailer from a full scan of the file.
func recoverXref(_ context: PDFContext) {
    context.warn("rebuilding cross-reference table by scanning the file")

    let offsets = scanObjectOffsets(context)

    // Scanned objects replace whatever the (broken) table said
    var recovered: [Int: XrefEntry] = [:]
    for (id, offset) in offsets {
        recovered[id] = .offset(offset, generation: 0)
    }
    // objects whose old entries pointed into object streams are kept
    for (id, entry) in context.xref {
        if case .compressed = entry, recovered[id] == nil {
            recovered[id] = entry
        }
    }
    context.xref = recovered
    context.objects = [:]
    context.objectStreams = [:]

    // Objects inside object streams cannot be found by scanning; enumerate them
    for (id, offset) in offsets.sorted(by: { $0.key < $1.key }) where headerContains(context, offset: offset, "/ObjStm") {
        guard let objectStream = objectStream(context, id: id) else { continue }
        for (member, _) in objectStream.offsets where context.xref[member] == nil {
            context.xref[member] = .compressed(stream: id, index: 0)
        }
    }

    // Trailer: merge every "trailer" dictionary in file order (later ones win)
    let trailer = context.trailer ?? ^[:]
    let all = HalfHitch(sourceObject: nil,
                        raw: context.start,
                        count: context.end - context.start,
                        from: 0,
                        to: context.end - context.start)
    var searchFrom = 0
    while let index = all.firstIndex(of: "trailer", offset: searchFrom) {
        searchFrom = index + 7
        var ptr = context.start + index + 7
        skipWhitespace(&ptr, context.start, context.end)
        guard ptr + 1 < context.end, ptr[0] == .lessThan, ptr[1] == .lessThan,
              let dict = context.with(stringMode: .hex, {
                  getDictionary(context: context, id: -1, generation: -1, &ptr, context.start, context.end)
              }) else { continue }
        for (key, value) in dict.iterWalking {
            trailer.set(key: key, value: value)
        }
    }

    // Cross-reference stream dictionaries also act as trailers
    if trailer[element: "Root"] == nil {
        for (_, offset) in offsets.sorted(by: { $0.value < $1.value }) where headerContains(context, offset: offset, "/XRef") {
            var ptr = context.start + offset
            guard let wrapper = context.with(stringMode: .hex, {
                      getObject(context: context, id: -1, generation: -1, &ptr, context.start, context.end)
                  }),
                  let info = wrapper[element: "value"],
                  isXRef(info) else { continue }
            for key in ["Root", "Info", "Encrypt", "ID"] {
                if let value = info[element: key] {
                    trailer.set(key: HalfHitch(string: key), value: value)
                }
            }
        }
    }

    // Last resort: find the catalog itself
    if trailer[element: "Root"] == nil {
        for (id, offset) in offsets.sorted(by: { $0.key < $1.key }) where headerContains(context, offset: offset, "/Catalog") {
            if let catalog = resolve(context, id: id), catalog[hitch: "Type"] == "Catalog" {
                trailer.set(key: "Root", value: makeReference(id: id, generation: 0))
                break
            }
        }
    }

    trailer.remove(key: "Prev")
    trailer.remove(key: "XRefStm")
    context.trailer = trailer
}
