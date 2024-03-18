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
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.stringValue, "SomeName")
    }
    
    // MARK: - Strings
    func testParseString0() {
        let pdf: Hitch = "(This is a string)"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.stringValue, "This is a string")
    }
    
    func testParseMultilineString0() {
        let pdf: Hitch = "(These \\\ntwo strings \\\nare the same.)"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.stringValue, "These two strings are the same.")
    }
    
    func testParseEscapedString0() {
        let pdf: Hitch = #"(\n\r\t\(\)\\\053\53"#
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.stringValue, "\n\r\t()\\++")
    }
    
    func testParseStringWithNewLines0() {
        let pdf: Hitch = "(Strings may contain newlines\nand such.)"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.stringValue, "Strings may contain newlines\nand such.")
    }
    
    func testParseStringWithSpecialCharacters0() {
        let pdf: Hitch = "(Strings may contain balanced parentheses () and\nspecial characters (*!&}^% and so on).)"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.stringValue, "Strings may contain balanced parentheses () and\nspecial characters (*!&}^% and so on).")
    }
    
    func testParseEmptyString0() {
        let pdf: Hitch = "()"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.stringValue, "")
    }
    
    // MARK: - Hexstrings
    func testParseHexstring0() {
        let pdf: Hitch = "<4E6F762073686D6F7A206B6120706F702E>"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.stringValue, "Nov shmoz ka pop.")
    }
    
    func testParseHexstringMissingLastChar() {
        let pdf: Hitch = "<41424>"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.stringValue, "AB@")
    }
    
    // MARK: - Numbers
    func testParseInteger0() {
        let pdf: Hitch = "42"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.intValue, 42)
    }
    
    func testParseInteger1() {
        let pdf: Hitch = "[ 123 43445 +17 -98 0 ]"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.description, #"[123,43445,17,-98,0]"#)
    }
    
    func testParseDouble0() {
        let pdf: Hitch = "42.42"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.doubleValue, 42.42)
    }
    
    func testParseDouble1() {
        let pdf: Hitch = "[ 34.5 -3.62 +123.6 4. -.002 0.0 ]"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.description, #"[34.5,-3.62,123.6,4.0,-0.002,0.0]"#)
    }
    
    // MARK: - Arrays
    func testParseArray0() {
        let pdf: Hitch = "[ (hello) <776f726c64> /SomeKey false true null 1 2.0 null ]"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.description, #"["hello","world","SomeKey",false,true,null,1,2.0,null]"#)
    }
    
    // MARK: - Dictionaries
    func testParseDictionary0() {
        let pdf: Hitch = "<< /Title (untitled 2) >>"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.description, #"{"Title":"untitled 2"}"#)
    }
    
    func testParseDictionary1() {
        let pdf: Hitch = #"""
        << /Title (untitled 2) /Producer (macOS Version 13.6.1 \(Build 22G313\) Quartz PDFContext)
        /Author (Rocco Bowling) /Creator (TextMate) /CreationDate (D:20240301135834Z00'00')
        /ModDate (D:20240301135834Z00'00') >>
        """#
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.description, #"{"Title":"untitled 2","Producer":"macOS Version 13.6.1 (Build 22G313) Quartz PDFContext","Author":"Rocco Bowling","Creator":"TextMate","CreationDate":"D:20240301135834Z00'00'","ModDate":"D:20240301135834Z00'00'"}"#)
    }
    
    func testParseDictionary2() {
        let pdf: Hitch = #"""
        1 0 obj
        << /Type /Page /Parent 2 0 R /Resources 4 0 R /Contents 3 0 R /MediaBox [0 0 612 792]
        >>
        endobj
        """#
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.description, #"{"id":1,"generation":0,"value":{"Type":"Page","Parent":{"id":2,"generation":0},"Resources":{"id":4,"generation":0},"Contents":{"id":3,"generation":0},"MediaBox":[0,0,612,792]}}"#)
    }
    
    func testParseDictionary3() {
        let pdf: Hitch = #"""
        <<
        /ProcSet [/PDF /Text /ImageB /ImageC]
        >>
        """#
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.description, #"{"ProcSet":["PDF","Text","ImageB","ImageC"]}"#)
    }
    
    func testParseDictionary4() {
        let pdf: Hitch = #"""
        3 0 obj
        <<
        /SMask /None>>
        endobj
        """#
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.description, #"{"id":3,"generation":0,"value":{"SMask":"None"}}"#)
    }
    
    func testParseDictionary5() {
        let pdf: Hitch = #"<</Subtype/Form/Filter/FlateDecode/Type/XObject/Matrix [1 0 0 1 0 0]/FormType 1/Resources<</ProcSet [/PDF /Text /ImageB /ImageC /ImageI]/Font<</F1 2 0 R>>>>/BBox[-20 -20 100 100]/Length 38>>"#
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.description, #"{"Subtype":"Form","Filter":"FlateDecode","Type":"XObject","Matrix":[1,0,0,1,0,0],"FormType":1,"Resources":{"ProcSet":["PDF","Text","ImageB","ImageC","ImageI"],"Font":{"F1":{"id":2,"generation":0}}},"BBox":[-20,-20,100,100],"Length":38}"#)
    }
    
    func testParseDictionary6() {
        let pdf: Hitch = """
        9 0 obj
        <</Kids[10 0 R]/Type/Pages/Count 1/ITXT(2.1.7)>>
        endobj
        """
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.description, #"{"id":9,"generation":0,"value":{"Kids":[{"id":10,"generation":0}],"Type":"Pages","Count":1,"ITXT":"2.1.7"}}"#)
    }
    
    func testParseDictionary7() {
        let pdf: Hitch = """
        <</XObject <</Im0 5 0 R
        /Im1 18 0 R
        >>
        /Font <</F2 13 0 R
        /F1 8 0 R
        /F3 21 0 R
        >>
        /ProcSet [ /PDF /Text ]
        >>
        """
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.description, #"{"XObject":{"Im0":{"id":5,"generation":0},"Im1":{"id":18,"generation":0}},"Font":{"F2":{"id":13,"generation":0},"F1":{"id":8,"generation":0},"F3":{"id":21,"generation":0}},"ProcSet":["PDF","Text"]}"#)
    }
    
    func testParseDictionary8() {
        let pdf: Hitch = """
        2 0 obj
        << /Type /Page % 1
           /Parent 1 0 R
           /MediaBox [ 0 0 612 792 ]
           /Contents 4 0 R
           /Group <<
              /Type /Group
              /S /Transparency
              /I true
              /CS /DeviceRGB
           >>
           /Resources 3 0 R
        >>
        endobj
        """
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.description, #"{"id":2,"generation":0,"value":{"Type":"Page","Parent":{"id":1,"generation":0},"MediaBox":[0,0,612,792],"Contents":{"id":4,"generation":0},"Group":{"Type":"Group","S":"Transparency","I":true,"CS":"DeviceRGB"},"Resources":{"id":3,"generation":0}}}"#)
    }
    
    func testParseDictionary9() {
        let pdf: Hitch = """
        6 0 obj<</BaseFont/Courier-Bold/Type/Font/Encoding/WinAnsiEncoding/Subtype/Type1>>
        endobj
        """
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.description, #"{"id":6,"generation":0,"value":{"BaseFont":"Courier-Bold","Type":"Font","Encoding":"WinAnsiEncoding","Subtype":"Type1"}}"#)
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
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.description, #"{"id":13,"generation":0,"value":"hello world"}"#)
    }
    
    // MARK: - Object Reference
    func testParseObjectReference0() {
        let pdf: Hitch = "13 0 R"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.description, #"{"id":13,"generation":0}"#)
    }
    
    func testParseObjectReference1() {
        let pdf: Hitch = "[ 1 0 R 2 0 R 3 0 R ]"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.description, #"[{"id":1,"generation":0},{"id":2,"generation":0},{"id":3,"generation":0}]"#)
    }
        
    // MARK: - Misc
    func testParseNull0() {
        let pdf: Hitch = "null"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.type, .null)
    }
    
    func testParseBooleanTrue() {
        let pdf: Hitch = "true"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.boolValue, true)
    }
    
    func testParseBooleanFalse() {
        let pdf: Hitch = "false"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end)?.boolValue, false)
    }
    
    func testParseComment() {
        let pdf: Hitch = "% this is a comment"
        guard var ptr = pdf.raw() else { XCTFail(); return }
        let end = ptr + pdf.count
        XCTAssertEqual(getObject(document: ^[],
                                 id: 0,
                                 generation: 0, &ptr, ptr, end), nil)
    }
    
    // MARK: - PostScript
    
    func testToUnicode() {
        XCTAssertEqual(toUnicode("006F"), 111)
    }
    
    func testPostScript0() {
        let postscript: HalfHitch = """
        q Q q 12.49999 756.7543 587 23 re W n /Cs1 cs 1 sc 12.49999 779.7543 m 599.5
        779.7543 l 599.5 756.7543 l 12.49999 756.7543 l h f /Cs2 cs 0 0 0 sc q 1 0 0 1 12.49999 741.7543
        cm BT 0.0001 Tc 11 0 0 11 8 19 Tm /TT1 1 Tf (hello world) Tj ET Q Q
        """
        XCTAssertEqual(reify(document: ^[], id: -1, generation: -1, postScript: postscript)?.description,
                       #"[{"x":20,"y":760,"text":"hello world"}]"#)
    }
    
    func testPostScript1() {
        let postscript: HalfHitch = """
        BT
        1 0 0 1 14 796 Tm
        /F1 12 Tf
        ()Tj
        ET
        """
        XCTAssertEqual(reify(document: ^[], id: -1, generation: -1, postScript: postscript)?.description,
                       #"[]"#)
    }
    
    func testPostScript2() {
        let postscript: HalfHitch = """
        q Q q 12.49999 756.7543 587 23 re W n /Cs1 cs 1 sc 12.49999 779.7543 m 599.5
        779.7543 l 599.5 756.7543 l 12.49999 756.7543 l h f /Cs2 cs 0 0 0 sc q 1 0 0 1 12.49999 741.7543
        cm BT 0.0001 Tc 11 0 0 11 8 19 Tm /TT1 1 Tf [(hello) 200 (world)] TJ ET Q Q
        """
        XCTAssertEqual(reify(document: ^[], id: -1, generation: -1, postScript: postscript)?.description,
                       #"[{"x":20,"y":760,"text":"helloworld"}]"#)
    }
}
