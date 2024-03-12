import Foundation
import Spanker
import Hitch

// TODO: move to hitch
public extension UInt8 {
    @inlinable
    func htod() -> UInt8 {
        if self >= .zero && self <= .nine {
            return self - .zero
        } else if self >= .a && self <= .z {
            return self - .a + 10
        } else if self >= .A && self <= .Z {
            return self - .A + 10
        }
        return 0
    }
    
    @inlinable
    func isWhitspace() -> Bool {
        switch self {
        case .space, .newLine, .carriageReturn, .tab:
            return true
        default:
            return false
        }
    }
}

@inlinable
func getHexstring(_ ptr: inout UnsafePointer<UInt8>,
                  _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard ptr[0] == .lessThan else { return nil }
    
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
    return JsonElement(unknown: string)
}
