# PDFtoJSON

A Swift library that parses a PDF into JSON (via [Spanker](https://github.com/KittyMac/Spanker)): the document's objects, its metadata, and the text of every page with positions.

## Usage

```swift
import Hitch
import Spanker
import PDFtoJSON

let pdf = Hitch(contentsOfFile: "document.pdf")!
PDFtoJSON.parsed(hitch: pdf) { root in
    for page in root?[element: "pages"]?.iterValues ?? JsonElement(unknown: []).iterValues {
        for item in page[element: "text"]?.iterValues ?? JsonElement(unknown: []).iterValues {
            print(item[int: "x"]!, item[int: "y"]!, item[string: "text"]!)
        }
    }
}
```

Entry points accept `Hitch`, `HalfHitch`, `Data` or `String`. The `JsonElement` passed to the callback may refer to the input buffer, so use it inside the callback (or copy what you need).

### Options

```swift
let options = PDFtoJSON.Options(password: "secret",        // user or owner password
                                includeParseDate: false,   // identical output across runs
                                textBlocks: true)          // add "blocks" (reading order)
PDFtoJSON.parsed(hitch: pdf, options: options) { root in ... }
```

Encrypted files with an empty user password (the common "restrictions only" case) open without a password. When a password is required and missing or wrong, the result is still a document, with `"__error"` set and no pages.

## Output

```json
{
    "__parse_date": 1793300000,
    "version": "1.7",
    "pages": [
        {
            "text": [ { "x": 72, "y": 700, "text": "hello world" } ],
            "width": 612.0,
            "height": 792.0
        }
    ],
    "info": { "Title": "Quarterly Report", "Author": "René" },
    "objects": { "1": { "id": 1, "generation": 0, "value": { "Type": "Catalog", "Pages": { "id": 2, "generation": 0 } } } },
    "xref": { "1": { "offset": 15, "generation": 0 }, "7": { "stream": 12, "index": 3 } },
    "trailer": { "Root": { "id": 1, "generation": 0 }, "ID": [ "<9A3F…>", "<9A3F…>" ] },
    "__warnings": [ "rebuilding cross-reference table by scanning the file" ],
    "__error": "document requires a password"
}
```

- **pages**: in document order. Each text item is a run of text on one line. `x`/`y` are the start of its baseline in points, measured from the lower-left corner of the visible page box (CropBox, else MediaBox) with the page's `/Rotate` applied, so `y` grows upward. Items are sorted top to bottom, then left to right. `width`/`height` are the visible box's size after rotation.
- **blocks** (with `textBlocks: true`): the same lines grouped into blocks (columns, boxes, paragraphs, tables) in reading order: `[{ "x", "y", "width", "height", "text": [ { "x", "y", "text" } ] }]`, where `x`/`y` is the block's lower-left corner. Use this for multi-column pages, sidebars and side-by-side boxes, where `text`'s top-to-bottom order interleaves columns. See "Reading order" below.
- **info**: the document information dictionary.
- **objects**: every object that was loaded, keyed by object number. Indirect references are `{ "id", "generation" }`. Names are written without the slash.
- **Strings** are decoded to text (UTF-16 with a byte-order mark, UTF-8, else PDFDocEncoding). Strings that aren't text are written as `"<HEX>"`; in the trailer and the Encrypt dictionary every string is written that way so binary values (IDs, keys) are lossless.
- **xref**: offsets for uncompressed objects, `{ "stream", "index" }` for objects inside object streams.
- **`__warnings`**: problems the parser worked around. **`__error`**: why the document could not be read (only when that happens).

## What is supported

**File structure**: classic xref tables and xref streams, object streams, incremental updates (newest revision wins, hybrid files), junk before the `%PDF` header, and reconstruction of damaged files by scanning for objects when the xref is missing or wrong.

**Streams**: FlateDecode (keeps what decodes from damaged data), LZWDecode, ASCIIHexDecode, ASCII85Decode, RunLengthDecode, filter chains, PNG and TIFF predictors. Image codecs (DCT, JPX, CCITT, JBIG2) are left encoded. Wrong or missing `/Length` is tolerated.

**Encryption**: the standard security handler: RC4 40–128 bit, AES-128, AES-256 (R5 and R6), crypt filters.

**Text**: Type1, TrueType, Type3 and Type0 (CID) fonts; ToUnicode CMaps; standard, WinAnsi, MacRoman, Symbol and ZapfDingbats encodings with `/Differences` resolved through the Adobe Glyph List; standard 14 font metrics; Form XObjects; the full text state (character/word spacing, scaling, leading, rise).

## Reading order

`blocks` come from recursive XY-cut: a region is split at a vertical gutter (an empty strip through its full height) or at a horizontal gap larger than its usual line spacing, and the pieces are visited top to bottom, left to right. When the lines on both sides of a gutter share baselines, the layout is ambiguous, and it is resolved like this:

- a side of short right-aligned values (amounts), or a side that is itself a table, is read row by row with its labels;
- two sides of long lines (article columns) are read one after the other;
- two sides that each start with a larger heading (side-by-side boxes such as "Pickup" and "Return") are read one after the other;
- anything else (label : value forms) is read row by row.

Headings are recognized by size only, not weight, and drawn rules and boxes are not used, so layouts that rely on those cues alone can still be read in the wrong order.

## Limitations

- CID fonts without a ToUnicode map, using predefined CJK CMaps other than Identity and UCS-2, produce no text (the CMap data is not bundled).
- Text is grouped into lines, not reordered into columns or paragraphs, and hyphenated words at line ends are not rejoined.
- Text drawn as images (scans) is not recognized.
- Annotation and form-field appearance streams are not included in page text.

## Development

```
swift test                                  # unit tests + corpus tests
swift run -c release pdfdump --text file.pdf  # extracted text; also --json, --password pw
```

`Tests/PDFtoJSONTests/Data/corpus` holds small PDFs that each exercise one feature; `gen.py` there regenerates them (needs Python, reportlab and qpdf). `Scripts/generate_tables.py` regenerates the font encoding and metrics tables.
