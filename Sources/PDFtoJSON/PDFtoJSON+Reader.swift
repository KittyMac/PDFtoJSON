import Foundation
import Spanker
import Hitch

@inlinable
func getLine(_ ptr: inout UnsafePointer<UInt8>,
             _ start: UnsafePointer<UInt8>,
             _ end: UnsafePointer<UInt8>) -> HalfHitch? {
    let start = ptr
    while ptr < end {
        ptr += 1
        if ptr.pointee == .newLine {
            break
        }
    }
    
    guard ptr > start else { return fail("failed to get line") }
    
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
            
            let document = JsonElement(unknown: ^[
                "__parse_date": Int(Date().timeIntervalSince1970)
            ])
            
            let documentObjects = JsonElement(unknown: [:])
            
            guard let start = pdf.raw() else { return ("unable to get raw bytes", nil) }
            let end = start + pdf.count
            var ptr = start
            
            // Parse the header
            guard let header = getLine(&ptr, start, end) else { return ("unable to get pdf header", nil) }
            
            guard header[0] == .percentSign,
                  header[1] == .P,
                  header[2] == .D,
                  header[3] == .F,
                  header[4] == .minus,
                  header[6] == .dot else {
                return ("malformed pdf header", nil)
            }
            
            document.set(key: "version", value: header.substring(5, header.count))
            document.set(key: "objects", value: documentObjects)
            
            // Extract the xref table
            guard let startxrefIdx = pdf.lastIndex(of: "startxref") else { return ("unable to find startxref", nil) }
            
            ptr = start + startxrefIdx + 10
            guard let startxrefLine = getLine(&ptr, start, end) else { return ("unable to get startxref", nil) }
            
            guard let xrefIdx = startxrefLine.toInt() else { return ("unable to get xref offset", nil) }

            ptr = start + xrefIdx
            if let error = getXrefTable(document: document, &ptr, start, end) { return (error, nil) }
            
            // preload all xref objects
            guard let xref = document[element: "xref"] else { return ("xref is missing", nil) }
            for objectId in 0..<xref.count {
                _ = reify(document: document, id: objectId, start, end)
            }
                        
            // Now that we have the xref table, parse needed info
            // from the trailer (encryption keys and such)
            //guard let trailer = document[element: "trailer"] else { return ("trailer is missing", nil) }
            //guard let documentInfoRef = trailer[element: "Info"] else { return ("trailer Info missing", nil) }
            
            
            
            //var elementStack: [JsonElement] = []

            //var jsonAttribute = ParseValue()
            //var rootElement: JsonElement?
            //var jsonElement: JsonElement?

            
            
            
            return (nil, document)
        }
    }
    
}
