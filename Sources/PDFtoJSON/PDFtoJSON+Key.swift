import Foundation
import Spanker
import Hitch

@inlinable
func getKey(_ ptr: inout UnsafePointer<UInt8>,
               _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard ptr[0] == .forwardSlash else { return nil }
    
    ptr += 1
    let start = ptr
    while ptr < end {
        guard ptr[0].isWhitspace() == false else { break }
        ptr += 1
    }
    
    return JsonElement(unknown: HalfHitch(sourceObject: nil,
                                          raw: start,
                                          count: ptr - start,
                                          from: 0,
                                          to: ptr - start))
}
