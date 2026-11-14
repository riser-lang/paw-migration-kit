#!/usr/bin/env python3
"""Strict acceptance check for the 50 GiB QEMU chain serial log.

The guest prints machine-readable PAW3_STEP markers.  A host-side "TARGET_BOOT_SEEN"
alone is not acceptance: the log must contain the exact source/target/media
capacities and every mandatory stage at PASS, with no FAIL marker.
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

REQUIRED = [
    "live_boot", "cpu", "sata", "lab_target_blank", "source_os",
    "evidence_transport", "console_font", "fault_injection", "rescue_sshd",
    "rescue_key", "rescue_ssh", "source_identity_negative", "source_identity",
    "pawdata", "target_enrollment", "memtest", "hardware", "readiness",
    "mixed_stream", "ssh_interrupt", "final_authorization_wrong",
    "final_authorization_correct", "compressed_transfer", "clone_complete",
    "sha256_verify", "offline_repair", "gpt_expand", "preboot_handoff",
    "auto_reboot",
]
SOURCE_BYTES = 53687091200
TARGET_BYTES = 240000000000
MEDIA_BYTES = 32000000000
STEP_RE = re.compile(r"PAW3_STEP=([A-Za-z0-9_]+) STATUS=([A-Z]+)(?: (.*))?$")
AUTO_REBOOT_RE = re.compile(r"PAW3_STEP=auto_reboot STATUS=PASS(?: [^\r\n]*)?")
TARGET_BANNER_RE = re.compile(r"Ubuntu\s+24\.04(?:\.\d+)?(?:\s+LTS)?\s+ubuntu\s+ttyS0")
TARGET_LOGIN_RE = re.compile(r"(?:^|[\r\n])ubuntu login:")
HOST_RUNNER_RE = re.compile(r"main result=TARGET_BOOT_SEEN\b[^\r\n]*\bchain_pass=True\b[^\r\n]*\btarget_boot=True\b")


def validate_target_bytes(raw) -> int:
    if isinstance(raw, bool):
        raise ValueError("target_bytes must be an integer, not bool")
    if isinstance(raw, int):
        val = raw
    else:
        s = str(raw).strip()
        if not re.fullmatch(r"[1-9][0-9]*", s):
            raise ValueError(f"invalid target_bytes {raw!r}: must be a positive integer")
        val = int(s)
    if val < SOURCE_BYTES:
        raise ValueError(f"target_bytes {val} must be >= SOURCE_BYTES {SOURCE_BYTES}")
    if val % 512 != 0:
        raise ValueError(f"target_bytes {val} must be 512-byte sector aligned")
    return val


def evaluate_evidence(text: str, runner_text: str | None = None, target_bytes: int = TARGET_BYTES) -> dict:
    target_bytes = validate_target_bytes(target_bytes)
    steps, failures = {}, []
    for raw in text.splitlines():
        match = STEP_RE.search(raw)
        if not match:
            continue
        name, status, detail = match.group(1), match.group(2), match.group(3) or ""
        steps[name] = {"status": status, "detail": detail}
        if status == "FAIL":
            failures.append(f"step {name} FAIL: {detail}")

    missing = [name for name in REQUIRED if name not in steps]
    not_pass = [name for name in REQUIRED if name in steps and steps[name]["status"] != "PASS"]
    sata = steps.get("sata", {}).get("detail", "")

    def field(detail, key):
        match = re.search(rf"(?:^| ){re.escape(key)}=(\S+)", detail)
        return match.group(1) if match else None

    def int_field(detail, key):
        raw = field(detail, key)
        return int(raw) if raw is not None and raw.isdigit() else None

    reboot_match = AUTO_REBOOT_RE.search(text)
    post_reboot = text[reboot_match.end():] if reboot_match else ""
    banner_match = TARGET_BANNER_RE.search(post_reboot) if reboot_match else None
    login_match = TARGET_LOGIN_RE.search(post_reboot[banner_match.end():]) if banner_match else None
    target_boot_login = bool(reboot_match and banner_match and login_match)

    checks = {
        "chain_result_pass": "PAW3_CHAIN_RESULT=PASS" in text.splitlines(),
        "auto_reboot_before_target_login": bool(reboot_match),
        "target_boot_login": target_boot_login,
        "no_fail_steps": not failures,
        "all_required_steps_present": not missing,
        "all_required_steps_pass": not not_pass,
        "source_exact_50gib": field(sata, "bytes") == str(SOURCE_BYTES),
    }
    enrollment = steps.get("target_enrollment", {}).get("detail", "")
    target_capacity = field(enrollment, "capacity")
    sata_target_bytes = field(sata, "target_bytes")
    checks["target_exact_bytes"] = (
        target_capacity == str(target_bytes)
        and (sata_target_bytes is None or sata_target_bytes == str(target_bytes))
    )
    checks["source_transport_ata_ahci"] = field(sata, "tran") == "ata" and "ich9-ahci" in sata
    checks["usb_media_32gb"] = field(sata, "media_bytes") == str(MEDIA_BYTES)

    gpt_detail = steps.get("gpt_expand", {}).get("detail", "")
    part_before = int_field(gpt_detail, "before_bytes")
    part_after = int_field(gpt_detail, "after_bytes")
    fs_before = int_field(gpt_detail, "fs_before_blocks")
    fs_after = int_field(gpt_detail, "fs_after_blocks")
    part_grew_flag = (field(gpt_detail, "grew") or "").lower()
    fs_grew_flag = (field(gpt_detail, "fs_grew") or "").lower()
    gpt_verified_flag = field(gpt_detail, "gpt_verified")
    free_bytes = int_field(gpt_detail, "free_bytes")
    block_size = int_field(gpt_detail, "block_size")
    free_blocks = int_field(gpt_detail, "free_blocks")
    disk_bytes = int_field(gpt_detail, "disk_bytes")

    if target_bytes > SOURCE_BYTES:
        checks["gpt_partition_expanded"] = bool(
            part_before is not None and part_after is not None and part_after > part_before and part_grew_flag == "true"
        )
        checks["ext4_filesystem_expanded"] = bool(
            fs_before is not None and fs_after is not None and fs_after > fs_before and fs_grew_flag == "true"
        )
    else:
        checks["gpt_partition_expanded"] = bool(
            part_before is not None and part_after is not None and part_after >= part_before
        )
        checks["ext4_filesystem_expanded"] = bool(
            fs_before is not None and fs_after is not None and fs_after >= fs_before
        )
    if gpt_verified_flag is not None:
        checks["gpt_table_verified"] = gpt_verified_flag.lower() == "true"
    if runner_text is not None:
        checks["host_runner_corroborated"] = bool(HOST_RUNNER_RE.search(runner_text))

    accepted = all(checks.values())
    return {
        "schema": "paw.prehardware-chain-acceptance.v1",
        "status": "PASS" if accepted else "FAIL",
        "source_bytes_required": SOURCE_BYTES,
        "target_bytes_required": target_bytes,
        "target_bytes_observed": int(target_capacity) if target_capacity and target_capacity.isdigit() else target_capacity,
        "media_bytes_required": MEDIA_BYTES,
        "expansion_metrics": {
            "root_partition_before_bytes": part_before,
            "root_partition_after_bytes": part_after,
            "partition_grew": part_grew_flag == "true" if part_grew_flag else None,
            "filesystem_before_blocks": fs_before,
            "filesystem_after_blocks": fs_after,
            "filesystem_grew": fs_grew_flag == "true" if fs_grew_flag else None,
            "filesystem_block_size": block_size,
            "target_free_blocks": free_blocks,
            "target_free_bytes": free_bytes,
            "target_disk_bytes": disk_bytes,
            "gpt_verified": gpt_verified_flag.lower() == "true" if gpt_verified_flag else None,
        },
        "checks": checks,
        "target_boot_evidence": {
            "auto_reboot_pass_seen": bool(reboot_match),
            "ubuntu_ttyS0_banner_after_reboot": banner_match.group(0) if banner_match else None,
            "ubuntu_login_after_banner": bool(login_match),
            "host_runner_checked": runner_text is not None,
        },
        "missing_steps": missing,
        "non_pass_steps": not_pass,
        "failed_steps": failures,
        "steps": steps,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--summary", required=True)
    ap.add_argument("--runner-log", default=None)
    ap.add_argument("--target-bytes", default=os.environ.get("PAW_EXPECTED_TARGET_BYTES", str(TARGET_BYTES)))
    args = ap.parse_args()

    try:
        expected_target = validate_target_bytes(args.target_bytes)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    text = Path(args.log).read_text(errors="replace")
    runner_text = Path(args.runner_log).read_text(errors="replace") if args.runner_log else None
    document = evaluate_evidence(text, runner_text=runner_text, target_bytes=expected_target)
    accepted = document["status"] == "PASS"
    checks = document["checks"]
    steps = document["steps"]
    exp = document["expansion_metrics"]
    Path(args.output).write_text(json.dumps(document, indent=2) + "\n")

    lines = [
        "PAW 50 GiB virtual pre-hardware chain acceptance",
        f"status={'PASS' if accepted else 'FAIL'}",
        f"source_bytes={SOURCE_BYTES}",
        f"target_bytes={expected_target}",
        f"target_bytes_observed={document['target_bytes_observed']}",
        f"media_bytes={MEDIA_BYTES}",
        f"root_partition_before_bytes={exp['root_partition_before_bytes']}",
        f"root_partition_after_bytes={exp['root_partition_after_bytes']}",
        f"filesystem_before_blocks={exp['filesystem_before_blocks']}",
        f"filesystem_after_blocks={exp['filesystem_after_blocks']}",
        f"target_free_bytes={exp['target_free_bytes']}",
        f"steps_seen={len(steps)}",
        f"required_steps={len(REQUIRED)}",
    ]
    lines += [f"check {name}={'PASS' if value else 'FAIL'}" for name, value in checks.items()]
    lines += [line for line in text.splitlines() if line.startswith("PAW3_STEP=") or line.startswith("PAW3_CHAIN_RESULT=")]
    Path(args.summary).write_text("\n".join(lines) + "\n")
    print("\n".join(lines[:24]))
    return 0 if accepted else 1


if __name__ == "__main__":
    sys.exit(main())
