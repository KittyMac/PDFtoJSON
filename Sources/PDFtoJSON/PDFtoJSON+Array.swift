import Foundation
import Spanker
import Hitch

@inlinable
func getArray(document: JsonElement,
              _ ptr: inout UnsafePointer<UInt8>,
              _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard ptr[0] == .openBrace else { return fail("array not on open brace") }
    
    let results = JsonElement(unknown: [])
    
    ptr += 1
    while ptr < end {
        guard ptr[0] != .closeBrace else { break }
        guard ptr[0].isDelimiter() == false else { ptr += 1; continue }
        guard let nextObject = getObject(document: document, &ptr, end) else { break }
        results.append(value: nextObject)
    }
    
    ptr += 1
    return results
}
