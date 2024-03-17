import XCTest
import PDFtoJSON
import Hitch

private func testdata(path: String) -> String {
    guard path.hasPrefix("/") == false else { return path }
    return URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent(path).path
}

final class ExternalTests: XCTestCase {
    
    func testPDF0() {
        let pdf = Hitch(contentsOfFile: testdata(path: "Data/pdfs/test0.pdf"))!
        
        PDFtoJSON.parsed(hitch: pdf) { root in
            print(root!.toHitch())
        }
        
        //let result = PDFtoJSON.parse(image: image.dataNoCopy())
        //XCTAssertEqual(result, "1234567890\n")
    }
    
    #if os(macOS)
    func testPDF1() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test1.pdf"))!
        
        PDFtoJSON.parsed(hitch: pdf) { root in
            print(root!.toHitch())
        }
        
        //let result = PDFtoJSON.parse(image: image.dataNoCopy())
        //XCTAssertEqual(result, "1234567890\n")
    }
    
    func testPDF2() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test2.pdf"))!
        
        PDFtoJSON.parsed(hitch: pdf) { root in
            print(root!.toHitch())
        }
        
        //let result = PDFtoJSON.parse(image: image.dataNoCopy())
        //XCTAssertEqual(result, "1234567890\n")
    }
    
    func testPDF3() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test3.pdf"))!
        
        PDFtoJSON.parsed(hitch: pdf) { root in
            print(root!.toHitch())
        }
        
        //let result = PDFtoJSON.parse(image: image.dataNoCopy())
        //XCTAssertEqual(result, "1234567890\n")
    }
    
    func testPDF4() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test4.pdf"))!
        
        PDFtoJSON.parsed(hitch: pdf) { root in
            print(root!.toHitch())
        }
        
        //let result = PDFtoJSON.parse(image: image.dataNoCopy())
        //XCTAssertEqual(result, "1234567890\n")
    }
    
    func testPDF5() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test5.pdf"))!
        
        PDFtoJSON.parsed(hitch: pdf) { root in
            print(root!.toHitch())
        }
        
        //let result = PDFtoJSON.parse(image: image.dataNoCopy())
        //XCTAssertEqual(result, "1234567890\n")
    }
    
    func testPDF6() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test6.pdf"))!
        
        PDFtoJSON.parsed(hitch: pdf) { root in
            print(root!.toHitch())
        }
        
        //let result = PDFtoJSON.parse(image: image.dataNoCopy())
        //XCTAssertEqual(result, "1234567890\n")
    }
    
    func testPDF7() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test7.pdf"))!
        
        PDFtoJSON.parsed(hitch: pdf) { root in
            print(root!.toHitch())
        }
        
        //let result = PDFtoJSON.parse(image: image.dataNoCopy())
        //XCTAssertEqual(result, "1234567890\n")
    }
    
    func testPDF8() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test8.pdf"))!
        
        PDFtoJSON.parsed(hitch: pdf) { root in
            print(root!.toHitch())
        }
        
        //let result = PDFtoJSON.parse(image: image.dataNoCopy())
        //XCTAssertEqual(result, "1234567890\n")
    }
    
    func testPDF9() {
        let pdf = Hitch(contentsOfFile: testdata(path: "/Users/rjbowli/Development/data/pdfs/test9.pdf"))!
        
        PDFtoJSON.parsed(hitch: pdf) { root in
            print(root!.toHitch())
        }
        
        //let result = PDFtoJSON.parse(image: image.dataNoCopy())
        //XCTAssertEqual(result, "1234567890\n")
    }
    
    #endif
    
}
