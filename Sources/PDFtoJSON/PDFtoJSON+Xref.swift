import Foundation
import Spanker
import Hitch

@inlinable
func getXrefTable(_ ptr: inout UnsafePointer<UInt8>,
                  _ end: UnsafePointer<UInt8>,
                  _ result: JsonElement) -> String? {
    let xref = JsonElement(unknown: ^[])
    
    while ptr < end {
        guard let line = getLine(&ptr, end)?.trimmed() else { return "failed to read xref line" }
        if line == "trailer" {
            break
        }
        
        if line.last == .f {
            // 0000000000 65535 f
        }
        
        if line.last == .n {
            // 0000000351 00000 n
            guard let offset = line.substring(0, 10)?.toInt() else { return "malformed xref line: \(line)" }
            guard let generation = line.substring(11, 16)?.toInt() else { return "malformed xref line: \(line)" }
            
            xref.append(value: ^[
                "offset": offset,
                "generation": generation
            ])
        }
    }
    
    result.set(key: "xref", value: xref)
    return nil
}
