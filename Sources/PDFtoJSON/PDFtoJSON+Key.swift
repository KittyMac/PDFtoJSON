import Foundation
import Spanker
import Hitch

func getKey(_ ptr: inout UnsafePointer<UInt8>,
            _ start: UnsafePointer<UInt8>,
            _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard ptr[0] == .forwardSlash else { return fail("key not on forward slash") }
    
    ptr += 1
    let start = ptr
    while ptr < end {
        guard ptr[0].isDelimiter() == false else { break }
        ptr += 1
    }
    
    return JsonElement(unknown: HalfHitch(sourceObject: nil,
                                          raw: start,
                                          count: ptr - start,
                                          from: 0,
                                          to: ptr - start))
}
