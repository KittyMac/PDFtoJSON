import Foundation
import Spanker
import Hitch

// Content stream interpretation for text extraction (ISO 32000-1, 8.2 / 9.4).

/// An affine transform [a b c d e f] in PDF's row-vector convention:
/// x' = a·x + c·y + e,  y' = b·x + d·y + f
struct Matrix {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0

    static let identity = Matrix()

    init() { }
    init(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ e: Double, _ f: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.e = e; self.f = f
    }
    init?(_ operands: ArraySlice<Operand>) {
        let values = operands.compactMap { $0.number }
        guard values.count == 6 else { return nil }
        self.init(values[0], values[1], values[2], values[3], values[4], values[5])
    }

    /// self × other: apply self, then other
    func then(_ m: Matrix) -> Matrix {
        return Matrix(a * m.a + b * m.c,
                      a * m.b + b * m.d,
                      c * m.a + d * m.c,
                      c * m.b + d * m.d,
                      e * m.a + f * m.c + m.e,
                      e * m.b + f * m.d + m.f)
    }

    func apply(_ x: Double, _ y: Double) -> (Double, Double) {
        return (a * x + c * y + e, b * x + d * y + f)
    }

    static func translation(_ tx: Double, _ ty: Double) -> Matrix {
        return Matrix(1, 0, 0, 1, tx, ty)
    }
}

/// Page space -> output space: origin at the visible box's lower-left corner, /Rotate applied.
func pageMatrix(box: [Double], rotate: Int) -> Matrix {
    let width = box[2] - box[0]
    let height = box[3] - box[1]
    let origin = Matrix.translation(-box[0], -box[1])
    switch rotate {
    case 90: return origin.then(Matrix(0, -1, 1, 0, 0, width))
    case 180: return origin.then(Matrix(-1, 0, 0, -1, width, height))
    case 270: return origin.then(Matrix(0, 1, -1, 0, height, 0))
    default: return origin
    }
}

// MARK: - Text layout

/// A run of text on one baseline, built glyph by glyph.
private struct TextItem {
    var scalars: [UInt32]
    let x: Double
    let y: Double
    /// unit vector of the writing direction
    let dx: Double
    let dy: Double
    /// position across the baseline (constant for a line)
    let across: Double
    /// position along the baseline where the next glyph would start
    var end: Double
    var size: Double
}

/// Collects glyphs in content order and joins them into words and lines.
private final class TextCollector {
    var items: [TextItem] = []

    func add(_ scalars: [UInt32], x: Double, y: Double, dx: Double, dy: Double, advance: Double, size: Double) {
        let along = x * dx + y * dy
        let across = -x * dy + y * dx
        let size = max(size, 0.1)

        if var last = items.last,
           last.dx * dx + last.dy * dy > 0.99,
           abs(across - last.across) <= 0.3 * max(size, last.size),
           along >= last.end - 0.7 * max(size, last.size),
           along - last.end <= 2.0 * max(size, last.size) {
            let gap = along - last.end
            if gap > 0.15 * size,
               last.scalars.last != 0x20,
               scalars.first != 0x20 {
                last.scalars.append(0x20)
            }
            last.scalars.append(contentsOf: scalars)
            last.end = max(last.end, along + advance)
            last.size = max(last.size, size)
            items[items.count - 1] = last
            return
        }

        // a lone space does not start a new item
        if scalars.allSatisfy({ $0 == 0x20 }) {
            return
        }
        items.append(TextItem(scalars: scalars, x: x, y: y, dx: dx, dy: dy,
                              across: across, end: along + advance, size: size))
    }

    /// Items sorted top to bottom, then left to right.
    func output() -> JsonElement {
        var results: [(y: Double, x: Double, size: Double, text: String)] = []
        for item in items {
            var text = String(String.UnicodeScalarView(item.scalars.compactMap(Unicode.Scalar.init)))
            text = text.trimmingCharacters(in: .whitespaces)
            guard text.isEmpty == false else { continue }
            results.append((item.y, item.x, item.size, text))
        }

        results.sort { $0.y > $1.y }
        // rows: items whose baselines are within a fraction of the font size
        var ordered: [(y: Double, x: Double, size: Double, text: String)] = []
        var row: [(y: Double, x: Double, size: Double, text: String)] = []
        for item in results {
            if let first = row.first, first.y - item.y > max(1.0, 0.3 * min(first.size, item.size)) {
                ordered.append(contentsOf: row.sorted { $0.x < $1.x })
                row = []
            }
            row.append(item)
        }
        ordered.append(contentsOf: row.sorted { $0.x < $1.x })

        let output = JsonElement(unknown: [])
        for item in ordered {
            let element = JsonElement(unknown: [:])
            element.set(key: "x", value: Int(item.x.rounded(.down)))
            element.set(key: "y", value: Int(item.y.rounded(.down)))
            element.set(key: "text", value: item.text)
            output.append(value: element)
        }
        return output
    }
}

/// Map extracted scalars to plain text: expand ligatures, normalize spaces, drop controls.
private func normalize(_ scalars: [UInt32]) -> [UInt32] {
    var out: [UInt32] = []
    out.reserveCapacity(scalars.count)
    for u in scalars {
        switch u {
        case 0x09, 0xA0, 0x2000...0x200A, 0x202F, 0x205F, 0x3000: out.append(0x20)
        case 0x00..<0x20, 0x7F, 0xAD, 0x200B...0x200D, 0xFEFF, 0xFFFD: continue
        case 0xFB00: out += [0x66, 0x66]
        case 0xFB01: out += [0x66, 0x69]
        case 0xFB02: out += [0x66, 0x6C]
        case 0xFB03: out += [0x66, 0x66, 0x69]
        case 0xFB04: out += [0x66, 0x66, 0x6C]
        case 0xFB05, 0xFB06: out += [0x73, 0x74]
        default: out.append(u)
        }
    }
    return out
}

// MARK: - Interpreter

private struct GraphicsState {
    var ctm = Matrix.identity
    var font: Font? = nil
    var fontSize = 0.0
    var charSpacing = 0.0
    var wordSpacing = 0.0
    var horizontalScale = 1.0
    var leading = 0.0
    var rise = 0.0
}

private final class Interpreter {
    let context: PDFContext?
    let collector = TextCollector()
    var visitedForms = Set<Int>()

    init(_ context: PDFContext?) {
        self.context = context
    }

    func font(_ name: Hitch, _ resources: JsonElement?) -> Font? {
        guard let context = context,
              let fonts = resolve(context, resources?[element: "Font"]),
              let reference = fonts[element: name.halfhitch()] else { return nil }
        let id = isReference(reference) ? reference[int: "id"] : nil
        if let id = id, let cached = context.fonts[id] {
            return cached
        }
        guard let dict = resolve(context, reference), dict.type == .dictionary else { return nil }
        let font = loadFont(context, dict)
        if let id = id {
            context.fonts[id] = font
        }
        return font
    }

    func run(_ content: HalfHitch, resources: JsonElement?, ctm: Matrix) {
        guard var lexer = ContentLexer(content) else { return }

        var gs = GraphicsState()
        gs.ctm = ctm
        var stack: [GraphicsState] = []
        var tm = Matrix.identity
        var tlm = Matrix.identity
        var operands: [Operand] = []

        func show(_ bytes: Hitch) {
            let font = gs.font
            let size = gs.fontSize
            for (code, length) in font?.codes(bytes) ?? bytes.map({ (UInt32($0), 1) }) {
                let scalars = normalize(font?.unicode(code) ?? [code])
                let w0 = (font?.width(code) ?? 500) / 1000
                let isSpace = length == 1 && code == 32

                // glyph origin and direction in output space
                let trm = Matrix(size * gs.horizontalScale, 0, 0, size, 0, gs.rise).then(tm).then(gs.ctm)
                let (x, y) = trm.apply(0, 0)
                let scale = (trm.a * trm.a + trm.b * trm.b).squareRoot()
                let fontHeight = (trm.c * trm.c + trm.d * trm.d).squareRoot()

                var tx = 0.0
                var ty = 0.0
                if font?.vertical == true {
                    ty = -(w0 * size + gs.charSpacing + (isSpace ? gs.wordSpacing : 0))
                } else {
                    tx = (w0 * size + gs.charSpacing + (isSpace ? gs.wordSpacing : 0)) * gs.horizontalScale
                }

                if scale > 0 {
                    let dx = trm.a / scale
                    let dy = trm.b / scale
                    let advance = w0 * scale
                    collector.add(scalars, x: x, y: y, dx: dx, dy: dy, advance: advance, size: fontHeight)
                }
                tm = Matrix.translation(tx, ty).then(tm)
            }
        }

        func nextLine() {
            tlm = Matrix.translation(0, -gs.leading).then(tlm)
            tm = tlm
        }

        while let token = lexer.next() {
            let op: HalfHitch
            switch token {
            case .operand(let value):
                operands.append(value)
                continue
            case .op(let value):
                op = value
            }
            defer { operands.removeAll(keepingCapacity: true) }

            func num(_ idx: Int) -> Double? {
                let i = operands.count - 1 - idx
                return i >= 0 ? operands[i].number : nil
            }

            switch op {
            case "q":
                stack.append(gs)
            case "Q":
                if let saved = stack.popLast() { gs = saved }
            case "cm":
                if operands.count >= 6, let m = Matrix(operands.suffix(6)) {
                    gs.ctm = m.then(gs.ctm)
                }
            case "BT":
                tm = .identity
                tlm = .identity
            case "ET":
                break
            case "Tf":
                if let size = num(0), operands.count >= 2, let name = operands[operands.count - 2].name {
                    gs.font = font(name, resources)
                    gs.fontSize = size
                }
            case "Tc": gs.charSpacing = num(0) ?? gs.charSpacing
            case "Tw": gs.wordSpacing = num(0) ?? gs.wordSpacing
            case "Tz": gs.horizontalScale = (num(0) ?? 100) / 100
            case "TL": gs.leading = num(0) ?? gs.leading
            case "Ts": gs.rise = num(0) ?? gs.rise
            case "Td", "TD":
                if let ty = num(0), let tx = num(1) {
                    if op == "TD" { gs.leading = -ty }
                    tlm = Matrix.translation(tx, ty).then(tlm)
                    tm = tlm
                }
            case "Tm":
                if operands.count >= 6, let m = Matrix(operands.suffix(6)) {
                    tlm = m
                    tm = m
                }
            case "T*":
                nextLine()
            case "Tj":
                if let bytes = operands.last?.bytes { show(bytes) }
            case "'":
                nextLine()
                if let bytes = operands.last?.bytes { show(bytes) }
            case "\"":
                if operands.count >= 3 {
                    gs.wordSpacing = operands[operands.count - 3].number ?? gs.wordSpacing
                    gs.charSpacing = operands[operands.count - 2].number ?? gs.charSpacing
                }
                nextLine()
                if let bytes = operands.last?.bytes { show(bytes) }
            case "TJ":
                if case .array(let items)? = operands.last {
                    for item in items {
                        if let bytes = item.bytes {
                            show(bytes)
                        } else if let adjust = item.number {
                            let shift = -adjust / 1000 * gs.fontSize
                            if gs.font?.vertical == true {
                                tm = Matrix.translation(0, shift).then(tm)
                            } else {
                                tm = Matrix.translation(shift * gs.horizontalScale, 0).then(tm)
                            }
                        }
                    }
                }
            case "Do":
                if let name = operands.last?.name {
                    runForm(name, resources: resources, ctm: gs.ctm)
                }
            case "BI":
                // inline image: dictionary entries up to ID, then binary data up to EI
                var length: Int? = nil
                var entries: [Operand] = []
                while let token = lexer.next() {
                    if case .op(let value) = token, value == "ID" { break }
                    if case .operand(let value) = token { entries.append(value) }
                }
                var idx = 0
                while idx + 1 < entries.count {
                    if let key = entries[idx].name, key == "L" || key == "Length" {
                        length = entries[idx + 1].number.map(Int.init)
                    }
                    idx += 2
                }
                lexer.skipInlineImage(length: length)
            default:
                break
            }
        }
    }

    func runForm(_ name: Hitch, resources: JsonElement?, ctm: Matrix) {
        guard let context = context,
              let xobjects = resolve(context, resources?[element: "XObject"]),
              let reference = xobjects[element: name.halfhitch()],
              isReference(reference),
              let id = reference[int: "id"],
              visitedForms.contains(id) == false,
              visitedForms.count < 32,
              let xobject = resolve(context, id: id),
              xobject[string: "Subtype"] == "Form",
              let data = streamData(context, id: id) else { return }

        var formCtm = ctm
        if let matrix = resolve(context, xobject[element: "Matrix"]), matrix.type == .array {
            let values = matrix.iterValues.map { Operand.number($0.doubleValue ?? Double($0.intValue ?? 0)) }
            if let m = Matrix(values[...]) {
                formCtm = m.then(ctm)
            }
        }
        visitedForms.insert(id)
        run(data.halfhitch(),
            resources: resolve(context, xobject[element: "Resources"]) ?? resources,
            ctm: formCtm)
        visitedForms.remove(id)
    }
}

/// Text items of a content stream (or a page's concatenated content streams).
func extractText(_ context: PDFContext?,
                 content: HalfHitch,
                 resources: JsonElement?,
                 matrix: Matrix = .identity) -> JsonElement {
    let interpreter = Interpreter(context)
    interpreter.run(content, resources: resources, ctm: matrix)
    return interpreter.collector.output()
}

/// Kept for tests: interpret a content stream without resources.
func reify(document: JsonElement,
           id: Int,
           generation: Int,
           postScript content: HalfHitch) -> JsonElement? {
    return extractText(nil, content: content, resources: nil)
}
