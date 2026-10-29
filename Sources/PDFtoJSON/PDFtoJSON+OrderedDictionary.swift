import Foundation
import Spanker
import Hitch

/// A JSON dictionary built in a given key order in O(n).
/// (JsonElement.set(key:) searches existing keys, so building large tables with it is quadratic.)
struct OrderedJsonDictionary: JsonElementable {
    var keys: [HalfHitch] = []
    var values: [JsonElement] = []

    mutating func append(key: HalfHitch, value: JsonElement) {
        keys.append(key)
        values.append(value)
    }

    func toJsonElement() -> JsonElement {
        return JsonElement(unknown: self)
    }

    func fillJsonElement(internalType: inout JsonType,
                         valueInt: inout Int,
                         valueDouble: inout Double,
                         valueString: inout HalfHitch,
                         valueArray: inout [JsonElement],
                         keyArray: inout [HalfHitch]) {
        internalType = .dictionary
        keyArray = keys
        valueArray = values
    }
}
