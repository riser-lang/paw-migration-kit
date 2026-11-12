#!/usr/bin/env python3
"""Verify a QEMU screendump by matching cells against the PAW console PSF.

This is deliberately not OCR.  Every cell is compared bit-for-bit with a
glyph parsed from the same PSF2 font that the console loaded on this boot.  The
report records the screenshot SHA256, font SHA256, matched Unicode code points
and the reconstructed text rows, so a reviewer can reproduce the match.
"""
import argparse, hashlib, json, os, struct, sys

def psf2(path):
    data = open(path, "rb").read()
    if data[:4] != b"\x72\xb5\x4a\x86":
        raise SystemExit("not a PSF2 font")
    version, hdr, flags, length, charsize, height, width = struct.unpack("<7I", data[4:32])
    glyphs = []
    for i in range(length):
        off = hdr + i * charsize
        glyphs.append(data[off:off + charsize])
    # PSF2 stores one UTF-8 byte sequence per glyph, each terminated by 0xFF.
    table_at = hdr + length * charsize
    table = data[table_at:]
    mapping = {}
    idx = 0
    for glyph in glyphs:
        end = table.find(b"\xff", idx)
        if end < 0:
            break
        try:
            ch = table[idx:end].decode("utf-8")
        except UnicodeDecodeError:
            ch = ""
        if ch:
            mapping.setdefault(glyph, ch)
        idx = end + 1
    return width, height, charsize, glyphs, mapping

def ppm(path):
    data = open(path, "rb").read()
    if not data.startswith(b"P6"):
        raise SystemExit("screenshot is not binary PPM P6")
    pos = 2; fields = []
    while len(fields) < 3:
        while pos < len(data) and data[pos:pos+1].isspace():
            pos += 1
        if data[pos:pos+1] == b"#":
            pos = data.index(b"\n", pos) + 1; continue
        start = pos
        while pos < len(data) and not data[pos:pos+1].isspace():
            pos += 1
        fields.append(int(data[start:pos]))
    pos += 1
    w, h, maxv = fields
    return w, h, data[pos:pos + w * h * 3]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", required=True)
    ap.add_argument("--screenshot", required=True)
    ap.add_argument("--report", required=True)
    ap.add_argument("--require", default="PAW,迁移")
    args = ap.parse_args()
    width, height, charsize, glyphs, mapping = psf2(args.font)
    sw, sh, pixels = ppm(args.screenshot)
    if len(pixels) < sw * sh * 3:
        raise SystemExit("short PPM payload")
    cols, rows = sw // width, sh // height
    recognized = []
    matched_cp = set()
    unmatched = 0
    cursor_cells = 0
    for row in range(rows):
        text = []
        for col in range(cols):
            raw = bytearray()
            for y in range(height):
                bits = 0
                for x in range(width):
                    idx = ((row * height + y) * sw + (col * width + x)) * 3
                    lum = pixels[idx] + pixels[idx + 1] + pixels[idx + 2]
                    if lum > 96 * 3:
                        bits |= 1 << (width - 1 - x)
                if width <= 8:
                    raw.append(bits & 0xFF)
                else:
                    raw.extend(struct.pack(">H", bits))
            glyph = bytes(raw)
            ch = mapping.get(glyph)
            if ch is None:
                # A cursor/underline cell is common at the prompt; do not count
                # it as proof of a missing glyph.
                if any(glyph):
                    unmatched += 1
                    text.append("\ufffd")
                else:
                    text.append(" ")
            else:
                text.append(ch)
                if ord(ch) > 0x2FFF:
                    matched_cp.add(ch)
        line = "".join(text).rstrip()
        if line.strip():
            recognized.append(line)
    joined = "\n".join(recognized)
    required = [s for s in args.require.split(",") if s]
    checks = {s: (s in joined) for s in required}
    cjk = len(matched_cp)
    doc = {
        "schema": "paw.console-glyphs.v1",
        "status": "PASS" if all(checks.values()) and cjk >= 4 else "FAIL",
        "screenshot": os.path.basename(args.screenshot),
        "screenshot_sha256": hashlib.sha256(open(args.screenshot, "rb").read()).hexdigest(),
        "font": os.path.basename(args.font),
        "font_sha256": hashlib.sha256(open(args.font, "rb").read()).hexdigest(),
        "font_cell": f"{width}x{height}",
        "screen": [sw, sh],
        "grid": [cols, rows],
        "required": checks,
        "matched_cjk_glyphs": cjk,
        "matched_cjk_characters": "".join(sorted(matched_cp)),
        "unmatched_nonblank_cells": unmatched,
        "glyph_match_method": "bitmap_exact_against_loaded_psf2_not_ocr",
        "text_rows": recognized,
    }
    os.makedirs(os.path.dirname(args.report), exist_ok=True)
    tmp = args.report + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(doc, handle, indent=2, ensure_ascii=False)
    os.chmod(tmp, 0o600); os.replace(tmp, args.report)
    print(json.dumps({k: doc[k] for k in ("status", "required", "matched_cjk_glyphs", "unmatched_nonblank_cells")}, ensure_ascii=False))
    return 0 if doc["status"] == "PASS" else 1

if __name__ == "__main__":
    sys.exit(main())
