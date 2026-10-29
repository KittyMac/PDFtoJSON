import Foundation
import Spanker
import Hitch

/// Undecoded stream bytes, kept until somebody asks for the data.
struct RawStream {
    let data: HalfHitch
    let info: JsonElement
    let id: Int
    let generation: Int
}

private let endstreamKeyword: HalfHitch = "endstream"

private func isKeyword(_ ptr: UnsafePointer<UInt8>,
                       _ end: UnsafePointer<UInt8>,
                       _ keyword: HalfHitch) -> Bool {
    guard end - ptr >= keyword.count, let raw = keyword.raw() else { return false }
    return memcmp(ptr, raw, keyword.count) == 0
}

/// Is "endstream" the next token at ptr (after optional whitespace)?
private func endstreamFollows(_ ptr: UnsafePointer<UInt8>,
                              _ end: UnsafePointer<UInt8>) -> Bool {
    var ptr = ptr
    while ptr < end, ptr[0].isWhitspace() { ptr += 1 }
    return isKeyword(ptr, end, endstreamKeyword)
}

/// Position of the next "endstream" at or after ptr.
private func findEndstream(_ ptr: UnsafePointer<UInt8>,
                           _ end: UnsafePointer<UInt8>) -> UnsafePointer<UInt8>? {
    var ptr = ptr
    while ptr + endstreamKeyword.count <= end {
        if ptr[0] == .e, isKeyword(ptr, end, endstreamKeyword) {
            return ptr
        }
        ptr += 1
    }
    return nil
}

func getStream(context: PDFContext,
               id: Int,
               generation: Int,
               streamInfo: JsonElement,
               parentInfo: JsonElement,
               _ ptr: inout UnsafePointer<UInt8>,
               _ start: UnsafePointer<UInt8>,
               _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard isKeyword(ptr, end, "stream") else {
        return fail("stream not on open stream")
    }
    ptr += 6

    // The keyword should be followed by CRLF or LF; tolerate CR alone and trailing spaces
    while ptr < end, ptr[0] == .space || ptr[0] == .tab { ptr += 1 }
    if ptr < end, ptr[0] == .carriageReturn { ptr += 1 }
    if ptr < end, ptr[0] == .newLine { ptr += 1 }
    let dataStart = ptr

    // Trust /Length only if "endstream" is where it says; otherwise search for it
    var length = -1
    if let declared = resolve(context, streamInfo[element: "Length"])?.intValue,
       declared >= 0,
       declared <= end - dataStart,
       endstreamFollows(dataStart + declared, end) {
        length = declared
    } else if let endstream = findEndstream(dataStart, end) {
        var dataEnd = endstream
        // the EOL before endstream is not part of the data
        if dataEnd > dataStart, dataEnd[-1] == .newLine { dataEnd -= 1 }
        if dataEnd > dataStart, dataEnd[-1] == .carriageReturn { dataEnd -= 1 }
        length = dataEnd - dataStart
        context.warn("object \(id): stream /Length is wrong or missing, found endstream instead")
    } else {
        length = end - dataStart
        context.warn("object \(id): stream has no endstream")
    }

    let raw = HalfHitch(sourceObject: nil,
                        raw: dataStart,
                        count: length,
                        from: 0,
                        to: length)
    if id >= 0 {
        context.rawStreams[id] = RawStream(data: raw, info: streamInfo, id: id, generation: generation)
        context.streamData[id] = nil
    }

    ptr = dataStart + length
    while ptr < end, ptr[0].isWhitspace() { ptr += 1 }
    if isKeyword(ptr, end, endstreamKeyword) {
        ptr += endstreamKeyword.count
    }

    return streamInfo
}

/// Decrypted and decoded data of the stream held by object `id` (cached).
func streamData(_ context: PDFContext,
                id: Int) -> Hitch? {
    if let cached = context.streamData[id] {
        return cached
    }
    guard let raw = context.rawStreams[id] else { return nil }

    let content = decryptStream(context, raw)

    guard let decoded = decodeFilters(context, streamFilters(context, raw.info), content) else {
        return nil
    }
    context.streamData[id] = decoded
    return decoded
}
