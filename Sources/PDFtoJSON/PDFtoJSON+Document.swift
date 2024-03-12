import Foundation
import Spanker
import Hitch

@inlinable
func reify(document: JsonElement,
           reference: JsonElement?) -> JsonElement? {
    guard let reference = reference else { return nil }
    guard let id = reference[int: "id"] else { return reference }
    guard let objects = document[element: "objects"] else { return fail("document has no objects") }
    return objects[element: "{0}" << [id]]
}
