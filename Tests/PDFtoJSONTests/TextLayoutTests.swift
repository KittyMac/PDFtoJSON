import XCTest
import Hitch
import Spanker

@testable import PDFtoJSON

private func firstItem(_ name: String) -> (x: Int, y: Int, text: String)? {
    guard let item = corpusParse(name)?[element: "pages"]?[element: 0]?[element: "text"]?[element: 0] else { return nil }
    return (item[int: "x"] ?? -1, item[int: "y"] ?? -1, item[string: "text"] ?? "")
}

final class TextLayoutTests: XCTestCase {

    func testRotatedTextMatrix() {
        // 0 1 -1 0 300 400 Tm: the glyph origin is (300, 400)
        let item = firstItem("rotated")
        XCTAssertEqual(item?.x, 300)
        XCTAssertEqual(item?.y, 400)
    }

    func testScaledCTM() {
        // 2 0 0 2 0 0 cm, 36 350 Td -> (72, 700)
        let item = firstItem("cm_scaled")
        XCTAssertEqual(item?.x, 72)
        XCTAssertEqual(item?.y, 700)
    }

    func testPositionsAreRelativeToTheVisibleBox() {
        // MediaBox [100 100 712 892], text at (172, 800)
        let item = firstItem("mediabox_offset")
        XCTAssertEqual(item?.x, 72)
        XCTAssertEqual(item?.y, 700)
        let page = corpusParse("mediabox_offset")?[element: "pages"]?[element: 0]
        XCTAssertEqual(page?[double: "width"], 612)
        XCTAssertEqual(page?[double: "height"], 792)
    }

    func testPageRotation() {
        // /Rotate 90 on a 612x792 page: (72, 700) is displayed at (700, 612 - 72)
        let item = firstItem("page_rotate")
        XCTAssertEqual(item?.x, 700)
        XCTAssertEqual(item?.y, 540)
        let page = corpusParse("page_rotate")?[element: "pages"]?[element: 0]
        XCTAssertEqual(page?[double: "width"], 792)
        XCTAssertEqual(page?[double: "height"], 612)
    }

    func testMatrix() {
        let m = Matrix(0, 1, -1, 0, 300, 400)
        let (x, y) = m.apply(10, 0)
        XCTAssertEqual(x, 300, accuracy: 1e-9)
        XCTAssertEqual(y, 410, accuracy: 1e-9)
        let t = Matrix.translation(5, 0).then(Matrix(2, 0, 0, 2, 0, 0))
        XCTAssertEqual(t.apply(0, 0).0, 10, accuracy: 1e-9)
    }

    func testPublicMatrix3x3Transform() {
        let m = Matrix3x3(m11: 0, m12: -1, m13: 300, m21: 1, m22: 0, m23: 400, m31: 0, m32: 0, m33: 1)
        let (x, y) = m.transform(x: 0, y: 0)
        XCTAssertEqual(x, 300)
        XCTAssertEqual(y, 400)
    }

    func testGlyphNames() {
        XCTAssertEqual(glyphNameToUnicode("A"), [0x41])
        XCTAssertEqual(glyphNameToUnicode("uni00E9"), [0xE9])
        XCTAssertEqual(glyphNameToUnicode("uni00660069"), [0x66, 0x69])
        XCTAssertEqual(glyphNameToUnicode("u1F600"), [0x1F600])
        XCTAssertEqual(glyphNameToUnicode("a.sc"), [0x61])
        XCTAssertEqual(glyphNameToUnicode("f_f_i"), [0xFB03])
        XCTAssertEqual(glyphNameToUnicode("T_h_e"), [0x54, 0x68, 0x65])
        XCTAssertNil(glyphNameToUnicode("g123"))
    }

    func testCMapRanges() {
        let cmap = CMap("""
        1 begincodespacerange <0000> <FFFF> endcodespacerange
        2 beginbfrange
        <0010> <0012> <0041>
        <0020> <0021> [<0061> <D83DDE00>]
        endbfrange
        1 beginbfchar <0030> /space endbfchar
        """)
        XCTAssertEqual(cmap.unicode(0x11), [0x42])
        XCTAssertEqual(cmap.unicode(0x21), [0x1F600])
        XCTAssertEqual(cmap.unicode(0x30), [0x20])
        XCTAssertNil(cmap.unicode(0x13))
    }
}
