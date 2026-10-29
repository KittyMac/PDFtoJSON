import XCTest
import Hitch
import Spanker

@testable import PDFtoJSON

private func parse(_ pdf: Hitch) -> JsonElement? {
    guard var ptr = pdf.raw() else { return nil }
    return getObject(document: ^[], id: -1, generation: -1, &ptr, ptr, ptr + pdf.count)
}

final class LexerTests: XCTestCase {

    // MARK: whitespace and comments

    func testCommentsAreWhitespace() {
        XCTAssertEqual(parse("[1 % comment ]\n 2]")?.description, "[1,2]")
        XCTAssertEqual(parse("<< /A % c\n 1 /B 2 >>")?.description, #"{"A":1,"B":2}"#)
        XCTAssertEqual(parse("12 % c\n 0 R")?.description, #"{"id":12,"generation":0}"#)
    }

    func testNulAndFormFeedAreWhitespace() {
        XCTAssertEqual(parse("<< /A 1\u{0}/B\u{0C}2 >>")?.description, #"{"A":1,"B":2}"#)
    }

    func testCurlyBracesDelimitTokens() {
        XCTAssertEqual(parse("[1{2}3]")?.description, "[1,2,3]")
    }

    // MARK: robustness

    func testUnknownKeywordsDoNotAbortParsing() {
        XCTAssertEqual(parse("[1 junk 2]")?.description, "[1,2]")
        XCTAssertEqual(parse("<< /A junk 1 /B 2 >>")?[int: "B"], 2)
    }

    func testMissingDictionaryValue() {
        XCTAssertEqual(parse("<< /A >>")?.description, #"{"A":null}"#)
    }

    func testUnterminatedArrayInsideDictionary() {
        XCTAssertEqual(parse("<< /A [1 2 >> ")?.description, #"{"A":[1,2]}"#)
    }

    func testMalformedNumbers() {
        XCTAssertEqual(parse("--5")?.intValue, -5)
        XCTAssertEqual(parse("4.")?.doubleValue, 4.0)
        XCTAssertEqual(parse("-.5")?.doubleValue, -0.5)
    }

    func testMissingEndobj() {
        let pdf: Hitch = "1 0 obj << /A 1 >>\n2 0 obj << /B 2 >> endobj"
        let wrapper = parse(pdf)
        XCTAssertEqual(wrapper?[int: "id"], 1)
        XCTAssertEqual(wrapper?[element: "value"]?.description, #"{"A":1}"#)
    }

    func testTruncatedInput() {
        XCTAssertNotNil(parse("<< /A (unterminated"))
        XCTAssertNotNil(parse("[1 2"))
        XCTAssertEqual(parse("<4142"), parse("<4142>"))
    }

    // MARK: names

    func testNameEscapes() {
        XCTAssertEqual(parse("/lime#20Green")?.stringValue, "lime Green")
        XCTAssertEqual(parse("/A#23B")?.stringValue, "A#B")
        XCTAssertEqual(parse("/F#31")?.stringValue, "F1")
    }

    // MARK: strings

    func testHexStringWhitespace() {
        XCTAssertEqual(parse("<48 65\n6C 6C\t6F>")?.stringValue, "Hello")
    }

    func testOctalEscapesAreBytes() {
        // \351 is 0xE9 = é in PDFDocEncoding, \222 is 0x92 = ™
        XCTAssertEqual(parse(#"(caf\351\222)"#)?.stringValue, "café™")
    }

    func testEndOfLineNormalization() {
        XCTAssertEqual(parse("(a\r\nb\rc)")?.stringValue, "a\nb\nc")
        XCTAssertEqual(parse("(a\\\r\nb)")?.stringValue, "ab")
    }

    func testUTF16Strings() {
        XCTAssertEqual(parse("<FEFF00480069>")?.stringValue, "Hi")
        XCTAssertEqual(parse("<FEFFD83DDE00>")?.stringValue, "😀")
        XCTAssertEqual(parse("<FFFE48006900>")?.stringValue, "Hi")
    }

    func testUTF8Strings() {
        XCTAssertEqual(parse("<EFBBBF68C3A9>")?.stringValue, "hé")
        XCTAssertEqual(parse("<68C3A9>")?.stringValue, "hé")
    }

    func testBinaryStringsAreHex() {
        XCTAssertEqual(parse("<00FF10>")?.stringValue, "<00FF10>")
        XCTAssertEqual(stringBytes(parse("<00FF10>")), Hitch(bytes: [0x00, 0xFF, 0x10], offset: 0, count: 3))
    }

    func testHexMode() {
        let pdf: Hitch = "(AB)"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let context = PDFContext(document: ^[], start: ptr, end: ptr + pdf.count)
        context.stringMode = .hex
        XCTAssertEqual(getObject(context: context, id: -1, generation: -1, &ptr, ptr, ptr + pdf.count)?.stringValue, "<4142>")
    }

    // MARK: document level

    func testInfoStrings() {
        let root = corpusParse("info_strings")
        XCTAssertEqual(root?[element: "info"]?[string: "Title"], "Hi ɣ")
        XCTAssertEqual(root?[element: "info"]?[string: "Author"], "René")
        XCTAssertEqual(root?[element: "info"]?[string: "Subject"], "plain")
    }
}
