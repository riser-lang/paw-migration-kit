#!/usr/bin/env python3
"""Fail-closed source-mount safety check.

Runs on the Rescue host (normally fed through SSH stdin).  It proves two
independent facts before source registration:
  1. findmnt exists and can execute;
  2. every supplied source device has no read-write mount according to
     /proc/self/mountinfo, matched by st_rdev major:minor (not by a mutable
     /dev symlink or by a display name).

Any inability to prove the safe state is a BLOCKED result.  Exit 0 only for
PASS, 2 for a proven BLOCKED condition, 3 for malformed invocation.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import stat
import subprocess
import sys

FINDMNT_MISSING = "FINDMNT_MISSING"
FINDMNT_ERROR = "FINDMNT_ERROR"
MOUNTINFO_UNREADABLE = "MOUNTINFO_UNREADABLE"
MOUNTINFO_MALFORMED = "MOUNTINFO_MALFORMED"
READ_WRITE_MOUNT = "READ_WRITE_MOUNT"
MOUNTINFO_MISMATCH = "MOUNTINFO_MISMATCH"
DEVICE_INVALID = "DEVICE_INVALID"


def blocked(reason: str, detail: str, **extra) -> dict:
    result = {"status": "BLOCKED", "reason": reason, "detail": detail}
    result.update(extra)
    return result


def parse_mountinfo(path: str) -> list[dict]:
    mounts: list[dict] = []
    with open(path, encoding="utf-8", errors="strict") as handle:
        for number, line in enumerate(handle, 1):
            fields = line.rstrip("\n").split(" ")
            if len(fields) < 10:
                raise ValueError(f"line {number}: too few fields")
            try:
                mount_id = int(fields[0])
                parent_id = int(fields[1])
                major_s, minor_s = fields[2].split(":", 1)
                major, minor = int(major_s), int(minor_s)
            except ValueError as exc:
                raise ValueError(f"line {number}: invalid id/device: {exc}") from exc
            sep = fields.index("-") if "-" in fields else -1
            if sep < 6 or sep + 3 >= len(fields):
                raise ValueError(f"line {number}: missing separator or tail fields")
            mounts.append({
                "mount_id": mount_id,
                "parent_id": parent_id,
                "major": major,
                "minor": minor,
                "root": fields[3],
                "mountpoint": fields[4].replace("\\040", " ").replace("\\011", "\t"),
                "options": fields[5].split(","),
                "optional": fields[6:sep],
                "fstype": fields[sep + 1],
                "source": fields[sep + 2],
                "super_options": fields[sep + 3].split(","),
            })
    return mounts


def findmnt_probe(findmnt: str, devices: list[str]) -> tuple[bool, str, dict[str, list[str]]]:
    if not findmnt:
        return False, FINDMNT_MISSING, {}
    if not (os.path.isfile(findmnt) and os.access(findmnt, os.X_OK)):
        found = shutil.which(findmnt)
        if not found:
            return False, FINDMNT_MISSING, {}
        findmnt = found
    try:
        version = subprocess.run([findmnt, "--version"], capture_output=True,
                                 text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, f"{FINDMNT_ERROR}: {exc}", {}
    if version.returncode != 0:
        return False, f"{FINDMNT_ERROR}: --version rc={version.returncode}", {}
    observed: dict[str, list[str]] = {}
    for dev in devices:
        try:
            proc = subprocess.run(
                [findmnt, "--noheadings", "--raw", "--source", dev,
                 "--output", "TARGET,OPTIONS"],
                capture_output=True, text=True, timeout=15)
        except (OSError, subprocess.TimeoutExpired) as exc:
            return False, f"{FINDMNT_ERROR}: {dev}: {exc}", {}
        if proc.returncode == 1 and not proc.stdout.strip():
            observed[dev] = []
            continue
        if proc.returncode != 0:
            return False, f"{FINDMNT_ERROR}: {dev}: rc={proc.returncode} {proc.stderr.strip()}", {}
        rows = []
        for line in proc.stdout.splitlines():
            line = line.strip()
            if line:
                rows.append(line)
        observed[dev] = rows
    return True, "OK", observed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mountinfo", default="/proc/self/mountinfo")
    parser.add_argument("--findmnt", default="findmnt")
    parser.add_argument("devices", nargs="+")
    args = parser.parse_args()

    devices = sorted(set(args.devices))
    for dev in devices:
        if not dev.startswith("/dev/") or ".." in dev.split("/"):
            print(json.dumps(blocked(DEVICE_INVALID, f"invalid device path: {dev}")))
            return 2
        try:
            st = os.stat(dev)
        except OSError as exc:
            print(json.dumps(blocked(DEVICE_INVALID, f"{dev}: {exc}")))
            return 2
        if not stat.S_ISBLK(st.st_mode):
            print(json.dumps(blocked(DEVICE_INVALID, f"{dev}: not a block device")))
            return 2

    try:
        mounts = parse_mountinfo(args.mountinfo)
    except (OSError, UnicodeError, ValueError) as exc:
        print(json.dumps(blocked(MOUNTINFO_MALFORMED, str(exc))))
        return 2

    findmnt_ok, findmnt_detail, findmnt_rows = findmnt_probe(args.findmnt, devices)
    if not findmnt_ok:
        print(json.dumps(blocked(FINDMNT_MISSING if findmnt_detail == FINDMNT_MISSING else FINDMNT_ERROR,
                                 findmnt_detail)))
        return 2

    by_rdev: dict[tuple[int, int], list[dict]] = {}
    for mount in mounts:
        by_rdev.setdefault((mount["major"], mount["minor"]), []).append(mount)

    findings = []
    for dev in devices:
        st = os.stat(dev)
        rdev = (os.major(st.st_rdev), os.minor(st.st_rdev))
        matched = by_rdev.get(rdev, [])
        rw = [m for m in matched if "rw" in m["options"] or "rw" in m["super_options"]]
        if rw:
            print(json.dumps(blocked(
                READ_WRITE_MOUNT,
                f"{dev} is mounted read-write",
                device=dev,
                mounts=[{"mountpoint": m["mountpoint"], "source": m["source"],
                         "options": ",".join(m["options"])} for m in rw],
            )))
            return 2
        # Cross-check findmnt's independent view.  It may legitimately show no
        # row for an unmounted path; a row must agree with mountinfo.
        for row in findmnt_rows.get(dev, []):
            target, _, options = row.partition(" ")
            options = options.strip()
            if "rw" in [o.strip() for o in options.split(",")]:
                print(json.dumps(blocked(
                    MOUNTINFO_MISMATCH,
                    f"findmnt reports read-write mount for {dev}",
                    device=dev, mountpoint=target, options=options)))
                return 2
        findings.append({
            "device": dev,
            "mounts_total": len(matched),
            "mounts_read_only": len(matched),
            "mountpoints": [m["mountpoint"] for m in matched],
            "findmnt_rows": len(findmnt_rows.get(dev, [])),
        })

    print(json.dumps({
        "status": "PASS",
        "schema": "paw.source-mount-check.v1",
        "method": "findmnt executable probe + /proc/self/mountinfo st_rdev matching",
        "findmnt": findmnt_detail,
        "devices": findings,
        "read_write_mounts": 0,
    }, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
