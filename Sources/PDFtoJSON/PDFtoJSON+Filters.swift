import Foundation
import Spanker
import Hitch
import Gzip

#if canImport(zlibLinux)
import zlibLinux
#elseif canImport(zlib)
import zlib
#endif

// Stream filters (ISO 32000-1, 7.4). Decoding is lenient: damaged data yields
// whatever could be decoded rather than nothing.

/// Filters whose output is image data we don't interpret; decoding stops before them.
private let imageFilters: Set<HalfHitch> = [
    "DCTDecode", "DCT", "JPXDecode", "CCITTFaxDecode", "CCF", "JBIG2Decode"
]

/// The (filter, parameters) pairs of a stream, in order.
func streamFilters(_ context: PDFContext?,
                   _ streamInfo: JsonElement) -> [(HalfHitch, JsonElement?)] {
    var names: [HalfHitch] = []
    var parms: [JsonElement?] = []

    let filter = context.map { resolve($0, streamInfo[element: "Filter"]) } ?? streamInfo[element: "Filter"]
    if let filter = filter {
        if filter.type == .array {
            for name in filter.iterValues {
                if let name = name.halfHitchValue { names.append(name) }
            }
        } else if let name = filter.halfHitchValue {
            names.append(name)
        }
    }

    let decodeParms = context.map { resolve($0, streamInfo[element: "DecodeParms"]) } ?? streamInfo[element: "DecodeParms"]
    if let decodeParms = decodeParms {
        if decodeParms.type == .array {
            for parm in decodeParms.iterValues {
                let resolved = context.map { resolve($0, parm) } ?? parm
                parms.append(resolved?.type == .dictionary ? resolved : nil)
            }
        } else if decodeParms.type == .dictionary {
            parms.append(decodeParms)
        }
    }

    return names.enumerated().map { (idx, name) in
        (name, idx < parms.count ? parms[idx] : nil)
    }
}

/// Apply the stream's filters. Image codecs are left encoded.
/// Returns nil only if a filter is unknown.
func decodeFilters(_ context: PDFContext?,
                   _ filters: [(HalfHitch, JsonElement?)],
                   _ data: Hitch) -> Hitch? {
    var data = data
    for (name, parms) in filters {
        if imageFilters.contains(name) {
            return data
        }
        switch name {
        case "FlateDecode", "Fl":
            data = predict(flateDecode(data), parms)
        case "LZWDecode", "LZW":
            let earlyChange = parms?[int: "EarlyChange"] ?? 1
            data = predict(lzwDecode(data, earlyChange: earlyChange != 0), parms)
        case "ASCIIHexDecode", "AHx":
            data = asciiHexDecode(data)
        case "ASCII85Decode", "A85":
            data = ascii85Decode(data)
        case "RunLengthDecode", "RL":
            data = runLengthDecode(data)
        case "Crypt":
            // handled by the security handler before filtering
            continue
        default:
            context?.warn("unsupported stream filter \(name)")
            return nil
        }
    }
    return data
}

// MARK: - Flate

/// Inflate zlib (or raw deflate) data. On a corrupt or truncated stream, returns
/// everything that was decoded before the error.
func flateDecode(_ input: Hitch) -> Hitch {
    #if canImport(zlibLinux) || canImport(zlib)
    guard input.count > 0, let inputRaw = input.raw() else { return Hitch() }

    func run(windowBits: Int32) -> (Hitch, Bool) {
        let output = Hitch(capacity: max(input.count * 4, 1024))
        var stream = z_stream()
        guard inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return (output, false)
        }
        defer { inflateEnd(&stream) }

        stream.next_in = UnsafeMutablePointer(mutating: inputRaw)
        stream.avail_in = uInt(input.count)

        let chunkSize = 64 * 1024
        let chunk = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { chunk.deallocate() }

        var status: Int32 = Z_OK
        repeat {
            stream.next_out = chunk
            stream.avail_out = uInt(chunkSize)
            status = inflate(&stream, Z_NO_FLUSH)
            let produced = chunkSize - Int(stream.avail_out)
            if produced > 0 {
                output.append(UnsafePointer(chunk), count: produced)
            }
        } while status == Z_OK && (stream.avail_in > 0 || stream.avail_out == 0)

        return (output, status == Z_STREAM_END || status == Z_OK || status == Z_BUF_ERROR)
    }

    // zlib header first (the normal case); fall back to raw deflate for writers that omit it
    let (zlibOutput, ok) = run(windowBits: MAX_WBITS + 32)
    if zlibOutput.count > 0 || ok {
        return zlibOutput
    }
    return run(windowBits: -MAX_WBITS).0
    #else
    if let data = try? input.dataNoCopy().gunzipped() {
        return Hitch(data: data)
    }
    return Hitch()
    #endif
}

// MARK: - Predictors

/// Undo a TIFF (2) or PNG (10-15) predictor described by DecodeParms.
func predict(_ data: Hitch, _ parms: JsonElement?) -> Hitch {
    guard let parms = parms else { return data }
    let predictor = parms[int: "Predictor"] ?? 1
    guard predictor >= 2 else { return data }

    let colors = max(1, parms[int: "Colors"] ?? 1)
    let bpc = max(1, parms[int: "BitsPerComponent"] ?? 8)
    let columns = max(1, parms[int: "Columns"] ?? 1)
    let bpp = max(1, (colors * bpc + 7) / 8)
    let rowBytes = (colors * bpc * columns + 7) / 8
    guard rowBytes > 0, let input = data.raw() else { return data }

    if predictor == 2 {
        return tiffPredictor(input, data.count, rowBytes: rowBytes, colors: colors, bpc: bpc)
    }
    return pngPredictor(input, data.count, rowBytes: rowBytes, bpp: bpp)
}

private func pngPredictor(_ input: UnsafePointer<UInt8>,
                          _ count: Int,
                          rowBytes: Int,
                          bpp: Int) -> Hitch {
    let rows = count / (rowBytes + 1)
    let output = Hitch(capacity: rows * rowBytes)
    var previous = [UInt8](repeating: 0, count: rowBytes)
    var current = [UInt8](repeating: 0, count: rowBytes)

    for row in 0..<rows {
        let rowStart = input + row * (rowBytes + 1)
        let filterType = rowStart[0]
        let src = rowStart + 1
        for x in 0..<rowBytes {
            let raw = src[x]
            let a: UInt8 = x >= bpp ? current[x - bpp] : 0
            let b: UInt8 = previous[x]
            let c: UInt8 = x >= bpp ? previous[x - bpp] : 0
            switch filterType {
            case 1: // Sub
                current[x] = raw &+ a
            case 2: // Up
                current[x] = raw &+ b
            case 3: // Average
                current[x] = raw &+ UInt8((Int(a) + Int(b)) / 2)
            case 4: // Paeth
                let p = Int(a) + Int(b) - Int(c)
                let pa = abs(p - Int(a))
                let pb = abs(p - Int(b))
                let pc = abs(p - Int(c))
                let predictor = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)
                current[x] = raw &+ predictor
            default: // None
                current[x] = raw
            }
        }
        output.append(current, count: rowBytes)
        swap(&previous, &current)
    }
    return output
}

private func tiffPredictor(_ input: UnsafePointer<UInt8>,
                           _ count: Int,
                           rowBytes: Int,
                           colors: Int,
                           bpc: Int) -> Hitch {
    let output = Hitch(capacity: count)
    // Only 8 bits per component is common; other depths are passed through
    guard bpc == 8 else {
        output.append(input, count: count)
        return output
    }
    var row = [UInt8](repeating: 0, count: rowBytes)
    var offset = 0
    while offset + rowBytes <= count {
        for x in 0..<rowBytes {
            row[x] = x >= colors ? input[offset + x] &+ row[x - colors] : input[offset + x]
        }
        output.append(row, count: rowBytes)
        offset += rowBytes
    }
    return output
}

// MARK: - LZW

func lzwDecode(_ data: Hitch, earlyChange: Bool) -> Hitch {
    guard let input = data.raw() else { return Hitch() }
    let output = Hitch(capacity: data.count * 3)

    var table: [[UInt8]] = (0..<256).map { [UInt8($0)] }
    table.append([]) // 256: clear
    table.append([]) // 257: end of data
    var codeLength = 9
    var previous: [UInt8]? = nil

    var bitBuffer = 0
    var bitCount = 0
    var index = 0

    while true {
        while bitCount < codeLength && index < data.count {
            bitBuffer = (bitBuffer << 8) | Int(input[index])
            bitCount += 8
            index += 1
        }
        guard bitCount >= codeLength else { break }
        bitCount -= codeLength
        let code = (bitBuffer >> bitCount) & ((1 << codeLength) - 1)
        bitBuffer &= (1 << bitCount) - 1

        if code == 256 {
            table.removeSubrange(258...)
            codeLength = 9
            previous = nil
            continue
        }
        if code == 257 {
            break
        }

        var entry: [UInt8]
        if code < table.count {
            entry = table[code]
        } else if let previous = previous, code == table.count {
            entry = previous + [previous[0]]
        } else {
            break // corrupt
        }
        output.append(entry, count: entry.count)

        if let previous = previous, table.count < 4096 {
            table.append(previous + [entry[0]])
        }
        previous = entry

        let threshold = earlyChange ? table.count + 1 : table.count
        if threshold >= (1 << codeLength) && codeLength < 12 {
            codeLength += 1
        }
    }
    return output
}

// MARK: - ASCII filters

func asciiHexDecode(_ data: Hitch) -> Hitch {
    let output = Hitch(capacity: data.count / 2 + 1)
    var high: UInt8? = nil
    for c in data {
        if c == .greaterThan { break }
        guard let value: UInt8 = hex(c) else { continue } // whitespace and junk are ignored
        if let h = high {
            output.append(h << 4 | value)
            high = nil
        } else {
            high = value
        }
    }
    if let h = high {
        output.append(h << 4)
    }
    return output
}

func ascii85Decode(_ data: Hitch) -> Hitch {
    let output = Hitch(capacity: data.count)
    var group: [UInt32] = []
    group.reserveCapacity(5)

    func flush(_ group: [UInt32], _ bytes: Int) {
        var value: UInt32 = 0
        for idx in 0..<5 {
            value = value &* 85 &+ (idx < group.count ? group[idx] : 84)
        }
        for idx in 0..<bytes {
            output.append(UInt8((value >> UInt32(24 - idx * 8)) & 0xFF))
        }
    }

    var bytes = Array(data)
    // optional "<~" prefix
    if bytes.count >= 2 && bytes[0] == .lessThan && bytes[1] == 0x7E {
        bytes.removeFirst(2)
    }
    for c in bytes {
        if c == 0x7E { break } // "~>" end of data
        if c == 0x7A && group.isEmpty { // 'z' = four zero bytes
            output.append(0); output.append(0); output.append(0); output.append(0)
            continue
        }
        guard c >= 0x21 && c <= 0x75 else { continue }
        group.append(UInt32(c - 0x21))
        if group.count == 5 {
            flush(group, 4)
            group.removeAll(keepingCapacity: true)
        }
    }
    if group.count > 1 {
        flush(group, group.count - 1)
    }
    return output
}

func runLengthDecode(_ data: Hitch) -> Hitch {
    let output = Hitch(capacity: data.count * 2)
    guard let input = data.raw() else { return output }
    var idx = 0
    while idx < data.count {
        let length = Int(input[idx])
        idx += 1
        if length == 128 { break }
        if length < 128 {
            let count = min(length + 1, data.count - idx)
            output.append(input + idx, count: count)
            idx += count
        } else if idx < data.count {
            let byte = input[idx]
            for _ in 0..<(257 - length) { output.append(byte) }
            idx += 1
        }
    }
    return output
}
