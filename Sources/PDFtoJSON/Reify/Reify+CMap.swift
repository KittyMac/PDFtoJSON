import Foundation
import Spanker
import Hitch

@inlinable
func isCMap(_ content: HalfHitch) -> Bool {
    return content.contains("/CMapName") && (
        content.contains("beginbfchar") || 
        content.contains("beginbfrange")
    )
}

@inlinable
func reify(document: JsonElement,
           id: Int,
           generation: Int,
           cMap content: HalfHitch) -> JsonElement? {
    guard isCMap(content) else { return nil }

    let map = JsonElement(unknown: [:])
    
    if let start = content.raw() {
        
        if let idx = content.firstIndex(of: "beginbfchar") {
            var ptr = start + idx + 11
            let end = start + content.count
            beginbfchar(map: map,
                        &ptr, start, end)
        }
        
        if let idx = content.firstIndex(of: "beginbfrange") {
            var ptr = start + idx + 12
            let end = start + content.count
            beginbfrange(map: map,
                         &ptr, start, end)
        }
        
    }
    
    return ^[
        "map": map
    ]
}

@inlinable
func beginbfchar(map: JsonElement,
                 _ ptr: inout UnsafePointer<UInt8>,
                 _ start: UnsafePointer<UInt8>,
                 _ end: UnsafePointer<UInt8>) {
    while ptr < end {
        var ptr2 = ptr
        
        skipWhitespace(&ptr, start, end)
        
        guard let line = getLine(&ptr, start, end) else { break }
        guard line.trimmed() != "endbfchar" else { break }
        
        skipWhitespace(&ptr2, start, ptr)
        guard let cid = getHexstringRaw(&ptr2, start, ptr) else { return }
        skipWhitespace(&ptr2, start, ptr)
        guard let unicode = getHexstringRaw(&ptr2, start, ptr) else { return }
        
        map.set(key: cid, value: unicode)
    }
}

@inlinable
func beginbfrange(map: JsonElement,
                  _ ptr: inout UnsafePointer<UInt8>,
                  _ start: UnsafePointer<UInt8>,
                  _ end: UnsafePointer<UInt8>) {
    while ptr < end {
        var ptr2 = ptr
        
        skipWhitespace(&ptr, start, end)
        
        guard let line = getLine(&ptr, start, end) else { break }
        guard line.trimmed() != "endbfrange" else { break }
        
        // <low> <high> <unicode start>
        // -- or --
        // <low> <high> [<unicode map]
        
        if line.contains(.openBrace) {
            skipWhitespace(&ptr2, start, ptr)
            guard let low = getHexstringRaw(&ptr2, start, ptr) else {
                return
            }
            skipWhitespace(&ptr2, start, ptr)
            guard let _ = getHexstringRaw(&ptr2, start, ptr) else {
                return
            }
            skipWhitespace(&ptr2, start, ptr)
            guard ptr2[0] == .openBrace else { return }
            
            var lowNum = toUnicode(low)
            
            ptr2 += 1
            while ptr2 < ptr {
                guard ptr2[0] != .closeBrace else { break }
                skipWhitespace(&ptr2, start, ptr)
                guard let unicode = getHexstringRaw(&ptr2, start, ptr) else {
                    return
                }
                
                let cid = fromUnicode(lowNum)
                map.set(key: cid.halfhitch(), value: unicode)
                lowNum += 1
            }
        } else {
            skipWhitespace(&ptr2, start, ptr)
            guard let low = getHexstringRaw(&ptr2, start, ptr) else { return }
            skipWhitespace(&ptr2, start, ptr)
            guard let high = getHexstringRaw(&ptr2, start, ptr) else { return }
            skipWhitespace(&ptr2, start, ptr)
            guard let unicode = getHexstringRaw(&ptr2, start, ptr) else { return }
            
            let lowNum = toUnicode(low)
            let highNum = toUnicode(high)
            let unicodeNum = toUnicode(unicode)
            
            for i in 0...(highNum - lowNum) {
                let cid = fromUnicode(lowNum + i)
                let unicode = fromUnicode(unicodeNum + i)
                map.set(key: cid.halfhitch(), value: unicode)
            }
        }
    }
}

/*
 function strToInt(str) {
   let a = 0;
   for (let i = 0; i < str.length; i++) {
     a = (a << 8) | str.charCodeAt(i);
   }
   return a >>> 0;
 }
func parseBfRange(cMap, lexer) {
  while (true) {
    let obj = lexer.getObj();
    if (obj === EOF) {
      break;
    }
    if (isCmd(obj, "endbfrange")) {
      return;
    }
    expectString(obj);
    const low = strToInt(obj);
    obj = lexer.getObj();
    expectString(obj);
    const high = strToInt(obj);
    obj = lexer.getObj();
    if (Number.isInteger(obj) || typeof obj === "string") {
      const dstLow = Number.isInteger(obj) ? String.fromCharCode(obj) : obj;
      cMap.mapBfRange(low, high, dstLow);
    } else if (isCmd(obj, "[")) {
      obj = lexer.getObj();
      const array = [];
      while (!isCmd(obj, "]") && obj !== EOF) {
        array.push(obj);
        obj = lexer.getObj();
      }
      cMap.mapBfRangeToArray(low, high, array);
    } else {
      break;
    }
  }
  throw new FormatError("Invalid bf range.");
}
 mapBfRangeToArray(low, high, array) {
     if (high - low > MAX_MAP_RANGE) {
       throw new Error("mapBfRangeToArray - ignoring data above MAX_MAP_RANGE.");
     }
     const ii = array.length;
     let i = 0;
     while (low <= high && i < ii) {
       this._map[low] = array[i++];
       ++low;
     }
   }
 mapBfRange(low, high, dstLow) {
     if (high - low > MAX_MAP_RANGE) {
       throw new Error("mapBfRange - ignoring data above MAX_MAP_RANGE.");
     }
     const lastByte = dstLow.length - 1;
     while (low <= high) {
       this._map[low++] = dstLow;
       // Only the last byte has to be incremented (in the normal case).
       const nextCharCode = dstLow.charCodeAt(lastByte) + 1;
       if (nextCharCode > 0xff) {
         dstLow =
           dstLow.substring(0, lastByte - 1) +
           String.fromCharCode(dstLow.charCodeAt(lastByte - 1) + 1) +
           "\x00";
         continue;
       }
       dstLow =
         dstLow.substring(0, lastByte) + String.fromCharCode(nextCharCode);
     }
   }
*/
