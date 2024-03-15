import Foundation
import Spanker
import Hitch

func isPostScript(_ content: HalfHitch) -> Bool {
    return content.contains(" Tf") || content.contains(" Tj")
}

func reify(document: JsonElement,
           id: Int,
           generation: Int,
           postScript content: HalfHitch) -> JsonElement? {
    guard isPostScript(content) else { return nil }
    // Given a postscript string, extract all text renders and their positioning
    
    // TODO: actually handle the postscript movement and transformations. For now, just find
    // all strings and output them...
    
    // print("=======================")
    // print(content)
    // print("=======================")
    
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
    
    var strings: [JsonElement] = []
    
    var stack: [HalfHitch] = []
    
    var docMatrixStack: [Matrix3x3] = []
    var docMatrix = Matrix3x3()
    var textMatrix = Matrix3x3()
    
    let documentFonts = document[element: "fonts"] ?? ^[:]
    var font: JsonElement? = nil
    
    while ptr < end {
        guard ptr[0].isWhitspace() == false else {
            ptr += 1
            continue
        }
        
        if ptr[0] == .openBrace || ptr[0] == .parenOpen || ptr[0] == .forwardSlash,
           let object = getObject(document: document,
                                  id: id,
                                  generation: generation,
                                  &ptr, start, end) {
            if let string = object.halfHitchValue {
                stack.append(string)
                continue
            }
            
            for item in object.iterValues {
                if let string = item.halfHitchValue {
                    stack.append(string)
                }
            }
            continue
        }
        
        if ptr[0] == .lessThan,
           let string = getHexstringRaw(&ptr, start, end) {
            if let font = font,
               let cmap = font[element: "ToUnicode"]?[element: "content"]?[element: "cmap"],
               string.count % 4 == 0 {
                let convertedString = Hitch(capacity: string.count)
                for idx in stride(from: 0, to: string.count, by: 4) {
                    let code = HalfHitch(source: string, from: idx, to: idx + 4)
                    if let unicode = cmap[halfhitch: code] {
                        let value = toUnicode(unicode)
                        switch value {
                        case 0: break
                        case 9: convertedString.append("    ")
                        case 160: convertedString.append(.space)
                        default:
                            if let scalar = UnicodeScalar(value) {
                                for v in Character(scalar).utf8 {
                                    convertedString.append(v)
                                }
                            }
                        }
                    }
                }
                stack.append(convertedString.halfhitch())
            } else {
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
            docMatrixStack.append(docMatrix)
            ptr += value.count
            break
        case "Q":
            if docMatrixStack.isEmpty == false {
                docMatrix = docMatrixStack.removeLast()
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
                
                docMatrix = docMatrix.multiply(by: m)
            }
            ptr += value.count
            break
        case "Td":
            // 5 0 Td
            if stack.count >= 2 {
                let f = stack.removeLast().toDouble() ?? 0.0
                let e = stack.removeLast().toDouble() ?? 0.0
                
                let m = Matrix3x3(m11: 1, m12: 0, m13: e,
                                  m21: 0, m22: 1, m23: f,
                                  m31: 0, m32: 0, m33: 1)

                textMatrix = textMatrix.multiply(by: m)
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

                textMatrix = m
            }
            ptr += value.count
            break
        case "Tj":
            if stack.isEmpty == false {
                let (x, y) = docMatrix.multiply(by: textMatrix).transform(x: 0, y: 0)
                let text = ^[:]
                text.set(key: "x", value: Int(x))
                text.set(key: "y", value: Int(floor(y / 4) * 4))
                text.set(key: "text", value: stack.removeLast())
                strings.append(text)
            }
            ptr += value.count
            break
        case "TJ":
            if stack.isEmpty == false {
                let (x, y) = docMatrix.multiply(by: textMatrix).transform(x: 0, y: 0)
                let text = ^[:]
                text.set(key: "x", value: Int(x))
                text.set(key: "y", value: Int(floor(y / 4) * 4))
                text.set(key: "text", value: stack.removeLast())
                strings.append(text)
            }
            ptr += value.count
            break
        case "Tf":
            // /F1 12 Tf
            if stack.count >= 2 {
                let _ = stack.removeLast()
                let name = stack.removeLast()
                font = documentFonts[element: name]
            }
            ptr += value.count
        default:
            ptr += value.count
            stack.append(value)
        }
    }
    
    // remove empty strings
    strings = strings.filter {
        ($0[element: "text"]?.halfHitchValue?.count ?? 0) > 0
    }
    
    strings = strings.filter {
        $0[element: "text"]?.halfHitchValue != " "
    }
    
    // sort top to bottom, left to right
    strings = strings.sorted {
        let y0 = $0[int: "y"] ?? 0
        let y1 = $1[int: "y"] ?? 0
        guard y0 == y1 else {
            return y0 > y1
        }
        let x0 = $0[int: "x"] ?? 0
        let x1 = $1[int: "x"] ?? 0
        return x0 < x1
    }
    
    // print(strings)
    
    // Combine potentially broken up strings into words
    // (ie we have pdfs which place each letter individually,
    // it would be ideal to combin e these correctly)
    var combinedStrings: [JsonElement] = []

    var yOffset = 0
    var currentLine: [JsonElement] = []
    for string in strings {
        let y = string[int: "y"] ?? 0
        //let x = string[int: "y"] ?? 0

        if y != yOffset {
            if currentLine.isEmpty == false {
                combinedStrings.append(
                    combine(texts: currentLine)
                )
                currentLine = []
            }
            
            yOffset = y
        }
        
        currentLine.append(string)
    }
    
    if currentLine.isEmpty == false {
        combinedStrings.append(
            combine(texts: currentLine)
        )
        currentLine = []
    }
    
    return JsonElement(unknown: combinedStrings)
}

fileprivate func combine(texts: [JsonElement]) -> JsonElement {
    // Combine everything in currentLine to one new string object
    let lineY = texts[0][int: "y"] ?? 0
    let lineX = texts[0][int: "x"] ?? 0
    
    let combined = Hitch(capacity: 1024)
    for other in texts {
        combined.append(other[halfhitch: "text"] ?? " ")
    }
    
    let text = ^[:]
    text.set(key: "x", value: lineX)
    text.set(key: "y", value: lineY)
    text.set(key: "text", value: combined.halfhitch())
    return text
}
