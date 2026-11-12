#!/usr/bin/env python3
"""Build a 16x16 (and 8x16 fallback) Linux console font with Chinese glyphs.

The PAW console runs on tty1.  vgacon cannot render CJK at all and a plain
8x16 VGA font has only 256 slots, so the release image uses the kernel
framebuffer console (fbcon) with a 16x16 PSF2 font built from GNU Unifont's
hand-designed bitmap glyphs.  Every character that can be printed by the PAW
scripts is included; the build fails if the 512-glyph kernel limit would be
exceeded, so a missing glyph can never silently ship.

This script uses only the Python standard library.  Input is the Debian
``unifont.hex`` file (package ``unifont``); no font renderer is required.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

PSF2_MAGIC = b"\x72\xb5\x4a\x86"  # on-disk byte order
PSF2_HEADERSIZE = 32
PSF2_HAS_UNICODE_TABLE = 0x00000001
MAX_GLYPHS = 512
CELL_W = 16
CELL_H = 16
ASCII_FIRST = 0x20
ASCII_LAST = 0x7E

CJK_RANGES = (
    (0x3000, 0x303F),   # CJK symbols and punctuation
    (0x3400, 0x4DBF),   # CJK extension A
    (0x4E00, 0x9FFF),   # CJK unified ideographs
    (0xF900, 0xFAFF),   # CJK compatibility ideographs
    (0xFF00, 0xFFEF),   # fullwidth forms
    (0x2000, 0x206F),   # general punctuation (ellipsis, quotes)
)


def is_cjk_or_ui(ch: str) -> bool:
    """Any printable non-ASCII character that could reach the console.

    This deliberately includes Latin-1 punctuation such as ``-`` and ``degC``
    and curly quotes, not just the CJK blocks: a missing glyph shows as the
    replacement box and is just as bad as a blank Chinese character.
    """
    cp = ord(ch)
    if cp < 0x80:
        return False
    if cp in (0xFEFF, 0x200B, 0x200C, 0x200D):
        return False
    if 0xE000 <= cp <= 0xF8FF:      # private use
        return False
    return True


def load_unifont(path: Path) -> dict[int, tuple[int, bytes]]:
    """Return codepoint -> (width, row-major bitmap bytes)."""
    glyphs: dict[int, tuple[int, bytes]] = {}
    with path.open("r", encoding="ascii", errors="strict") as handle:
        for lineno, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            try:
                code_hex, bitmap_hex = line.split(":", 1)
                codepoint = int(code_hex, 16)
                bitmap = bytes.fromhex(bitmap_hex)
            except ValueError as exc:
                raise SystemExit(f"{path}:{lineno}: invalid unifont line: {exc}") from exc
            if len(bitmap) == 16:
                width = 8
            elif len(bitmap) == 32:
                width = 16
            elif len(bitmap) == 64:
                width = 32
            elif len(bitmap) in (24, 48):
                width = len(bitmap) // 16
            else:
                raise SystemExit(f"{path}:{lineno}: unsupported glyph byte length {len(bitmap)}")
            glyphs[codepoint] = (width, bitmap)
    if not glyphs:
        raise SystemExit(f"{path}: no glyphs found")
    return glyphs


def glyph_rows(width: int, bitmap: bytes) -> list[int]:
    """Expand a Unifont glyph into 16-bit rows, MSB = leftmost pixel."""
    if width == 16:
        return [(bitmap[i] << 8) | bitmap[i + 1] for i in range(0, len(bitmap), 2)]
    if width == 8:
        # 8x16 ASCII in the 16-wide cell: centre it (x=4..11).
        return [bitmap[i] << 4 for i in range(len(bitmap))]
    if width == 32:
        # Not used for the 16-wide cell; take the left half.
        return [(bitmap[i] << 8) | bitmap[i + 1] for i in range(0, len(bitmap), 4)]
    raise SystemExit(f"unsupported glyph width {width}")


def build_cell(glyphs: dict[int, tuple[int, bytes]], ch: str) -> bytes:
    cp = ord(ch)
    if cp not in glyphs:
        raise KeyError(ch)
    width, bitmap = glyphs[cp]
    rows = glyph_rows(width, bitmap)
    if len(rows) < CELL_H:
        rows = rows + [0] * (CELL_H - len(rows))
    rows = rows[:CELL_H]
    return b"".join(row.to_bytes(2, "big") for row in rows)


def collect_chars(paths: list[Path]) -> tuple[list[str], dict[str, list[str]]]:
    found: dict[str, set[str]] = {}
    for path in paths:
        if path.is_dir():
            # Runtime assets only.  CI/test scripts contain extra Chinese
            # diagnostics that never reach the operator console; including
            # them would waste the kernel's 512-glyph budget.
            files = sorted(
                p for p in path.rglob("*")
                if p.is_file()
                and not {"ci", "tests", "__pycache__"} & set(p.parts)
                and p.suffix in {".sh", ".py", ".service", ".mount", ".network", ".json"}
            )
        else:
            files = [path]
        for file in files:
            try:
                text = file.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            for ch in text:
                if is_cjk_or_ui(ch):
                    found.setdefault(ch, set()).add(str(file))
    chars = sorted(found, key=ord)
    return chars, {ch: sorted(files) for ch, files in found.items()}


def write_psf2(path: Path, slot_chars: list[str | None], glyphs: dict[int, tuple[int, bytes]]) -> None:
    if len(slot_chars) > MAX_GLYPHS:
        raise SystemExit(f"font needs {len(slot_chars)} slots, kernel limit is {MAX_GLYPHS}")
    slot_chars = slot_chars + [None] * (MAX_GLYPHS - len(slot_chars))
    header = PSF2_MAGIC + b"".join(
        value.to_bytes(4, "little")
        for value in (
            0,                    # version
            PSF2_HEADERSIZE,
            PSF2_HAS_UNICODE_TABLE,
            MAX_GLYPHS,
            CELL_H * 2,           # charsize
            CELL_H,
            CELL_W,
        )
    )
    body = bytearray(header)
    table = bytearray()
    for ch in slot_chars:
        if ch is None:
            body += bytes(CELL_H * 2)
            table += b"\xff"
            continue
        try:
            body += build_cell(glyphs, ch)
        except KeyError as exc:
            raise SystemExit(f"unifont has no glyph for U+{ord(ch):04X} ({ch!r})") from exc
        # PSF2 Unicode table: UTF-8 codepoint(s), 0xFF terminates this slot.
        table += ch.encode("utf-8") + b"\xff"
    path.write_bytes(bytes(body) + bytes(table))


def write_psf1_fallback(path: Path, slot_chars: list[str | None], glyphs: dict[int, tuple[int, bytes]]) -> None:
    """8x16 emergency fallback for vgacon (CJK is horizontally sampled).

    This is deliberately labelled a fallback: 16x16 Chinese is halved to 8x16
    and complex characters lose strokes.  It is only loaded when /dev/fb0 is
    absent, so the operator still sees something instead of blank glyphs.
    """
    if len(slot_chars) > MAX_GLYPHS:
        raise SystemExit(f"font needs {len(slot_chars)} slots, kernel limit is {MAX_GLYPHS}")
    slot_chars = slot_chars + [None] * (MAX_GLYPHS - len(slot_chars))
    body = bytearray(b"\x36\x04\x01\x10")  # PSF1 magic, mode 512, charsize 16
    for ch in slot_chars:
        if ch is None:
            body += bytes(CELL_H)
            continue
        width, bitmap = glyphs[ord(ch)]
        rows = glyph_rows(width, bitmap)
        for row in rows:
            # Take the left half (x=0..7) of the 16-wide cell.
            body += bytes([(row >> 8) & 0xFF])
    path.write_bytes(bytes(body))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--unifont", required=True, type=Path)
    ap.add_argument("--scan", action="append", default=[], type=Path,
                    help="file or directory whose CJK characters must be covered")
    ap.add_argument("--extra-char", action="append", default=[],
                    help="additional character(s) to include (repeatable)")
    ap.add_argument("--out", required=True, type=Path, help="16x16 PSF2 output")
    ap.add_argument("--fallback-out", type=Path, help="8x16 PSF1 fallback output")
    ap.add_argument("--manifest", type=Path, help="JSON manifest output")
    ap.add_argument("--unifont-version", default="unknown")
    args = ap.parse_args()

    glyphs = load_unifont(args.unifont)
    chars, sources = collect_chars(args.scan)
    extra = sorted({ch for item in args.extra_char for ch in item if is_cjk_or_ui(ch)}, key=ord)
    for ch in extra:
        if ch not in chars:
            chars.append(ch)
            sources[ch] = ["--extra-char"]
    chars = sorted(set(chars), key=ord)

    # Keep printable ASCII at its standard VGA positions (space MUST be slot
    # 32: the VT's blank fill uses font position 32, and putting "@" there
    # makes every blank look like "@").  Slots 0..31 and 127..511 are unused
    # by ASCII, so they hold the Chinese glyphs.  The embedded Unicode table
    # is authoritative; these slots need not equal code points.
    slot_chars: list[str | None] = [None] * MAX_GLYPHS
    for cp in range(ASCII_FIRST, ASCII_LAST + 1):
        slot_chars[cp] = chr(cp)
    if 0xFFFD in glyphs and "\ufffd" not in chars:
        chars.append("\ufffd")
        sources["\ufffd"] = ["missing-glyph marker"]
    non_ascii = [ch for ch in chars if ord(ch) > 0x7F]
    free_slots = list(range(0, ASCII_FIRST)) + list(range(127, MAX_GLYPHS))
    if len(non_ascii) > len(free_slots):
        raise SystemExit(
            f"PAW console needs {len(non_ascii)} non-ASCII glyphs but only "
            f"{len(free_slots)} free kernel slots remain (limit {MAX_GLYPHS}). "
            "Reduce on-screen Chinese text or split the UI."
        )
    for slot, ch in zip(free_slots, non_ascii):
        slot_chars[slot] = ch

    args.out.parent.mkdir(parents=True, exist_ok=True)
    write_psf2(args.out, slot_chars, glyphs)
    if args.fallback_out:
        args.fallback_out.parent.mkdir(parents=True, exist_ok=True)
        write_psf1_fallback(args.fallback_out, slot_chars, glyphs)

    manifest = {
        "schema": "paw.cjk-console-font.v1",
        "generated_at": "SOURCE_DATE_EPOCH",
        "unifont_version": args.unifont_version,
        "source": str(args.unifont),
        "source_sha256": hashlib.sha256(args.unifont.read_bytes()).hexdigest(),
        "cell": f"{CELL_W}x{CELL_H}",
        "glyph_slots": len(slot_chars),
        "ascii_slots": [ASCII_FIRST, ASCII_LAST],
        "non_ascii_count": len(non_ascii),
        "non_ascii": "".join(non_ascii),
        "characters": {ch: sources.get(ch, []) for ch in non_ascii},
        "primary_font": str(args.out),
        "primary_font_sha256": hashlib.sha256(args.out.read_bytes()).hexdigest(),
        "fallback_font": str(args.fallback_out) if args.fallback_out else None,
        "fallback_font_sha256": hashlib.sha256(args.fallback_out.read_bytes()).hexdigest()
        if args.fallback_out else None,
    }
    if args.manifest:
        args.manifest.parent.mkdir(parents=True, exist_ok=True)
        args.manifest.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                                 encoding="utf-8")
    print(f"built {args.out}: {len(non_ascii)} CJK/UI glyphs + ASCII, "
          f"{len(slot_chars)} slots, unifont {args.unifont_version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
