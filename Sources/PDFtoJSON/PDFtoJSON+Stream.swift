import Foundation
import Spanker
import Hitch
import SWCompression

@inlinable
func getStream(document: JsonElement,
               info: JsonElement,
               _ ptr: inout UnsafePointer<UInt8>,
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
    
    guard let lengthObj = reify(document: document, reference: info[element: "Length"]) else { return fail("failed to reify length") }
    guard let length = lengthObj.intValue else { return fail("failed to get stream length") }
    
    var streamContent = HalfHitch(sourceObject: nil,
                                  raw: ptr,
                                  count: length,
                                  from: 0,
                                  to: length)
        
    // TODO: decrypt / deflate the content
    if let filter = info[halfhitch: "Filter"] {
        if filter == "FlateDecode" {
            if let decompressed = try? ZlibArchive.unarchive(archive: streamContent.dataNoCopy()) {
                streamContent = HalfHitch(data: decompressed)
            }
        }
    }
    
    if streamContent.isPrintable() {
        info.set(key: "__content", value: streamContent)
        
        if let strings = getPostScript(streamContent) {
            info.set(key: "__strings", value: strings)
        }
        
    } else {
        info.set(key: "__content", value: streamContent.base64Encoded())
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
    
    return info
}
