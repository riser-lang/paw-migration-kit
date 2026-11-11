#!/usr/bin/env python3
"""Decode a QEMU PPM screendump with a known PSF console font.

This is deliberately not OCR: every 16x16 (or 8x16) cell is compared with the
exact bitmap shipped in the PSF file.  A decoded character therefore proves
that the corresponding font glyph was painted into the framebuffer.
"""
from __future__ import annotations

import struct
from pathlib import Path


class Psffont:
    def __init__(self, path: str | Path):
        raw = Path(path).read_bytes()
        if raw[:4] == b"\x72\xb5\x4a\x86":
            (magic, version, headersize, flags, length,
             charsize, height, width) = struct.unpack("<8I", raw[:32])
            self.psf2 = True
        elif raw[:2] == b"\x36\x04":
            headersize = 4
            charsize = raw[3]
            length = 512 if raw[2] & 1 else 256
            width, height = 8, charsize
            flags = 1 if raw[2] & 2 else 0
            self.psf2 = False
        else:
            raise ValueError(f"not a PSF font: {path}")

        bytewidth = (width + 7) // 8
        if charsize != bytewidth * height:
            raise ValueError(f"inconsistent PSF geometry {width}x{height} charsize={charsize}")

        self.width = width
        self.height = height
        self.charsize = charsize
        self.charcount = length
        self.glyphs: list[tuple[int, ...]] = []
        for index in range(length):
            start = headersize + index * charsize
            glyph = raw[start:start + charsize]
            rows = []
            for y in range(height):
                value = 0
                for b in range(bytewidth):
                    value = (value << 8) | glyph[y * bytewidth + b]
                rows.append(value)
            self.glyphs.append(tuple(rows))
        self.lookup: dict[tuple[int, ...], str] = {}
        self.mapped: dict[int, str] = {}

        if self.psf2:
            table = raw[headersize + length * charsize:]
            idx = glyph = 0
            while glyph < length and idx < len(table):
                end = table.find(b"\xff", idx)
                if end < 0:
                    break
                if end > idx:
                    try:
                        self.mapped[glyph] = table[idx:end].decode("utf-8")
                    except UnicodeDecodeError:
                        pass
                idx = end + 1
                glyph += 1
        else:
            # PSF1 tables mix UTF-16LE code points and sequence markers; the
            # PAW fallback font is built without a table (mode 512 only).
            pass
        for index, text in self.mapped.items():
            if len(text) == 1:
                self.lookup.setdefault(self.glyphs[index], text)

    def char_for(self, bitmap: tuple[int, ...]) -> str | None:
        return self.lookup.get(bitmap)


def read_ppm(path: str | Path) -> tuple[int, int, bytes]:
    data = Path(path).read_bytes()
    if not data.startswith(b"P6"):
        raise ValueError("screendump is not binary PPM P6")
    fields: list[int] = []
    idx = 2
    while len(fields) < 3:
        while idx < len(data) and data[idx] in b" \t\r\n":
            idx += 1
        if data[idx:idx + 1] == b"#":
            while idx < len(data) and data[idx] not in b"\r\n":
                idx += 1
            continue
        start = idx
        while idx < len(data) and data[idx] not in b" \t\r\n":
            idx += 1
        fields.append(int(data[start:idx]))
    idx += 1
    width, height, maxval = fields
    if maxval != 255:
        raise ValueError(f"unsupported PPM maxval {maxval}")
    return width, height, data[idx:]


def decode(path: str | Path, font: Psffont) -> dict:
    width, height, pixels = read_ppm(path)
    cols, rows = width // font.width, height // font.height
    lines: list[str] = []
    exact = 0
    inexact = 0
    for row in range(rows):
        chars: list[str] = []
        for col in range(cols):
            bitmap = []
            for y in range(font.height):
                value = 0
                base = ((row * font.height + y) * width + col * font.width) * 3
                for x in range(font.width):
                    off = base + x * 3
                    lum = (pixels[off] + pixels[off + 1] + pixels[off + 2]) / 3.0
                    value = (value << 1) | (1 if lum > 96 else 0)
                bitmap.append(value)
            key = tuple(bitmap)
            if not any(key):
                chars.append(" ")
                continue
            ch = font.char_for(key)
            if ch is None:
                # Tolerate a cursor/partial cell but count it; never guess a
                # Chinese character from a fuzzy match.
                chars.append("\ufffd")
                inexact += 1
            else:
                chars.append(ch)
                exact += 1
        lines.append("".join(chars).rstrip())
    return {
        "width": width,
        "height": height,
        "cols": cols,
        "rows": rows,
        "lines": lines,
        "exact_cells": exact,
        "inexact_cells": inexact,
        "match_ratio": exact / (exact + inexact) if exact + inexact else 0.0,
    }


def compact(text: str) -> str:
    """Drop whitespace so double-width CJK padding does not break matching."""
    return "".join(text.split())


def screen_text(decoded: dict) -> str:
    return "\n".join(decoded["lines"])


def contains(decoded: dict, needle: str) -> bool:
    return compact(needle) in compact(screen_text(decoded))


if __name__ == "__main__":
    import argparse
    import json

    ap = argparse.ArgumentParser()
    ap.add_argument("ppm")
    ap.add_argument("font")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    font = Psffont(args.font)
    result = decode(args.ppm, font)
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        for number, line in enumerate(result["lines"]):
            print(f"{number:02d} {line}")
        print(f"exact={result['exact_cells']} inexact={result['inexact_cells']} "
              f"ratio={result['match_ratio']:.4f}")
