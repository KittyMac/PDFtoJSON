import XCTest
import Hitch
import Spanker

@testable import PDFtoJSON

final class InternalTests: XCTestCase {
    
    // MARK: - Keys
    func testParseKey0() {
        let pdf: Hitch = "/SomeName"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.stringValue, "SomeName")
    }
    
    // MARK: - Strings
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
    
    // MARK: - Hexstrings
    func testParseHexstring0() {
        let pdf: Hitch = "<4E6F762073686D6F7A206B6120706F702E>"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.stringValue, "Tm92IHNobW96IGthIHBvcC4=")
    }
    
    func testParseHexstringMissingLastChar() {
        let pdf: Hitch = "<41424>"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.stringValue, "QUJA")
    }
    
    // MARK: - Numbers
    func testParseInteger0() {
        let pdf: Hitch = "42"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.intValue, 42)
    }
    
    func testParseInteger1() {
        let pdf: Hitch = "[ 123 43445 +17 -98 0 ]"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.description, #"[123,43445,17,-98,0]"#)
    }
    
    func testParseDouble0() {
        let pdf: Hitch = "42.42"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.doubleValue, 42.42)
    }
    
    func testParseDouble1() {
        let pdf: Hitch = "[ 34.5 -3.62 +123.6 4. -.002 0.0 ]"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.description, #"[34.5,-3.62,123.6,4.0,-0.002,0.0]"#)
    }
    
    // MARK: - Arrays
    func testParseArray0() {
        let pdf: Hitch = "[ (hello) <776f726c64> /SomeKey false true null 1 2.0 null ]"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.description, #"["hello","d29ybGQ=","SomeKey",false,true,null,1,2.0,null]"#)
    }
    
    // MARK: - Dictionaries
    func testParseDictionary0() {
        let pdf: Hitch = "<< /Title (untitled 2) >>"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.description, #"{"Title":"untitled 2"}"#)
    }
    
    func testParseDictionary1() {
        let pdf: Hitch = #"""
        << /Title (untitled 2) /Producer (macOS Version 13.6.1 \(Build 22G313\) Quartz PDFContext)
        /Author (Rocco Bowling) /Creator (TextMate) /CreationDate (D:20240301135834Z00'00')
        /ModDate (D:20240301135834Z00'00') >>
        """#
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.description, #"{"Title":"untitled 2","Producer":"macOS Version 13.6.1 (Build 22G313) Quartz PDFContext","Author":"Rocco Bowling","Creator":"TextMate","CreationDate":"D:20240301135834Z00'00'","ModDate":"D:20240301135834Z00'00'"}"#)
    }
    
    // MARK: - Object Definitions
    func testParseObjectDefinition0() {
        let pdf: Hitch = """
        13 0 obj
        (hello world)
        endobj
        """
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.description, #"{"id":13,"generation":0,"value":"hello world"}"#)
    }
    
    // MARK: - Object Reference
    func testParseObjectReference0() {
        let pdf: Hitch = "13 0 R"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.description, #"{"id":13,"generation":0}"#)
    }
    
    func testParseObjectReference1() {
        let pdf: Hitch = "[ 1 0 R 2 0 R 3 0 R ]"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end)?.description, #"[{"id":1,"generation":0},{"id":2,"generation":0},{"id":3,"generation":0}]"#)
    }
        
    // MARK: - Misc
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
    
    func testParseComment() {
        let pdf: Hitch = "% this is a comment"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(&ptr, end), nil)
    }
    
}
