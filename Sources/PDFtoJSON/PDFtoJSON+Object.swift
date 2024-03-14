import Foundation
import Spanker
import Hitch

// << /Name0 Value0 /Name1 Value1 >>
// (String literal)
//   escape chars: \n \r \t \b \f \( \) \\ \ddd (octal char code)
// <Hexstring literal>  <4E6F762073686D6F7A206B6120706F702E>
// [ ArrayObject0 ArrayObject1 ]
// /lime#20Green -> Lime Green
// 123 43445 +17 -98 0
// 34.5 -3.62 +123.6 4. -.002 0.0
// true false
// % this is a comment %
// stream\n...more bytes...\nendstream
// null
// indirect object definition:
// 12 0 obj   <-- object number, generation
//   (thing)
// endobj
// indirect object reference
// 12 0 R

public extension UInt8 {
    @inlinable
    func isDelimiter() -> Bool {
        switch self {
        case .space, .newLine, .carriageReturn, .tab, .closeBrace, .openBrace, .greaterThan, .lessThan, .forwardSlash, .parenOpen, .parenClose:
            return true
        default:
            return false
        }
    }
}

@usableFromInline
func peekParts(n: Int,
               _ start: UnsafePointer<UInt8>,
               _ end: UnsafePointer<UInt8>) -> [HalfHitch] {
    var parts: [HalfHitch] = []
    var ptr = start
    
    // advance until we've encountered n whitespaces
    var partStart = ptr
    while ptr < end && parts.count < n {
        if ptr[0].isDelimiter() {
            if ptr - partStart > 0 {
                parts.append(HalfHitch(sourceObject: nil,
                                       raw: partStart,
                                       count: ptr - partStart,
                                       from: 0,
                                       to: ptr - partStart))
            }
            partStart = ptr + 1
        }
        ptr += 1
    }
    
    if ptr - partStart > 0 {
        parts.append(HalfHitch(sourceObject: nil,
                               raw: partStart,
                               count: ptr - partStart,
                               from: 0,
                               to: ptr - partStart))
    }
    
    while parts.count < n {
        parts.append(HalfHitch.empty)
    }
    
    return parts
}

@inlinable
func getObject(document: JsonElement,
               id: Int,
               generation: Int,
               _ ptr: inout UnsafePointer<UInt8>,
               _ start: UnsafePointer<UInt8>,
               _ end: UnsafePointer<UInt8>) -> JsonElement? {
    while ptr < end {
        guard ptr[0].isWhitspace() == false else { ptr += 1; continue }
        
        // Comment
        if ptr[0] == .percentSign {
            while ptr < end && ptr[0].isWhitspace() == false {
                ptr += 1
            }
            return nil
        }
        
        // String
        if ptr[0] == .parenOpen {
            return getString(document: document,
                             id: id,
                             generation: generation, &ptr, start, end)
        }
        
        // Dictionary
        if ptr + 1 <= end,
           ptr[0] == .lessThan,
           ptr[1] == .lessThan {
            guard let dictionary = getDictionary(document: document,
                                                 id: id,
                                                 generation: generation, &ptr, start, end) else { return fail("failed to get dictionary when expected") }
            
            // a dictionary can be followed by a steam object; the dictionary
            // is necessary to parse the stream. Therefor we need to skip
            // all whitespace to see if the next token is a stream.
            while ptr < end && ptr[0].isWhitspace() {
                ptr += 1
            }
            
            // stream
            if ptr + 6 <= end,
               ptr[0] == .s,
               ptr[1] == .t,
               ptr[2] == .r,
               ptr[3] == .e,
               ptr[4] == .a,
               ptr[5] == .m {
                return getStream(document: document,
                                 id: id,
                                 generation: generation,
                                 streamInfo: dictionary, &ptr, start, end)
            }
            
            return dictionary
        }
        
        // Hexstring
        if ptr[0] == .lessThan {
            return getHexstring(document: document,
                                id: id,
                                generation: generation,
                                &ptr, start, end)
        }
        
        // Array
        if ptr[0] == .openBrace {
            return getArray(document: document,
                            id: id,
                            generation: generation, &ptr, start, end)
        }
        
        // Key
        if ptr[0] == .forwardSlash {
            return getKey(&ptr, start, end)
        }
        
        // null
        if ptr + 4 <= end,
           ptr[0] == .n,
           ptr[1] == .u,
           ptr[2] == .l,
           ptr[3] == .l {
            ptr += 4
            return JsonElement.null()
        }
        
        // true
        if ptr + 4 <= end,
           ptr[0] == .t,
           ptr[1] == .r,
           ptr[2] == .u,
           ptr[3] == .e {
            ptr += 4
            return JsonElement(unknown: true)
        }
        
        // false
        if ptr + 5 <= end,
           ptr[0] == .f,
           ptr[1] == .a,
           ptr[2] == .l,
           ptr[3] == .s,
           ptr[4] == .e {
            ptr += 5
            return JsonElement(unknown: false)
        }
        
        let nextParts = peekParts(n: 3, ptr, end)
        
        // obj definition
        if nextParts[2] == "obj",
           let id = nextParts[0].toInt(fuzzy: true),
           let generation = nextParts[1].toInt(fuzzy: true) {
            return getObjectDefinition(document: document, id: id, generation: generation, &ptr, start, end)
        }
        
        // obj reference
        if nextParts[2] == "R",
           let id = nextParts[0].toInt(fuzzy: true),
           let generation = nextParts[1].toInt(fuzzy: true) {
            ptr += nextParts[0].count + nextParts[1].count + nextParts[2].count + 2
            let results = JsonElement(unknown: [:])
            results.set(key: "id", value: id)
            results.set(key: "generation", value: generation)
            return results
        }
        
        // double
        if nextParts[0].contains(.dot),
           let value = nextParts[0].toDouble(fuzzy: true) {
            ptr += nextParts[0].count
            return JsonElement(unknown: value)
        }
        
        // int
        if let value = nextParts[0].toInt(fuzzy: true) {
            ptr += nextParts[0].count
            return JsonElement(unknown: value)
        }
        
        printAround(ptr: ptr,
                    start: start,
                    end: end)
        
        fatalError("UNKNOWN TOKEN")
    }
    
    
    return nil
}
