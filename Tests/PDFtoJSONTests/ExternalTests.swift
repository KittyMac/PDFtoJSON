import XCTest
import PDFtoJSON
import Hitch
import Spanker

private func testdata(path: String) -> String {
    guard path.hasPrefix("/") == false else { return path }
    return URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent(path).path
}

private func text(_ root: JsonElement?, _ debug: Bool) -> Hitch {
    if debug { print(root!.toHitch()) }
    guard let pages = root?[element: "pages"] else { return "" }
    return pages.toHitch()
}

final class ExternalTests: XCTestCase {
    
    func testPDF0() {
        let pdf = Hitch(contentsOfFile: testdata(path: "Data/pdfs/test0.pdf"))!
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("hello world"))
        }
    }
    
    #if os(macOS)
    func testPDF1() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test1.pdf"))!
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("United States"))
        }
    }
    
    func testPDF2() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test2.pdf"))!
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("automatically"))
        }
    }
    
    func testPDF3() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test3.pdf"))!
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("See complete"))

        }
    }
    
    func testPDF4() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test4.pdf"))!
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("Entry Method"))
        }
    }
    
    func testPDF5() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test5.pdf"))!
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("may be applicable"))

        }
    }
    
    func testPDF6() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test6.pdf"))!
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, true).contains("NOT WORKING"))

        }
    }
    
    func testPDF7() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test7.pdf"))!
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("Appreciation Night"))
        }
    }
    
    func testPDF8() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test8.pdf"))!
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, true).contains("NOT WORKING"))
        }
    }
    
    func testPDF9() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test9.pdf"))!
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("Operated under"))
        }
    }
    
    func testPDF10() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test10.pdf"))!
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("Operated under"))
        }
    }
    
    #endif
    
}
