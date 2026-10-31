import Foundation
import Spanker
import Hitch

func toUnicode(_ ptr: Hitch) -> UInt16 {
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
        internal static func parsed<T>(hitch: Hitch, options: Options, _ callback: (JsonElement?) -> T?) -> T? {
            return parsed(halfhitch: hitch.halfhitch(), options: options, callback)
        }

        @usableFromInline
        internal static func parsed<T>(string: String, options: Options, _ callback: (JsonElement?) -> T?) -> T? {
            return parsed(halfhitch: HalfHitch(string: string), options: options, callback)
        }

        @usableFromInline
        internal static func parsed<T>(data: Data, options: Options, _ callback: (JsonElement?) -> T?) -> T? {
            return HalfHitch.using(data: data) { pdf in
                return parsed(halfhitch: pdf, options: options, callback)
            }
        }

        @usableFromInline
        internal static func parsed<T>(halfhitch pdf: HalfHitch, options: Options, _ callback: (JsonElement?) -> T?) -> T? {
            let (error, result) = parse(halfhitch: pdf, options: options)
            #if DEBUG
            if let error = error {
                print(error)
            }
            #endif
            return callback(result)
        }
        
        @usableFromInline
        internal static func parse(halfhitch pdf: HalfHitch, options: Options = Options()) -> (String?, JsonElement?) {
            let document = JsonElement(unknown: [:])
            if options.includeParseDate {
                document.set(key: "__parse_date", value: Int(Date().timeIntervalSince1970))
            }

            guard let bufferStart = pdf.raw() else { return ("unable to get raw bytes", nil) }
            let end = bufferStart + pdf.count
            let context = PDFContext(document: document, start: bufferStart, end: end, options: options)

            // The header may be preceded by junk; readers accept it anywhere in the first 1024 bytes
            let headerWindow = HalfHitch(sourceObject: nil, raw: bufferStart,
                                         count: min(1024, pdf.count), from: 0, to: min(1024, pdf.count))
            if let headerIdx = headerWindow.firstIndex(of: "%PDF-") {
                context.start = bufferStart + headerIdx
                if headerIdx > 0 {
                    context.warn("\(headerIdx) bytes before %PDF header")
                }
                var ptr = context.start + 5
                let versionStart = ptr
                while ptr < end, (ptr[0] >= .zero && ptr[0] <= .nine) || ptr[0] == .dot {
                    ptr += 1
                }
                document.set(key: "version", value: HalfHitch(sourceObject: nil, raw: versionStart,
                                                              count: ptr - versionStart, from: 0,
                                                              to: ptr - versionStart).hitch())
            } else {
                context.warn("no %PDF header")
            }

            // Cross-reference table; rebuild it if it is missing or does not lead to a catalog
            var recovered = false
            if loadXref(context) == false || context.trailer?[element: "Root"] == nil {
                recoverXref(context)
                recovered = true
            }
            guard let trailer = context.trailer else { return ("document is missing trailer", nil) }

            // Encryption: the Encrypt dictionary's strings are binary, so keep them lossless
            let encryptRef = trailer[element: "Encrypt"]
            if let encrypt = context.with(stringMode: .hex, { resolve(context, encryptRef) }),
               encrypt.type == .dictionary {
                if let error = setupEncryption(context, encrypt: encrypt, password: options.password) {
                    // Return what we have (structure, trailer) along with the reason
                    context.warn(error)
                    document.set(key: "__error", value: error)
                    finish(context)
                    return (error, document)
                }
                // anything loaded before the keys were known (object streams found while
                // recovering, for example) was read without decryption: load it again
                let encryptId = isReference(encryptRef) ? encryptRef?[int: "id"] : nil
                let keep = encryptId.flatMap { context.objects[$0] }
                context.objects = [:]
                context.objectStreams = [:]
                context.streamData = [:]
                if let encryptId = encryptId, let keep = keep {
                    context.objects[encryptId] = keep
                }
            }

            var root = resolve(context, trailer[element: "Root"])
            if root == nil && recovered == false {
                context.warn("catalog could not be loaded from the xref table")
                recoverXref(context)
                root = resolve(context, context.trailer?[element: "Root"])
            }

            if root == nil {
                // should always be a root; if there is not, just load everything in the xref
                for objectId in context.xref.keys.sorted() {
                    _ = resolve(context, id: objectId)
                }
            }

            document.set(key: "pages", value: buildPages(context))

            if let info = resolve(context, context.trailer?[element: "Info"]), info.type == .dictionary {
                document.set(key: "info", value: info)
            }

            finish(context)
            return (nil, document)
        }

        /// Copy the parser's tables into the output document.
        private static func finish(_ context: PDFContext) {
            let document = context.document

            // Built in one pass, in object-number order (deterministic output)
            var objects = OrderedJsonDictionary()
            for id in context.objects.keys.sorted() {
                objects.append(key: Hitch(number: id).halfhitch(), value: context.objects[id]!)
            }
            document.set(key: "objects", value: objects.toJsonElement())

            var xref = OrderedJsonDictionary()
            for id in context.xref.keys.sorted() {
                let entry = JsonElement(unknown: [:])
                switch context.xref[id]! {
                case .offset(let offset, let generation):
                    entry.set(key: "offset", value: offset)
                    entry.set(key: "generation", value: generation)
                case .compressed(let stream, let index):
                    entry.set(key: "stream", value: stream)
                    entry.set(key: "index", value: index)
                case .free:
                    continue
                }
                xref.append(key: Hitch(number: id).halfhitch(), value: entry)
            }
            document.set(key: "xref", value: xref.toJsonElement())

            if let trailer = context.trailer {
                document.set(key: "trailer", value: trailer)
            }
            if context.warnings.isEmpty == false {
                document.set(key: "__warnings", value: JsonElement(unknown: context.warnings))
            }
        }
    }

}
