import Foundation
import Spanker
import Hitch
import CryptoSwift

public let ENCRYPTION_TYPE_NONE = 0
public let ENCRYPTION_TYPE_RC4_40 = 1
public let ENCRYPTION_TYPE_RC4_128 = 2
public let ENCRYPTION_TYPE_AES_128 = 3
public let ENCRYPTION_TYPE_AES_256 = 4

protocol EncryptionHandler {
    func crypt(start: UnsafePointer<UInt8>,
               end: UnsafePointer<UInt8>) -> Hitch
}

@usableFromInline
class RC4: EncryptionHandler {
    let key: UnsafePointer<UInt8>
    var sbox = Array<UInt8>(repeating: 0, count: 256)
    var sbox_idx: UInt8 = 0
    var sbox_jdx: UInt8 = 0
    
    @usableFromInline
    init(key: UnsafePointer<UInt8>, len: Int) {
        self.key = key
        
        for i in 0..<256 {
            sbox[i] = UInt8(i)
        }
        
        var j: UInt8 = 0
        var tmp: UInt8 = 0
        for i in 0..<256 {
            // j = (j + Si + Ki) mod 256
            j &+= sbox[i] &+ key[i % len]
            
            // Swap Si and Sj...
            tmp = sbox[i]
            sbox[i] = sbox[Int(j)]
            sbox[Int(j)] = tmp
        }
    }
    
    @usableFromInline
    func crypt(_ hitch: Hitch) -> Hitch {
        guard let raw = hitch.raw() else { return "" }
        return crypt(start: raw, end: raw + hitch.count)
    }
    
    @usableFromInline
    func crypt(_ hitch: HalfHitch) -> Hitch {
        guard let raw = hitch.raw() else { return "" }
        return crypt(start: raw, end: raw + hitch.count)
    }
    
    @usableFromInline
    func crypt(start: UnsafePointer<UInt8>,
               end: UnsafePointer<UInt8>) -> Hitch {
        var tmp: UInt8 = 0
        var t: UInt8 = 0
        
        var i = sbox_idx
        var j = sbox_jdx
        
        let output = Hitch(capacity: end - start)
        
        var ptr = start
        while ptr < end {
            // Get the next S box indices...
            i &+= 1
            j &+= sbox[Int(i)]
            
            // Swap Si and Sj...
            tmp = sbox[Int(i)]
            sbox[Int(i)] = sbox[Int(j)]
            sbox[Int(j)] = tmp
            
            // Get the S box index for this byte...
            t = sbox[Int(i)] &+ sbox[Int(j)]
            
            // Encrypt using the S box...
            output.append(ptr[0] ^ sbox[Int(t)])
            ptr += 1
        }
        
        return output
    }
}
