import Foundation
import Spanker
import Hitch

@inlinable
func getXrefTable(document: JsonElement,
                  _ ptr: inout UnsafePointer<UInt8>,
                  _ start: UnsafePointer<UInt8>,
                  _ end: UnsafePointer<UInt8>) -> String? {
    let xref = JsonElement(unknown: ^[])
    
    var index = 0
    while ptr < end {
        guard let line = getLine(&ptr, start, end)?.trimmed() else { return "failed to read xref line" }
        if line == "trailer" {
            guard let trailerDict = getDictionary(document: document, &ptr, start, end) else { return "failed to parse trailer dictionary" }
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

            xref.append(value: JsonElement.null())
            
            index += 1
        }
        
        if line.last == .n {
            // 0000000351 00000 n
            guard let offset = line.substring(0, 10)?.toInt() else { return "malformed xref line: \(line)" }
            guard let generation = line.substring(11, 16)?.toInt() else { return "malformed xref line: \(line)" }
            
            xref.append(value: ^[
                "index": index,
                "offset": offset,
                "generation": generation
            ])
            
            index += 1
        }
    }
    
    document.set(key: "xref", value: xref)
    return nil
}
