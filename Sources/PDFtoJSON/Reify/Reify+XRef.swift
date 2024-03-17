import Foundation
import Spanker
import Hitch

func isXRef(_ info: JsonElement) -> Bool {
    return info[hitch: "Type"] == "XRef"
}

fileprivate func ptrTo(_ ptr: inout UnsafePointer<UInt8>,
                       _ size: Int) -> Int {
    var value: Int = 0
    for _ in 0..<size {
        value = value << 8 | Int(ptr[0])
        ptr += 1
    }
    return value
}

func reify(document: JsonElement,
           id: Int,
           generation: Int,
           info: JsonElement,
           xref content: HalfHitch) -> JsonElement? {
    guard let start = content.raw() else { return nil }
    var ptr = start
    let end = start + content.count
    
    // the "W" field means that the xref table is in a binary
    // format.
    // widths[0] is number of bytes for object number
    // widths[1] is number of bytes for generation number
    // widths[2] is number of bytes for status
    guard let widths = info[element: "W"] else {
        let error = getXrefTable(document: document,
                                 &ptr, start, end)
        return ^error
    }
    
    let numObjects = info[int: "Size"] ?? 0
    
    guard let typeSize = widths[int: 0] else { return nil }
    guard let offsetSize = widths[int: 1] else { return nil }
    guard let generationSize = widths[int: 2] else { return nil }
    
    let xref = JsonElement(unknown: ^[:])
    
    var index = 0
    while ptr < end && index < numObjects {
        let type = ptrTo(&ptr, typeSize)
        let offset = ptrTo(&ptr, offsetSize)
        let generation = ptrTo(&ptr, generationSize)
        
        if type == 0 {
            xref.set(key: "{0}" << [index], value: JsonElement.null())
        } else {
            xref.set(key: "{0}" << [index], value: ^[
                "offset": offset,
                "generation": generation
            ])
        }
        
        index += 1
    }
    
    document.set(key: "xref", value: xref)
    document.set(key: "trailer", value: info)
    
    return nil
}
