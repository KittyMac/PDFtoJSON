import Foundation
import Spanker
import Hitch

extension HalfHitch {
    @inlinable
    func isPrintable() -> Bool {
        return isUTF8()
    }
    
    @inlinable
    func isUTF8() -> Bool {
        guard let data = raw() else { return false }
        var index = 0
        while index < count {
            let byte = data[index]
            if (byte & 0x80) == 0 {
                // Single-byte UTF-8 character
                index += 1
            } else if (byte & 0xE0) == 0xC0 {
                // Two-byte UTF-8 character
                if index + 1 >= count {
                    return false
                }
                if (data[index + 1] & 0xC0) != 0x80 {
                    return false
                }
                index += 2
            } else if (byte & 0xF0) == 0xE0 {
                // Three-byte UTF-8 character
                if index + 2 >= count {
                    return false
                }
                if (data[index + 1] & 0xC0) != 0x80 || (data[index + 2] & 0xC0) != 0x80 {
                    return false
                }
                index += 3
            } else if (byte & 0xF8) == 0xF0 {
                // Four-byte UTF-8 character
                if index + 3 >= count {
                    return false
                }
                if (data[index + 1] & 0xC0) != 0x80 || (data[index + 2] & 0xC0) != 0x80 || (data[index + 3] & 0xC0) != 0x80 {
                    return false
                }
                index += 4
            } else {
                // Invalid UTF-8 byte sequence
                return false
            }
        }
        return true
    }
}

extension Hitch {
    @inlinable
    func isPrintable() -> Bool {
        return isUTF8()
    }
    
    @inlinable
    func isUTF8() -> Bool {
        guard let data = raw() else { return false }
        var index = 0
        while index < count {
            let byte = data[index]
            if (byte & 0x80) == 0 {
                // Single-byte UTF-8 character
                index += 1
            } else if (byte & 0xE0) == 0xC0 {
                // Two-byte UTF-8 character
                if index + 1 >= count {
                    return false
                }
                if (data[index + 1] & 0xC0) != 0x80 {
                    return false
                }
                index += 2
            } else if (byte & 0xF0) == 0xE0 {
                // Three-byte UTF-8 character
                if index + 2 >= count {
                    return false
                }
                if (data[index + 1] & 0xC0) != 0x80 || (data[index + 2] & 0xC0) != 0x80 {
                    return false
                }
                index += 3
            } else if (byte & 0xF8) == 0xF0 {
                // Four-byte UTF-8 character
                if index + 3 >= count {
                    return false
                }
                if (data[index + 1] & 0xC0) != 0x80 || (data[index + 2] & 0xC0) != 0x80 || (data[index + 3] & 0xC0) != 0x80 {
                    return false
                }
                index += 4
            } else {
                // Invalid UTF-8 byte sequence
                return false
            }
        }
        return true
    }
}

@inlinable
func getHexstring(document: JsonElement,
                  id: Int,
                  generation: Int,
                  _ value: HalfHitch) -> JsonElement? {
    guard var ptr = value.raw() else { return nil }
    return getHexstring(document: document,
                        id: id,
                        generation: generation,
                        &ptr,
                        ptr,
                        ptr + value.count)
}

@inlinable
func getHexstring(document: JsonElement,
                  id: Int,
                  generation: Int,
                  _ ptr: inout UnsafePointer<UInt8>,
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
        let hex0: UInt8 = hex(ptr2[0]) ?? 0
        let hex1: UInt8 = ptr2+1 < ptr ? hex(ptr2[1]) ?? 0 : 0
                
        let value = hex0 &* 16 &+ hex1
        string.append(value)
        ptr2 += 2
    }
    
    ptr += 1
    
    let (error, newString) = decrypt(document: document,
                                     id: id,
                                     generation: generation,
                                     content: string.halfhitch())
    guard let newString = newString else { return fail(error ?? "unknown error decrypting hexstring") }
    
    if string.isPrintable() {
        return JsonElement(unknown: newString)
    }
    
    return JsonElement(unknown: newString.base64Encoded())
}

@inlinable
func getHexstringRaw(_ ptr: inout UnsafePointer<UInt8>,
                     _ start: UnsafePointer<UInt8>,
                     _ end: UnsafePointer<UInt8>) -> HalfHitch? {
    guard ptr[0] == .lessThan else { return nil }
    
    let start = ptr
    
    // find the whole string content first to find the capacity
    ptr += 1
    while ptr < end {
        guard ptr[0] != .greaterThan else { break }
        ptr += 1
    }
    
    ptr += 1
    
    return Hitch(bytes: start+1, offset: 0, count: ptr - (start + 2)).halfhitch()
}
