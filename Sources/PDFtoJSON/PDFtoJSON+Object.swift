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

func getObject(_ ptr: inout UnsafePointer<UInt8>,
               _ end: UnsafePointer<UInt8>) -> JsonElement? {
    while ptr < end {
        
        // String
        if ptr[0] == .parenOpen {
            return getString(&ptr, end)
        }
        
        // Dictionary
        if ptr + 1 <= end,
           ptr[0] == .lessThan,
           ptr[1] == .lessThan {
            
        }
        
        // Hexstring
        if ptr[0] == .lessThan {
            
        }
        
        // Array
        if ptr[0] == .openBracket {
            
        }
        
        // Name / Value pairing
        if ptr[0] == .forwardSlash {
            
        }
        
        // Comment
        if ptr[0] == .percentSign {
            
        }
        
        // null
        if ptr + 4 <= end,
           ptr[0] == .n,
           ptr[1] == .u,
           ptr[2] == .l,
           ptr[3] == .l {
            return JsonElement.null()
        }
        
        // true
        if ptr + 4 <= end,
           ptr[0] == .t,
           ptr[1] == .r,
           ptr[2] == .u,
           ptr[3] == .e {
            return JsonElement(unknown: true)
        }
        
        // false
        if ptr + 5 <= end,
           ptr[0] == .f,
           ptr[1] == .a,
           ptr[2] == .l,
           ptr[3] == .s,
           ptr[4] == .e {
            return JsonElement(unknown: false)
        }
        
        // stream
        if ptr + 6 <= end,
           ptr[0] == .s,
           ptr[1] == .t,
           ptr[2] == .r,
           ptr[3] == .e,
           ptr[4] == .a,
           ptr[5] == .m {
            return JsonElement(unknown: false)
        }
        
        // int, double, indirect obj definition, indirect obj reference
        fatalError("TO BE IMPLEMENTED")
    }
    
    
    return nil
}
