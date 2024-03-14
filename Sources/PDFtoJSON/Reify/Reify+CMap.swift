import Foundation
import Spanker
import Hitch

@inlinable
func isCMap(_ content: HalfHitch) -> Bool {
    return content.contains("/CMapName") && content.contains("beginbfchar")
}

@inlinable
func reify(document: JsonElement,
           id: Int,
           generation: Int,
           cMap content: HalfHitch) -> JsonElement? {
    guard isCMap(content) else { return nil }

    let map = JsonElement(unknown: [:])
    
    let parts: [HalfHitch] = content.components(separatedBy: "beginbfchar")
    guard parts.count > 1 else { return nil }
    
    guard var ptr = parts[1].raw() else { return nil }
    let start = ptr
    let end = ptr + content.count
    
    while ptr < end {
        guard let line = getLine(&ptr, start, end) else { break }
        let lineParts: [HalfHitch] = line.components(separatedBy: " ")
        if lineParts[0][0] == .lessThan,
           lineParts.count == 2 {
            let charCode = lineParts[0].trimmed()
            let unicode = lineParts[1].trimmed()
            
            if let charCode = charCode.substring(1, charCode.count - 1),
               let unicode = unicode.substring(1, unicode.count - 1) {
                map.set(key: charCode.halfhitch(), value: unicode)
            }
        }
    }
    
    return ^[
        "map": map
    ]
}

/*
 /CIDInit /ProcSet findresource begin
 12 dict begin begincmap /CIDSystemInfo
 << /Registry (Oracle) /Ordering(UCS) /Supplement 0 >> def
 /CMapName /Oracle-Identity-UCS def
 1 begincodespacerange
 <0000> <FFFF>
 endcodespacerange
 50 beginbfchar
 <0000> <003F>
 <0001> <0049>
 <0002> <0074>
 <0003> <0065>
 <0004> <006D>
 <0005> <00A0>
 <0006> <0051>
 <0007> <0079>
 <0008> <0050>
 <0009> <0072>
 <000A> <0069>
 <000B> <0063>
 <000C> <0041>
 <000D> <006F>
 <000E> <0075>
 <000F> <006E>
 <0010> <0054>
 <0011> <0061>
 <0012> <006C>
 <0013> <0038>
 <0014> <0034>
 <0015> <002E>
 <0016> <0035>
 <0017> <0031>
 <0018> <002A>
 <0019> <0066>
 <001A> <0064>
 <001B> <0068>
 <001C> <0055>
 <001D> <0042>
 <001E> <0043>
 <001F> <0062>
 <0020> <0046>
 <0021> <002C>
 <0022> <0030>
 <0023> <0028>
 <0024> <0029>
 <0025> <0033>
 <0026> <002D>
 <0027> <0070>
 <0028> <0067>
 <0029> <007A>
 <002A> <0073>
 <002B> <006B>
 <002C> <0078>
 <002D> <0047>
 <002E> <0045>
 <002F> <0053>
 <0030> <004F>
 <0031> <0059>
 endbfchar
 endcmap
 CMapName currentdict /CMap defineresource pop
 end end
 */
