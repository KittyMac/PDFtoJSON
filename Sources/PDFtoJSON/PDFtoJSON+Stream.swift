import Foundation
import Spanker
import Hitch
import SWCompression

fileprivate func predictorPNG(bpp: Int,
                              rowBytes: Int,
                              _ start: UnsafeMutablePointer<UInt8>,
                              _ end: UnsafeMutablePointer<UInt8>) {
    // https://www.w3.org/TR/PNG-Filters.html
    // Each row is:
    // 1-byte: predictor algo used for this row
    // row bytes amount of data
    var readPtr = start
    var readPPtr = start + 1
    var writePtr = start
    while readPtr < end {
        // advance past the algo identifier
        readPtr += 1
        
        switch readPtr[-1] {
        case 1, 11: // Sub
            for idx in 0..<rowBytes {
                writePtr[idx] = readPtr[idx] &+ readPtr[idx - bpp]
                // print(String(format: "sub: %u = %u + %u", writePtr[idx], readPtr[idx], readPtr[idx - bpp]))
            }
            break
        case 2, 12: // Up
            if readPtr == start + 1 {
                for idx in 0..<rowBytes {
                    writePtr[idx] = readPtr[idx]
                    // print(String(format: "up: %u = %u + 0", writePtr[idx], readPtr[idx]))
                }
            } else {
                for idx in 0..<rowBytes {
                    writePtr[idx] = readPtr[idx] &+ readPPtr[idx]
                    // print(String(format: "up: %u = %u + %u", writePtr[idx], readPtr[idx], readPPtr[idx]))
                }
            }
            break
        case 3, 13: // Avg
            fatalError("TO BE IMPEMENTED")
            break
        case 4, 14: // Paeth
            fatalError("TO BE IMPEMENTED")
            break
        default: // 0, 10: None
            for idx in 0..<rowBytes {
                writePtr[idx] = readPtr[idx]
                // print(String(format: "none: %u = %u + 0", writePtr[idx], readPtr[idx]))
            }
            break
        }
        
        // previous pointer points to the unfiltered bytes of the previous row
        readPPtr = writePtr
        
        // advance the ptr to the algo identifier on the next row
        writePtr += rowBytes
        readPtr += rowBytes
    }
}

func getStream(document: JsonElement,
               id: Int,
               generation: Int,
               streamInfo: JsonElement,
               parentInfo: JsonElement,
               _ ptr: inout UnsafePointer<UInt8>,
               _ start: UnsafePointer<UInt8>,
               _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard ptr + 6 <= end,
          ptr[0] == .s,
          ptr[1] == .t,
          ptr[2] == .r,
          ptr[3] == .e,
          ptr[4] == .a,
          ptr[5] == .m else {
        return fail("stream not on open stream")
    }
    ptr += 6
    
    if ptr[0] == .carriageReturn {
        ptr += 1
    }
    guard ptr[0] == .lineFeed else { return fail("stream does not have a newline") }
    ptr += 1
    
    guard let lengthObj = reify(document: document,
                                reference: streamInfo[element: "Length"],
                                parentInfo: parentInfo,
                                start, end) else { return fail("failed to reify length") }
    guard let length = lengthObj.intValue else { return fail("failed to get stream length") }
        
    var streamContent = HalfHitch(sourceObject: nil,
                                  raw: ptr,
                                  count: length,
                                  from: 0,
                                  to: length)

    let (error, newStreamContent) = decrypt(document: document,
                                            id: id,
                                            generation: generation,
                                            content: streamContent)
    if let error = error {
        return fail(error)
    }
    
    streamContent = newStreamContent ?? streamContent
    
    if let filter = streamInfo[halfhitch: "Filter"] {
        if filter == "FlateDecode" {
            var rowBytes = 0
            var bpp = 0
            var predictor = 0
            if let decodeParams = streamInfo[element: "DecodeParms"] {
                predictor = decodeParams[int: "Predictor"] ?? 0
                if predictor >= 10 && predictor <= 15 {
                    let bpc = decodeParams[int: "BitsPerComponent"] ?? 8
                    let colors = decodeParams[int: "Colors"] ?? 1
                    let columns = decodeParams[int: "Columns"] ?? 1
                    bpp = (bpc * colors + 7) / 8
                    rowBytes = (bpc * colors * columns + 7) / 8
                }
            }
                
            if let decompressed = try? ZlibArchive.unarchive(archive: streamContent.dataNoCopy()) {
                let dataAsHitch = Hitch(data: decompressed)
                
                // PNG predictor
                if predictor >= 10 && predictor <= 15,
                   let start = dataAsHitch.mutableRaw() {
                    let end = start + dataAsHitch.count
                    predictorPNG(bpp: bpp,
                                 rowBytes: rowBytes,
                                 start, end)
                }
                
                streamContent = dataAsHitch.halfhitch()
            }
        }
    }
    
    if let content = reify(document: document,
                           id: -1,
                           generation: -1,
                           objectInfo: streamInfo,
                           parentInfo: parentInfo,
                           unknown: streamContent) {
        streamInfo.set(key: "content", value: content)
        //streamInfo.set(key: "__content", value: streamContent.base64Encoded())
    } else {
        //streamInfo.set(key: "__content", value: streamContent.base64Encoded())
    }
        
    ptr += length
    
    while ptr < end && ptr[0].isWhitspace() {
        ptr += 1
    }
    
    guard ptr + 9 <= end,
          ptr[0] == .e,
          ptr[1] == .n,
          ptr[2] == .d,
          ptr[3] == .s,
          ptr[4] == .t,
          ptr[5] == .r,
          ptr[6] == .e,
          ptr[7] == .a,
          ptr[8] == .m else {
        return fail("failed to find endstream")
    }
    
    ptr += 9
    
    return streamInfo
}
