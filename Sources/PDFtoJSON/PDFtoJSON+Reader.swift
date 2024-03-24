import Foundation
import Spanker
import Hitch

func getLine(_ ptr: inout UnsafePointer<UInt8>,
             _ start: UnsafePointer<UInt8>,
             _ end: UnsafePointer<UInt8>) -> HalfHitch? {
    let start = ptr
    while ptr < end {
        ptr += 1
        if ptr[0] == .carriageReturn && ptr[1] == .lineFeed {
            ptr += 1
            break
        }
        if ptr[0] == .newLine || ptr[0] == .carriageReturn {
            break
        }
    }
    
    guard ptr > start else { return fail("failed to get line") }
    
    ptr += 1
    return HalfHitch(sourceObject: nil, raw: start, count: ptr - start, from: 0, to: ptr - start)
}

func skipWhitespace(_ ptr: inout UnsafePointer<UInt8>,
                    _ start: UnsafePointer<UInt8>,
                    _ end: UnsafePointer<UInt8>) {
    while ptr < end {
        guard ptr[0].isWhitspace() else { break }
        ptr += 1
    }
}

func fromUnicode(_ num: UInt16) -> Hitch {
    let hitch = Hitch(capacity: 4)
    let num32 = UInt32(num)
    hitch.append(hex2((num32 >> 12) & 0xF))
    hitch.append(hex2((num32 >> 8) & 0xF))
    hitch.append(hex2((num32 >> 4) & 0xF))
    hitch.append(hex2((num32 >> 0) & 0xF))
    return hitch
}

func toUnicode(_ ptr: UnsafePointer<UInt8>) -> UInt16 {
    let a: UInt32 = hex(ptr[0]) ?? 0
    let b: UInt32 = hex(ptr[1]) ?? 0
    let c: UInt32 = hex(ptr[2]) ?? 0
    let d: UInt32 = hex(ptr[3]) ?? 0
    return UInt16((a << 12) | (b << 8) | (c << 4) | d)
}

func toUnicode(_ ptr: Hitch) -> UInt16 {
    let a: UInt32 = hex(ptr[0]) ?? 0
    let b: UInt32 = hex(ptr[1]) ?? 0
    let c: UInt32 = hex(ptr[2]) ?? 0
    let d: UInt32 = hex(ptr[3]) ?? 0
    return UInt16((a << 12) | (b << 8) | (c << 4) | d)
}

func toUnicode(_ ptr: HalfHitch) -> UInt16 {
    let a: UInt32 = hex(ptr[0]) ?? 0
    let b: UInt32 = hex(ptr[1]) ?? 0
    let c: UInt32 = hex(ptr[2]) ?? 0
    let d: UInt32 = hex(ptr[3]) ?? 0
    return UInt16((a << 12) | (b << 8) | (c << 4) | d)
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
            
            // check for encryption
            guard let trailer = document[element: "trailer"] else { return ("document is missing trailer", nil) }
            if let encryptRef = trailer[element: "Encrypt"],
               let encrypt = reify(document: document,
                                   reference: encryptRef,
                                   parentInfo: JsonElement.null(),
                                   start, end) {
                
                if let error = generateKeys(document: document,
                                            encrypt: encrypt) {
                    return (error, nil)
                }
            }

            if let root = trailer[element: "Root"] {
                _ = reify(document: document,
                          reference: root,
                          parentInfo: JsonElement.null(),
                          start, end)
            } else {
                // should always be a root; if there is not, just load everything in the xref
                guard let xref = document[element: "xref"] else { return ("xref is missing", nil) }
                for objectIdString in xref.iterKeys {
                    guard let objectId = objectIdString.toInt() else { return ("xref key is not an objectId", nil) }
                    _ = reify(document: document,
                              id: objectId,
                              parentInfo: JsonElement.null(),
                              start, end)
                }
            }
            
            return (nil, document)
        }
    }
    
}
