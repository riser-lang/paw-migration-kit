#!/usr/bin/env python3
"""Fail-closed gate for the PAW Chinese console font.

The destructive migration entry points call this helper before changing a
partition, formatting a filesystem, streaming a clone, repairing a target or
expanding a GPT/ext4 root.  Only a same-boot report that proves the primary
16x16 PSF2 font was loaded on fbcon with an intact, manifest-matched hash is
accepted.  The vgacon 8x16 fallback is intentionally a WARN and never opens the
write gate.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import sys
from pathlib import Path

HEX64 = re.compile(r"^[0-9a-f]{64}$")
PSF2_MAGIC = b"\x72\xb5\x4a\x86"


def blocked(message: str) -> "NoReturn":
    print(f"BLOCKED: {message}", file=sys.stderr)
    raise SystemExit(2)


def load_json(path: Path, label: str) -> dict:
    try:
        with path.open("r", encoding="utf-8") as handle:
            document = json.load(handle)
    except OSError as exc:
        blocked(f"{label} is missing or unreadable: {path} ({exc})")
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        blocked(f"{label} is not valid JSON: {path} ({exc})")
    if not isinstance(document, dict):
        blocked(f"{label} must be a JSON object: {path}")
    return document


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--expected-font", required=True, type=Path)
    parser.add_argument("--expected-tty", default="/dev/tty1")
    parser.add_argument("--boot-id", required=True)
    return parser.parse_args()


def validate_psf2(path: Path) -> None:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        blocked(f"Font file is unreadable: {path} ({exc})")
    if len(raw) < 32:
        blocked(f"Font file is shorter than a PSF2 header: {path}")
    magic, version, headersize, flags, length, charsize, height, width = struct.unpack(
        "<8I", raw[:32]
    )
    if raw[:4] != PSF2_MAGIC or version != 0:
        blocked(f"Font is not PSF2 v0: {path}")
    if (headersize, length, charsize, height, width) != (32, 512, 32, 16, 16):
        blocked(
             "Font geometry is not fbcon 16x16/512 glyphs: "
            f"headersize={headersize} length={length} charsize={charsize} "
            f"height={height} width={width}"
        )
    if not flags & 1:
        blocked("Font has no Unicode mapping table")
    if len(raw) < headersize + length * charsize:
        blocked("Font is too short for 512 16x16 glyphs")
    if raw.find(b"\xff", headersize + length * charsize) < 0:
        blocked("Font Unicode mapping table has no terminator")


def main() -> int:
    args = parse_args()
    report = load_json(args.report, "font report")
    manifest = load_json(args.manifest, "font manifest")

    if report.get("schema") != "paw.console-font.v2":
        blocked(f"Font report schema is not paw.console-font.v2: {report.get('schema')!r}")
    if report.get("status") != "PASS":
        blocked(f"Font report status is not PASS: {report.get('status')!r}")
    if report.get("mode") != "fbcon":
        blocked(f"Font mode is not fbcon: {report.get('mode')!r}")
    if report.get("tty") != args.expected_tty:
        blocked(f"Font report tty is not {args.expected_tty}: {report.get('tty')!r}")
    if not str(report.get("framebuffer") or "").strip():
        blocked("Font report lacks a framebuffer name; fbcon is unproven")
    if not str(report.get("framebuffer_size") or "").strip():
        blocked("Font report lacks the framebuffer size")
    if report.get("fbcon_bound") is not True:
        blocked("Font report does not prove fbcon is bound")
    if report.get("boot_id") != args.boot_id or not args.boot_id:
        blocked("Font report is not from the current boot (boot_id mismatch or empty)")
    if report.get("setfont_exit_code") != 0:
        blocked(f"setfont exit code is not 0: {report.get('setfont_exit_code')!r}")

    actual_font = Path(str(report.get("font") or ""))
    expected_font = args.expected_font.resolve()
    try:
        actual_font_resolved = actual_font.resolve(strict=True)
    except OSError as exc:
        blocked(f"Font path in report does not exist: {actual_font} ({exc})")
    if actual_font_resolved != expected_font:
        blocked(f"Font in report is not the primary 16x16 font: {actual_font_resolved}")
    if actual_font_resolved.name != "paw-cjk-16x16.psf":
        blocked(f"Font filename is not paw-cjk-16x16.psf: {actual_font_resolved.name}")

    try:
        font_size = actual_font_resolved.stat().st_size
        font_sha = hashlib.sha256(actual_font_resolved.read_bytes()).hexdigest()
    except OSError as exc:
        blocked(f"Cannot read font: {actual_font_resolved} ({exc})")
    if report.get("font_size") != font_size:
        blocked(f"Reported font size does not match actual: {report.get('font_size')!r} != {font_size}")
    if not HEX64.fullmatch(str(report.get("font_sha256") or "")):
        blocked("Reported font SHA256 is not 64 lowercase hex characters")
    if report["font_sha256"] != font_sha:
        blocked("Reported font SHA256 does not match the actual file")
    if not HEX64.fullmatch(str(report.get("expected_font_sha256") or "")):
        blocked("Report lacks the manifest expected font SHA256")
    if report["expected_font_sha256"] != font_sha:
        blocked("Font SHA256 does not match the build manifest")

    if manifest.get("schema") != "paw.cjk-console-font.v1":
        blocked(f"Font manifest schema is invalid: {manifest.get('schema')!r}")
    if manifest.get("cell") != "16x16":
        blocked(f"Font manifest cell is not 16x16: {manifest.get('cell')!r}")
    manifest_sha = str(manifest.get("primary_font_sha256") or "")
    if not HEX64.fullmatch(manifest_sha):
        blocked("Font manifest lacks a valid primary font SHA256")
    if manifest_sha != font_sha:
        blocked("Font SHA256 does not match the manifest")

    validate_psf2(actual_font_resolved)
    print(
        "PASS: fbcon 16x16 font loaded on current boot; "
        f"sha256={font_sha}; tty={args.expected_tty}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
