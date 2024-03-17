import Foundation
import Spanker
import Hitch

func getDictionary(document: JsonElement,
                   id: Int,
                   generation: Int,
                   _ ptr: inout UnsafePointer<UInt8>,
                   _ start: UnsafePointer<UInt8>,
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
        
        // NOTE: comments will return nil
        if let titleObject = getObject(document: document,
                                       id: id,
                                       generation: generation,
                                       &ptr, start, end) {
            guard let titleString = titleObject.halfHitchValue else { break }
            guard let valueObject = getObject(document: document,
                                              id: id,
                                              generation: generation,
                                              &ptr, start, end) else { break }
            results.set(key: titleString, value: valueObject)
        }
    }
    
    // Recognize specific dictionaries and put them into a lookup table
    if let fonts = results[element: "Font"] {
        let documentFonts = document[element: "fonts"] ?? ^[:]
        for (key, font) in fonts.iterWalking {
            documentFonts.set(key: key,
                              value: reify(document: document,
                                           font: font,
                                           start, end))
        }
        document.set(key: "fonts", value: documentFonts)
    }
    
    if let type = results[hitch: "Type"] {
        if type == "Page" {
            let documentPages = document[element: "pages"] ?? ^[]
                        
            documentPages.append(value: reify(document: document,
                                              page: results,
                                              start, end))
            
            document.set(key: "pages", value: documentPages)
        }
    }
    
    
    return results
}
