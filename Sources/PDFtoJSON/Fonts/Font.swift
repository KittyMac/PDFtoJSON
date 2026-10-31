import Foundation
import Spanker
import Hitch

// MARK: - Glyph names

private let adobeGlyphList: [String: [UInt32]] = {
    var table: [String: [UInt32]] = [:]
    table.reserveCapacity(14200)
    for line in adobeGlyphListData.split(separator: "\n") {
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { continue }
        table[String(parts[0])] = parts.dropFirst().compactMap { UInt32($0, radix: 16) }
    }
    return table
}()

private func hexScalars(_ hex: Substring, groupSize: Int) -> [UInt32]? {
    guard hex.isEmpty == false, hex.count % groupSize == 0 else { return nil }
    var result: [UInt32] = []
    var idx = hex.startIndex
    while idx < hex.endIndex {
        let next = hex.index(idx, offsetBy: groupSize)
        guard let value = UInt32(hex[idx..<next], radix: 16) else { return nil }
        result.append(value)
        idx = next
    }
    return result
}

/// Unicode for a glyph name (Adobe Glyph List specification rules).
func glyphNameToUnicode(_ name: String) -> [UInt32]? {
    if let known = adobeGlyphList[name] {
        return known
    }
    // "name.suffix" -> "name"
    if let dot = name.firstIndex(of: "."), dot != name.startIndex {
        return glyphNameToUnicode(String(name[..<dot]))
    }
    // ligatures: "f_f_i"
    if name.contains("_") {
        let parts = name.split(separator: "_").compactMap { glyphNameToUnicode(String($0)) }
        return parts.isEmpty ? nil : parts.flatMap { $0 }
    }
    if name.hasPrefix("uni"), let values = hexScalars(name.dropFirst(3), groupSize: 4) {
        return values
    }
    if name.hasPrefix("u"), (5...7).contains(name.count), let value = UInt32(name.dropFirst(), radix: 16) {
        return [value]
    }
    return nil
}

// MARK: - Standard 14 fonts

private let standardFontWidths: [String: [UInt32: Int]] = {
    var fonts: [String: [UInt32: Int]] = [:]
    for line in standardFontWidthData.split(separator: "\n") {
        let parts = line.split(separator: "|")
        guard parts.count == 2 else { continue }
        var widths: [UInt32: Int] = [:]
        for entry in parts[1].split(separator: ",") {
            let kv = entry.split(separator: ":")
            if kv.count == 2, let u = UInt32(kv[0], radix: 16), let w = Int(kv[1]) {
                widths[u] = w
            }
        }
        fonts[String(parts[0])] = widths
    }
    return fonts
}()

/// The standard font a base font name refers to (handles subset prefixes and common aliases).
private func standardFontName(_ baseFont: String) -> String? {
    var name = baseFont
    if let plus = name.firstIndex(of: "+"), name.distance(from: name.startIndex, to: plus) == 6 {
        name = String(name[name.index(after: plus)...])
    }
    let lower = name.lowercased().replacingOccurrences(of: " ", with: "")
    let bold = lower.contains("bold")
    let italic = lower.contains("italic") || lower.contains("oblique")
    if lower.hasPrefix("courier") {
        return bold ? (italic ? "Courier-BoldOblique" : "Courier-Bold") : (italic ? "Courier-Oblique" : "Courier")
    }
    if lower.hasPrefix("times") {
        return bold ? (italic ? "Times-BoldItalic" : "Times-Bold") : (italic ? "Times-Italic" : "Times-Roman")
    }
    if lower.hasPrefix("helvetica") || lower.hasPrefix("arial") {
        return bold ? (italic ? "Helvetica-BoldOblique" : "Helvetica-Bold") : (italic ? "Helvetica-Oblique" : "Helvetica")
    }
    if lower.hasPrefix("symbol") { return "Symbol" }
    if lower.hasPrefix("zapfdingbats") || lower.hasPrefix("dingbats") { return "ZapfDingbats" }
    return nil
}

// MARK: - Fonts

/// Everything text extraction needs to know about a font.
final class Font {
    /// Type0 font: multi-byte codes, widths by CID
    var composite = false
    var vertical = false
    /// Type0 with a UCS-2/UTF-16 encoding CMap: codes are Unicode
    var codesAreUnicode = false

    var toUnicode: CMap? = nil
    /// Type0 encoding (codespace and code -> CID)
    var encoding: CMap? = nil
    /// Simple fonts: code -> Unicode
    var simpleEncoding: [[UInt32]?] = Array(repeating: nil, count: 256)

    /// widths by code (simple) or CID (composite), in 1/1000 text space units
    var widths: [Int: Double] = [:]
    var defaultWidth: Double = 500
    /// fallback widths by Unicode (standard 14 fonts)
    var standardWidths: [UInt32: Int]? = nil

    /// Split a string into codes.
    func codes(_ bytes: Hitch) -> [(code: UInt32, length: Int)] {
        guard let raw = bytes.raw() else { return [] }
        let count = bytes.count
        guard composite else {
            return (0..<count).map { (UInt32(raw[$0]), 1) }
        }
        var result: [(UInt32, Int)] = []
        var idx = 0
        while idx < count {
            let length = encoding?.codeLength(raw, count, at: idx)
                ?? toUnicode?.codeLength(raw, count, at: idx)
                ?? 2
            let available = min(max(1, length), count - idx)
            var code: UInt32 = 0
            for k in 0..<available { code = code << 8 | UInt32(raw[idx + k]) }
            result.append((code, available))
            idx += available
        }
        return result
    }

    func unicode(_ code: UInt32) -> [UInt32] {
        if let mapped = toUnicode?.unicode(code) {
            return mapped
        }
        if composite {
            return codesAreUnicode ? scalars(fromUTF16: [UInt16(truncatingIfNeeded: code)]) : []
        }
        return code < 256 ? (simpleEncoding[Int(code)] ?? []) : []
    }

    /// Advance width in 1/1000 text space units.
    func width(_ code: UInt32) -> Double {
        let key = composite ? (encoding?.cid(code) ?? Int(code)) : Int(code)
        if let width = widths[key] {
            return width
        }
        if let standard = standardWidths, let u = unicode(code).first, let width = standard[u] {
            return Double(width)
        }
        return defaultWidth
    }
}

private func number(_ context: PDFContext, _ element: JsonElement?) -> Double? {
    guard let value = resolve(context, element) else { return nil }
    return value.doubleValue ?? value.intValue.map(Double.init)
}

private func encodingTable(_ name: String?) -> [UInt16]? {
    switch name {
    case "WinAnsiEncoding": return winAnsiEncoding
    case "MacRomanEncoding": return macRomanEncoding
    case "StandardEncoding": return standardEncoding
    case "PDFDocEncoding": return pdfDocEncoding
    case "MacExpertEncoding": return standardEncoding
    default: return nil
    }
}

/// Build a Font from a font dictionary.
func loadFont(_ context: PDFContext, _ dict: JsonElement) -> Font {
    let font = Font()
    let subtype = dict[string: "Subtype"] ?? ""
    let baseFont = dict[string: "BaseFont"] ?? ""

    if let toUnicode = dict[element: "ToUnicode"], isReference(toUnicode),
       let id = toUnicode[int: "id"], resolve(context, id: id) != nil,
       let data = streamData(context, id: id) {
        font.toUnicode = CMap(data.halfhitch())
    }

    if subtype == "Type0" {
        font.composite = true
        font.defaultWidth = 1000

        let encoding = dict[element: "Encoding"]
        if let name = encoding?.stringValue {
            let cmap = CMap()
            cmap.apply(predefined: name)
            font.encoding = cmap
            font.codesAreUnicode = name.contains("UCS2") || name.contains("UTF16")
        } else if isReference(encoding), let id = encoding?[int: "id"],
                  resolve(context, id: id) != nil, let data = streamData(context, id: id) {
            font.encoding = CMap(data.halfhitch())
        }
        font.vertical = font.encoding?.vertical ?? false

        // widths of the descendant CIDFont: /DW and /W [c [w...]] or [cfirst clast w]
        if let descendants = resolve(context, dict[element: "DescendantFonts"]),
           let cidFont = resolve(context, descendants[element: 0]) {
            font.defaultWidth = number(context, cidFont[element: "DW"]) ?? 1000
            if let w = resolve(context, cidFont[element: "W"]), w.type == .array {
                let items = Array(w.iterValues)
                var idx = 0
                while idx + 1 < items.count {
                    guard let first = number(context, items[idx]).map(Int.init) else { idx += 1; continue }
                    if let list = resolve(context, items[idx + 1]), list.type == .array {
                        for (offset, value) in list.iterValues.enumerated() {
                            if let width = number(context, value) { font.widths[first + offset] = width }
                        }
                        idx += 2
                    } else if idx + 2 < items.count,
                              let last = number(context, items[idx + 1]).map(Int.init),
                              let width = number(context, items[idx + 2]),
                              last >= first, last - first < 0x10000 {
                        for cid in first...last { font.widths[cid] = width }
                        idx += 3
                    } else {
                        idx += 2
                    }
                }
            }
        }
        return font
    }

    // Simple fonts (Type1, MMType1, TrueType, Type3)
    let standardName = standardFontName(baseFont)
    var base: [UInt16]
    if standardName == "Symbol" {
        base = symbolEncoding
    } else if standardName == "ZapfDingbats" {
        base = zapfDingbatsEncoding
    } else if subtype == "TrueType" {
        base = winAnsiEncoding
    } else {
        base = standardEncoding
    }

    let encoding = resolve(context, dict[element: "Encoding"])
    var differences: JsonElement? = nil
    if let name = encoding?.stringValue, let table = encodingTable(name) {
        base = table
    } else if let encoding = encoding, encoding.type == .dictionary {
        if let table = encodingTable(encoding[string: "BaseEncoding"]) {
            base = table
        }
        differences = resolve(context, encoding[element: "Differences"])
    }

    for code in 0..<256 where base[code] != 0 {
        font.simpleEncoding[code] = [UInt32(base[code])]
    }
    if let differences = differences, differences.type == .array {
        var code = 0
        for item in differences.iterValues {
            if let value = item.intValue ?? item.doubleValue.map(Int.init) {
                code = value
            } else if let name = item.stringValue {
                if code >= 0 && code < 256 {
                    font.simpleEncoding[code] = glyphNameToUnicode(name)
                }
                code += 1
            }
        }
    }

    // Widths: /FirstChar + /Widths, /MissingWidth, else standard metrics
    var scale = 1.0
    if subtype == "Type3", let matrix = resolve(context, dict[element: "FontMatrix"]),
       let a = number(context, matrix[element: 0]) {
        scale = a * 1000
    }
    let descriptor = resolve(context, dict[element: "FontDescriptor"])
    if let widths = resolve(context, dict[element: "Widths"]), widths.type == .array {
        let first = number(context, dict[element: "FirstChar"]).map(Int.init) ?? 0
        for (offset, value) in widths.iterValues.enumerated() {
            if let width = number(context, value) { font.widths[first + offset] = width * scale }
        }
        font.defaultWidth = (number(context, descriptor?[element: "MissingWidth"]) ?? 0) * scale
        if font.defaultWidth == 0 {
            font.defaultWidth = number(context, descriptor?[element: "AvgWidth"]) ?? 500
        }
    } else if let standardName = standardName {
        font.standardWidths = standardFontWidths[standardName]
        font.defaultWidth = standardName.hasPrefix("Courier") ? 600 : 500
    } else {
        font.defaultWidth = number(context, descriptor?[element: "AvgWidth"])
            ?? number(context, descriptor?[element: "MissingWidth"]) ?? 500
    }
    return font
}
