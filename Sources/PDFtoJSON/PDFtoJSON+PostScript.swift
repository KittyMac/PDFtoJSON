import Foundation
import Spanker
import Hitch
import SWCompression

@inlinable
func getPostScript(document: JsonElement,
                   id: Int,
                   generation: Int,
                   _ hitch: HalfHitch) -> JsonElement? {
    guard hitch.contains("g ") || hitch.contains("G ") else { return nil }
    // Given a postscript string, extract all text renders and their positioning
    
    // TODO: actually handle the postscript movement and transformations. For now, just find
    // all strings and output them...
    
    let strings = JsonElement(unknown: [])
    
    
    guard var ptr = hitch.raw() else { return fail("failed to get raw for postscript") }
    let start = ptr
    let end = ptr + hitch.count
    
    while ptr < end {
        if ptr[0] == .parenOpen {
            if let string = getString(document: document,
                                      id: id,
                                      generation: generation, &ptr, start, end) {
                strings.append(value: string)
            }
        }
        if ptr[0] == .lessThan {
            if let string = getHexstring(document: document,
                                         id: id,
                                         generation: generation, &ptr, start, end) {
                strings.append(value: string)
            }
        }
        
        ptr += 1
    }
    
    return strings
}
