import Foundation
import Spanker
import Hitch

@inlinable
func isPostScript(_ content: HalfHitch) -> Bool {
    return content.contains(" Tf") || content.contains(" Tj")
}

@inlinable
func reify(document: JsonElement,
           id: Int,
           generation: Int,
           postScript content: HalfHitch) -> JsonElement? {
    guard isPostScript(content) else { return nil }
    // Given a postscript string, extract all text renders and their positioning
    
    // TODO: actually handle the postscript movement and transformations. For now, just find
    // all strings and output them...
    
    let strings = JsonElement(unknown: [])
    
    
    guard var ptr = content.raw() else { return fail("failed to get raw for postscript") }
    let start = ptr
    let end = ptr + content.count
    
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
