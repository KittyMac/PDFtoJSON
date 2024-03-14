import Foundation
import Spanker
import Hitch

@inlinable
func getObjectDefinition(document: JsonElement,
                         id: Int,
                         generation: Int,
                         _ ptr: inout UnsafePointer<UInt8>,
                         _ start: UnsafePointer<UInt8>,
                         _ end: UnsafePointer<UInt8>) -> JsonElement? {
    var value = JsonElement.null()
    
    // advance until obj\n
    while ptr < end {
        if ptr[0] == .o,
           ptr[1] == .b,
           ptr[2] == .j,
           ptr[3].isWhitspace() {
            ptr += 4
            break
        }
        ptr += 1
    }
    
    while ptr < end {
        if ptr[0] == .e,
           ptr[1] == .n,
           ptr[2] == .d,
           ptr[3] == .o,
           ptr[4] == .b,
           ptr[5] == .j {
            ptr += 6
            break
        }
        
        guard ptr[0].isWhitspace() == false else { ptr += 1; continue }
        guard let nextObject = getObject(document: document,
                                         id: id,
                                         generation: generation, &ptr, start, end) else { break }
        value = nextObject
    }
    
    let results = JsonElement(unknown: [:])
    results.set(key: "id", value: id)
    results.set(key: "generation", value: generation)
    results.set(key: "value", value: value)
    return results
}
