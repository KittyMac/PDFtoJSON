import Foundation
import Spanker
import Hitch

@inlinable
func getLine(_ ptr: inout UnsafePointer<UInt8>,
             _ end: UnsafePointer<UInt8>) -> HalfHitch? {
    let start = ptr
    while ptr < end {
        ptr += 1
        if ptr.pointee == .newLine {
            break
        }
    }
    
    guard ptr > start else { return nil }
    
    ptr += 1
    return HalfHitch(sourceObject: nil, raw: start, count: ptr - start, from: 0, to: ptr - start)
}

extension PDFtoJSON {
    
    @usableFromInline
    internal enum Reader {
        @usableFromInline
        internal static func parsed<T>(hitch: Hitch, _ callback: (JsonElement?) -> T?) -> T? {
            return parsed(halfhitch: hitch.halfhitch(), callback)
        }

        @usableFromInline
        internal static func parsed<T>(string: String, _ callback: (JsonElement?) -> T?) -> T? {
            return parsed(halfhitch: HalfHitch(string: string), callback)
        }

        @usableFromInline
        internal static func parsed<T>(data: Data, _ callback: (JsonElement?) -> T?) -> T? {
            return HalfHitch.using(data: data) { pdf in
                return parsed(halfhitch: pdf, callback)
            }
        }

        @usableFromInline
        internal static func parsed<T>(halfhitch pdf: HalfHitch, _ callback: (JsonElement?) -> T?) -> T? {
            let (error, result) = parse(halfhitch: pdf)
            #if DEBUG
            if let error = error {
                print(error)
            }
            #endif
            return callback(result)
        }
        
        @usableFromInline
        internal static func parse(halfhitch pdf: HalfHitch) -> (String?, JsonElement?) {
            var currentIdx = 0
            var char: UInt8 = 0
            
            let result = JsonElement(unknown: ^[
                "parseDate": Date.timeIntervalBetween1970AndReferenceDate
            ])
            
            guard let start = pdf.raw() else { return ("unable to get raw bytes", nil) }
            let end = start + pdf.count
            var ptr = start
            
            // Parse the header
            guard let header = getLine(&ptr, end) else { return ("unable to get pdf header", nil) }
            
            guard header[0] == .percentSign,
                  header[1] == .P,
                  header[2] == .D,
                  header[3] == .F,
                  header[4] == .minus,
                  header[6] == .dot else {
                return ("malformed pdf header", nil)
            }
            
            result.set(key: "version", value: header.substring(5, header.count))
            
            // Find startxref - next line is byte offset to the xref table
            guard let startxrefIdx = pdf.lastIndex(of: "startxref") else { return ("unable to find startxref", nil) }
            
            ptr = start + startxrefIdx + 10
            guard let startxrefLine = getLine(&ptr, end) else { return ("unable to get startxref", nil) }
            
            guard let xrefIdx = startxrefLine.toInt() else { return ("unable to get xref offset", nil) }

            ptr = start + xrefIdx
            if let error = getXrefTable(&ptr, end, result) { return (error, nil) }
            
            
            
            //var elementStack: [JsonElement] = []

            //var jsonAttribute = ParseValue()
            //var rootElement: JsonElement?
            //var jsonElement: JsonElement?

            
            
            
            return (nil, result)
        }
    }
    
}
