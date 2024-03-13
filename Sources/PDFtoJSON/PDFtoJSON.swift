import Foundation
import Spanker
import Hitch

@inlinable
func fail(_ error: String) -> JsonElement? {
    #if DEBUG
    fatalError(error)
    #endif
    return nil
}

@inlinable
func fail(_ error: String) -> HalfHitch? {
    #if DEBUG
    fatalError(error)
    #endif
    return nil
}

@inlinable
func printAround(ptr: UnsafePointer<UInt8>,
                 start: UnsafePointer<UInt8>,
                 end: UnsafePointer<UInt8>) {
    let minIdx = max(0, ptr - start - 20)
    let maxIdx = min(end - start, ptr - start + 20)
    let snip: Hitch = HalfHitch(sourceObject: nil, raw: start, count: end - start, from: minIdx, to: maxIdx).hitch()
    snip.replace(occurencesOf: "\n", with: "_")
    snip.replace(occurencesOf: "\r", with: "_")
    
    var startIdx = ptr - start - 20
    while startIdx < 0 {
        snip.insert(.space, index: 0)
        startIdx += 1
    }
    
    print(snip)
    print("                    ^                    ")
}

public enum PDFtoJSON {

    @inlinable
    public static func parsed<T>(hitch: Hitch, _ callback: (JsonElement?) -> T?) -> T? {
        return Reader.parsed(hitch: hitch, callback)
    }

    @inlinable
    public static func parsed<T>(halfhitch: HalfHitch, _ callback: (JsonElement?) -> T?) -> T? {
        return Reader.parsed(halfhitch: halfhitch, callback)
    }

    @inlinable
    public static func parsed<T>(data: Data, _ callback: (JsonElement?) -> T?) -> T? {
        return Reader.parsed(data: data, callback)
    }

    @inlinable
    public static func parsed<T>(string: String, _ callback: (JsonElement?) -> T?) -> T? {
        return Reader.parsed(string: string, callback)
    }

    @inlinable
    public static func parse(halfhitch: HalfHitch) -> JsonElement? {
        let (error, result) = Reader.parse(halfhitch: halfhitch)
        #if DEBUG
        if let error = error {
            print(error)
        }
        #endif
        return result
    }

}
