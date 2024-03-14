import Foundation
import Spanker
import Hitch

@inlinable
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

@inlinable
func reify(document: JsonElement,
           id: Int,
           parentInfo: JsonElement,
           _ start: UnsafePointer<UInt8>,
           _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard let objects = document[element: "objects"] else { return nil }
    
    let objectId = "{0}" << [id]
    guard let object = objects[element: objectId] else {
        
        // load the document object
        // preload all xref objects
        guard let xref = document[element: "xref"] else { return fail("document has no xref") }
        guard let xrefValue = xref[element: "{0}" << [id]] else { return fail("object ref missing") }
        guard xrefValue.type != .null else { return nil }
        guard let offset = xrefValue[int: "offset"] else { return fail("missing xref offset") }
        guard let generation = xrefValue[int: "generation"] else { return fail("missing xref generation") }

        var objectPtr = start + offset
        guard let newObject = getObject(document: document,
                                        id: id,
                                        generation: generation,
                                        parentInfo: parentInfo, &objectPtr, start, end) else { return fail("failed to load xref object \(id)") }
        
        objects.set(key: objectId, value: newObject)
        return newObject[element: "value"]
    }
    return object[element: "value"]
}

@inlinable
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
    
    return font
}

@inlinable
func reify(document: JsonElement,
           page: JsonElement?,
           _ start: UnsafePointer<UInt8>,
           _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard let page = reify(document: document,
                           reference: page,
                           parentInfo: document,
                           start, end) else { return page }
    
    // TODO: what we really want to do it extract strings and
    // put it into a new page object based on the contents
    let textContent = ^[]
    let width = page[element: "MediaBox"]?[int: 2] ?? 0
    let height = page[element: "MediaBox"]?[int: 3] ?? 0
    
    // Force resources to be loaded (to ensure things
    // like fonts are loaded before we parse content)
    _ = reify(document: document,
              reference: page[element: "Resources"],
              parentInfo: page,
              start, end)
    
    // Load the contents
    if let contents = reify(document: document,
                            reference: page[element: "Contents"],
                            parentInfo: page,
                            start, end),
       let texts = contents[element: "content"],
       texts.type == .array {
        for text in texts.iterValues {
            textContent.append(value: text)
        }
    }
    
    return ^[
        "text": textContent,
        "width": width,
        "height": height
    ]
}
