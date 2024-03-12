import XCTest
import Hitch
import Spanker

@testable import PDFtoJSON

final class InternalTests: XCTestCase {
    
    func testParseString0() {
        let pdf: Hitch = "(This is a string)"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.stringValue, "This is a string")
    }
    
    func testParseMultilineString0() {
        let pdf: Hitch = "(These \\\ntwo strings \\\nare the same.)"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.stringValue, "These two strings are the same.")
    }
    
    func testParseEscapedString0() {
        let pdf: Hitch = #"(\n\r\t\(\)\\\053\53"#
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.stringValue, "\n\r\t()\\++")
    }
    
    func testParseStringWithNewLines0() {
        let pdf: Hitch = "(Strings may contain newlines\nand such.)"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.stringValue, "Strings may contain newlines\nand such.")
    }
    
    func testParseStringWithSpecialCharacters0() {
        let pdf: Hitch = "(Strings may contain balanced parentheses () and\nspecial characters (*!&}^% and so on).)"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.stringValue, "Strings may contain balanced parentheses () and\nspecial characters (*!&}^% and so on).")
    }
    
    func testParseEmptyString0() {
        let pdf: Hitch = "()"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.stringValue, "")
    }
    
    func testParseNull0() {
        let pdf: Hitch = "null"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.type, .null)
    }
    
    func testParseBooleanTrue() {
        let pdf: Hitch = "true"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.boolValue, true)
    }
    
    func testParseBooleanFalse() {
        let pdf: Hitch = "false"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.boolValue, false)
    }
    
}
