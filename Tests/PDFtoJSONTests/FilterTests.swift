import XCTest
import Hitch
import Spanker

@testable import PDFtoJSON

// Test vectors generated with Data/corpus/gen.py's reference encoders.

private func bytes(hex: String) -> Hitch {
    let out = Hitch(capacity: hex.count / 2)
    var chars = Array(hex.utf8)
    if chars.count % 2 == 1 { chars.append(UInt8(ascii: "0")) }
    var idx = 0
    while idx < chars.count {
        let pair = String(bytes: chars[idx..<idx+2], encoding: .ascii)!
        out.append(UInt8(pair, radix: 16)!)
        idx += 2
    }
    return out
}

final class FilterTests: XCTestCase {

    let plain = bytes(hex: "54686520717569636b2062726f776e20666f78206a756d7073206f76657220746865206c617a7920646f67203031323334353637383921")
    let padded = bytes(hex: "54686520717569636b2062726f776e20666f78206a756d7073206f76657220746865206c617a7920646f67203031323334353637383921")
    let rgbPlain = bytes(hex: "00050a0f14191e23282d32373c41464b50555a5f64696e73787d82878c91969ba0a5aaafb4b9bec3c8cdd2d7dce1e6eb")

    func testPNGPredictors() {
        let vectors = ["789c0dcad90140301404c02d6575e03efad080236e798408aa67be07e5a0b8c38ecd4cd4469c063bb989c9aedb01caa50c78fe094bf53e442b3d7d0461142748b3bcf03e8c291228", "789c630c11f9bb3b90b1f4cb2f8ead8c49027f39be332ab87172ae60cce2fec1cccca8e0cffe9e975121e4cbdfdd8c395f25ff2f674ce1feb15380d1901104cc80f805001b8415d6", "789c630ac9485528645264fce7bd9ee92d270f8f1fd3be2f0c8c9b98bcf8fffd0866daf68bf3eb7f2606d64f0ceb987cde0a893030fde07bbb5c80e9ece13322ac4cac40f00600029c1716", "789c014200bdff03543e31ee61034bfbfc2ab203280d050a2303ef1d0505ad035a0dfbfe2b03eb2508f20603102df3ffb5035cf1160ad4032e0df3b01003ffe2e70b03031e030303eafa2c1711", "789c014200bdff045414fdbb510421f4fe4baf04ed1006084e04be460901b2044a0bf8f85304b64f09ef0d040005f200ae044ced19ff0004f80eedb91004cd010114010405010101e81b7915ec"]
        for (ftype, vector) in vectors.enumerated() {
            let parms: JsonElement = ^["Predictor": 12, "Columns": 5]
            let decoded = decodeFilters(nil, [("FlateDecode", parms)], bytes(hex: vector))
            XCTAssertEqual(decoded, padded, "PNG filter type \(ftype)")
        }
    }

    func testPNGPredictorsMultiByte() {
        let vectors = ["789c013400cbff0000050a0f14191e23282d3237003c41464b50555a5f64696e7300787d82878c91969ba0a5aaaf00b4b9bec3c8cdd2d7dce1e6eb7b171609", "789c636460e5e28701461b473704a7a2b609c1d9b2731f9c03008e5a0695", "789c636260e5e217919453d6d0353267b24102b83900dd9c09c3", "789c636660e5e2171211979491535466b6b177548301e6a8d87804a7a2ba16ce0100b82d0843", "789c636160e5e28701161b1b1b2238006b6e0458"]
        for (ftype, vector) in vectors.enumerated() {
            let parms: JsonElement = ^["Predictor": 15, "Columns": 4, "Colors": 3]
            let decoded = decodeFilters(nil, [("FlateDecode", parms)], bytes(hex: vector))
            XCTAssertEqual(decoded, rgbPlain, "PNG filter type \(ftype), 3 bytes per pixel")
        }
    }

    func testLZW() {
        let expected = Hitch(capacity: plain.count * 20)
        for _ in 0..<20 { expected.append(plain) }
        XCTAssertEqual(decodeFilters(nil, [("LZWDecode", nil)], bytes(hex: "80150d065101c4ea69319ac4062391bcee6e10198de78101a8ea6d381cc406f3b194e4203a40c406c309e8f220321bcce20180c464331a0d46c371c0e443028241a110a8643a21128a45a311a8e47a41229249a512a964ba61329a4da710583c26170d87c4627158bc66371d8fc86094993ca6572d97cc667359bc8a75569ed66815ca1d7e8d6291c96cb4cb453ed752b755679589fd6e855ea2d86917aa5d9e9d6aa8db67382abcfab541aed12c147b1e32cd4db4d42d953b7e0f2d73c3e6aef8ba567efb90d1e067795b961b3376c56775b7cc7e8b0193d9dc70b98bae273979dde3b437fc95538384cbdd3119bbc5931ba0bf6474994e174753b8e3f5b5dbde676f9fa7db717a9acbdf2bb3b1e05c3a1a8dbf1bab9ede72fb5b2f97a388e9b56dd3daec360dfb9cfeb6affb54dcb9101b5edf39ad2b68e1ba505bc2fc3dd02c22ee3e6f4c01063c4fcbdf03424eebe8f540306baf07bcafe34d04c2af03eee4c09083cd04428efbecf6456f23228080")), expected)
    }

    func testASCII85() {
        XCTAssertEqual(decodeFilters(nil, [("ASCII85Decode", nil)], Hitch(string: #"<+ohcEHPu*CER),Dg-(AAoDo:C3=B4F!,CEATAo8BOr<&@=!2AA8c*'0JP==1c70M3&r,~>"#)), plain)
        XCTAssertEqual(ascii85Decode("<~z~>"), bytes(hex: "00000000"))
    }

    func testASCIIHex() {
        XCTAssertEqual(asciiHexDecode("48 65\n6c6C 6F>"), "Hello")
        XCTAssertEqual(asciiHexDecode("414>"), "A@")
    }

    func testRunLength() {
        XCTAssertEqual(decodeFilters(nil, [("RunLengthDecode", nil)], bytes(hex: "3654686520717569636b2062726f776e20666f78206a756d7073206f76657220746865206c617a7920646f6720303132333435363738392180")), plain)
        XCTAssertEqual(runLengthDecode(bytes(hex: "FE41 01 4242 80".replacingOccurrences(of: " ", with: ""))), "AAABB")
    }

    func testFilterChain() {
        let hex = Hitch(string: "789c0dcad90140301404c02d6575e03efad080236e798408aa67be07e5a0b8c38ecd4cd4469c063bb989c9aedb01caa50c78fe094bf53e442b3d7d0461142748b3bcf03e8c291228>")
        let parms: JsonElement = ^["Predictor": 12, "Columns": 5]
        let decoded = decodeFilters(nil, [("ASCIIHexDecode", nil), ("FlateDecode", parms)], hex)
        XCTAssertEqual(decoded, padded)
    }

    func testImageFiltersAreLeftEncoded() {
        let data: Hitch = "jpegbytes"
        XCTAssertEqual(decodeFilters(nil, [("DCTDecode", nil)], data), data)
    }

    func testTruncatedFlateKeepsPrefix() {
        let full = bytes(hex: "789c0dcad90140301404c02d6575e03efad080236e798408aa67be07e5a0b8c38ecd4cd4469c063bb989c9aedb01caa50c78fe094bf53e442b3d7d0461142748b3bcf03e8c291228")
        let truncated = Hitch(bytes: full.raw()!, offset: 0, count: full.count - 8)
        XCTAssertGreaterThan(flateDecode(truncated).count, 0)
    }
}
