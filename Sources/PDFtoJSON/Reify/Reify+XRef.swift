import Foundation
import Spanker
import Hitch

func isXRef(_ info: JsonElement) -> Bool {
    return info[hitch: "Type"] == "XRef"
}

private func readField(_ ptr: inout UnsafePointer<UInt8>,
                       _ size: Int) -> Int {
    var value: Int = 0
    for _ in 0..<size {
        value = value << 8 | Int(ptr[0])
        ptr += 1
    }
    return value
}

/// Decode the entries of a cross-reference stream into the context's xref table.
/// Entries already present (from newer sections) are kept.
func parseXrefStream(_ context: PDFContext,
                     info: JsonElement,
                     data: Hitch) -> Bool {
    guard let widths = info[element: "W"],
          let typeSize = widths[int: 0],
          let field2Size = widths[int: 1],
          let field3Size = widths[int: 2],
          typeSize >= 0, field2Size >= 0, field3Size >= 0,
          typeSize <= 8, field2Size <= 8, field3Size <= 8 else { return false }
    let entrySize = typeSize + field2Size + field3Size
    guard entrySize > 0, let start = data.raw() else { return false }
    let end = start + data.count

    // /Index [first count first count ...], defaulting to [0 Size]
    var subsections: [(Int, Int)] = []
    if let index = info[element: "Index"], index.type == .array {
        var values: [Int] = []
        for value in index.iterValues {
            values.append(value.intValue ?? 0)
        }
        var idx = 0
        while idx + 1 < values.count {
            subsections.append((values[idx], values[idx + 1]))
            idx += 2
        }
    } else {
        subsections.append((0, info[int: "Size"] ?? 0))
    }

    var ptr = start
    for (first, count) in subsections {
        for index in 0..<max(0, count) {
            guard ptr + entrySize <= end else { return true }
            // a zero-width type field means type 1
            let type = typeSize == 0 ? 1 : readField(&ptr, typeSize)
            let field2 = readField(&ptr, field2Size)
            let field3 = readField(&ptr, field3Size)

            let id = first + index
            guard context.xref[id] == nil else { continue }
            switch type {
            case 0:
                context.xref[id] = .free
            case 1:
                context.xref[id] = .offset(field2, generation: field3)
            case 2:
                context.xref[id] = .compressed(stream: field2, index: field3)
            default:
                // unknown types are treated as null references
                break
            }
        }
    }
    return true
}
