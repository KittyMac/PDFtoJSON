import Foundation
import Spanker
import Hitch

@inlinable
func reify(document: JsonElement,
           reference: JsonElement?,
           _ start: UnsafePointer<UInt8>,
           _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard let reference = reference else { return nil }
    guard let id = reference[int: "id"] else { return reference }
    return reify(document: document, id: id, start, end)
}


@inlinable
func reify(document: JsonElement,
           id: Int,
           _ start: UnsafePointer<UInt8>,
           _ end: UnsafePointer<UInt8>) -> JsonElement? {
    guard let objects = document[element: "objects"] else { return fail("document has no objects") }
    
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
                                        generation: generation, &objectPtr, start, end) else { return fail("failed to load xref object \(id)") }
        
        objects.set(key: objectId, value: newObject)
        return newObject[element: "value"]
    }
    return object[element: "value"]
}
