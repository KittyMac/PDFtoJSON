import Foundation
import Spanker
import Hitch

/// A leaf of the page tree with its inherited attributes applied.
struct PageInfo {
    let dict: JsonElement
    let resources: JsonElement?
    let mediaBox: [Double]
    let cropBox: [Double]?
    let rotate: Int
}

/// Attributes a page inherits from its ancestors (ISO 32000-1, 7.7.3.4).
private struct Inherited {
    var resources: JsonElement? = nil
    var mediaBox: JsonElement? = nil
    var cropBox: JsonElement? = nil
    var rotate: Int? = nil

    func merged(with node: JsonElement, _ context: PDFContext) -> Inherited {
        var result = self
        if let value = resolve(context, node[element: "Resources"]), value.type == .dictionary { result.resources = value }
        if let value = resolve(context, node[element: "MediaBox"]), value.type == .array { result.mediaBox = value }
        if let value = resolve(context, node[element: "CropBox"]), value.type == .array { result.cropBox = value }
        if let value = resolve(context, node[element: "Rotate"])?.intValue { result.rotate = value }
        return result
    }
}

/// A rectangle [x1 y1 x2 y2], normalized so x1 <= x2 and y1 <= y2.
func rectangle(_ context: PDFContext, _ element: JsonElement?) -> [Double]? {
    guard let element = resolve(context, element), element.type == .array, element.count >= 4 else { return nil }
    var values: [Double] = []
    for idx in 0..<4 {
        guard let value = resolve(context, element[element: idx]) else { return nil }
        values.append(value.doubleValue ?? Double(value.intValue ?? 0))
    }
    return [min(values[0], values[2]), min(values[1], values[3]), max(values[0], values[2]), max(values[1], values[3])]
}

private func makePage(_ context: PDFContext, _ dict: JsonElement, _ inherited: Inherited) -> PageInfo {
    let mediaBox = rectangle(context, inherited.mediaBox) ?? [0, 0, 612, 792]
    var rotate = (inherited.rotate ?? 0) % 360
    if rotate < 0 { rotate += 360 }
    return PageInfo(dict: dict,
                    resources: inherited.resources,
                    mediaBox: mediaBox,
                    cropBox: rectangle(context, inherited.cropBox),
                    rotate: rotate)
}

/// All pages in document order.
func collectPages(_ context: PDFContext) -> [PageInfo] {
    var pages: [PageInfo] = []
    var visited = Set<Int>()

    func walk(_ reference: JsonElement?, _ inherited: Inherited, depth: Int) {
        guard depth < 64 else { return }
        if isReference(reference), let id = reference?[int: "id"] {
            guard visited.contains(id) == false else {
                context.warn("page tree: object \(id) appears more than once")
                return
            }
            visited.insert(id)
        }
        guard let node = resolve(context, reference), node.type == .dictionary else { return }

        let attributes = inherited.merged(with: node, context)
        if let kids = resolve(context, node[element: "Kids"]), kids.type == .array, node[string: "Type"] != "Page" {
            for kid in kids.iterValues {
                walk(kid, attributes, depth: depth + 1)
            }
        } else {
            pages.append(makePage(context, node, attributes))
        }
    }

    if let root = resolve(context, context.trailer?[element: "Root"]) {
        walk(root[element: "Pages"], Inherited(), depth: 0)
    }

    // Broken page tree: fall back to every /Type /Page object, in object order
    if pages.isEmpty {
        for id in context.xref.keys.sorted() {
            guard let dict = resolve(context, id: id),
                  dict.type == .dictionary,
                  dict[string: "Type"] == "Page" else { continue }
            // inherit through the /Parent chain
            var chain: [JsonElement] = [dict]
            var parent = resolve(context, dict[element: "Parent"])
            while let p = parent, chain.count < 64, chain.contains(where: { $0 === p }) == false {
                chain.append(p)
                parent = resolve(context, p[element: "Parent"])
            }
            var inherited = Inherited()
            for node in chain.reversed() {
                inherited = inherited.merged(with: node, context)
            }
            pages.append(makePage(context, dict, inherited))
        }
        if pages.isEmpty == false {
            context.warn("page tree is broken; found \(pages.count) pages by scanning objects")
        }
    }
    return pages
}

/// The decoded content of a page: all content streams, concatenated.
func pageContent(_ context: PDFContext, _ page: PageInfo) -> Hitch {
    let content = Hitch(capacity: 4096)
    var streams: [JsonElement] = []
    if let contents = page.dict[element: "Contents"] {
        if isReference(contents) {
            // either a stream or a reference to an array of streams
            if let resolved = resolve(context, contents), resolved.type == .array {
                streams = Array(resolved.iterValues)
            } else {
                streams = [contents]
            }
        } else if contents.type == .array {
            streams = Array(contents.iterValues)
        }
    }
    for stream in streams {
        guard isReference(stream), let id = stream[int: "id"] else { continue }
        _ = resolve(context, id: id)
        if let data = streamData(context, id: id) {
            content.append(data)
            // streams are concatenated as if one; keep tokens from running together
            content.append(.newLine)
        }
    }
    return content
}

/// Output for every page: { "text", "width", "height" }
func buildPages(_ context: PDFContext) -> JsonElement {
    let output = JsonElement(unknown: [])
    for page in collectPages(context) {
        let box = page.cropBox ?? page.mediaBox
        let content = pageContent(context, page)
        let text = extractText(context,
                               content: content.halfhitch(),
                               resources: page.resources,
                               matrix: pageMatrix(box: box, rotate: page.rotate))
        let rotated = page.rotate == 90 || page.rotate == 270

        let pageOutput = JsonElement(unknown: [:])
        pageOutput.set(key: "text", value: text)
        pageOutput.set(key: "width", value: rotated ? box[3] - box[1] : box[2] - box[0])
        pageOutput.set(key: "height", value: rotated ? box[2] - box[0] : box[3] - box[1])
        output.append(value: pageOutput)
    }
    return output
}
