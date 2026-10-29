import Foundation
import Spanker
import Hitch

/// An operand in a content stream or CMap.
enum Operand {
    case number(Double)
    case string(Hitch)          // raw bytes
    case name(Hitch)
    case array([Operand])
    case dictionary(JsonElement)
    case boolean(Bool)
    case null

    var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
    var bytes: Hitch? {
        if case .string(let value) = self { return value }
        return nil
    }
    var name: Hitch? {
        if case .name(let value) = self { return value }
        return nil
    }
}

enum ContentToken {
    case operand(Operand)
    case op(HalfHitch)
}

/// Tokenizer for content streams and CMaps: operands, then an operator.
struct ContentLexer {
    var ptr: UnsafePointer<UInt8>
    let start: UnsafePointer<UInt8>
    let end: UnsafePointer<UInt8>
    private let context: PDFContext

    init?(_ data: HalfHitch) {
        guard let raw = data.raw() else { return nil }
        start = raw
        ptr = raw
        end = raw + data.count
        context = PDFContext(document: ^[], start: raw, end: raw + data.count)
        context.stringMode = .raw
    }

    mutating func next() -> ContentToken? {
        skipWhitespace(&ptr, start, end)
        guard ptr < end else { return nil }

        switch ptr[0] {
        case .parenOpen:
            return .operand(.string(getStringBytes(&ptr, end) ?? Hitch()))
        case .lessThan:
            if ptr + 1 < end, ptr[1] == .lessThan {
                let dict = getDictionary(context: context, id: -1, generation: -1, &ptr, start, end)
                return .operand(dict.map { .dictionary($0) } ?? .null)
            }
            return .operand(.string(getHexstringBytes(&ptr, end) ?? Hitch()))
        case .openBrace:
            ptr += 1
            var values: [Operand] = []
            while let token = next() {
                switch token {
                case .operand(let value): values.append(value)
                case .op(let op) where op == "]": return .operand(.array(values))
                case .op: continue
                }
            }
            return .operand(.array(values))
        case .closeBrace:
            ptr += 1
            return .op("]")
        case .openBracket, .closeBracket:
            ptr += 1
            return .op(ptr[-1] == .openBracket ? "{" : "}")
        case .forwardSlash:
            return .operand(.name(getKey(&ptr, start, end)?.hitchValue ?? Hitch()))
        case .greaterThan, .parenClose:
            ptr += 1
            return next()
        default:
            break
        }

        let token = readToken(&ptr, end)
        guard token.count > 0 else {
            ptr += 1
            return next()
        }
        let c = token[0]
        if (c >= .zero && c <= .nine) || c == .minus || c == .plus || c == .dot {
            if let value = token.toDouble(fuzzy: true) {
                return .operand(.number(value))
            }
        }
        switch token {
        case "true": return .operand(.boolean(true))
        case "false": return .operand(.boolean(false))
        case "null": return .operand(.null)
        default: return .op(token)
        }
    }

    /// After an inline image's ID operator: skip the image data up to and including EI.
    mutating func skipInlineImage(length: Int?) {
        // one whitespace byte separates ID from the data
        if ptr < end, ptr[0].isPDFWhitespace() { ptr += 1 }
        if let length = length, length >= 0, length <= end - ptr {
            ptr += length
        }
        while ptr + 1 < end {
            if ptr[0] == .E, ptr[1] == .I,
               (ptr == start || ptr[-1].isPDFWhitespace()),
               (ptr + 2 == end || ptr[2].isDelimiter()) {
                ptr += 2
                return
            }
            ptr += 1
        }
        ptr = end
    }
}
