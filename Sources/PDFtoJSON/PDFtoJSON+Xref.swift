import Foundation
import Spanker
import Hitch

// MARK: - Loading the cross-reference chain

/// Load every xref section reachable from `startxref`, newest first.
/// Entries already present are never overwritten, so the newest revision of each object wins.
/// Returns false if no usable table was found (the caller then rebuilds by scanning).
func loadXref(_ context: PDFContext) -> Bool {
    guard let startxref = findStartxref(context) else {
        context.warn("startxref not found")
        return false
    }

    // Offsets are normally relative to %PDF; some writers make them relative to the
    // start of the buffer instead. Use whichever one points at an xref section.
    if looksLikeXrefSection(context, offset: startxref) == false,
       context.bufferStart != context.start {
        let alternate = context.start - context.bufferStart
        let saved = context.start
        context.start = context.bufferStart
        if looksLikeXrefSection(context, offset: startxref) == false {
            context.start = saved
        } else {
            context.warn("xref offsets are relative to the file start, not %PDF (\(alternate) bytes earlier)")
        }
    }

    var visited = Set<Int>()
    var next: Int? = startxref
    var loadedAny = false

    while let offset = next, visited.contains(offset) == false {
        visited.insert(offset)
        next = nil

        guard let section = loadXrefSection(context, offset: offset) else {
            context.warn("xref section at \(offset) is invalid")
            break
        }
        loadedAny = true
        mergeTrailer(context, section)

        // Hybrid files: the xref stream named by /XRefStm takes precedence over /Prev
        if let xrefStm = section[int: "XRefStm"], visited.contains(xrefStm) == false {
            visited.insert(xrefStm)
            if loadXrefSection(context, offset: xrefStm) == nil {
                context.warn("XRefStm section at \(xrefStm) is invalid")
            }
        }

        next = section[int: "Prev"]
    }

    return loadedAny
}

/// The newest trailer wins; older trailers only fill in keys it is missing.
private func mergeTrailer(_ context: PDFContext,
                          _ section: JsonElement) {
    guard let trailer = context.trailer else {
        context.trailer = section
        return
    }
    for key in ["Root", "Info", "Encrypt", "ID"] where trailer[element: key] == nil {
        if let value = section[element: key] {
            trailer.set(key: HalfHitch(string: key), value: value)
        }
    }
}

private func findStartxref(_ context: PDFContext) -> Int? {
    let all = HalfHitch(sourceObject: nil,
                        raw: context.bufferStart,
                        count: context.end - context.bufferStart,
                        from: 0,
                        to: context.end - context.bufferStart)
    guard let index = all.lastIndex(of: "startxref") else { return nil }
    var ptr = context.bufferStart + index + 9
    skipWhitespace(&ptr, context.bufferStart, context.end)
    return readInt(&ptr, context.end)
}

private func looksLikeXrefSection(_ context: PDFContext,
                                  offset: Int) -> Bool {
    guard var ptr = context.pointer(offset: offset) else { return false }
    skipWhitespace(&ptr, context.start, context.end)
    if ptr + 4 <= context.end, ptr[0] == .x, ptr[1] == .r, ptr[2] == .e, ptr[3] == .f {
        return true
    }
    let parts = peekParts(n: 3, ptr, context.end)
    return parts[2] == "obj" && parts[0].toInt() != nil
}

/// Load one section (classic table or xref stream); returns its trailer dictionary.
private func loadXrefSection(_ context: PDFContext,
                             offset: Int) -> JsonElement? {
    guard var ptr = context.pointer(offset: offset) else { return nil }
    skipWhitespace(&ptr, context.start, context.end)

    if ptr + 4 <= context.end, ptr[0] == .x, ptr[1] == .r, ptr[2] == .e, ptr[3] == .f {
        return loadXrefTable(context, &ptr)
    }
    return loadXrefStream(context, &ptr)
}

// MARK: - Classic xref tables

private func loadXrefTable(_ context: PDFContext,
                           _ ptr: inout UnsafePointer<UInt8>) -> JsonElement? {
    let end = context.end
    ptr += 4 // "xref"

    var firstSubsection = true
    while ptr < end {
        skipWhitespace(&ptr, context.start, end)
        if ptr + 7 <= end, ptr[0] == .t, ptr[1] == .r, ptr[2] == .a, ptr[3] == .i,
           ptr[4] == .l, ptr[5] == .e, ptr[6] == .r {
            ptr += 7
            skipWhitespace(&ptr, context.start, end)
            guard ptr + 1 < end, ptr[0] == .lessThan, ptr[1] == .lessThan,
                  let trailer = context.with(stringMode: .hex, {
                      getDictionary(context: context, id: -1, generation: -1, &ptr, context.start, end)
                  }) else { return nil }
            return trailer
        }

        // subsection header: "firstObject count"
        guard var first = readInt(&ptr, end) else { return nil }
        skipSpaces(&ptr, end)
        guard let count = readInt(&ptr, end) else { return nil }

        for index in 0..<count {
            skipWhitespace(&ptr, context.start, end)
            guard let offset = readInt(&ptr, end) else { return nil }
            skipSpaces(&ptr, end)
            guard let generation = readInt(&ptr, end) else { return nil }
            skipSpaces(&ptr, end)
            guard ptr < end else { return nil }
            let type = ptr[0]
            ptr += 1

            // Common writer bug: the table starts at 1 even though its first entry is object 0
            if firstSubsection, index == 0, first == 1, type == .f, offset == 0, generation == 65535 {
                first = 0
            }

            let id = first + index
            guard context.xref[id] == nil else { continue }
            if type == .n && offset > 0 {
                context.xref[id] = .offset(offset, generation: generation)
            } else {
                context.xref[id] = .free
            }
        }
        firstSubsection = false
    }
    return nil
}

private func skipSpaces(_ ptr: inout UnsafePointer<UInt8>,
                        _ end: UnsafePointer<UInt8>) {
    while ptr < end, ptr[0] == .space || ptr[0] == .tab {
        ptr += 1
    }
}

// MARK: - Cross-reference streams

private func loadXrefStream(_ context: PDFContext,
                            _ ptr: inout UnsafePointer<UInt8>) -> JsonElement? {
    guard let wrapper = context.with(stringMode: .hex, {
              getObject(context: context, id: -1, generation: -1, &ptr, context.start, context.end)
          }),
          let id = wrapper[int: "id"],
          let info = wrapper[element: "value"],
          info[hitch: "Type"] == "XRef",
          let data = streamData(context, id: id) else { return nil }

    // keep the stream object itself so it can be found later
    if context.objects[id] == nil {
        context.objects[id] = wrapper
    }

    guard parseXrefStream(context, info: info, data: data) else { return nil }
    return info
}
