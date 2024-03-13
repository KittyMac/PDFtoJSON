import Foundation
import Spanker
import Hitch
import SWCompression

@inlinable
func getPostScript(_ hitch: HalfHitch) -> JsonElement? {
    // Given a postscript string, extract all text renders and their positioning
    
    // TODO: actually handle the postscript movement and transformations. For now, just find
    // all strings and output them...
    
    let strings = JsonElement(unknown: [])
    
    
    guard var ptr = hitch.raw() else { return fail("failed to get raw for postscript") }
    let start = ptr
    let end = ptr + hitch.count
    
    while ptr < end {
        if ptr[0] == .parenOpen {
            if let string = getString(&ptr, start, end) {
                strings.append(value: string)
            }
        }
        
        ptr += 1
    }
    
    return strings
}
