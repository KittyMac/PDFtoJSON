import Foundation
import Spanker
import Hitch

@inlinable
func isPostScript(_ content: HalfHitch) -> Bool {
    return content.contains(" Tf") || content.contains(" Tj")
}

@inlinable
func reify(document: JsonElement,
           id: Int,
           generation: Int,
           postScript content: HalfHitch) -> JsonElement? {
    guard isPostScript(content) else { return nil }
    // Given a postscript string, extract all text renders and their positioning
    
    // TODO: actually handle the postscript movement and transformations. For now, just find
    // all strings and output them...
    
    let strings = JsonElement(unknown: [])
    
    print(content)
    
    guard var ptr = content.raw() else { return fail("failed to get raw for postscript") }
    let start = ptr
    let end = ptr + content.count
    
    
    // PostScript commands of interest:
    // m (move pen): 12.49999 779.7543 m
    // cm (modify transform matrix): 1 0 0 1 12.49999 741.7543 cm
    // BT: begin text object
    // ET: end text object
    // Tm (text matrix): 11 0 0 11 8 19 Tm  (hori scale, hori skew, verti skew, verti scale, hori move, vert move)
    // Tm (text matrix): 11 0 0 11 8 19 Tm  (hori scale, hori skew, verti skew, verti scale, hori move, vert move)
    // Tf (set font): /TT1 1 Tf
    // Tj (render string): (hello world) Tj
    // TJ (render string, allow idv glyph positions): [<01>2<0203>2<04>-10<0503>2<04>-2<0506070809>2<0A>1<0B>]TJ
    // ' (move to next line and show text): example needed...
    // " (set word spacing, mvoe to next line and show text): example needed...
    
    var stack: [HalfHitch] = []
    
    var matrixStack: [Matrix3x3] = []
    var matrix = Matrix3x3()
    
    while ptr < end {
        guard ptr[0].isWhitspace() == false else {
            ptr += 1
            continue
        }
        
        if ptr[0] == .openBrace {
            if let array = getArray(document: document,
                                    id: id,
                                    generation: generation,
                                    &ptr, start, end) {
                stack.append("")
            }
            continue
        } else if ptr[0] == .parenOpen {
            if let string = getString(document: document,
                                      id: id,
                                      generation: generation,
                                      &ptr, start, end)?.halfHitchValue {
                stack.append(string)
            }
            continue
        } else if ptr[0] == .lessThan {
            if let string = getHexstring(document: document,
                                         id: id,
                                         generation: generation,
                                         &ptr, start, end)?.halfHitchValue {
                stack.append(string)
            }
            continue
        }
        
        guard let value = peekParts(n: 1, ptr, end).first else {
            fatalError("should not happen")
            break
        }
        
        switch value {
        case "q":
            matrixStack.append(matrix)
            ptr += value.count
            break
        case "Q":
            if matrixStack.isEmpty == false {
                matrix = matrixStack.removeLast()
            }
            ptr += value.count
            break
        case "cm":
            // 1 0 0 1 12.49999 741.7543 cm
            if stack.count >= 6 {
                let f = stack.removeLast().toDouble() ?? 0.0
                let e = stack.removeLast().toDouble() ?? 0.0
                let d = stack.removeLast().toDouble() ?? 0.0
                let c = stack.removeLast().toDouble() ?? 0.0
                let b = stack.removeLast().toDouble() ?? 0.0
                let a = stack.removeLast().toDouble() ?? 0.0
                
                let m = Matrix3x3(m11: a, m12: b, m13: e,
                                  m21: c, m22: d, m23: f,
                                  m31: 0, m32: 0, m33: 1)
                
                matrix = matrix.multiply(by: m)
            }
            ptr += value.count
            break
        case "Tm":
            // 11 0 0 11 8 19 Tm
            if stack.count >= 6 {
                let f = stack.removeLast().toDouble() ?? 0.0
                let e = stack.removeLast().toDouble() ?? 0.0
                let d = stack.removeLast().toDouble() ?? 0.0
                let c = stack.removeLast().toDouble() ?? 0.0
                let b = stack.removeLast().toDouble() ?? 0.0
                let a = stack.removeLast().toDouble() ?? 0.0
                
                let m = Matrix3x3(m11: a, m12: b, m13: e,
                                  m21: c, m22: d, m23: f,
                                  m31: 0, m32: 0, m33: 1)

                matrix = matrix.multiply(by: m)
            }
            ptr += value.count
            break
        case "Tj":
            if stack.isEmpty == false {
                let (x, y) = matrix.transform(x: 0, y: 0)
                let text = ^[:]
                text.set(key: "x", value: x)
                text.set(key: "y", value: y)
                text.set(key: "text", value: stack.removeLast())
                strings.append(value: text)
            }
            ptr += value.count
            break
        case "TJ":
            if stack.isEmpty == false {
                let (x, y) = matrix.transform(x: 0, y: 0)
                let text = ^[:]
                text.set(key: "x", value: x)
                text.set(key: "y", value: y)
                text.set(key: "text", value: stack.removeLast())
                strings.append(value: text)
            }
            ptr += value.count
            break
        default:
            ptr += value.count
            stack.append(value)
        }
    }
    
    return strings
}
