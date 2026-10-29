import Foundation
import Spanker
import Hitch

/// A CMap: codespace ranges plus code -> Unicode (ToUnicode) and/or code -> CID mappings.
final class CMap {
    struct CodespaceRange {
        let low: [UInt8]
        let high: [UInt8]
    }

    private struct UnicodeRange {
        let low: UInt32
        let high: UInt32
        /// UTF-16 units of the destination for `low`; the last unit increases with the code
        let start: [UInt16]
    }

    private struct CIDRange {
        let low: UInt32
        let high: UInt32
        let cid: Int
    }

    var codespace: [CodespaceRange] = []
    var vertical = false
    private var unicodeChars: [UInt32: [UInt32]] = [:]
    private var unicodeRanges: [UnicodeRange] = []
    private var cidChars: [UInt32: Int] = [:]
    private var cidRanges: [CIDRange] = []

    var hasCIDMappings: Bool { cidChars.isEmpty == false || cidRanges.isEmpty == false }

    // MARK: lookups

    func unicode(_ code: UInt32) -> [UInt32]? {
        if let chars = unicodeChars[code] {
            return chars
        }
        for range in unicodeRanges.reversed() where code >= range.low && code <= range.high {
            var units = range.start
            if let last = units.last {
                units[units.count - 1] = last &+ UInt16(truncatingIfNeeded: code - range.low)
            }
            return scalars(fromUTF16: units)
        }
        return nil
    }

    func cid(_ code: UInt32) -> Int? {
        if let cid = cidChars[code] {
            return cid
        }
        for range in cidRanges.reversed() where code >= range.low && code <= range.high {
            return range.cid + Int(code - range.low)
        }
        return nil
    }

    /// Length in bytes of the code starting at `bytes[index]`, per the codespace ranges.
    func codeLength(_ bytes: UnsafePointer<UInt8>, _ count: Int, at index: Int) -> Int? {
        guard codespace.isEmpty == false else { return nil }
        for length in 1...4 where index + length <= count {
            for range in codespace where range.low.count == length {
                var matches = true
                for k in 0..<length where bytes[index + k] < range.low[k] || bytes[index + k] > range.high[k] {
                    matches = false
                    break
                }
                if matches { return length }
            }
        }
        // no match: consume the shortest code length
        return codespace.map { $0.low.count }.min()
    }

    // MARK: parsing

    init() { }

    init(_ data: HalfHitch) {
        guard var lexer = ContentLexer(data) else { return }
        var operands: [Operand] = []
        while let token = lexer.next() {
            switch token {
            case .operand(let value):
                operands.append(value)
                continue
            case .op(let op):
                switch op {
                case "endcodespacerange":
                    forEach(operands, 2) { o in
                        if let low = o[0].bytes, let high = o[1].bytes, low.count == high.count, low.count > 0 {
                            codespace.append(CodespaceRange(low: Array(low), high: Array(high)))
                        }
                    }
                case "endbfchar":
                    forEach(operands, 2) { o in
                        guard let src = o[0].bytes else { return }
                        if let dst = destination(o[1]) {
                            unicodeChars[codeValue(src)] = dst
                        }
                    }
                case "endbfrange":
                    forEach(operands, 3) { o in
                        guard let lowBytes = o[0].bytes, let highBytes = o[1].bytes else { return }
                        let low = codeValue(lowBytes)
                        let high = codeValue(highBytes)
                        guard high >= low, high - low < 0x10000 else { return }
                        if case .array(let values) = o[2] {
                            for (offset, value) in values.enumerated() where low + UInt32(offset) <= high {
                                if let dst = destination(value) {
                                    unicodeChars[low + UInt32(offset)] = dst
                                }
                            }
                        } else if let dst = o[2].bytes {
                            unicodeRanges.append(UnicodeRange(low: low, high: high, start: utf16Units(dst)))
                        }
                    }
                case "endcidchar":
                    forEach(operands, 2) { o in
                        if let src = o[0].bytes, let cid = o[1].number {
                            cidChars[codeValue(src)] = Int(cid)
                        }
                    }
                case "endcidrange":
                    forEach(operands, 3) { o in
                        if let low = o[0].bytes, let high = o[1].bytes, let cid = o[2].number {
                            cidRanges.append(CIDRange(low: codeValue(low), high: codeValue(high), cid: Int(cid)))
                        }
                    }
                case "def":
                    if operands.count >= 2, operands[operands.count - 2].name == "WMode",
                       operands[operands.count - 1].number == 1 {
                        vertical = true
                    }
                case "usecmap":
                    if let name = operands.last?.name {
                        apply(predefined: name.toString())
                    }
                default:
                    break
                }
                operands.removeAll(keepingCapacity: true)
            }
        }
    }

    /// The parts of a predefined CMap we can use without its data.
    func apply(predefined name: String) {
        if name.hasPrefix("Identity") || name.contains("UCS2") || name.contains("UTF16") {
            codespace.append(CodespaceRange(low: [0x00, 0x00], high: [0xFF, 0xFF]))
        }
        if name.hasSuffix("-V") {
            vertical = true
        }
    }

    private func forEach(_ operands: [Operand], _ stride: Int, _ body: ([Operand]) -> Void) {
        var idx = 0
        while idx + stride <= operands.count {
            body(Array(operands[idx..<idx + stride]))
            idx += stride
        }
    }

    private func destination(_ operand: Operand) -> [UInt32]? {
        if let bytes = operand.bytes {
            return scalars(fromUTF16: utf16Units(bytes))
        }
        if let name = operand.name {
            return glyphNameToUnicode(name.toString())
        }
        return nil
    }
}

func codeValue(_ bytes: Hitch) -> UInt32 {
    var value: UInt32 = 0
    for b in bytes.prefix(4) {
        value = value << 8 | UInt32(b)
    }
    return value
}

private func utf16Units(_ bytes: Hitch) -> [UInt16] {
    let raw = Array(bytes)
    if raw.count == 1 {
        return [UInt16(raw[0])]
    }
    var units: [UInt16] = []
    var idx = 0
    while idx + 1 < raw.count {
        units.append(UInt16(raw[idx]) << 8 | UInt16(raw[idx + 1]))
        idx += 2
    }
    return units
}

func scalars(fromUTF16 units: [UInt16]) -> [UInt32] {
    var result: [UInt32] = []
    var idx = 0
    while idx < units.count {
        let u = UInt32(units[idx])
        if u >= 0xD800 && u < 0xDC00 && idx + 1 < units.count {
            let low = UInt32(units[idx + 1])
            if low >= 0xDC00 && low < 0xE000 {
                result.append(0x10000 + ((u - 0xD800) << 10) + (low - 0xDC00))
                idx += 2
                continue
            }
        }
        if u < 0xD800 || u >= 0xE000 {
            result.append(u)
        }
        idx += 1
    }
    return result
}
