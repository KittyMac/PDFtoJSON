import Foundation
import Spanker
import Hitch

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
