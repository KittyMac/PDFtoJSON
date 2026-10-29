import Foundation
import Hitch
import Spanker
import PDFtoJSON

// usage: pdfdump [--text | --json] [--password pw] file.pdf...
//   default: one summary line per file
//   --text:  all extracted text, items separated by newlines, pages by form feeds
//   --json:  the full parsed document

var mode = "summary"
var password: String? = nil
var paths: [String] = []
var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--text": mode = "text"
    case "--json": mode = "json"
    case "--password": password = args.next()
    default: paths.append(arg)
    }
}

for path in paths {
    let name = (path as NSString).lastPathComponent
    guard let pdf = Hitch(contentsOfFile: path) else { print("\(name): unreadable"); continue }
    let t0 = Date()
    let root: JsonElement? = PDFtoJSON.parsed(hitch: pdf, options: PDFtoJSON.Options(password: password, includeParseDate: false)) { $0 }
    let elapsed = Date().timeIntervalSince(t0)
    guard let root = root else { print("\(name): PARSE FAILED (nil)"); continue }

    switch mode {
    case "json":
        print(root.toString(pretty: true))
    case "text":
        var pagesOut: [String] = []
        for page in root[element: "pages"]?.iterValues ?? JsonElement(unknown: []).iterValues {
            var items: [String] = []
            for t in page[element: "text"]?.iterValues ?? JsonElement(unknown: []).iterValues {
                items.append(t[string: "text"] ?? "")
            }
            pagesOut.append(items.joined(separator: "\n"))
        }
        print(pagesOut.joined(separator: "\u{0C}"))
    default:
        var texts: [String] = []
        for page in root[element: "pages"]?.iterValues ?? JsonElement(unknown: []).iterValues {
            for t in page[element: "text"]?.iterValues ?? JsonElement(unknown: []).iterValues {
                texts.append("\(t[string: "text"] ?? "?")@(\(t[int: "x"] ?? -1),\(t[int: "y"] ?? -1))")
            }
        }
        let n = root[element: "pages"]?.count ?? 0
        let shown = texts.count > 4 ? Array(texts.prefix(3)) + ["… (\(texts.count) total)"] : texts
        let warnings = root[element: "__warnings"]?.count ?? 0
        print("\(name): pages=\(n) dt=\(String(format: "%.2f", elapsed))s warnings=\(warnings) text=\(shown)")
    }
}
