import XCTest
import PDFtoJSON
import Hitch

private func testdata(path: String) -> String {
    return URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent(path).path
}

final class PDFtoJSONTests: XCTestCase {
    
    func testImage0() {
        //let pdf = Hitch(contentsOfFile: testdata(path: "Data/pdfs/test0.pdf"))!
        
        //guard let pdfJson = PDFtoJSON.parse(file: testdata(path: "Data/pdfs/test1.pdf")) else { XCTFail(); return }
        
        //let result = PDFtoJSON.parse(image: image.dataNoCopy())
        //XCTAssertEqual(result, "1234567890\n")
    }
    
}
