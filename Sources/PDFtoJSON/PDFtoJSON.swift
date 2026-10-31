import Foundation
import Spanker
import Hitch

func fail(_ error: String) -> JsonElement? {
    // #if DEBUG
    // fatalError(error)
    // #else
    return nil
    //#endif
}

public enum PDFtoJSON {

    public struct Options {
        /// Password for encrypted documents (user or owner). Documents with an
        /// empty user password open without one.
        public var password: String?
        /// Include "__parse_date" (seconds since 1970) in the output. Turn off for
        /// output that is identical across runs.
        public var includeParseDate: Bool
        /// Also output each page's text grouped into "blocks" (columns, boxes,
        /// paragraphs) in reading order.
        public var textBlocks: Bool

        public init(password: String? = nil,
                    includeParseDate: Bool = true,
                    textBlocks: Bool = true) {
            self.password = password
            self.includeParseDate = includeParseDate
            self.textBlocks = textBlocks
        }
    }

    public static func parsed<T>(hitch: Hitch, options: Options = Options(), _ callback: (JsonElement?) -> T?) -> T? {
        return Reader.parsed(hitch: hitch, options: options, callback)
    }

    public static func parsed<T>(halfhitch: HalfHitch, options: Options = Options(), _ callback: (JsonElement?) -> T?) -> T? {
        return Reader.parsed(halfhitch: halfhitch, options: options, callback)
    }

    public static func parsed<T>(data: Data, options: Options = Options(), _ callback: (JsonElement?) -> T?) -> T? {
        return Reader.parsed(data: data, options: options, callback)
    }

    public static func parsed<T>(string: String, options: Options = Options(), _ callback: (JsonElement?) -> T?) -> T? {
        return Reader.parsed(string: string, options: options, callback)
    }

    public static func parse(halfhitch: HalfHitch, options: Options = Options()) -> JsonElement? {
        let (error, result) = Reader.parse(halfhitch: halfhitch, options: options)
        #if DEBUG
        if let error = error {
            print(error)
        }
        #endif
        return result
    }

}
