import XCTest
import Hitch
import Spanker

@testable import PDFtoJSON

final class EncryptionTests: XCTestCase {

    func testDecryptedInfoStrings() {
        let root = corpusParse("enc_aes_256_info")
        XCTAssertEqual(root?[element: "info"]?[string: "Title"], "Hi ɣ")
        XCTAssertEqual(root?[element: "info"]?[string: "Author"], "René")
    }

    func testMissingPasswordReturnsDocumentWithError() {
        let root = corpusParse("enc_aes_256_userpw")
        XCTAssertNotNil(root)
        XCTAssertEqual(root?[string: "__error"], "document requires a password")
        XCTAssertEqual(root?[element: "pages"]?.count ?? 0, 0)
    }

    func testWrongPassword() {
        let root = corpusParse("enc_rc4_128_userpw", password: "nope")
        XCTAssertEqual(root?[string: "__error"], "incorrect password")
    }

    func testOwnerPasswordOpensRC4AndAES128() {
        for name in ["enc_rc4_128_userpw", "enc_aes_128_userpw"] {
            let text = corpusText(corpusParse(name, password: "owner"))
            XCTAssertTrue(text.contains("hello world"), name)
        }
    }

    func testKeysAreNotInOutput() {
        let json = corpusParse("enc_rc4_128")?.toString() ?? ""
        XCTAssertFalse(json.contains("fileKey"))
        XCTAssertFalse(json.contains("\"password\""))
        XCTAssertFalse(json.contains("encryptionType"))
    }

    func testEncryptionDictionaryKeptLossless() {
        // /O and /U are binary; they're exported as <HEX>
        let root = corpusParse("enc_rc4_128")
        let encryptId = root?[element: "trailer"]?[element: "Encrypt"]?[int: "id"] ?? -1
        let o = root?[element: "objects"]?[element: String(encryptId)]?[element: "value"]?[string: "O"]
        XCTAssertEqual(o?.first, "<")
        XCTAssertEqual(o?.count, 66)
    }

    func testRC4() {
        // RFC 6229 test vector: key 0x0102030405, first output bytes
        XCTAssertEqual(rc4([1, 2, 3, 4, 5], [0, 0, 0, 0]), [0xb2, 0x39, 0x63, 0x05])
    }
}

final class OutputTests: XCTestCase {
    func testOutputIsDeterministic() {
        let path = URL(fileURLWithPath: #file).deletingLastPathComponent()
            .appendingPathComponent("Data/corpus/objstm.pdf").path
        let pdf = Hitch(contentsOfFile: path)!
        let options = PDFtoJSON.Options(includeParseDate: false)
        let first = PDFtoJSON.parsed(hitch: pdf, options: options) { $0?.toString() }
        let second = PDFtoJSON.parsed(hitch: pdf, options: options) { $0?.toString() }
        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first?.contains("__parse_date") ?? true)
    }
}
