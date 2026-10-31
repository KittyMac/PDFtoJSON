import Foundation
import Spanker
import Hitch
import CryptoSwift

// Standard security handler (ISO 32000-1 7.6.3, ISO 32000-2 7.6.4):
// RC4 40-128 bit (R2-R4), AES-128 (V4 AESV2), AES-256 (V5 R5/R6 AESV3), crypt filters.

public let ENCRYPTION_TYPE_NONE = 0
public let ENCRYPTION_TYPE_RC4_40 = 1
public let ENCRYPTION_TYPE_RC4_128 = 2
public let ENCRYPTION_TYPE_AES_128 = 3
public let ENCRYPTION_TYPE_AES_256 = 4

private let passwordPadding: [UInt8] = [
    0x28, 0xbf, 0x4e, 0x5e, 0x4e, 0x75, 0x8a, 0x41,
    0x64, 0x00, 0x4e, 0x56, 0xff, 0xfa, 0x01, 0x08,
    0x2e, 0x2e, 0x00, 0xb6, 0xd0, 0x68, 0x3e, 0x80,
    0x2f, 0x0c, 0xa9, 0xfe, 0x64, 0x53, 0x69, 0x7a
]

enum CryptMethod {
    case identity
    case rc4
    case aesV2
    case aesV3
}

struct CryptState {
    let fileKey: [UInt8]
    let stringMethod: CryptMethod
    let streamMethod: CryptMethod
    let encryptMetadata: Bool
    /// named crypt filters, for streams that select one with a /Crypt filter
    let filters: [String: CryptMethod]
}

// MARK: - Primitives

func rc4(_ key: [UInt8], _ data: [UInt8]) -> [UInt8] {
    guard key.isEmpty == false else { return data }
    var s = [UInt8](0...255)
    var j = 0
    for i in 0..<256 {
        j = (j + Int(s[i]) + Int(key[i % key.count])) & 0xFF
        s.swapAt(i, j)
    }
    var out = [UInt8](repeating: 0, count: data.count)
    var i = 0
    j = 0
    for idx in 0..<data.count {
        i = (i + 1) & 0xFF
        j = (j + Int(s[i])) & 0xFF
        s.swapAt(i, j)
        out[idx] = data[idx] ^ s[(Int(s[i]) + Int(s[j])) & 0xFF]
    }
    return out
}

/// AES-CBC decrypt with the IV in the first 16 bytes; PKCS#7 padding removed leniently.
private func aesDecrypt(_ key: [UInt8], _ data: [UInt8]) -> [UInt8]? {
    guard data.count >= 16 else { return [] }
    let iv = Array(data[0..<16])
    let body = data[16..<(16 + (data.count - 16) / 16 * 16)]
    guard body.isEmpty == false else { return [] }
    guard let aes = try? AES(key: key, blockMode: CBC(iv: iv), padding: .noPadding),
          var plain = try? aes.decrypt(Array(body)) else { return nil }
    if let last = plain.last, last >= 1, last <= 16, Int(last) <= plain.count,
       plain.suffix(Int(last)).allSatisfy({ $0 == last }) {
        plain.removeLast(Int(last))
    }
    return plain
}

private func aesNoPadding(_ key: [UInt8], iv: [UInt8], _ data: [UInt8], encrypt: Bool) -> [UInt8]? {
    guard let aes = try? AES(key: key, blockMode: CBC(iv: iv), padding: .noPadding) else { return nil }
    return encrypt ? try? aes.encrypt(data) : try? aes.decrypt(data)
}

// MARK: - Decryption of objects

/// Per-object key for RC4 and AESV2 (Algorithm 1).
private func objectKey(_ state: CryptState, id: Int, generation: Int, aes: Bool) -> [UInt8] {
    var input = state.fileKey
    input.append(UInt8(truncatingIfNeeded: id))
    input.append(UInt8(truncatingIfNeeded: id >> 8))
    input.append(UInt8(truncatingIfNeeded: id >> 16))
    input.append(UInt8(truncatingIfNeeded: generation))
    input.append(UInt8(truncatingIfNeeded: generation >> 8))
    if aes {
        input.append(contentsOf: [0x73, 0x41, 0x6C, 0x54]) // "sAlT"
    }
    return Array(input.md5().prefix(min(state.fileKey.count + 5, 16)))
}

private func decrypt(_ state: CryptState,
                     method: CryptMethod,
                     id: Int,
                     generation: Int,
                     _ data: [UInt8]) -> [UInt8]? {
    switch method {
    case .identity:
        return data
    case .rc4:
        return rc4(objectKey(state, id: id, generation: generation, aes: false), data)
    case .aesV2:
        return aesDecrypt(objectKey(state, id: id, generation: generation, aes: true), data)
    case .aesV3:
        return aesDecrypt(state.fileKey, data)
    }
}

/// Decrypt a string belonging to object `id` (nil `crypt` or id < 0: unchanged).
func decryptString(_ context: PDFContext,
                   id: Int,
                   generation: Int,
                   _ bytes: Hitch) -> Hitch {
    guard id >= 0, let state = context.crypt else { return bytes }
    guard let plain = decrypt(state, method: state.stringMethod, id: id, generation: generation, Array(bytes)) else {
        context.warn("object \(id): string could not be decrypted")
        return bytes
    }
    return Hitch(bytes: plain, offset: 0, count: plain.count)
}

/// Decrypt the raw data of a stream, honoring /Crypt filters and unencrypted metadata.
func decryptStream(_ context: PDFContext,
                   _ raw: RawStream) -> Hitch {
    guard let state = context.crypt else { return raw.data.hitch() }

    if isXRef(raw.info) {
        return raw.data.hitch()
    }
    if state.encryptMetadata == false, raw.info[hitch: "Type"] == "Metadata" {
        return raw.data.hitch()
    }

    var method = state.streamMethod
    // a /Crypt entry in the filter list selects a named crypt filter
    for (name, parms) in streamFilters(context, raw.info) where name == HalfHitch("Crypt") {
        let filterName = parms?[string: "Name"] ?? "Identity"
        method = filterName == "Identity" ? .identity : (state.filters[filterName] ?? method)
    }

    guard let plain = decrypt(state, method: method, id: raw.id, generation: raw.generation, Array(raw.data)) else {
        context.warn("object \(raw.id): stream could not be decrypted")
        return raw.data.hitch()
    }
    return Hitch(bytes: plain, offset: 0, count: plain.count)
}

// MARK: - Key derivation

private func padded(_ password: [UInt8]) -> [UInt8] {
    return Array((password.prefix(32) + passwordPadding).prefix(32))
}

private func le32(_ value: Int) -> [UInt8] {
    let v = UInt32(truncatingIfNeeded: value)
    return [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
}

/// Algorithm 2: file key from a (user) password, revisions 2-4.
private func fileKeyR4(password: [UInt8], o: [UInt8], p: Int, id0: [UInt8],
                       revision: Int, length: Int, encryptMetadata: Bool) -> [UInt8] {
    var input = padded(password)
    input += o.prefix(32)
    input += le32(p)
    input += id0
    if revision >= 4 && encryptMetadata == false {
        input += [0xFF, 0xFF, 0xFF, 0xFF]
    }
    var digest = input.md5()
    if revision >= 3 {
        for _ in 0..<50 {
            digest = Array(digest.prefix(length)).md5()
        }
    }
    return Array(digest.prefix(length))
}

/// Algorithm 6: does `key` validate against /U?
private func checkUserKeyR4(_ key: [UInt8], u: [UInt8], id0: [UInt8], revision: Int) -> Bool {
    if revision == 2 {
        return rc4(key, passwordPadding) == Array(u.prefix(32))
    }
    var x = rc4(key, (passwordPadding + id0).md5())
    for i in 1...19 {
        x = rc4(key.map { $0 ^ UInt8(i) }, x)
    }
    return Array(x.prefix(16)) == Array(u.prefix(16))
}

/// Algorithm 7: recover the padded user password from an owner password.
private func userPasswordFromOwnerR4(owner: [UInt8], o: [UInt8], revision: Int, length: Int) -> [UInt8] {
    var digest = padded(owner).md5()
    if revision >= 3 {
        for _ in 0..<50 { digest = digest.md5() }
    }
    let key = Array(digest.prefix(revision == 2 ? 5 : length))
    if revision == 2 {
        return rc4(key, Array(o.prefix(32)))
    }
    var x = Array(o.prefix(32))
    for i in stride(from: 19, through: 0, by: -1) {
        x = rc4(key.map { $0 ^ UInt8(i) }, x)
    }
    return x
}

/// Algorithm 2.A/2.B: password hash for revisions 5 and 6.
private func hashR6(password: [UInt8], salt: [UInt8], udata: [UInt8], revision: Int) -> [UInt8] {
    var k = (password + salt + udata).sha256()
    guard revision >= 6 else { return k }

    var round = 0
    while true {
        var k1: [UInt8] = []
        let block = password + k + udata
        k1.reserveCapacity(block.count * 64)
        for _ in 0..<64 { k1 += block }
        guard let e = aesNoPadding(Array(k[0..<16]), iv: Array(k[16..<32]), k1, encrypt: true) else { return k }
        let remainder = e.prefix(16).reduce(0) { ($0 + Int($1)) } % 3
        switch remainder {
        case 0: k = e.sha256()
        case 1: k = e.sha384()
        default: k = e.sha512()
        }
        round += 1
        if round >= 64, let last = e.last, Int(last) <= round - 32 {
            break
        }
    }
    return Array(k.prefix(32))
}

private func cryptMethod(_ name: String?, filters: [String: CryptMethod]) -> CryptMethod {
    guard let name = name, name != "Identity" else { return .identity }
    return filters[name] ?? .identity
}

/// Set up decryption from the /Encrypt dictionary. Returns an error message if the
/// file cannot be decrypted (unsupported handler or wrong/missing password).
func setupEncryption(_ context: PDFContext,
                     encrypt: JsonElement,
                     password: String?) -> String? {
    guard encrypt[string: "Filter"] == "Standard" else {
        return "unsupported security handler \(encrypt[string: "Filter"] ?? "(none)")"
    }
    let version = encrypt[int: "V"] ?? 0
    let revision = encrypt[int: "R"] ?? 0
    let encryptMetadata = encrypt[element: "EncryptMetadata"]?.boolValue ?? true
    let permissions = encrypt[int: "P"] ?? 0

    guard let o = stringBytes(encrypt[element: "O"]).map(Array.init),
          let u = stringBytes(encrypt[element: "U"]).map(Array.init) else {
        return "encryption dictionary is missing /O or /U"
    }

    // Crypt filters (V4/V5); V1-V3 always use RC4 for everything
    var filters: [String: CryptMethod] = [:]
    var stringMethod = CryptMethod.rc4
    var streamMethod = CryptMethod.rc4
    var length = version == 1 ? 5 : max(5, min(16, (encrypt[int: "Length"] ?? 40) / 8))

    if version >= 4 {
        if let cf = encrypt[element: "CF"], cf.type == .dictionary {
            for (name, filter) in cf.iterWalking {
                switch filter[string: "CFM"] {
                case "V2": filters[name.toString()] = .rc4
                case "AESV2": filters[name.toString()] = .aesV2
                case "AESV3": filters[name.toString()] = .aesV3
                default: filters[name.toString()] = .identity
                }
                if let bits = filter[int: "Length"] {
                    // Length is in bytes for crypt filters in practice, sometimes bits
                    length = bits > 32 ? bits / 8 : bits
                }
            }
        }
        stringMethod = cryptMethod(encrypt[string: "StrF"], filters: filters)
        streamMethod = cryptMethod(encrypt[string: "StmF"], filters: filters)
        if version == 4 { length = 16 }
    }

    let passwordBytes = Array((password ?? "").utf8)
    var fileKey: [UInt8]? = nil

    if revision >= 5 {
        // AES-256: /U and /O are 48 bytes (hash, validation salt, key salt)
        guard u.count >= 48, o.count >= 48,
              let ue = stringBytes(encrypt[element: "UE"]).map(Array.init),
              let oe = stringBytes(encrypt[element: "OE"]).map(Array.init),
              ue.count >= 32, oe.count >= 32 else {
            return "encryption dictionary is missing AES-256 key data"
        }
        let pw = Array(passwordBytes.prefix(127))
        let u48 = Array(u.prefix(48))
        let zeroIV = [UInt8](repeating: 0, count: 16)

        if hashR6(password: pw, salt: Array(o[32..<40]), udata: u48, revision: revision) == Array(o.prefix(32)) {
            let key = hashR6(password: pw, salt: Array(o[40..<48]), udata: u48, revision: revision)
            fileKey = aesNoPadding(key, iv: zeroIV, Array(oe.prefix(32)), encrypt: false)
        } else if hashR6(password: pw, salt: Array(u[32..<40]), udata: [], revision: revision) == Array(u.prefix(32)) {
            let key = hashR6(password: pw, salt: Array(u[40..<48]), udata: [], revision: revision)
            fileKey = aesNoPadding(key, iv: zeroIV, Array(ue.prefix(32)), encrypt: false)
        }
        if version < 5 || filters.isEmpty {
            stringMethod = .aesV3
            streamMethod = .aesV3
        }
    } else {
        guard revision >= 2 else { return "unsupported encryption revision \(revision)" }
        let id0 = context.trailer?[element: "ID"].flatMap { stringBytes($0[element: 0]) }.map(Array.init) ?? []
        if revision == 2 { length = 5 }

        // the password as a user password
        let userKey = fileKeyR4(password: passwordBytes, o: o, p: permissions, id0: id0,
                                revision: revision, length: length, encryptMetadata: encryptMetadata)
        if checkUserKeyR4(userKey, u: u, id0: id0, revision: revision) {
            fileKey = userKey
        } else {
            // the password as an owner password
            let userPassword = userPasswordFromOwnerR4(owner: passwordBytes, o: o, revision: revision, length: length)
            let ownerKey = fileKeyR4(password: userPassword, o: o, p: permissions, id0: id0,
                                     revision: revision, length: length, encryptMetadata: encryptMetadata)
            if checkUserKeyR4(ownerKey, u: u, id0: id0, revision: revision) {
                fileKey = ownerKey
            }
        }
    }

    guard let key = fileKey else {
        return password == nil ? "document requires a password" : "incorrect password"
    }

    context.crypt = CryptState(fileKey: key,
                               stringMethod: stringMethod,
                               streamMethod: streamMethod,
                               encryptMetadata: encryptMetadata,
                               filters: filters)
    return nil
}
