import Foundation
import Spanker
import Hitch

// Conversion of PDF string bytes to UTF-8 text (ISO 32000-1, 7.9.2).

/// PDFDocEncoding -> Unicode; 0 marks codes that are undefined.
let pdfDocEncoding: [UInt16] = [
    0x0000, 0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006, 0x0007, 0x0008, 0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x000E, 0x000F,
    0x0010, 0x0011, 0x0012, 0x0013, 0x0014, 0x0015, 0x0000, 0x0017, 0x02D8, 0x02C7, 0x02C6, 0x02D9, 0x02DD, 0x02DB, 0x02DA, 0x02DC,
    0x0020, 0x0021, 0x0022, 0x0023, 0x0024, 0x0025, 0x0026, 0x0027, 0x0028, 0x0029, 0x002A, 0x002B, 0x002C, 0x002D, 0x002E, 0x002F,
    0x0030, 0x0031, 0x0032, 0x0033, 0x0034, 0x0035, 0x0036, 0x0037, 0x0038, 0x0039, 0x003A, 0x003B, 0x003C, 0x003D, 0x003E, 0x003F,
    0x0040, 0x0041, 0x0042, 0x0043, 0x0044, 0x0045, 0x0046, 0x0047, 0x0048, 0x0049, 0x004A, 0x004B, 0x004C, 0x004D, 0x004E, 0x004F,
    0x0050, 0x0051, 0x0052, 0x0053, 0x0054, 0x0055, 0x0056, 0x0057, 0x0058, 0x0059, 0x005A, 0x005B, 0x005C, 0x005D, 0x005E, 0x005F,
    0x0060, 0x0061, 0x0062, 0x0063, 0x0064, 0x0065, 0x0066, 0x0067, 0x0068, 0x0069, 0x006A, 0x006B, 0x006C, 0x006D, 0x006E, 0x006F,
    0x0070, 0x0071, 0x0072, 0x0073, 0x0074, 0x0075, 0x0076, 0x0077, 0x0078, 0x0079, 0x007A, 0x007B, 0x007C, 0x007D, 0x007E, 0x0000,
    0x2022, 0x2020, 0x2021, 0x2026, 0x2014, 0x2013, 0x0192, 0x2044, 0x2039, 0x203A, 0x2212, 0x2030, 0x201E, 0x201C, 0x201D, 0x2018,
    0x2019, 0x201A, 0x2122, 0xFB01, 0xFB02, 0x0141, 0x0152, 0x0160, 0x0178, 0x017D, 0x0131, 0x0142, 0x0153, 0x0161, 0x017E, 0x0000,
    0x20AC, 0x00A1, 0x00A2, 0x00A3, 0x00A4, 0x00A5, 0x00A6, 0x00A7, 0x00A8, 0x00A9, 0x00AA, 0x00AB, 0x00AC, 0x0000, 0x00AE, 0x00AF,
    0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7, 0x00B8, 0x00B9, 0x00BA, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x00BF,
    0x00C0, 0x00C1, 0x00C2, 0x00C3, 0x00C4, 0x00C5, 0x00C6, 0x00C7, 0x00C8, 0x00C9, 0x00CA, 0x00CB, 0x00CC, 0x00CD, 0x00CE, 0x00CF,
    0x00D0, 0x00D1, 0x00D2, 0x00D3, 0x00D4, 0x00D5, 0x00D6, 0x00D7, 0x00D8, 0x00D9, 0x00DA, 0x00DB, 0x00DC, 0x00DD, 0x00DE, 0x00DF,
    0x00E0, 0x00E1, 0x00E2, 0x00E3, 0x00E4, 0x00E5, 0x00E6, 0x00E7, 0x00E8, 0x00E9, 0x00EA, 0x00EB, 0x00EC, 0x00ED, 0x00EE, 0x00EF,
    0x00F0, 0x00F1, 0x00F2, 0x00F3, 0x00F4, 0x00F5, 0x00F6, 0x00F7, 0x00F8, 0x00F9, 0x00FA, 0x00FB, 0x00FC, 0x00FD, 0x00FE, 0x00FF,
]

extension Hitch {
    /// Append a Unicode scalar as UTF-8.
    func append(scalar value: UInt32) {
        guard let scalar = Unicode.Scalar(value) else { return }
        for byte in String(Character(scalar)).utf8 {
            append(byte)
        }
    }
}

/// Is this valid UTF-8 containing at least one multi-byte sequence?
private func isMultibyteUTF8(_ bytes: UnsafePointer<UInt8>, _ count: Int) -> Bool {
    var idx = 0
    var multibyte = false
    while idx < count {
        let b = bytes[idx]
        var length = 0
        if b < 0x80 { idx += 1; continue }
        else if b & 0xE0 == 0xC0 && b >= 0xC2 { length = 2 }
        else if b & 0xF0 == 0xE0 { length = 3 }
        else if b & 0xF8 == 0xF0 && b <= 0xF4 { length = 4 }
        else { return false }
        guard idx + length <= count else { return false }
        for k in 1..<length where bytes[idx + k] & 0xC0 != 0x80 { return false }
        multibyte = true
        idx += length
    }
    return multibyte
}

/// Decode UTF-16 code units (big or little endian) to UTF-8, skipping
/// language-tag escapes (U+001B ... U+001B).
func decodeUTF16(_ bytes: UnsafePointer<UInt8>, _ count: Int, bigEndian: Bool) -> Hitch {
    let out = Hitch(capacity: count)
    var idx = 0
    var inEscape = false
    func unit(_ i: Int) -> UInt32 {
        return bigEndian ? UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1]) : UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i])
    }
    while idx + 1 < count {
        let u = unit(idx)
        idx += 2
        if u == 0x1B { inEscape.toggle(); continue }
        if inEscape { continue }
        if u >= 0xD800 && u < 0xDC00, idx + 1 < count {
            let low = unit(idx)
            if low >= 0xDC00 && low < 0xE000 {
                idx += 2
                out.append(scalar: 0x10000 + ((u - 0xD800) << 10) + (low - 0xDC00))
                continue
            }
        }
        out.append(scalar: u)
    }
    return out
}

/// Lossless representation of binary data: "<hex digits>".
func hexForm(_ bytes: Hitch) -> Hitch {
    let out = Hitch(capacity: bytes.count * 2 + 2)
    out.append(.lessThan)
    for b in bytes {
        out.append(hex2(b >> 4))
        out.append(hex2(b & 0x0F))
    }
    out.append(.greaterThan)
    return out
}

/// The bytes of a string element: "<hex>" forms are decoded, anything else is returned as-is.
func stringBytes(_ element: JsonElement?) -> Hitch? {
    guard let value = element?.hitchValue else { return nil }
    if value.count >= 2, value[0] == .lessThan, value[value.count - 1] == .greaterThan {
        let inner = Hitch(capacity: value.count)
        for idx in 1..<(value.count - 1) { inner.append(value[idx]) }
        return asciiHexDecode(inner)
    }
    return value
}

/// Convert the bytes of a PDF text string to UTF-8.
/// - UTF-16BE/LE with a byte order mark, or UTF-8 with a BOM
/// - otherwise valid multi-byte UTF-8 (common from non-conforming writers)
/// - otherwise PDFDocEncoding, if every byte is a defined, printable code
/// - otherwise the string is binary and is returned as "<hex>"
func decodeTextString(_ bytes: Hitch) -> Hitch {
    let count = bytes.count
    guard count > 0, let raw = bytes.raw() else { return Hitch() }

    if count >= 2 && raw[0] == 0xFE && raw[1] == 0xFF {
        return decodeUTF16(raw + 2, count - 2, bigEndian: true)
    }
    if count >= 2 && raw[0] == 0xFF && raw[1] == 0xFE {
        return decodeUTF16(raw + 2, count - 2, bigEndian: false)
    }
    if count >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF {
        return Hitch(bytes: raw + 3, offset: 0, count: count - 3)
    }
    if isMultibyteUTF8(raw, count) {
        return bytes
    }

    let out = Hitch(capacity: count + count / 4)
    for idx in 0..<count {
        let b = raw[idx]
        if b < 0x20 {
            guard b == .tab || b == .newLine || b == .carriageReturn || b == 0x0C else { return hexForm(bytes) }
            out.append(b)
        } else if b < 0x7F {
            out.append(b)
        } else {
            let unicode = pdfDocEncoding[Int(b)]
            guard unicode != 0 else { return hexForm(bytes) }
            out.append(scalar: UInt32(unicode))
        }
    }
    return out
}

/// Bytes -> UTF-8 for names: UTF-8 if valid, otherwise Latin-1.
func decodeNameBytes(_ bytes: Hitch) -> Hitch {
    guard let raw = bytes.raw() else { return bytes }
    var ascii = true
    for idx in 0..<bytes.count where raw[idx] >= 0x80 { ascii = false; break }
    if ascii || isMultibyteUTF8(raw, bytes.count) {
        return bytes
    }
    let out = Hitch(capacity: bytes.count * 2)
    for idx in 0..<bytes.count {
        out.append(scalar: UInt32(raw[idx]))
    }
    return out
}
