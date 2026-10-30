// Encryption code based on  https://github.com/michaelrsweet/pdfio

import Foundation
import Spanker
import Hitch
import CryptoSwift

@usableFromInline
let sAlT: Hitch = "sAlT"

@usableFromInline
let defaultPasswordPadding: [UInt8] = [
    0x28, 0xbf, 0x4e, 0x5e, 0x4e, 0x75, 0x8a, 0x41,
    0x64, 0x00, 0x4e, 0x56, 0xff, 0xfa, 0x01, 0x08,
    0x2e, 0x2e, 0x00, 0xb6, 0xd0, 0x68, 0x3e, 0x80,
    0x2f, 0x0c, 0xa9, 0xfe, 0x64, 0x53, 0x69, 0x7a
]

extension Hitchable {
    @usableFromInline
    func asArray() -> Array<UInt8> {
        let buffer = UnsafeBufferPointer(start: raw(), count: count)
        return Array(buffer)
    }
    
    @usableFromInline
    func asHexString() -> Hitch {
        let output = Hitch(capacity: count * 2)
        guard let start = raw() else { return output }
        var ptr = start
        let end = start + count
        while ptr < end {
            output.append(hex2((ptr[0] >> 4)))
            output.append(hex2(ptr[0] & 0x0F))
            ptr += 1
        }
        return output
    }
}

func decrypt(document: JsonElement,
             id: Int,
             generation: Int,
             content: HalfHitch) -> (String?, HalfHitch?) {
    guard id >= 0, generation >= 0 else { return (nil, content) }
    guard let fileKey = document[hitch: "fileKey"] else { return (nil, content) }
    guard let encryptionType = document[int: "encryptionType"] else { return (nil, content) }
    
    do {
        
        switch encryptionType {
            
        case ENCRYPTION_TYPE_RC4_40:
            let rc4 = RC4(key: fileKey.raw()!, len: 16)
            return (nil, rc4.crypt(content).halfhitch())
            
            
            
        case ENCRYPTION_TYPE_RC4_128, ENCRYPTION_TYPE_AES_128:
            let data = Hitch(capacity: 21)
            data.append(fileKey)
            data.append(UInt8(truncatingIfNeeded: id))
            data.append(UInt8(truncatingIfNeeded: id >> 8))
            data.append(UInt8(truncatingIfNeeded: id >> 16))
            data.append(UInt8(truncatingIfNeeded: generation))
            data.append(UInt8(truncatingIfNeeded: generation >> 8))
            
            var md5 = MD5()
            _ = try md5.update(withBytes: data.asArray())
            if encryptionType == ENCRYPTION_TYPE_AES_128 {
                _ = try md5.update(withBytes: sAlT.asArray())
            }
            let digest = try md5.finish()
            
            if encryptionType == ENCRYPTION_TYPE_RC4_128 {
                let rc4 = RC4(key: digest, len: digest.count)
                return (nil, rc4.crypt(content).halfhitch())
            } else {
                return ("AES 128 encryption not yet implemented", nil)
            }
        default:
            return ("unsupported encryption type", nil)
        }
    } catch {
        return ("\(error)", nil)
    }
    
    /*
    // a) Obtain the object number and generation number from the object identifier of the string or stream to be encrypted
    // (see 7.3.10, "Indirect Objects"). If the string is a direct object, use the identifier of the indirect object
    // containing it.
    guard let id = info[int: "id"] else { return ("failed to get object id for decryption", nil) }
    guard let generation = info[int: "generation"] else { return ("failed to get object id for decryption", nil) }
    
    // b) For all strings and streams without crypt filter specifier; treating the object number and generation number as binary
    // integers, extend the original -byte encryption key to n + 5 bytes by appending the low-order 3 bytes of the object number
    // and the low-order 2 bytes of the generation number in that order, low-order byte first. (n is 5 unless the value of V in
    // the encryption dictionary is greater than 1, in which case n is the value of Length divided by 8.)
    // If using the AES algorithm, extend the encryption key an additional 4 bytes by adding the value "sAIT" which corresponds
    // to the hexadecimal values 0x73, 0×41, 0x6C, 0×54. (This addition is done for backward compatibility and is not intended
    // to provide additional security.)
    
    // c) Initialize the MD5 hash function and pass the result of step (b) as input to this function.
    
    // d) Use the first (n + 5) bytes, up to a maximum of 16, of the output from the MD5 hash as the key for the RC4 or AES symmetric
    // key algorithms, along with the string or stream data to be encrypted. If using the AES algorithm, the Cipher Block Chaining (CBC) mode,
    // which requires an initialization vector, is used. The block size parameter is set to 16 bytes, and the initialization vector is a 16-byte
    // random number that is stored as the first 16 bytes of the encrypted stream or string. The output is the encrypted data to be stored in the PDF file.
    */
    return (nil, content)
}

func generateKeys(document: JsonElement,
                  encrypt: JsonElement) -> String? {
    guard document[hitch: "fileKey"] == nil else { return nil }
    
    // Filter entry identifies the file's security handler
    // SubFilter entry specifies the syntax of the encryption dictionary contents
    // V entry, in specifying which algorithm to use, determines the length of the encryption key,
    //   on which the encryption (and decryption) of data in a PDF file shall be based
    // For V values 2 and 3, the Length entry specifies the exact length of the encryption key.
    // value of 4 for V permits the security handler to use its own encryption and decryption algorithms
    // and to specify crypt filters to use on specific streams
    guard let handler = encrypt[string: "Filter"] else { return "encrypt missing filter" }
    
    guard let version = encrypt[int: "V"] else { return "encrypt missing version" }
    // O An algorithm that is undocumented. This value shall not be used.
    // 1 "Algorithm 1: Encryption of data using the RC4 or AES algorithms" in 7.6.2, "General Encryption Algorithm," with an encryption key length of 40 bits; see below.
    // 2 (PDF 1.4) "Algorithm 1: Encryption of data using the RC4 or AES algorithms" in 7.6.2, "General Encryption Algorithm," but permitting encryption key lengths greater than 40 bits.
    // 3 (PDF 1.4) An unpublished algorithm that permits encryption key lengths ranging from 40 to 128 bits. This value shall not appear in a conforming PDF file.
    // 4 (PDF 1.5) The security handler defines the use of encryption and decryption in the document, using the rules specified by the CF, StmF, and StrF entries.
    
    guard let revision = encrypt[int: "R"] else { return "encrypt missing revision" }
    
    
    var length = encrypt[int: "Length"] ?? 40
    // (Optional; PDF 1.4; only if V is 2 or 3) The length of the encryption key, in bits. The value shall be a multiple of 8, in the range 40 to 128. Default value: 40.
    
    
    // CF:
    // (Optional; meaningful only when the value of V is 4; PDF 1.5) A dictionary whose keys shall be crypt filter names and whose values shall be the corresponding crypt
    // filter dictionaries (see Table 25). Every crypt filter used in the document shall have an entry in this dictionary, except for the standard crypt filter names (see Table 26).
    // The conforming reader shall ignore entries in CF dictionary with the keys equal to those listed in Table 26 and use properties of the respective standard crypt filters.
    
    // StmF:
    // (Optional; meaningful only when the value of V is 4; PDF 1.5) The name of the crypt filter that shall be used by default when decrypting streams. The name shall be a key in
    // the CF dictionary or a standard crypt filter name specified in Table 26.
    // All streams in the document, except for cross-reference streams (see 7.5.8, "Cross-Reference Streams") or streams that have a Crypt entry in their Filter array (see Table 6),
    // shall be decrypted by the security handler, using this crypt filter.
    // Default value: Identity.
    
    // StrF
    // (Optional; meaningful only when the value of V is 4; PDF 1.5) The name of the crypt filter that shall be used when decrypting all strings in the document. The name shall be a
    // key in the CF dictionary or a standard crypt filter name specified in Table 26.
    // Default value: Identity.
    
    // EFF:
    // (Optional; meaningful only when the value of V is 4; PDF 1.6) The name of the crypt filter that shall be used when encrypting embedded file streams that do not have their own crypt filter specifier;
    // it shall correspond to a key in the CF dictionary or a standard crypt filter name specified in Table 26. This entry shall be provided by the security handler. Conforming writers shall respect this
    // value when encrypting embedded files, except for embedded file streams that have their own crypt filter specifier. If this entry is not present, and the embedded file stream does not contain a crypt
    // filter specifier, the stream shall be encrypted using the default stream crypt filter specified by StmF.
    
    
    guard handler == "Standard" else { return "unsupported encryption filter" }
    
    var encryptionType: Int = ENCRYPTION_TYPE_NONE
    
    if version == 1 || version == 2 || version == 3 {
        // length contains the length of the encryption key
        if revision == 2 {
            // RC4 / 40
            length = 40
            encryptionType = ENCRYPTION_TYPE_RC4_40
        } else if revision == 3 {
            // RC4 / 128
            if length < 40 || length > 128 {
                length = 128
            }
            encryptionType = length == 40 ? ENCRYPTION_TYPE_RC4_40 : ENCRYPTION_TYPE_RC4_128
        }
    } else if (version == 6 && revision == 6) {
        // AES / 256
        encryptionType = ENCRYPTION_TYPE_AES_256
    }
    
    guard encryptionType != ENCRYPTION_TYPE_NONE else { return "unsupported encryption type \(version) / \(revision)" }
    
    
    let permissions = encrypt[int: "P"] ?? 0
    
    guard let ownerKey = encrypt[hitch: "O"] else { return "missing owner key" }
    guard ownerKey.count >= 32 else { return "malformed owner key" }
    guard let userKey = encrypt[hitch: "U"] else { return "missing user key" }
    guard userKey.count >= 32 else { return "malformed user key" }
    
    //print("ownerKey[\(ownerKey.count)]: \(ownerKey.asHexString())")
    //print("userKey[\(userKey.count)]: \(userKey.asHexString())")
    
    guard let trailer = document[element: "trailer"] else { return "trailer missing" }
    guard let fileIdArray = trailer[element: "ID"] else { return "file id array missing" }
    guard let fileIdData = fileIdArray[hitch: 0]?.base64Decoded() else { return "file id missing" }
    let fileId = HalfHitch(data: fileIdData)
        
    // Generate keys to see if things match...
    let password = document[hitch: "password"]
    let paddedPassword = pad(password: password)
    
    //print("Trying: \(paddedPassword.asHexString())")
    //print("P: \(permissions)")
    //print("Fid[\(fileId.count)]: \(fileId.asHexString())")
    
    guard let userPad = try? makeOwnerKey(encryptionType: encryptionType,
                                          ownerPad: paddedPassword,
                                          userPad: ownerKey) else {
        return "failed to make padded user key"
    }
    //print("Upad[\(userPad.count)]: \(userPad.asHexString())")

    guard let fileKey = try? makeFileKey(encryptionType: encryptionType,
                                         permissions: permissions,
                                         fileId: fileId,
                                         userPad: userPad,
                                         ownerKey: ownerKey) else {
        return "failed to make file key"
    }
    //print("Fown[\(fileKey.count)]: \(fileKey.asHexString())")
    
    guard let ownUserKey = try? makeUserKey(fileId: fileId) else {
        return "failed to make own user key"
    }
    //print("U[\(userKey.count)]: \(userKey.asHexString())")
    //print("Uown[\(ownUserKey.count)]: \(ownUserKey.asHexString())")
    
    // Check if we have a match
    if userKey == ownerKey {
        document.set(key: "encryptionType", value: encryptionType)
        document.set(key: "fileKey", value: fileKey)
        document.set(key: "password", value: paddedPassword)
        return nil
    }
    
    // Not the owner password, try the user password...
    guard let fileKey = try? makeFileKey(encryptionType: encryptionType,
                                         permissions: permissions,
                                         fileId: fileId,
                                         userPad: paddedPassword,
                                         ownerKey: ownerKey) else {
        return "failed to make file key"
    }
    //print("Fuse[\(fileKey.count)]: \(fileKey.asHexString())")

    guard let ownUserKey = try? makeUserKey(fileId: fileId) else {
        return "failed to make own user key"
    }
    
    guard let pdfUserKey = try? decryptUserKey(encryptionType: encryptionType,
                                               fileKey: fileKey,
                                               userKey: userKey) else {
        return "failed to decrypt user key"
    }
    
    //print("Uuse[\(userKey.count)]: \(userKey.asHexString())")
    //print("Updf[\(pdfUserKey.count)]: \(pdfUserKey.asHexString())")
    
    if pdfUserKey == paddedPassword || ownUserKey.substring(0, 16) == pdfUserKey.substring(0, 16) {
        document.set(key: "encryptionType", value: encryptionType)
        document.set(key: "fileKey", value: fileKey)
        document.set(key: "password", value: paddedPassword)
        return nil
    }

    return "failed to generate valid decryption keys"
}

@usableFromInline
func pad(password: Hitch?) -> Hitch {
    let padded = Hitch(capacity: 32)

    if let password = password {
        padded.append(password)
        padded.count = min(padded.count, 32)
    }
    
    for idx in 0..<32 {
        if padded.count <= idx {
            padded.append(defaultPasswordPadding[idx])
        }
    }
    return padded
}

@usableFromInline
func makeOwnerKey(encryptionType: Int,
                  ownerPad: Hitch,
                  userPad: Hitch) throws -> Hitch {
    // Hash the owner password...
    var md5 = MD5()
    _ = try md5.update(withBytes: ownerPad.asArray())
    var digest = try md5.finish()
    
    if encryptionType != ENCRYPTION_TYPE_RC4_40 {
        for _ in 0..<50 {
            var md5 = MD5()
            _ = try md5.update(withBytes: digest)
            digest = try md5.finish()
        }
    }
    
    // Copy and encrypt the padded user password...
    var ownerKey = userPad
    ownerKey.count = 32
    
    if encryptionType == ENCRYPTION_TYPE_RC4_40 {
        let rc4 = RC4(key: digest, len: 5)
        ownerKey = rc4.crypt(ownerKey)
    } else {
        // RC4 encryption key
        let encryptKey = Hitch(string: "0123456789012345")
        for i in 0..<20 {
            // XOR each byte in the digest with the loop counter to make a key...
            for j in 0..<16 {
                encryptKey[j] = digest[j] ^ UInt8(i)
            }
            
            let rc4 = RC4(key: encryptKey.raw()!, len: encryptKey.count)
            ownerKey = rc4.crypt(ownerKey)
        }
    }
    
    return ownerKey
}

@usableFromInline
func makeFileKey(encryptionType: Int,
                 permissions: Int,
                 fileId: HalfHitch,
                 userPad: Hitch,
                 ownerKey: Hitch) throws -> Hitch {
    let permission0 = Int8(truncatingIfNeeded: permissions)
    let permission1 = Int8(truncatingIfNeeded: permissions >> 8)
    let permission2 = Int8(truncatingIfNeeded: permissions >> 16)
    let permission3 = Int8(truncatingIfNeeded: permissions >> 24)
    let permissionBytes: [UInt8] = [
        UInt8(bitPattern: permission0),
        UInt8(bitPattern: permission1),
        UInt8(bitPattern: permission2),
        UInt8(bitPattern: permission3)
    ]
    
    var md5 = MD5()
    _ = try md5.update(withBytes: userPad.asArray())
    _ = try md5.update(withBytes: ownerKey.asArray())
    _ = try md5.update(withBytes: permissionBytes)
    _ = try md5.update(withBytes: fileId.asArray())
    var digest = try md5.finish()
    
    if encryptionType != ENCRYPTION_TYPE_RC4_40 {
        // MD5 the result 50 times..
        for _ in 0..<50 {
            var md5 = MD5()
            _ = try md5.update(withBytes: digest)
            digest = try md5.finish()
        }
    }
    
    return Hitch(bytes: digest, offset: 0, count: 16)
}

@usableFromInline
func makeUserKey(fileId: HalfHitch) throws -> Hitch {

    var md5 = MD5()
    _ = try md5.update(withBytes: defaultPasswordPadding)
    _ = try md5.update(withBytes: fileId.asArray())
    let userKey = try md5.finish()
        
    let userKeyHitch = Hitch(bytes: userKey, offset: 0, count: 16)
    for _ in 0..<16 {
        userKeyHitch.append(0)
    }
    return userKeyHitch
}

@usableFromInline
func decryptUserKey(encryptionType: Int,
                    fileKey: Hitch,
                    userKey: Hitch) throws -> Hitch {
    var userKey = userKey
    userKey.count = 32

    if encryptionType == ENCRYPTION_TYPE_RC4_40 {
        let rc4 = RC4(key: fileKey.raw()!, len: 5)
        userKey = rc4.crypt(userKey)
    } else {
        // RC4 encryption key
        let encryptKey = Hitch(string: "0123456789012345")
        for i in stride(from: 19, to: 0, by: -1) {
            // XOR each byte in the digest with the loop counter to make a key...
            for j in 0..<16 {
                encryptKey[j] = fileKey[j] ^ UInt8(i)
            }
            
            let rc4 = RC4(key: encryptKey.raw()!, len: 16)
            userKey = rc4.crypt(userKey)
        }
        
        let rc4 = RC4(key: fileKey.raw()!, len: 16)
        userKey = rc4.crypt(userKey)

    }
    
    return userKey
}
