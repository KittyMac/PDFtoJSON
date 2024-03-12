import Foundation
import Spanker
import Hitch

@inlinable
func getString(_ ptr: inout UnsafePointer<UInt8>,
               _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard ptr[0] == .parenOpen else { return fail("string not on open paren") }
    
    let start = ptr
    
    // find the whole string content first to find the capacity
    var parenLevel = 0
    ptr += 1
    while ptr < end {
        if ptr[0] == .backSlash {
            ptr += 1
        } else if ptr[0] == .parenOpen {
            parenLevel += 1
        } else if ptr[0] == .parenClose {
            if parenLevel <= 0 {
                break
            }
            parenLevel -= 1
        }
        ptr += 1
    }
        
    let string = Hitch(capacity: ptr - start)
    
    // run through it again unescaping characters
    var ptr2 = start + 1
    while ptr2 < ptr {
        if ptr2[0] == .backSlash {
            switch ptr2[1] {
            case .newLine, .carriageReturn: break
            case .n: string.append(.newLine)
            case .r: string.append(.carriageReturn)
            case .t: string.append(.tab)
            case .b: string.append(.backspace)
            case .f: string.append(.formFeed)
            case .parenOpen: string.append(.parenOpen)
            case .parenClose: string.append(.parenClose)
            case .backSlash: string.append(.backSlash)
            case .zero, .one, .two, .three, .four, .five, .six, .seven:
                var value = Int(ptr2[1] - .zero)
                if ptr2[2] >= .zero && ptr2[2] <= .seven {
                    value *= 8
                    value += Int(ptr2[2] - .zero)
                    ptr2 += 1
                    if ptr2[2] >= .zero && ptr2[2] <= .seven {
                        value *= 8
                        value += Int(ptr2[2] - .zero)
                        ptr2 += 1
                    }
                }
                if let scalar = UnicodeScalar(value) {
                    for v in Character(scalar).utf8 {
                        string.append(v)
                    }
                }
                break
            default: break
            }
            ptr2 += 2
        } else {
            string.append(ptr2.pointee)
            ptr2 += 1
        }
    }
    
    ptr += 1
    return JsonElement(unknown: string)
}
