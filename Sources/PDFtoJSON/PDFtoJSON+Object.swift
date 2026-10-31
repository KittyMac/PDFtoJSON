import Foundation
import Spanker
import Hitch

// PDF object syntax (ISO 32000-1, 7.3):
// << /Name0 Value0 /Name1 Value1 >>          dictionary
// (String literal)                            escapes: \n \r \t \b \f \( \) \\ \ddd, \<EOL>
// <4E6F762073686D6F7A>                        hex string (whitespace allowed, odd digit padded)
// [ ArrayObject0 ArrayObject1 ]               array
// /lime#20Green                               name (#xx escapes)
// 123 -98 +17 34.5 -.002 4.                   numbers
// true false null
// % comment to end of line                    treated as whitespace
// 12 0 obj ... endobj                         indirect object definition
// 12 0 R                                      indirect reference
// << ... >> stream\n...\nendstream            stream

public extension UInt8 {
    /// PDF whitespace: NUL, TAB, LF, FF, CR, SPACE
    @inlinable
    func isPDFWhitespace() -> Bool {
        switch self {
        case 0x00, 0x09, 0x0A, 0x0C, 0x0D, 0x20:
            return true
        default:
            return false
        }
    }

    /// Ends a token: whitespace or one of ( ) < > [ ] { } / %
    @inlinable
    func isDelimiter() -> Bool {
        switch self {
        case 0x00, 0x09, 0x0A, 0x0C, 0x0D, 0x20,
             .parenOpen, .parenClose, .lessThan, .greaterThan,
             .openBrace, .closeBrace, .openBracket, .closeBracket,
             .forwardSlash, .percentSign:
            return true
        default:
            return false
        }
    }
}

/// Skip whitespace and comments.
func skipWhitespace(_ ptr: inout UnsafePointer<UInt8>,
                    _ start: UnsafePointer<UInt8>,
                    _ end: UnsafePointer<UInt8>) {
    while ptr < end {
        if ptr[0].isPDFWhitespace() {
            ptr += 1
        } else if ptr[0] == .percentSign {
            while ptr < end, ptr[0] != .newLine, ptr[0] != .carriageReturn {
                ptr += 1
            }
        } else {
            break
        }
    }
}

/// Read a run of regular (non-delimiter) characters.
@inline(__always)
func readToken(_ ptr: inout UnsafePointer<UInt8>,
               _ end: UnsafePointer<UInt8>) -> HalfHitch {
    let tokenStart = ptr
    while ptr < end, ptr[0].isDelimiter() == false {
        ptr += 1
    }
    return HalfHitch(sourceObject: nil, raw: tokenStart, count: ptr - tokenStart, from: 0, to: ptr - tokenStart)
}

/// The next `n` tokens (regular characters only), without consuming them.
@usableFromInline
func peekParts(n: Int,
               _ start: UnsafePointer<UInt8>,
               _ end: UnsafePointer<UInt8>) -> [HalfHitch] {
    var parts: [HalfHitch] = []
    var ptr = start
    while ptr < end && parts.count < n {
        if ptr[0].isDelimiter() {
            ptr += 1
            continue
        }
        parts.append(readToken(&ptr, end))
    }
    while parts.count < n {
        parts.append(HalfHitch.empty)
    }
    return parts
}

private func isInteger(_ token: HalfHitch) -> Bool {
    guard token.count > 0, let raw = token.raw() else { return false }
    var idx = 0
    if raw[0] == .plus || raw[0] == .minus { idx = 1 }
    guard idx < token.count else { return false }
    while idx < token.count {
        guard raw[idx] >= .zero && raw[idx] <= .nine else { return false }
        idx += 1
    }
    return true
}

private func looksNumeric(_ token: HalfHitch) -> Bool {
    guard token.count > 0, let raw = token.raw() else { return false }
    let c = raw[0]
    return (c >= .zero && c <= .nine) || c == .plus || c == .minus || c == .dot
}

/// Parse the number token; tolerant of junk like "--5" or "1.2.3".
private func parseNumber(_ token: HalfHitch) -> JsonElement? {
    if isInteger(token), let value = token.toInt() {
        return JsonElement(unknown: value)
    }
    var cleaned = token.hitch()
    // collapse repeated leading signs ("--5", "+-5")
    while cleaned.count > 1, (cleaned[0] == .minus || cleaned[0] == .plus), (cleaned[1] == .minus || cleaned[1] == .plus) {
        cleaned = cleaned.substring(1, cleaned.count) ?? cleaned
    }
    if cleaned.contains(.dot) == false, let value = cleaned.halfhitch().toInt(fuzzy: true) {
        return JsonElement(unknown: value)
    }
    if let value = cleaned.halfhitch().toDouble(fuzzy: true) {
        return JsonElement(unknown: value)
    }
    return nil
}

func getObject(context: PDFContext,
               id: Int,
               generation: Int,
               _ ptr: inout UnsafePointer<UInt8>,
               _ start: UnsafePointer<UInt8>,
               _ end: UnsafePointer<UInt8>) -> JsonElement? {
    return getObject(context: context,
                     id: id,
                     generation: generation,
                     parentInfo: JsonElement.null(),
                     &ptr, start, end)
}

/// Parse the next object. Returns nil at end of data, at a closing ']' or '>>'
/// (not consumed), or after consuming a keyword that is not an object.
func getObject(context: PDFContext,
               id: Int,
               generation: Int,
               parentInfo: JsonElement,
               _ ptr: inout UnsafePointer<UInt8>,
               _ start: UnsafePointer<UInt8>,
               _ end: UnsafePointer<UInt8>) -> JsonElement? {
    skipWhitespace(&ptr, start, end)
    guard ptr < end else { return nil }

    switch ptr[0] {
    case .parenOpen:
        return getString(context: context, id: id, generation: generation, &ptr, start, end)

    case .lessThan:
        guard ptr + 1 < end, ptr[1] == .lessThan else {
            return getHexstring(context: context, id: id, generation: generation, &ptr, start, end)
        }
        guard let dictionary = getDictionary(context: context,
                                             id: id,
                                             generation: generation,
                                             &ptr, start, end) else { return nil }

        // a dictionary followed by the stream keyword is a stream
        var peek = ptr
        skipWhitespace(&peek, start, end)
        if peek + 6 <= end,
           peek[0] == .s, peek[1] == .t, peek[2] == .r, peek[3] == .e, peek[4] == .a, peek[5] == .m,
           peek + 6 == end || peek[6].isDelimiter() {
            ptr = peek
            return getStream(context: context,
                             id: id,
                             generation: generation,
                             streamInfo: dictionary,
                             parentInfo: parentInfo,
                             &ptr, start, end)
        }
        return dictionary

    case .openBrace:
        return getArray(context: context, id: id, generation: generation, &ptr, start, end)

    case .forwardSlash:
        return getKey(&ptr, start, end)

    case .closeBrace:
        // end of an enclosing array; let the caller consume it
        return nil

    case .greaterThan:
        if ptr + 1 < end, ptr[1] == .greaterThan {
            // end of an enclosing dictionary; let the caller consume it
            return nil
        }
        ptr += 1
        return nil

    case .parenClose, .openBracket, .closeBracket:
        // stray delimiter
        ptr += 1
        return nil

    default:
        break
    }

    let tokenStart = ptr
    let token = readToken(&ptr, end)
    guard token.count > 0 else {
        ptr += 1
        return nil
    }

    if looksNumeric(token) {
        // "id gen R" and "id gen obj" start with two unsigned integers
        if isInteger(token), token[0] != .minus, token[0] != .plus {
            var peek = ptr
            skipWhitespace(&peek, start, end)
            let second = readToken(&peek, end)
            if isInteger(second) {
                skipWhitespace(&peek, start, end)
                let keyword = readToken(&peek, end)
                if keyword == "R",
                   let objectId = token.toInt(),
                   let objectGeneration = second.toInt() {
                    ptr = peek
                    return makeReference(id: objectId, generation: objectGeneration)
                }
                if keyword == "obj",
                   let objectId = token.toInt(),
                   let objectGeneration = second.toInt() {
                    ptr = tokenStart
                    return getObjectDefinition(context: context,
                                               id: objectId,
                                               generation: objectGeneration,
                                               &ptr, start, end)
                }
            }
        }
        if let number = parseNumber(token) {
            return number
        }
        return nil
    }

    switch token {
    case "true": return JsonElement(unknown: true)
    case "false": return JsonElement(unknown: false)
    case "null": return JsonElement.null()
    default:
        // a keyword that is not an object (endobj, stray operators, junk): consumed
        return nil
    }
}

/// Parse a single object from a standalone buffer (used by tests).
func getObject(document: JsonElement,
               id: Int,
               generation: Int,
               _ ptr: inout UnsafePointer<UInt8>,
               _ start: UnsafePointer<UInt8>,
               _ end: UnsafePointer<UInt8>) -> JsonElement? {
    return getObject(context: PDFContext(document: document, start: start, end: end),
                     id: id,
                     generation: generation,
                     &ptr, start, end)
}

// MARK: - Arrays

func getArray(context: PDFContext,
              id: Int,
              generation: Int,
              _ ptr: inout UnsafePointer<UInt8>,
              _ start: UnsafePointer<UInt8>,
              _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard ptr < end, ptr[0] == .openBrace else { return fail("array not on open bracket") }
    ptr += 1

    let results = JsonElement(unknown: [])
    while true {
        skipWhitespace(&ptr, start, end)
        guard ptr < end else { break }
        if ptr[0] == .closeBrace {
            ptr += 1
            break
        }
        // unterminated array inside a dictionary: let the dictionary close
        if ptr[0] == .greaterThan, ptr + 1 < end, ptr[1] == .greaterThan {
            break
        }
        let before = ptr
        if let value = getObject(context: context, id: id, generation: generation, &ptr, start, end) {
            results.append(value: value)
        } else if ptr == before {
            ptr += 1
        }
    }
    return results
}

// MARK: - Dictionaries

func getDictionary(context: PDFContext,
                   id: Int,
                   generation: Int,
                   _ ptr: inout UnsafePointer<UInt8>,
                   _ start: UnsafePointer<UInt8>,
                   _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard ptr + 1 < end, ptr[0] == .lessThan, ptr[1] == .lessThan else {
        return fail("dictionary not on open angle brackets")
    }
    ptr += 2

    let results = JsonElement(unknown: [:])
    while true {
        skipWhitespace(&ptr, start, end)
        guard ptr < end else { break }
        if ptr[0] == .greaterThan {
            ptr += (ptr + 1 < end && ptr[1] == .greaterThan) ? 2 : 1
            break
        }

        guard ptr[0] == .forwardSlash,
              let key = getKey(&ptr, start, end)?.halfHitchValue else {
            // not a key: skip whatever it is
            let before = ptr
            _ = getObject(context: context, id: id, generation: generation, &ptr, start, end)
            if ptr == before { ptr += 1 }
            continue
        }

        skipWhitespace(&ptr, start, end)
        let before = ptr
        if let value = getObject(context: context, id: id, generation: generation, &ptr, start, end) {
            results.set(key: key, value: value)
        } else if ptr == before {
            // missing value before '>>' or ']'
            if ptr < end, ptr[0] == .closeBrace { ptr += 1 }
            results.set(key: key, value: JsonElement.null())
        }
    }

    return results
}

// MARK: - Names

func getKey(_ ptr: inout UnsafePointer<UInt8>,
            _ start: UnsafePointer<UInt8>,
            _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard ptr < end, ptr[0] == .forwardSlash else { return fail("key not on forward slash") }
    ptr += 1
    let token = readToken(&ptr, end)
    guard token.contains(.hashTag) else {
        return JsonElement(unknown: token.hitch())
    }

    // #xx escapes
    let bytes = Hitch(capacity: token.count)
    var idx = 0
    while idx < token.count {
        if token[idx] == .hashTag, idx + 2 < token.count,
           let high: UInt8 = hex(token[idx + 1]),
           let low: UInt8 = hex(token[idx + 2]) {
            bytes.append(high << 4 | low)
            idx += 3
        } else {
            bytes.append(token[idx])
            idx += 1
        }
    }
    return JsonElement(unknown: decodeNameBytes(bytes))
}

// MARK: - Strings

/// Finish a string: decrypt it, then represent it according to the context's string mode.
private func makeString(context: PDFContext,
                        id: Int,
                        generation: Int,
                        _ bytes: Hitch) -> JsonElement? {
    let bytes = decryptString(context, id: id, generation: generation, bytes)

    switch context.stringMode {
    case .text:
        return JsonElement(unknown: decodeTextString(bytes))
    case .hex:
        return JsonElement(unknown: hexForm(bytes))
    case .raw:
        return JsonElement(unknown: bytes)
    case .latin1:
        let out = Hitch(capacity: bytes.count)
        for b in bytes { out.append(scalar: UInt32(b)) }
        return JsonElement(unknown: out)
    }
}

/// Bytes of a literal string, with escapes resolved.
func getStringBytes(_ ptr: inout UnsafePointer<UInt8>,
                    _ end: UnsafePointer<UInt8>) -> Hitch? {
    guard ptr < end, ptr[0] == .parenOpen else { return nil }
    ptr += 1

    let bytes = Hitch(capacity: 64)
    var depth = 0
    while ptr < end {
        let c = ptr[0]
        if c == .backSlash {
            ptr += 1
            guard ptr < end else { break }
            let e = ptr[0]
            ptr += 1
            switch e {
            case .n: bytes.append(.newLine)
            case .r: bytes.append(.carriageReturn)
            case .t: bytes.append(.tab)
            case .b: bytes.append(.backspace)
            case .f: bytes.append(.formFeed)
            case .carriageReturn:
                // line continuation
                if ptr < end, ptr[0] == .newLine { ptr += 1 }
            case .newLine:
                break
            case .zero, .one, .two, .three, .four, .five, .six, .seven:
                var value = Int(e - .zero)
                for _ in 0..<2 {
                    guard ptr < end, ptr[0] >= .zero, ptr[0] <= .seven else { break }
                    value = value * 8 + Int(ptr[0] - .zero)
                    ptr += 1
                }
                bytes.append(UInt8(truncatingIfNeeded: value))
            default:
                // \( \) \\ and unknown escapes: the character itself
                bytes.append(e)
            }
            continue
        }
        if c == .parenOpen {
            depth += 1
        } else if c == .parenClose {
            if depth == 0 {
                ptr += 1
                break
            }
            depth -= 1
        }
        if c == .carriageReturn {
            // an unescaped end-of-line is always read as LF
            bytes.append(.newLine)
            ptr += 1
            if ptr < end, ptr[0] == .newLine { ptr += 1 }
            continue
        }
        bytes.append(c)
        ptr += 1
    }
    return bytes
}

func getString(context: PDFContext,
               id: Int,
               generation: Int,
               _ ptr: inout UnsafePointer<UInt8>,
               _ start: UnsafePointer<UInt8>,
               _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard let bytes = getStringBytes(&ptr, end) else { return fail("string not on open paren") }
    return makeString(context: context, id: id, generation: generation, bytes)
}

/// Bytes of a hex string; whitespace is ignored and an odd final digit is padded with 0.
func getHexstringBytes(_ ptr: inout UnsafePointer<UInt8>,
                       _ end: UnsafePointer<UInt8>) -> Hitch? {
    guard ptr < end, ptr[0] == .lessThan else { return nil }
    ptr += 1
    let bytes = Hitch(capacity: 32)
    var high: UInt8? = nil
    while ptr < end, ptr[0] != .greaterThan {
        if let value: UInt8 = hex(ptr[0]) {
            if let h = high {
                bytes.append(h << 4 | value)
                high = nil
            } else {
                high = value
            }
        }
        ptr += 1
    }
    if let h = high {
        bytes.append(h << 4)
    }
    if ptr < end { ptr += 1 }
    return bytes
}

func getHexstring(context: PDFContext,
                  id: Int,
                  generation: Int,
                  _ ptr: inout UnsafePointer<UInt8>,
                  _ start: UnsafePointer<UInt8>,
                  _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard let bytes = getHexstringBytes(&ptr, end) else { return fail("hexstring not on open angle bracket") }
    return makeString(context: context, id: id, generation: generation, bytes)
}

// MARK: - Indirect object definitions

/// "id gen obj <object> endobj" -> { "id", "generation", "value" }
func getObjectDefinition(context: PDFContext,
                         id: Int,
                         generation: Int,
                         _ ptr: inout UnsafePointer<UInt8>,
                         _ start: UnsafePointer<UInt8>,
                         _ end: UnsafePointer<UInt8>) -> JsonElement? {
    // skip "id gen obj"
    for _ in 0..<3 {
        skipWhitespace(&ptr, start, end)
        _ = readToken(&ptr, end)
    }

    var value = JsonElement.null()
    while true {
        skipWhitespace(&ptr, start, end)
        guard ptr < end else { break }
        if ptr + 6 <= end, ptr[0] == .e, ptr[1] == .n, ptr[2] == .d, ptr[3] == .o, ptr[4] == .b, ptr[5] == .j {
            ptr += 6
            break
        }
        let before = ptr
        if let object = getObject(context: context, id: id, generation: generation, &ptr, start, end) {
            value = object
            // one object per definition; consume a following endobj if present
            skipWhitespace(&ptr, start, end)
            if ptr + 6 <= end, ptr[0] == .e, ptr[1] == .n, ptr[2] == .d, ptr[3] == .o, ptr[4] == .b, ptr[5] == .j {
                ptr += 6
            }
            break
        }
        // a stray keyword or delimiter before the value; stop at the next object header
        if ptr == before { ptr += 1 }
        let next = peekParts(n: 3, ptr, end)
        if next[2] == "obj" && isInteger(next[0]) { break }
    }

    return makeObjectWrapper(id: id, generation: generation, value: value)
}
