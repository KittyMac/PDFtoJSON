#!/usr/bin/env python3
"""
Regenerates the PDFtoJSON test corpus. Each file exercises one feature.

Requirements: python3, reportlab, qpdf (CLI). Run from this directory:
    python3 gen.py
Hand-built cases use only the stdlib, so their bytes are exact and stable.
"""
import re, subprocess, zlib

# ---------------------------------------------------------------- helpers

def build(objs, prefix=b"", header=b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n", root=1, extra_trailer=b""):
    """objs: {id: body bytes}. Writes a classic xref table. Offsets are relative to %PDF."""
    out = bytearray(prefix + header)
    offs = {}
    for i in sorted(objs):
        offs[i] = len(out) - len(prefix)
        out += b"%d 0 obj\n" % i + objs[i] + b"\nendobj\n"
    xref = len(out) - len(prefix)
    n = max(objs) + 1
    out += b"xref\n0 %d\n0000000000 65535 f \n" % n
    for i in range(1, n):
        out += (b"%010d 00000 n \n" % offs[i]) if i in offs else b"0000000000 65535 f \n"
    out += b"trailer\n<< /Size %d /Root %d 0 R %s>>\nstartxref\n%d\n%%%%EOF\n" % (n, root, extra_trailer, xref)
    return bytes(out)

def stream(data, extra=b"", compress=False):
    if compress:
        data = zlib.compress(data)
        extra += b" /Filter /FlateDecode"
    return b"<< /Length %d%s >>\nstream\n" % (len(data), extra) + data + b"\nendstream"

FONT = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"

def simple(content, font=FONT, res=None, pages_extra=b"", page_extra=None, compress=False):
    res = res if res is not None else b"<< /Font << /F1 4 0 R >> >>"
    page_extra = page_extra if page_extra is not None else b"/Resources " + res
    return {
        1: b"<< /Type /Catalog /Pages 2 0 R >>",
        2: b"<< /Type /Pages /Kids [3 0 R] /Count 1 " + pages_extra + b">>",
        3: b"<< /Type /Page /Parent 2 0 R " + (b"" if b"MediaBox" in page_extra else b"/MediaBox [0 0 612 792] ")
           + page_extra + b" /Contents 5 0 R >>",
        4: font,
        5: stream(content, compress=compress),
    }

def cmap(nbytes, bfchars=(), bfranges=()):
    lo, hi = (b"<00>", b"<FF>") if nbytes == 1 else (b"<0000>", b"<FFFF>")
    s = b"/CIDInit /ProcSet findresource begin 12 dict begin begincmap\n"
    s += b"/CMapName /Test def\n1 begincodespacerange " + lo + b" " + hi + b" endcodespacerange\n"
    if bfchars:
        s += b"%d beginbfchar\n" % len(bfchars) + b"".join(b"<%s> <%s>\n" % p for p in bfchars) + b"endbfchar\n"
    if bfranges:
        s += b"%d beginbfrange\n" % len(bfranges) + b"".join(r + b"\n" for r in bfranges) + b"endbfrange\n"
    return s + b"endcmap CMapName currentdict /CMap defineresource pop end end"

def type0(tounicode_id):
    return b"<< /Type /Font /Subtype /Type0 /BaseFont /Foo /Encoding /Identity-H /ToUnicode %d 0 R >>" % tounicode_id

def lzw_encode(data):
    """Minimal LZW encoder matching PDF's LZWDecode (EarlyChange 1)."""
    table = {bytes([i]): i for i in range(256)}
    nxt, width, out, acc, nacc = 258, 9, [], 0, 0
    def emit(code):
        nonlocal acc, nacc
        acc = (acc << width) | code; nacc += width
        while nacc >= 8:
            nacc -= 8; out.append((acc >> nacc) & 0xFF)
    emit(256)
    w = b""
    for c in data:
        wc = w + bytes([c])
        if wc in table:
            w = wc; continue
        emit(table[w]); table[wc] = nxt; nxt += 1
        if nxt + 1 > (1 << width) and width < 12: width += 1
        w = bytes([c])
    if w: emit(table[w])
    emit(257)
    if nacc: out.append((acc << (8 - nacc)) & 0xFF)
    return bytes(out)

def runlength_encode(data):
    out = bytearray()
    for i in range(0, len(data), 128):
        chunk = data[i:i+128]; out.append(len(chunk) - 1); out += chunk
    return bytes(out) + b"\x80"

def a85(data):
    import base64
    return base64.a85encode(data) + b"~>"

def png_predict(data, columns, ftype):
    """Apply a PNG predictor (bpp=1) row by row; ftype in 0..4."""
    rows = [data[i:i+columns] for i in range(0, len(data), columns)]
    out, prev = bytearray(), bytes(columns)
    for r in rows:
        r = r.ljust(columns, b"\0"); out.append(ftype)
        for x in range(columns):
            a = r[x-1] if x else 0; b = prev[x]; c = prev[x-1] if x else 0
            if ftype == 0: p = 0
            elif ftype == 1: p = a
            elif ftype == 2: p = b
            elif ftype == 3: p = (a + b) // 2
            else:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                p = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
            out.append((r[x] - p) & 0xFF)
        prev = r
    return bytes(out)

cases = {}

# ---------------------------------------------------------------- basics
cases["baseline"] = build(simple(b"BT /F1 12 Tf 72 700 Td (hello world) Tj ET"))
cases["compressed"] = build(simple(b"BT /F1 12 Tf 72 700 Td (compressed hello) Tj ET", compress=True))

# ---------------------------------------------------------------- structure
cases["junk_prefix"] = build(simple(b"BT /F1 12 Tf 72 700 Td (prefixed) Tj ET"), prefix=b"JUNKJUNK\r\n")
b = build(simple(b"BT /F1 12 Tf 72 700 Td (broken xref) Tj ET"))
cases["broken_startxref"] = re.sub(rb"startxref\n\d+", b"startxref\n12345", b)
b = build(simple(b"BT /F1 12 Tf 72 700 Td (no xref at all) Tj ET"))
cases["missing_xref"] = b[:b.index(b"xref\n0 ")] + b"%%EOF\n"
b = build(simple(b"BT /F1 12 Tf 72 700 Td (shifted offsets) Tj ET"))
cases["shifted_offsets"] = b.replace(b"%\xe2\xe3\xcf\xd3\n", b"%\xe2\xe3\xcf\xd3\n%padding padding\n", 1)

o = {i: b"null" for i in range(1, 2101)}
o[1] = b"<< /Type /Catalog /Pages 2090 0 R >>"
o[2090] = b"<< /Type /Pages /Kids [2091 0 R] /Count 1 >>"
o[2091] = b"<< /Type /Page /Parent 2090 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 2092 0 R >> >> /Contents 2093 0 R >>"
o[2092] = FONT
o[2093] = stream(b"BT /F1 12 Tf 72 700 Td (high object ids) Tj ET")
cases["over_2048"] = build(o)

# incremental update with a classic xref table and /Prev
b = cases["baseline"]
prev = int(re.search(rb"startxref\n(\d+)", b).group(1))
body = b"BT /F1 12 Tf 72 700 Td (updated text) Tj ET"
off = len(b)
add = b"5 0 obj\n<< /Length %d >>\nstream\n%s\nendstream\nendobj\n" % (len(body), body)
x = off + len(add)
add += (b"xref\n0 1\n0000000000 65535 f \n5 1\n%010d 00000 n \n"
        b"trailer\n<< /Size 6 /Root 1 0 R /Prev %d >>\nstartxref\n%d\n%%%%EOF\n") % (off, prev, x)
cases["incremental"] = b + add

# ---------------------------------------------------------------- lexer
o = simple(b"BT /F1 12 Tf 72 700 Td (comment array) Tj ET")
o[2] = b"<< /Type /Pages /Kids [ % a comment\n 3 0 R] /Count 1 >>"
cases["comment_in_array"] = build(o)
o = simple(b"BT /F1 12 Tf 72 700 Td (comment dict) Tj ET")
o[3] = o[3].replace(b"/Contents", b"% comment here\n/Contents")
cases["comment_in_dict"] = build(o)
cases["name_escape"] = build(simple(b"BT /F#31 12 Tf 72 700 Td (escaped name) Tj ET",
                                    res=b"<< /Font << /F#31 4 0 R >> >>"))
cases["hex_whitespace"] = build(simple(b"BT /F1 12 Tf 72 700 Td <68 65 6C\n6C 6F> Tj ET"))
cases["hex_plain"] = build(simple(b"BT /F1 12 Tf 72 700 Td <68656C6C6F> Tj ET"))

# ---------------------------------------------------------------- streams & filters
d = simple(b"BT /F1 12 Tf 72 700 Td (cr only) Tj ET"); d[5] = d[5].replace(b"stream\n", b"stream\r")
cases["stream_cr_only"] = build(d)
d = simple(b"BT /F1 12 Tf 72 700 Td (bad length) Tj ET"); d[5] = re.sub(rb"/Length \d+", b"/Length 20", d[5])
cases["bad_length"] = build(d)
d = simple(b"BT /F1 12 Tf 72 700 Td (missing length) Tj ET"); d[5] = re.sub(rb"/Length \d+", b"", d[5])
cases["missing_length"] = build(d)

def filtered(name, enc, filters, parms=b""):
    raw = b"BT /F1 12 Tf 72 700 Td (%s) Tj ET" % name.encode()
    data = enc(raw)
    d = simple(raw)
    d[5] = b"<< /Length %d /Filter %s %s>>\nstream\n" % (len(data), filters, parms) + data + b"\nendstream"
    cases[name] = build(d)

filtered("filter_chain", lambda r: zlib.compress(r).hex().encode() + b">", b"[/ASCIIHexDecode /FlateDecode]")
filtered("filter_a85", a85, b"/ASCII85Decode")
filtered("filter_lzw", lzw_encode, b"/LZWDecode")
filtered("filter_runlength", runlength_encode, b"/RunLengthDecode")
filtered("filter_abbrev", lambda r: zlib.compress(r).hex().encode() + b">", b"[/AHx /Fl]")
for ft, nm in [(1, "sub"), (2, "up"), (3, "avg"), (4, "paeth")]:
    filtered("predictor_" + nm, lambda r, ft=ft: zlib.compress(png_predict(r, 7, ft)), b"/FlateDecode",
             b"/DecodeParms << /Predictor 12 /Columns 7 >> ")
def tiff2(r):  # TIFF predictor 2, 1 color, 8 bpc, 7 columns
    out = bytearray()
    for i in range(0, len(r), 7):
        row = r[i:i+7].ljust(7, b"\0")
        out += bytes([row[0]] + [(row[x] - row[x-1]) & 0xFF for x in range(1, 7)])
    return zlib.compress(bytes(out))
filtered("predictor_tiff", tiff2, b"/FlateDecode", b"/DecodeParms << /Predictor 2 /Columns 7 >> ")
# corrupt tail on a flate stream: readers recover the prefix
raw = b"BT /F1 12 Tf 72 700 Td (truncated flate) Tj ET\n" + b"% padding " * 200
z = zlib.compress(raw)[:-30]
d = simple(raw); d[5] = b"<< /Length %d /Filter /FlateDecode >>\nstream\n" % len(z) + z + b"\nendstream"
cases["flate_truncated"] = build(d)

# ---------------------------------------------------------------- page tree
o = simple(b"BT /F1 12 Tf 72 700 Td (indirect font) Tj ET", res=b"<< /Font 6 0 R >>",
           font=type0(7))
o[5] = stream(b"BT /F1 12 Tf 72 700 Td <00010002> Tj ET")
o[6] = b"<< /F1 4 0 R >>"; o[7] = stream(cmap(2, [(b"0001", b"0048"), (b"0002", b"0069")]))
cases["indirect_fontdict"] = build(o)
o = simple(b"BT /F1 12 Tf 72 700 Td <00010002> Tj ET", pages_extra=b"/Resources << /Font << /F1 4 0 R >> >> ",
           page_extra=b"", font=type0(6))
o[6] = stream(cmap(2, [(b"0001", b"0048"), (b"0002", b"0069")]))
cases["inherited_resources"] = build(o)
cases["mediabox_offset"] = build(simple(b"BT /F1 12 Tf 172 800 Td (offset box) Tj ET",
    page_extra=b"/Resources << /Font << /F1 4 0 R >> >> /MediaBox [100 100 712 892]"))
cases["page_rotate"] = build(simple(b"BT /F1 12 Tf 72 700 Td (rotated page) Tj ET",
    page_extra=b"/Resources << /Font << /F1 4 0 R >> >> /Rotate 90"))
c = b"BT /F1 12 Tf 72 700 Td <00010002> Tj ET"
cases["shared_resources"] = build({
    1: b"<< /Type /Catalog /Pages 2 0 R >>",
    2: b"<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>",
    3: b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources 6 0 R /Contents 10 0 R >>",
    4: b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources 7 0 R /Contents 11 0 R >>",
    5: b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources 6 0 R /Contents 12 0 R >>",
    6: b"<< /Font << /F1 8 0 R >> >>", 7: b"<< /Font << /F1 9 0 R >> >>",
    8: type0(13), 9: type0(14), 10: stream(c), 11: stream(c), 12: stream(c),
    13: stream(cmap(2, [(b"0001", b"0041"), (b"0002", b"0042")])),
    14: stream(cmap(2, [(b"0001", b"0058"), (b"0002", b"0059")])),
})
# nested page tree, kids in a specific order
cases["page_order"] = build({
    1: b"<< /Type /Catalog /Pages 2 0 R >>",
    2: b"<< /Type /Pages /Kids [4 0 R 3 0 R] /Count 3 >>",
    3: b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 9 0 R >> >> /Contents 6 0 R >>",
    4: b"<< /Type /Pages /Parent 2 0 R /Kids [5 0 R 8 0 R] /Count 2 >>",
    5: b"<< /Type /Page /Parent 4 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 9 0 R >> >> /Contents 7 0 R >>",
    6: stream(b"BT /F1 12 Tf 72 700 Td (third) Tj ET"),
    7: stream(b"BT /F1 12 Tf 72 700 Td (first) Tj ET"),
    8: b"<< /Type /Page /Parent 4 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 9 0 R >> >> /Contents 10 0 R >>",
    9: FONT,
    10: stream(b"BT /F1 12 Tf 72 700 Td (second) Tj ET"),
})
o = simple(b"BT /F1 12 Tf 72 700 Td (two) Tj ET")
o[3] = o[3].replace(b"/Contents 5 0 R", b"/Contents [6 0 R 5 0 R]")
o[6] = stream(b"BT /F1 12 Tf 72 720 Td (one) Tj ET")
cases["contents_array"] = build(o)

# ---------------------------------------------------------------- content streams
cases["tj_kerning"] = build(simple(b"BT /F1 12 Tf 72 700 Td [(hello)-300(world)] TJ ET"))
cases["tstar_quote"] = build(simple(b"BT /F1 12 Tf 14 TL 72 700 Td (line one) Tj T* (line two) Tj (line three) ' ET"))
cases["td_leading"] = build(simple(b"BT /F1 12 Tf 72 700 Td (first) Tj 0 -14 TD (second) Tj T* (third) Tj ET"))
cases["separate_tj"] = build(simple(b"BT /F1 12 Tf 72 700 Td (hello) Tj ( world) Tj ET"))
cases["two_columns"] = build(simple(b"BT /F1 12 Tf 72 700 Td (left column) Tj ET BT /F1 12 Tf 350 700 Td (right column) Tj ET"))
cases["rotated"] = build(simple(b"BT /F1 12 Tf 0 1 -1 0 300 400 Tm (rotated) Tj ET"))
cases["cm_scaled"] = build(simple(b"q 2 0 0 2 0 0 cm BT /F1 6 Tf 36 350 Td (scaled) Tj ET Q"))
cases["bt_resets"] = build(simple(b"BT /F1 12 Tf 72 700 Td (before) Tj ET BT /F1 12 Tf 72 600 Td (after) Tj ET"))
img = b"BI /W 4 /H 1 /CS /G /BPC 8 ID \n(bad) Tj\nEI "
cases["inline_image"] = build(simple(b"BT /F1 12 Tf 72 700 Td (before) Tj ET\n" + img +
                                     b"\nBT /F1 12 Tf 72 600 Td (after) Tj ET"))
o = simple(b"q /X1 Do Q", res=b"<< /XObject << /X1 6 0 R >> >>")
o[6] = stream(b"BT /F1 12 Tf 72 700 Td (in xobject) Tj ET",
              extra=b" /Type /XObject /Subtype /Form /BBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >>")
cases["form_xobject"] = build(o)
o = simple(b"q /X1 Do Q", res=b"<< /XObject << /X1 6 0 R >> >>")
o[6] = stream(b"/X1 Do", extra=b" /Type /XObject /Subtype /Form /BBox [0 0 612 792] /Resources << /XObject << /X1 6 0 R >> >>")
cases["xobject_cycle"] = build(o)
# operators glued to operands without whitespace
cases["tight_syntax"] = build(simple(b"BT/F1 12 Tf 72 700 Td(tight)Tj ET"))

# ---------------------------------------------------------------- fonts & encodings
cases["winansi_accent"] = build(simple(b"BT /F1 12 Tf 72 700 Td (caf\\351 na\\357ve \\223quoted\\224) Tj ET"))
cases["differences"] = build(simple(b"BT /F1 12 Tf 72 700 Td (\\001\\002\\003) Tj ET",
    font=b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding << /Type /Encoding "
         b"/BaseEncoding /WinAnsiEncoding /Differences [1 /H /i /exclam] >> >>"))
cases["differences_uni"] = build(simple(b"BT /F1 12 Tf 72 700 Td (\\001\\002) Tj ET",
    font=b"<< /Type /Font /Subtype /Type1 /BaseFont /X /Encoding << /Differences [1 /uni00E9 /fi] >> >>"))
cases["macroman"] = build(simple(b"BT /F1 12 Tf 72 700 Td (\\216t\\216) Tj ET",
    font=b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /MacRomanEncoding >>"))
o = simple(b"BT /F1 12 Tf 72 700 Td <0102> Tj ET",
           font=b"<< /Type /Font /Subtype /TrueType /BaseFont /Foo /ToUnicode 6 0 R >>")
o[6] = stream(cmap(1, [(b"01", b"0048"), (b"02", b"0069")]))
cases["cmap_1byte"] = build(o)
o = simple(b"BT /F1 12 Tf 72 700 Td <00480069010000210100> Tj ET", font=type0(6))
o[6] = stream(cmap(2, bfranges=[b"<0000> <00FF> <0000>", b"<0100> <0100> <0058>"]))
cases["cmap_bigrange"] = build(o)
o = simple(b"BT /F1 12 Tf 72 700 Td <000100020003> Tj ET", font=type0(6))
o[6] = stream(cmap(2, [(b"0001", b"00660069"), (b"0002", b"006E0064"), (b"0003", b"D83DDE00")]))
cases["cmap_ligature"] = build(o)
o = simple(b"BT /F1 12 Tf 72 700 Td <000100020003> Tj ET", font=type0(6))
o[6] = stream(cmap(2, bfranges=[b"<0001> <0003> [<0041> <0042> <0043>]"]))
cases["cmap_range_array"] = build(o)
o = simple(b"BT /F1 12 Tf 72 700 Td (\\001\\002) Tj ET",
           font=b"<< /Type /Font /Subtype /TrueType /BaseFont /Foo /ToUnicode 6 0 R >>")
o[6] = stream(cmap(1, [(b"01", b"004F"), (b"02", b"004B")]))
cases["cmap_literal_string"] = build(o)
objs = {
    1: b"<< /Type /Catalog /Pages 2 0 R >>",
    2: b"<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 2 >>",
    3: b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
    4: type0(9), 5: stream(b"BT /F1 12 Tf 72 700 Td <00010002> Tj ET"),
    6: b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 7 0 R >> >> /Contents 8 0 R >>",
    7: type0(10), 8: stream(b"BT /F1 12 Tf 72 700 Td <00010002> Tj ET"),
    9: stream(cmap(2, [(b"0001", b"0041"), (b"0002", b"0042")])),
    10: stream(cmap(2, [(b"0001", b"0058"), (b"0002", b"0059")])),
}
cases["font_name_collision"] = build(objs)

# ---------------------------------------------------------------- strings (document level)
o = simple(b"BT /F1 12 Tf 72 700 Td (info strings) Tj ET")
o[6] = b"<< /Title <FEFF0048006900200263> /Author (Ren\\351) /Subject (plain) >>"
cases["info_strings"] = build(o, extra_trailer=b"/Info 6 0 R ")

for k, v in cases.items():
    open(k + ".pdf", "wb").write(v)

# ---------------------------------------------------------------- generated with reportlab + qpdf
from reportlab.pdfgen import canvas
cv = canvas.Canvas("reportlab.pdf", invariant=1); cv.drawString(72, 700, "hello world"); cv.showPage(); cv.save()
cv = canvas.Canvas("_many.pdf", invariant=1)
for i in range(1200):
    cv.drawString(72, 700, "page number %d" % i); cv.showPage()
cv.save()

def qpdf(*args):
    subprocess.run(["qpdf", "--static-id", "--deterministic-id"] + list(args), check=True) \
        if "--encrypt" not in args else subprocess.run(["qpdf", "--static-id"] + list(args), check=True)

qpdf("--object-streams=generate", "reportlab.pdf", "objstm.pdf")
qpdf("--object-streams=generate", "_many.pdf", "objstm_many.pdf")
qpdf("--allow-weak-crypto", "--encrypt", "", "owner", "40", "--", "reportlab.pdf", "enc_rc4_40.pdf")
qpdf("--allow-weak-crypto", "--encrypt", "", "owner", "128", "--use-aes=n", "--", "reportlab.pdf", "enc_rc4_128.pdf")
qpdf("--encrypt", "", "owner", "128", "--use-aes=y", "--", "reportlab.pdf", "enc_aes_128.pdf")
qpdf("--encrypt", "", "owner", "256", "--", "reportlab.pdf", "enc_aes_256.pdf")
qpdf("--encrypt", "", "owner", "256", "--", "info_strings.pdf", "enc_aes_256_info.pdf")
qpdf("--encrypt", "", "owner", "256", "--", "objstm.pdf", "enc_aes_256_objstm.pdf")
qpdf("--encrypt", "", "owner", "256", "--force-R5", "--", "reportlab.pdf", "enc_aes_256_r5.pdf")
qpdf("--encrypt", "user", "owner", "128", "--use-aes=y", "--", "reportlab.pdf", "enc_aes_128_userpw.pdf")
qpdf("--encrypt", "user", "owner", "256", "--", "reportlab.pdf", "enc_aes_256_userpw.pdf")
qpdf("--allow-weak-crypto", "--encrypt", "user", "owner", "128", "--use-aes=n", "--", "reportlab.pdf", "enc_rc4_128_userpw.pdf")
import os; os.remove("_many.pdf")

# incremental update on top of an xref-stream file (/Prev inside the xref stream dict)
b = open("objstm.pdf", "rb").read()
prev = int(re.search(rb"startxref\s+(\d+)", b[-64:]).group(1))
size = int(re.findall(rb"/Size (\d+)", b)[-1])
root = re.findall(rb"/Root (\d+) 0 R", b)[-1]
# find the page's content stream object number via qpdf
js = subprocess.run(["qpdf", "--json", "--json-key=pages", "objstm.pdf"], capture_output=True, text=True).stdout
cid = int(re.search(r'"contents":\s*\[\s*"(\d+) 0 R"', js).group(1))
body = b"BT /F1 12 Tf 72 700 Td (stream xref update) Tj ET"
off = len(b)
add = b"%d 0 obj\n<< /Length %d >>\nstream\n%s\nendstream\nendobj\n" % (cid, len(body), body)
xoff = off + len(add)
xid = size
rows = bytes([1]) + off.to_bytes(4, "big") + bytes([0]) + bytes([1]) + xoff.to_bytes(4, "big") + bytes([0])
add += (b"%d 0 obj\n<< /Type /XRef /Size %d /Root %s 0 R /Prev %d /W [1 4 1] /Index [%d 1 %d 1] /Length %d >>\nstream\n"
        % (xid, size + 1, root, prev, cid, xid, len(rows))) + rows + b"\nendstream\nendobj\n"
add += b"startxref\n%d\n%%%%EOF\n" % xoff
open("incremental_xrefstream.pdf", "wb").write(b + add)
print("generated", len(os.listdir(".")) - 1, "files")
