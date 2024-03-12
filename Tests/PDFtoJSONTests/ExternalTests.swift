import XCTest
import PDFtoJSON
import Hitch

private func testdata(path: String) -> String {
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
    
}
