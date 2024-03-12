import Foundation
import Spanker
import Hitch

@inlinable
func getArray(_ ptr: inout UnsafePointer<UInt8>,
              _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard ptr[0] == .openBrace else { return nil }
    
    let results = JsonElement(unknown: [])
    
    ptr += 1
    while true {
        guard ptr[0] != .closeBrace else { break }
        guard ptr[0].isWhitspace() == false else { ptr += 1; continue }
        guard let nextObject = getObject(&ptr, end) else { break }
        results.append(value: nextObject)
    }
    
    ptr += 1
    return results
}