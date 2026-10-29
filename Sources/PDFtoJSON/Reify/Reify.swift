import Foundation
import Spanker
import Hitch

/// Resolve an element: indirect references are loaded, anything else is returned as-is.
func resolve(_ context: PDFContext,
             _ element: JsonElement?) -> JsonElement? {
    guard let element = element else { return nil }
    guard isReference(element),
          let id = element[int: "id"] else { return element }
    return resolve(context, id: id)
}

/// Load the indirect object `id` and return its value (nil for free/missing objects).
func resolve(_ context: PDFContext,
             id: Int) -> JsonElement? {
    if let object = context.objects[id] {
        return object[element: "value"]
    }
    // protect against cyclic references; the object will be filled in by the outer call
    guard context.resolving.contains(id) == false else { return nil }
    context.resolving.insert(id)
    defer { context.resolving.remove(id) }

    var wrapper: JsonElement? = nil

    switch context.xref[id] {
    case .offset(let offset, _):
        wrapper = parseIndirectObject(context, id: id, offset: offset)
        // the xref offset is wrong; fall back to the location found by scanning the file
        if wrapper == nil,
           let scanned = scanObjectOffsets(context)[id],
           scanned != offset {
            context.warn("object \(id): xref offset \(offset) is wrong, using \(scanned)")
            wrapper = parseIndirectObject(context, id: id, offset: scanned)
        }
    case .compressed(let stream, let index):
        wrapper = parseCompressedObject(context, id: id, stream: stream, index: index)
    case .free:
        return nil
    case .none:
        // not in the xref at all; it may still exist in a damaged file
        if let scanned = scanObjectOffsets(context)[id] {
            wrapper = parseIndirectObject(context, id: id, offset: scanned)
        }
    }

    guard let wrapper = wrapper else { return nil }
    context.objects[id] = wrapper
    return wrapper[element: "value"]
}

/// Parse "id gen obj ... endobj" at a byte offset, verifying the object number.
func parseIndirectObject(_ context: PDFContext,
                         id: Int,
                         offset: Int) -> JsonElement? {
    guard var ptr = context.pointer(offset: offset) else { return nil }
    skipWhitespace(&ptr, context.start, context.end)

    // Verify that the object header matches before parsing anything
    let parts = peekParts(n: 3, ptr, context.end)
    guard parts[2] == "obj",
          let foundId = parts[0].toInt(),
          foundId == id,
          parts[1].toInt() != nil else { return nil }

    guard let wrapper = getObject(context: context,
                                  id: id,
                                  generation: parts[1].toInt() ?? 0,
                                  &ptr, context.start, context.end),
          wrapper[int: "id"] == id else { return nil }
    return wrapper
}

/// Load (and cache) the header of an object stream.
func objectStream(_ context: PDFContext,
                  id: Int) -> ObjectStream? {
    if let cached = context.objectStreams[id] {
        return cached
    }
    guard let streamInfo = resolve(context, id: id),
          let data = streamData(context, id: id),
          let count = streamInfo[int: "N"],
          let first = streamInfo[int: "First"],
          first >= 0, first <= data.count,
          let raw = data.raw() else {
        context.warn("object stream \(id) could not be loaded")
        return nil
    }

    // header: pairs of "objectNumber byteOffset"
    var offsets: [Int: Int] = [:]
    var ptr = raw
    let headerEnd = raw + first
    for _ in 0..<max(0, count) {
        skipWhitespace(&ptr, raw, headerEnd)
        guard let objectNumber = readInt(&ptr, headerEnd) else { break }
        skipWhitespace(&ptr, raw, headerEnd)
        guard let offset = readInt(&ptr, headerEnd) else { break }
        if offsets[objectNumber] == nil {
            offsets[objectNumber] = offset
        }
    }

    let objectStream = ObjectStream(data: data, first: first, offsets: offsets)
    context.objectStreams[id] = objectStream
    return objectStream
}

func parseCompressedObject(_ context: PDFContext,
                           id: Int,
                           stream: Int,
                           index: Int) -> JsonElement? {
    guard let objectStream = objectStream(context, id: stream),
          let offset = objectStream.offsets[id],
          let raw = objectStream.data.raw() else { return nil }

    let dataEnd = raw + objectStream.data.count
    var ptr = raw + objectStream.first + offset
    guard ptr < dataEnd else { return nil }

    // bound the parse by the start of the next object so values can't run together
    var objectEnd = dataEnd
    for other in objectStream.offsets.values where other > offset {
        objectEnd = min(objectEnd, raw + objectStream.first + other)
    }

    // Objects inside an object stream are not individually encrypted (id: -1)
    guard let value = getObject(context: context,
                                id: -1,
                                generation: -1,
                                &ptr, raw, objectEnd) else { return nil }
    return makeObjectWrapper(id: id, generation: 0, value: value)
}

/// Read an unsigned decimal integer.
func readInt(_ ptr: inout UnsafePointer<UInt8>,
             _ end: UnsafePointer<UInt8>) -> Int? {
    var value = 0
    var digits = 0
    while ptr < end, ptr[0] >= .zero, ptr[0] <= .nine {
        value = value &* 10 &+ Int(ptr[0] - .zero)
        digits += 1
        ptr += 1
    }
    return digits > 0 ? value : nil
}
