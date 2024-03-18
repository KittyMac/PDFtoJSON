import Foundation
import Spanker
import Hitch

func reify(document: JsonElement,
           reference: JsonElement?,
           parentInfo: JsonElement,
           _ start: UnsafePointer<UInt8>,
           _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard let reference = reference else { return nil }
    guard let id = reference[int: "id"] else { return reference }
    return reify(document: document,
                 id: id,
                 parentInfo: reference,
                 start, end)
}

func reify(document: JsonElement,
           id: Int,
           parentInfo: JsonElement,
           _ start: UnsafePointer<UInt8>,
           _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard let objects = document[element: "objects"] else { return nil }
    
    let objectId = "{0}" << [id]
    guard let object = objects[element: objectId] else {
        
        guard let xref = document[element: "xref"] else { return fail("document has no xref") }
        guard let xrefValue = xref[element: "{0}" << [id]] else { return fail("object ref missing") }
        guard xrefValue.type != .null else { return nil }
        guard let offset = xrefValue[int: "offset"] else { return fail("missing xref offset") }
        guard let generation = xrefValue[int: "generation"] else { return fail("missing xref generation") }

        var objectPtr = start + offset
        guard let newObject = getObject(document: document,
                                        id: id,
                                        generation: generation,
                                        parentInfo: parentInfo,
                                        &objectPtr, start, end) else { return fail("failed to load xref object \(id)") }
        
        objects.set(key: objectId, value: newObject)
        return newObject[element: "value"]
    }
    return object[element: "value"]
}

func reify(document: JsonElement,
           font: JsonElement?,
           _ start: UnsafePointer<UInt8>,
           _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard let font = reify(document: document,
                           reference: font,
                           parentInfo: document,
                           start, end) else { return font }
    
    if let toUnicode = reify(document: document,
                             reference: font[element: "ToUnicode"],
                             parentInfo: font,
                             start, end) {
        font.set(key: "ToUnicode",
                 value: toUnicode)
    }
    
    if let fontDescriptor = reify(document: document,
                                  reference: font[element: "FontDescriptor"],
                                  parentInfo: font,
                                  start, end) {
        font.set(key: "FontDescriptor",
                 value: fontDescriptor)
    }
    
    return font
}

func reify(document: JsonElement,
           page: JsonElement?,
           _ start: UnsafePointer<UInt8>,
           _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard let page = reify(document: document,
                           reference: page,
                           parentInfo: document,
                           start, end) else { return page }
    
    let textContent = ^[]
    let width = page[element: "MediaBox"]?[double: 2] ?? 0
    let height = page[element: "MediaBox"]?[double: 3] ?? 0
    
    // Force resources to be loaded (to ensure things
    // like fonts are loaded before we parse content)
    _ = reify(document: document,
              reference: page[element: "Resources"],
              parentInfo: page,
              start, end)
    
    // Load the contents
    if let pageContents = page[element: "Contents"] {
        var pageContentsArray: [JsonElement] = []
        if pageContents.type != .array {
            pageContentsArray.append(pageContents)
        } else {
            for pageContent in pageContents.iterValues {
                pageContentsArray.append(pageContent)
            }
        }
        
        for pageContent in pageContentsArray {
            if let contents = reify(document: document,
                                    reference: pageContent,
                                    parentInfo: page,
                                    start, end),
               let texts = contents[element: "content"],
               texts.type == .array {
                for text in texts.iterValues {
                    textContent.append(value: text)
                }
            }
        }
    }
    
    return ^[
        "text": textContent,
        "width": width,
        "height": height
    ]
}
