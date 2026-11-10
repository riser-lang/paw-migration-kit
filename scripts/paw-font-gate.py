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
        blocked(f"{label} 不存在或不可读：{path}（{exc}）")
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        blocked(f"{label} 不是有效 JSON：{path}（{exc}）")
    if not isinstance(document, dict):
        blocked(f"{label} 顶层必须是 JSON 对象：{path}")
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
        blocked(f"字体文件不可读：{path}（{exc}）")
    if len(raw) < 32:
        blocked(f"字体文件小于 PSF2 头部：{path}")
    magic, version, headersize, flags, length, charsize, height, width = struct.unpack(
        "<8I", raw[:32]
    )
    if raw[:4] != PSF2_MAGIC or version != 0:
        blocked(f"字体不是 PSF2 v0：{path}")
    if (headersize, length, charsize, height, width) != (32, 512, 32, 16, 16):
        blocked(
            "字体几何不符合 fbcon 16x16/512 槽："
            f"headersize={headersize} length={length} charsize={charsize} "
            f"height={height} width={width}"
        )
    if not flags & 1:
        blocked("字体缺少 Unicode 映射表")
    if len(raw) < headersize + length * charsize:
        blocked("字体长度不足以容纳 512 个 16x16 字形")
    if raw.find(b"\xff", headersize + length * charsize) < 0:
        blocked("字体 Unicode 映射表没有终止符")


def main() -> int:
    args = parse_args()
    report = load_json(args.report, "字体报告")
    manifest = load_json(args.manifest, "字体 manifest")

    if report.get("schema") != "paw.console-font.v2":
        blocked(f"字体报告 schema 不是 paw.console-font.v2：{report.get('schema')!r}")
    if report.get("status") != "PASS":
        blocked(f"字体报告状态不是 PASS：{report.get('status')!r}")
    if report.get("mode") != "fbcon":
        blocked(f"字体模式不是 fbcon：{report.get('mode')!r}")
    if report.get("tty") != args.expected_tty:
        blocked(f"字体报告 tty 不是 {args.expected_tty}：{report.get('tty')!r}")
    if not str(report.get("framebuffer") or "").strip():
        blocked("字体报告缺少 framebuffer 名称，无法证明 fbcon")
    if not str(report.get("framebuffer_size") or "").strip():
        blocked("字体报告缺少 framebuffer 尺寸")
    if report.get("fbcon_bound") is not True:
        blocked("字体报告没有证明 fbcon 已绑定")
    if report.get("boot_id") != args.boot_id or not args.boot_id:
        blocked("字体报告不属于当前启动（boot_id 不匹配或为空）")
    if report.get("setfont_exit_code") != 0:
        blocked(f"setfont 退出码不是 0：{report.get('setfont_exit_code')!r}")

    actual_font = Path(str(report.get("font") or ""))
    expected_font = args.expected_font.resolve()
    try:
        actual_font_resolved = actual_font.resolve(strict=True)
    except OSError as exc:
        blocked(f"报告中的字体路径不存在：{actual_font}（{exc}）")
    if actual_font_resolved != expected_font:
        blocked(f"报告中的字体不是主 16x16 字体：{actual_font_resolved}")
    if actual_font_resolved.name != "paw-cjk-16x16.psf":
        blocked(f"字体文件名不是 paw-cjk-16x16.psf：{actual_font_resolved.name}")

    try:
        font_size = actual_font_resolved.stat().st_size
        font_sha = hashlib.sha256(actual_font_resolved.read_bytes()).hexdigest()
    except OSError as exc:
        blocked(f"无法读取字体：{actual_font_resolved}（{exc}）")
    if report.get("font_size") != font_size:
        blocked(f"报告字体大小与实际不符：{report.get('font_size')!r} != {font_size}")
    if not HEX64.fullmatch(str(report.get("font_sha256") or "")):
        blocked("报告字体 SHA256 不是 64 位小写十六进制")
    if report["font_sha256"] != font_sha:
        blocked("报告字体 SHA256 与实际文件不符")
    if not HEX64.fullmatch(str(report.get("expected_font_sha256") or "")):
        blocked("报告缺少 manifest 期望字体 SHA256")
    if report["expected_font_sha256"] != font_sha:
        blocked("字体 SHA256 与构建 manifest 不一致")

    if manifest.get("schema") != "paw.cjk-console-font.v1":
        blocked(f"字体 manifest schema 无效：{manifest.get('schema')!r}")
    if manifest.get("cell") != "16x16":
        blocked(f"字体 manifest 单元不是 16x16：{manifest.get('cell')!r}")
    manifest_sha = str(manifest.get("primary_font_sha256") or "")
    if not HEX64.fullmatch(manifest_sha):
        blocked("字体 manifest 缺少有效的主字体 SHA256")
    if manifest_sha != font_sha:
        blocked("字体 SHA256 与 manifest 不一致")

    validate_psf2(actual_font_resolved)
    print(
        "PASS: fbcon 16x16 font loaded on current boot; "
        f"sha256={font_sha}; tty={args.expected_tty}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
