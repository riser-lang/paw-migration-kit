#!/usr/bin/env python3
"""Strict acceptance check for the 50 GiB QEMU chain serial log.

The guest prints machine-readable PAW3_STEP markers.  A host-side "TARGET_BOOT_SEEN"
alone is not acceptance: the log must contain the exact source/target/media
capacities and every mandatory stage at PASS, with no FAIL marker.
"""
import argparse
import json
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


def evaluate_evidence(text: str, runner_text: str | None = None) -> dict:
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
    checks["target_exact_240gb"] = target_capacity == str(TARGET_BYTES)
    checks["source_transport_ata_ahci"] = field(sata, "tran") == "ata" and "ich9-ahci" in sata
    checks["usb_media_32gb"] = field(sata, "media_bytes") == str(MEDIA_BYTES)
    if runner_text is not None:
        checks["host_runner_corroborated"] = bool(HOST_RUNNER_RE.search(runner_text))

    accepted = all(checks.values())
    return {
        "schema": "paw.prehardware-chain-acceptance.v1",
        "status": "PASS" if accepted else "FAIL",
        "source_bytes_required": SOURCE_BYTES,
        "target_bytes_required": TARGET_BYTES,
        "media_bytes_required": MEDIA_BYTES,
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
    args = ap.parse_args()

    text = Path(args.log).read_text(errors="replace")
    runner_text = Path(args.runner_log).read_text(errors="replace") if args.runner_log else None
    document = evaluate_evidence(text, runner_text=runner_text)
    accepted = document["status"] == "PASS"
    checks = document["checks"]
    steps = document["steps"]
    Path(args.output).write_text(json.dumps(document, indent=2) + "\n")

    lines = [
        "PAW 50 GiB virtual pre-hardware chain acceptance",
        f"status={'PASS' if accepted else 'FAIL'}",
        f"source_bytes={SOURCE_BYTES}",
        f"target_bytes={TARGET_BYTES}",
        f"media_bytes={MEDIA_BYTES}",
        f"steps_seen={len(steps)}",
        f"required_steps={len(REQUIRED)}",
    ]
    lines += [f"check {name}={'PASS' if value else 'FAIL'}" for name, value in checks.items()]
    lines += [line for line in text.splitlines() if line.startswith("PAW3_STEP=") or line.startswith("PAW3_CHAIN_RESULT=")]
    Path(args.summary).write_text("\n".join(lines) + "\n")
    print("\n".join(lines[:14]))
    return 0 if accepted else 1


if __name__ == "__main__":
    sys.exit(main())
