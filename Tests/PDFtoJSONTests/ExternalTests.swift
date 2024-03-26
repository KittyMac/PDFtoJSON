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
    
    func testPDF1() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test1.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("United States"))
        }
    }
    
    func testPDF2() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test2.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("automatically"))
        }
    }
    
    func testPDF3() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test3.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("See complete"))

        }
    }
    
    func testPDF4() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test4.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("Entry Method"))
        }
    }
    
    func testPDF5() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test5.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("may be applicable"))

        }
    }
    
    func testPDF6() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test6.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("First Floor"))

        }
    }
    
    func testPDF7() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test7.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("Appreciation Night"))
        }
    }
    
    func testPDF8() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test8.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, true).contains("NOT WORKING"))
        }
    }
    
    func testPDF9() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test9.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("Operated under"))
        }
    }
    
    func testPDF10() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test10.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("WEATHERSHIELD"))
        }
    }
    
    func testPDF11() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test11.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("sales tax"))
        }
    }
    
    func testPDF12() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test12.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, false).contains("Winter Blue Solo Loop"))
        }
    }
    
    func testPDF13() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test13.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, true).contains("Winter Blue Solo Loop"))
        }
    }
    
    func testPDF14() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test14.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, true).contains("Winter Blue Solo Loop"))
        }
    }
    
    func testPDF15() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test15.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, true).contains("Winter Blue Solo Loop"))
        }
    }
    
    func testPDF16() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test16.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, true).contains("Winter Blue Solo Loop"))
        }
    }
    
    func testPDF17() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test17.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, true).contains("Winter Blue Solo Loop"))
        }
    }
    
    func testPDF18() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test18.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, true).contains("Winter Blue Solo Loop"))
        }
    }
    
    
    
    func testPDF20() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test20.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, true).contains("Winter Blue Solo Loop"))
        }
    }
    
    func testPDF21() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test21.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, true).contains("Winter Blue Solo Loop"))
        }
    }
    
    func testPDF22() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test22.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, true).contains("Winter Blue Solo Loop"))
        }
    }
    
    func testPDF23() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test23.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, true).contains("Winter Blue Solo Loop"))
        }
    }
    
    func testPDF24() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test24.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, true).contains("Winter Blue Solo Loop"))
        }
    }
    
    func testPDF30() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test30.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, true).contains("Winter Blue Solo Loop"))
        }
    }
    
    func testPDF31() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test31.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, true).contains("Winter Blue Solo Loop"))
        }
    }
    
    func testPDF32() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test32.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, true).contains("Winter Blue Solo Loop"))
        }
    }
    
    func testPDF33() {
        guard let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test33.pdf")) else { return }
        PDFtoJSON.parsed(hitch: pdf) { root in
            XCTAssertTrue(text(root, true).contains("Winter Blue Solo Loop"))
        }
    }
}
