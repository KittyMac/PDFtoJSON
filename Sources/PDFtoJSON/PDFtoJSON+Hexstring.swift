import Foundation
import Spanker
import Hitch

extension HalfHitch {
    @inlinable
    func isPrintable() -> Bool {
        for i in self where i == 0 || i > 127 {
            return false
        }
        return true
    }
}

extension Hitch {
    @inlinable
    func isPrintable() -> Bool {
        for i in self where i == 0 || i > 127 {
            return false
        }
        return true
    }
}

@inlinable
func getHexstring(_ ptr: inout UnsafePointer<UInt8>,
                  _ start: UnsafePointer<UInt8>,
                  _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard ptr[0] == .lessThan else { return fail("hexstring not on open angle brackets") }
    
    let start = ptr
    
    // find the whole string content first to find the capacity
    ptr += 1
    while ptr < end {
        guard ptr[0] != .greaterThan else { break }
        ptr += 1
    }
        
    let string = Hitch(capacity: ptr - start)
    
    // run through it again and convert from hex to binary
    var ptr2 = start + 1
    while ptr2 < ptr {
        let hex0 = ptr2[0].htod()
        let hex1 = ptr2+1 < ptr ? ptr2[1].htod() : 0
                
        let value = hex0 &* 16 &+ hex1
        string.append(value)
        ptr2 += 2
    }
    
    ptr += 1
    
    if string.isPrintable() {
        return JsonElement(unknown: string)
    }
    
    return JsonElement(unknown: string.base64Encoded())
}
