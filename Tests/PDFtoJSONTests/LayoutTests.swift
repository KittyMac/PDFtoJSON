import XCTest
import Hitch
import Spanker

@testable import PDFtoJSON

/// Blocks of the first page, each block's lines joined with "|".
private func blocks(_ name: String) -> [String] {
    let path = URL(fileURLWithPath: #file).deletingLastPathComponent()
        .appendingPathComponent("Data/corpus/\(name).pdf").path
    guard let pdf = Hitch(contentsOfFile: path) else { return [] }
    return PDFtoJSON.parsed(hitch: pdf, options: PDFtoJSON.Options(textBlocks: true)) { root -> [String]? in
        var result: [String] = []
        for block in root?[element: "pages"]?[element: 0]?[element: "blocks"]?.iterValues ?? JsonElement(unknown: []).iterValues {
            var lines: [String] = []
            for item in block[element: "text"]?.iterValues ?? JsonElement(unknown: []).iterValues {
                lines.append(item[string: "text"] ?? "")
            }
            result.append(lines.joined(separator: "|"))
        }
        return result
    } ?? []
}

final class LayoutTests: XCTestCase {

    func testBlocksAreOptIn() {
        XCTAssertNil(corpusParse("layout_two_column")?[element: "pages"]?[element: 0]?[element: "blocks"])
    }

    func testTwoColumnArticleReadsColumnByColumn() {
        let result = blocks("layout_two_column")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.first, "Article Title")
        XCTAssertTrue(result[1].hasPrefix("Left column line 1"))
        XCTAssertTrue(result[1].hasSuffix("Left column line 8 of the article"))
        XCTAssertTrue(result[2].hasPrefix("Right column line 1"))
    }

    func testLabelValueFormReadsRowByRow() {
        XCTAssertEqual(blocks("layout_key_value"),
                       ["Name|Jane Doe|Phone|555-0100|Email|jane@example.com|City|Springfield|Country|USA"])
    }

    func testSidebarBoxesAndTable() {
        let result = blocks("layout_sidebar_boxes")
        // the sidebar comes before the main column
        XCTAssertEqual(result.first, "Customer|Name|JANE DOE")
        // side-by-side boxes stay together
        XCTAssertTrue(result.contains("Pickup|Monday, May 6|MAIN ST|SPRINGFIELD"))
        XCTAssertTrue(result.contains("Return|Friday, May 10|ELM ST|SHELBYVILLE"))
        // the table is read row by row, amounts next to their labels
        XCTAssertTrue(result.contains("Charges|Rate|4 days|$247.88|Mileage|Unlimited|Included|Tax|Sales tax|$20.15|Total|$272.03"))
    }

    func testBlocksContainEveryLineOnce() {
        for name in ["layout_sidebar_boxes", "layout_two_column", "layout_key_value", "baseline", "objstm"] {
            let fromBlocks = blocks(name).flatMap { $0.split(separator: "|").map(String.init) }.sorted()
            let fromText = corpusText(corpusParse(name)).split(whereSeparator: { $0 == "\n" || $0 == "\u{0C}" }).map(String.init).sorted()
            XCTAssertEqual(fromBlocks, fromText, name)
        }
    }
}
