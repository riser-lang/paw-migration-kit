#!/usr/bin/env python3
"""Build a test-only font/manifest/report fixture for the fail-closed gate.

This is never installed in the ISO.  CI uses it to exercise the production gate
without a framebuffer or root: the synthetic PSF2 still has to satisfy the real
header, size and SHA256 checks.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path

PRIMARY = "paw-cjk-16x16.psf"
FALLBACK = "paw-cjk-8x16.psf"
MANIFEST = "paw-cjk-font.json"
REPORT = "console-font.json"


def psf2() -> bytes:
    slots = 512
    charsize = 32
    unicode_table = bytearray()
    for slot in range(slots):
        if slot == 32:
            unicode_table.extend(b" \xff")
        elif slot == 0:
            unicode_table.extend("\ufffd".encode("utf-8") + b"\xff")
        else:
            unicode_table.append(0xFF)
    header = struct.pack("<8I", 0x864AB572, 0, 32, 1, slots, charsize, 16, 16)
    return header + b"\0" * (slots * charsize) + bytes(unicode_table)


def psf1() -> bytes:
    return b"\x36\x04\x01\x10" + b"\0" * (512 * 16)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("outdir", type=Path)
    parser.add_argument("--boot-id", default="")
    args = parser.parse_args()
    out = args.outdir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    primary = out / PRIMARY
    fallback = out / FALLBACK
    manifest_path = out / MANIFEST
    report_path = out / REPORT
    primary.write_bytes(psf2())
    fallback.write_bytes(psf1())
    primary_sha = hashlib.sha256(primary.read_bytes()).hexdigest()
    fallback_sha = hashlib.sha256(fallback.read_bytes()).hexdigest()
    manifest = {
        "schema": "paw.cjk-console-font.v1",
        "generated_at": "SOURCE_DATE_EPOCH",
        "unifont_version": "test-fixture",
        "cell": "16x16",
        "glyph_slots": 512,
        "primary_font": str(primary),
        "primary_font_sha256": primary_sha,
        "fallback_font": str(fallback),
        "fallback_font_sha256": fallback_sha,
    }
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    boot_id = args.boot_id or Path("/proc/sys/kernel/random/boot_id").read_text(
        encoding="utf-8"
    ).strip()
    report = {
        "schema": "paw.console-font.v2",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "boot_id": boot_id,
        "tty": "/dev/tty1",
        "mode": "fbcon",
        "fbcon_bound": True,
        "framebuffer": "test-fixture-fbcon",
        "framebuffer_size": "1024,768",
        "font": str(primary),
        "font_size": primary.stat().st_size,
        "font_sha256": primary_sha,
        "font_manifest": str(manifest_path),
        "manifest_schema": manifest["schema"],
        "expected_font_sha256": primary_sha,
        "setfont_exit_code": 0,
        "setfont_output": "",
        "status": "PASS",
        "reason": "",
    }
    report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        json.dumps(
            {
                "outdir": str(out),
                "font": str(primary),
                "fallback": str(fallback),
                "manifest": str(manifest_path),
                "report": str(report_path),
                "boot_id": boot_id,
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
