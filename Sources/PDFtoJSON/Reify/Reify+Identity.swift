import Foundation
import Spanker
import Hitch

@usableFromInline
func reify(document: JsonElement,
           id: Int,
           generation: Int,
           objectInfo: JsonElement,
           parentInfo: JsonElement,
           unknown content: HalfHitch) -> JsonElement? {
    
    //print(objectInfo)
    //print(parentInfo)
    
    // Given some content, parse it out.
    if isXRef(objectInfo) {
        return reify(document: document,
                     id: id,
                     generation: generation,
                     info: objectInfo,
                     xref: content)
    }
    
    if isImage(objectInfo) {
        return reify(document: document,
                     id: id,
                     generation: generation,
                     image: content)
    }
    
    if isCMap(content) {
        return reify(document: document,
                     id: id,
                     generation: generation,
                     cMap: content)
    }
    
    if isPostScript(content) {
        return reify(document: document,
                     id: id,
                     generation: generation,
                     postScript: content)
    }
    
    return nil
}
