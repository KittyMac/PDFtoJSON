import Foundation
import Spanker
import Hitch

/// One entry of the cross-reference table.
enum XrefEntry {
    case free
    /// uncompressed object at a byte offset (relative to the %PDF header)
    case offset(Int, generation: Int)
    /// object stored inside an object stream (/Type /ObjStm)
    case compressed(stream: Int, index: Int)
}

/// Parsed header of an object stream: object number -> byte offset in the decoded data.
struct ObjectStream {
    let data: Hitch
    let first: Int
    let offsets: [Int: Int]
}

/// How string objects are represented in parsed output.
enum StringMode {
    /// decoded to UTF-8 text; binary strings become "<hex>"
    case text
    /// always "<hex>" (lossless; used for the trailer and encryption dictionary)
    case hex
    /// raw bytes (internal use only; never exported)
    case raw
    /// each byte as a Latin-1 character (content streams, until fonts decode them)
    case latin1
}

/// Mutable state for a single parse. Owns everything that used to be
/// smuggled through the output document (xref, keys, caches).
final class PDFContext {
    /// The output document.
    let document: JsonElement

    /// Start of the PDF (the %PDF header); xref offsets are relative to this.
    var start: UnsafePointer<UInt8>
    /// Start of the buffer as given; may differ from `start` if there are bytes before %PDF.
    let bufferStart: UnsafePointer<UInt8>
    let end: UnsafePointer<UInt8>

    var xref: [Int: XrefEntry] = [:]
    var trailer: JsonElement?

    /// Resolved objects: id -> { "id", "generation", "value" }
    var objects: [Int: JsonElement] = [:]
    /// Objects currently being resolved; used to break reference cycles.
    var resolving: Set<Int> = []
    var objectStreams: [Int: ObjectStream] = [:]
    /// Fonts loaded for text extraction, keyed by font object id.
    var fonts: [Int: Font] = [:]
    /// Stream bytes as found in the file, keyed by the id of the object holding the stream.
    var rawStreams: [Int: RawStream] = [:]
    /// Decoded stream data (cache), keyed like rawStreams.
    var streamData: [Int: Hitch] = [:]

    /// Object offsets found by scanning the whole file (built lazily, only when needed).
    var scannedOffsets: [Int: Int]? = nil

    var warnings: [String] = []

    var stringMode: StringMode = .text

    /// Decryption state; nil for unencrypted files (or before keys are known).
    var crypt: CryptState? = nil
    let options: PDFtoJSON.Options

    /// Run `body` with a different string mode.
    func with<T>(stringMode mode: StringMode, _ body: () -> T) -> T {
        let saved = stringMode
        stringMode = mode
        defer { stringMode = saved }
        return body()
    }

    init(document: JsonElement,
         start: UnsafePointer<UInt8>,
         end: UnsafePointer<UInt8>,
         options: PDFtoJSON.Options = PDFtoJSON.Options()) {
        self.options = options
        self.document = document
        self.start = start
        self.bufferStart = start
        self.end = end
    }

    func warn(_ message: String) {
        // keep the list bounded for pathological files
        if warnings.count < 200 {
            warnings.append(message)
        }
    }

    /// Pointer for an xref offset, or nil if it falls outside the buffer.
    func pointer(offset: Int) -> UnsafePointer<UInt8>? {
        guard offset >= 0, offset < end - start else { return nil }
        return start + offset
    }
}

/// { "id": id, "generation": generation }, keys in that order.
func makeReference(id: Int, generation: Int) -> JsonElement {
    let reference = JsonElement(unknown: [:])
    reference.set(key: "id", value: id)
    reference.set(key: "generation", value: generation)
    return reference
}

/// { "id", "generation", "value" } wrapper for an indirect object.
func makeObjectWrapper(id: Int, generation: Int, value: JsonElement) -> JsonElement {
    let wrapper = makeReference(id: id, generation: generation)
    wrapper.set(key: "value", value: value)
    return wrapper
}

/// Is this element an indirect reference ({ "id": n, "generation": g })?
func isReference(_ element: JsonElement?) -> Bool {
    guard let element = element,
          element.type == .dictionary,
          element.count == 2,
          element[element: "id"]?.type == .int,
          element[element: "generation"]?.type == .int else { return false }
    return true
}
