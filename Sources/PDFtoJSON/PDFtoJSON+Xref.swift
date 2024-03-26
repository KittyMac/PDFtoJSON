import Foundation
import Spanker
import Hitch

func getXrefTable(document: JsonElement,
                  _ ptr: inout UnsafePointer<UInt8>,
                  _ start: UnsafePointer<UInt8>,
                  _ end: UnsafePointer<UInt8>) -> String? {
    guard ptr >= start && ptr < end else { return "invalid xref location" }
    
    // NOTE: can either be embedded xref or a reference to an xref stream.
    if ptr[0] != .x {
        let _ = getObject(document: document, id: -1, generation: -1, &ptr, start, end)
        return nil
    }
    
    let xref = document[element: "xref"] ?? ^[:]
    
    var index = 0
    while ptr < end {
        guard let line = getLine(&ptr, start, end)?.trimmed() else { return "failed to read xref line" }
        if line == "trailer" {
            guard let trailerDict = getDictionary(document: document,
                                                  id: -1,
                                                  generation: -1, &ptr, start, end) else { return "failed to parse trailer dictionary" }
            document.set(key: "trailer", value: trailerDict)
            break
        }
        
        if line == "xref" {
            continue
        }
        
        if line.last == .f {
            // 0000000000 65535 f
            guard let _ = line.substring(0, 10)?.toInt() else { return "malformed xref line: \(line)" }
            guard let _ = line.substring(11, 16)?.toInt() else { return "malformed xref line: \(line)" }

            xref.set(key: "{0}" << [index], value: JsonElement.null())
            
            index += 1
        } else if line.last == .n {
            // 0000000351 00000 n
            guard let offset = line.substring(0, 10)?.toInt() else { return "malformed xref line: \(line)" }
            guard let generation = line.substring(11, 16)?.toInt() else { return "malformed xref line: \(line)" }
            
            // NOTE: this is temporary, we should fix to handle very large pdfs with hundreds of thousands of refs
            if index < 2048 {
                xref.set(key: "{0}" << [index], value: ^[
                    "offset": offset,
                    "generation": generation
                ])
            }
            
            index += 1
        } else {
            // like: 28 10
            // object starting id and number of object references
            let parts: [HalfHitch] = line.components(separatedBy: " ")
            if let startIdx = parts[0].toInt() {
                index = startIdx
            }
        }
    }
    
    document.set(key: "xref", value: xref)
    
    if let trailer = document[element: "trailer"] {
        let prevOffset = trailer[int: "Prev"]
        let xrefStreamOffset = trailer[int: "XRefStm"]
        
        if let prevOffset = prevOffset {
            var ptr = start + prevOffset
            if let error = getXrefTable(document: document,
                                        &ptr, start, end) {
                return error
            }
        }
        if let xrefStreamOffset = xrefStreamOffset {
            var ptr = start + xrefStreamOffset
            if let error = getXrefTable(document: document,
                                        &ptr, start, end) {
                return error
            }
        }
    }
        
    return nil
}
