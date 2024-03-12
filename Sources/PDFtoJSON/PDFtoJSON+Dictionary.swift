import Foundation
import Spanker
import Hitch

@inlinable
func getDictionary(_ ptr: inout UnsafePointer<UInt8>,
                   _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard ptr[0] == .lessThan,
          ptr[1] == .lessThan else { return fail("dictionary not on open angle brackets") }
    
    let results = JsonElement(unknown: [:])
    
    ptr += 2
    while ptr < end {
        guard ptr[0].isWhitspace() == false else { ptr += 1; continue }
        
        if ptr[0] == .greaterThan,
           ptr[1] == .greaterThan {
            ptr += 2
            break
        }
        
        guard let titleObject = getObject(&ptr, end) else { break }
        guard let titleString = titleObject.halfHitchValue else { break }
        guard let valueObject = getObject(&ptr, end) else { break }
        
        results.set(key: titleString, value: valueObject)
    }
    
    return results
}
