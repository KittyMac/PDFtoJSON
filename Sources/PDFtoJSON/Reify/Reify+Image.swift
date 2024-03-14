import Foundation
import Spanker
import Hitch

@inlinable
func isImage(_ info: JsonElement) -> Bool {
    return info[hitch: "Subtype"] == "Image" || info[element: "Width"] != nil || info[element: "Height"] != nil
}

@inlinable
func reify(document: JsonElement,
           id: Int,
           generation: Int,
           image content: HalfHitch) -> JsonElement? {
    return ^[
        "Image", true
    ]
}
