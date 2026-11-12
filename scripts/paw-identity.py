#!/usr/bin/env python3
"""Stable PAW target-disk identity.

A kernel device path (/dev/sda) is a locator, never an identity.  This helper
builds a canonical composite identity from serial, WWN, model, exact capacity,
/dev/disk/by-id links, the sysfs physical path and a partition fingerprint.

Two hashes are emitted:

* composite_identity_sha256 includes the partition fingerprint.  It is used
  while the target is still blank (enrolment / pre-write checks).
* hardware_identity_sha256 excludes the partition fingerprint.  A clone
  deliberately replaces the partition table, so every post-write stage checks
  this hash instead.  The hardware hash is never a bare capacity or device
  name: at least one of serial, WWN or by-id is required for a strong identity.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

SCHEMA = "paw.device-identity.v1"
SYSFS_ROOT = Path(os.environ.get("PAW_IDENTITY_SYSFS_ROOT", "/sys/class/block"))
BY_ID_ROOT = Path(os.environ.get("PAW_IDENTITY_BY_ID_ROOT", "/dev/disk/by-id"))
DEV_RE = re.compile(r"^/dev/[A-Za-z0-9/]+$")


def out(args: list[str]) -> str:
    try:
        return subprocess.run(args, text=True, capture_output=True, check=False).stdout.strip()
    except OSError:
        return ""


def one(args: list[str]) -> str:
    value = out(args)
    return value.splitlines()[0].strip() if value else ""


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha(value: object) -> str:
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def sysfs_path(name: str) -> str:
    candidate = SYSFS_ROOT / name
    try:
        return str(candidate.resolve(strict=True))
    except OSError:
        return ""


def by_id_links(device: str) -> list[str]:
    target = Path(os.path.realpath(device))
    links: list[str] = []
    if not BY_ID_ROOT.is_dir():
        return links
    for entry in sorted(BY_ID_ROOT.iterdir()):
        if "-part" in entry.name:
            continue
        if Path(os.path.realpath(entry)) == target:
            links.append(entry.name)
    return links


def partition_fingerprint(device: str) -> tuple[str, list[dict]]:
    # -J works on util-linux >= 2.27; mocked tests override lsblk.
    raw = out(["lsblk", "-J", "-b", "-o",
               "NAME,PATH,TYPE,SIZE,START,PARTN,PARTTYPE,PARTUUID,FSTYPE", device])
    parts: list[dict] = []
    try:
        tree = json.loads(raw) if raw else {}
    except ValueError:
        tree = {}
    for disk in tree.get("blockdevices", []):
        for child in disk.get("children") or []:
            if child.get("type") != "part":
                continue
            parts.append({
                "name": child.get("name") or "",
                "start": child.get("start"),
                "size": child.get("size"),
                "partn": child.get("partn"),
                "parttype": (child.get("parttype") or "").lower(),
                "partuuid": (child.get("partuuid") or "").lower(),
                "fstype": (child.get("fstype") or "").lower(),
            })
    parts.sort(key=lambda p: (str(p.get("start")), str(p.get("name"))))
    return sha(parts), parts


def collect(device: str) -> dict:
    if not DEV_RE.fullmatch(device or ""):
        raise SystemExit("device path must match /dev/[A-Za-z0-9/]+")
    name = os.path.basename(device)
    model = one(["lsblk", "-dn", "-o", "MODEL", device])
    serial = one(["lsblk", "-dn", "-o", "SERIAL", device])
    wwn = one(["lsblk", "-dn", "-o", "WWN", device]).lower()
    tran = one(["lsblk", "-dn", "-o", "TRAN", device]).lower()
    try:
        capacity = int(one(["blockdev", "--getsize64", device]))
    except ValueError:
        capacity = 0
    links = by_id_links(device)
    syspath = sysfs_path(name)
    partition_sha, partitions = partition_fingerprint(device)
    # sysfs is a locator that changes with kernel enumeration.  It is part of
    # the hash only when no stronger anchor exists; serial/WWN/by-id disks can
    # move from /dev/sda to /dev/sdb without changing their stable identity.
    hardware = {
        "serial": serial,
        "wwn": wwn,
        "model": model,
        "capacity_bytes": capacity,
        "transport": tran,
        "by_id": links,
    }
    if not (serial or wwn or links):
        hardware["sysfs_path"] = syspath
    full = dict(hardware)
    full["partition_fingerprint"] = partition_sha
    anchors = []
    if serial:
        anchors.append("serial")
    if wwn:
        anchors.append("wwn")
    if links:
        anchors.append("by-id")
    if serial:
        basis = "serial+wwn+model+exact_capacity+by-id+sysfs+partition"
        strength = "strong"
    elif wwn:
        basis = "wwn+model+exact_capacity+by-id+sysfs+partition"
        strength = "strong"
    elif links:
        basis = "by-id+model+exact_capacity+sysfs+partition"
        strength = "strong"
    elif syspath:
        basis = "model+exact_capacity+sysfs+partition"
        strength = "weak"
    else:
        basis = "insufficient"
        strength = "insufficient"
    return {
        "schema": SCHEMA,
        "device_path": device,
        "device_name": name,
        "model": model,
        "serial": serial,
        "wwn": wwn,
        "capacity_bytes": capacity,
        "transport": tran,
        "by_id": links,
        "sysfs_path": syspath,
        "partition_fingerprint": partition_sha,
        "partitions": partitions,
        "anchors": anchors,
        "identity_basis": basis,
        "identity_strength": strength,
        "device_name_used_as_identity": False,
        "hardware_identity_sha256": sha(hardware),
        "composite_identity_sha256": sha(full),
        "sufficient": strength != "insufficient",
    }


def inventory(boot_device: str = "", source_device: str = "") -> dict:
    # Production inventories only whole disks.  The QEMU final-authorization
    # fixture uses a loop device as a disposable target stand-in; it opts in
    # explicitly so a loop can never become an eligible production target.
    include_loop = os.environ.get("PAW_IDENTITY_INCLUDE_LOOP") == "1"
    raw = out(["lsblk", "--json", "--bytes", "--output",
               "NAME,PATH,TYPE,SIZE,MODEL,SERIAL,WWN,TRAN,RM,MOUNTPOINTS,PARTTYPE,FSTYPE,PKNAME,ROTA"])
    try:
        tree = json.loads(raw) if raw else {}
    except ValueError:
        tree = {}
    devices = []
    for item in tree.get("blockdevices", []) or []:
        kind = item.get("type")
        if kind != "disk" and not (include_loop and kind == "loop"):
            continue
        path = item.get("path") or "/dev/" + str(item.get("name", ""))
        ident = collect(path)
        kids = item.get("children") or []
        mounted = [m for child in kids for m in (child.get("mountpoints") or []) if m]
        windows = any(str(c.get("fstype") or "").lower() in ("ntfs", "ntfs3", "exfat") or
                      str(c.get("parttype") or "").lower().startswith("ebd0a0a2-") for c in kids)
        efi = any(str(c.get("parttype") or "").lower() == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" for c in kids)
        reasons = []
        if kind == "loop":
            reasons.append("loop_device")
        if int(item.get("size") or 0) <= 0:
            reasons.append("zero_capacity")
        if str(item.get("rm", "0")) == "1":
            reasons.append("removable")
        if mounted:
            reasons.append("mounted")
        if windows:
            reasons.append("windows_or_ntfs")
        if boot_device and path == boot_device:
            reasons.append("current_boot_medium")
        if source_device and path == source_device:
            reasons.append("registered_source")
        if not ident["sufficient"]:
            reasons.append("unstable_identity")
        devices.append({
            **ident,
            "rm": str(item.get("rm", "0")) == "1",
            "mounted": bool(mounted),
            "mountpoints": mounted,
            "windows": windows,
            "efi": efi,
            "partition_table": [
                {"partn": c.get("partn"), "size": c.get("size"), "fstype": c.get("fstype"),
                 "parttype": c.get("parttype")} for c in kids
            ],
            "eligible": not reasons,
            "exclusion_reasons": reasons,
        })
    # Two disks with the same hardware hash cannot be told apart.  A path is
    # only a locator, so this must block instead of picking the first one.
    counts: dict[str, int] = {}
    hw_counts: dict[str, int] = {}
    for d in devices:
        # A duplicated non-empty serial/WWN is a firmware/clone red flag even
        # if sysfs currently differs; block instead of guessing.
        key = (d["serial"].lower(), d["wwn"].lower())
        if key != ("", ""):
            counts[str(key)] = counts.get(str(key), 0) + 1
        hw_counts[d["hardware_identity_sha256"]] = hw_counts.get(d["hardware_identity_sha256"], 0) + 1
    for d in devices:
        key = (d["serial"].lower(), d["wwn"].lower())
        duplicate_key = key != ("", "") and counts.get(str(key), 0) > 1
        d["ambiguous"] = duplicate_key or hw_counts[d["hardware_identity_sha256"]] > 1
        if d["ambiguous"] and "ambiguous_identity" not in d["exclusion_reasons"]:
            d["exclusion_reasons"].append("ambiguous_identity")
            d["eligible"] = False
    return {"schema": "paw.device-inventory.v1", "devices": devices,
            "eligible_count": sum(1 for d in devices if d["eligible"])}


def load_config(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError) as exc:
        raise SystemExit(f"cannot read identity config {path}: {exc}")


def verify(config_path: str, device: str, phase: str, check_unique: bool) -> dict:
    cfg = load_config(config_path)
    ident = collect(device)
    expected_hw = str(cfg.get("hardware_identity_sha256") or "")
    expected_comp = str(cfg.get("composite_identity_sha256") or "")
    expected_serial = str(cfg.get("serial") or "")
    expected_capacity = cfg.get("capacity_bytes")
    expected_model = str(cfg.get("model") or "")
    problems: list[str] = []
    if not ident["sufficient"]:
        problems.append("current device has no stable identity (no serial, WWN or by-id)")
    if expected_hw:
        if ident["hardware_identity_sha256"] != expected_hw:
            problems.append("hardware identity hash changed")
        if phase == "prewrite" and expected_comp and ident["composite_identity_sha256"] != expected_comp:
            problems.append("pre-write composite identity (partition fingerprint) changed")
    elif expected_comp:
        if ident["composite_identity_sha256"] != expected_comp:
            problems.append("composite identity hash changed")
    else:
        # Legacy enrollment: serial/capacity/model only.  Never accept a
        # no-serial disk through this path.
        if not expected_serial:
            problems.append("enrollment has no stable identity hash or serial")
        elif ident["serial"] != expected_serial:
            problems.append("serial mismatch")
        if expected_capacity is not None and int(ident["capacity_bytes"]) != int(expected_capacity):
            problems.append("capacity mismatch")
        if expected_model and ident["model"] != expected_model:
            problems.append("model mismatch")
    if check_unique:
        inv = inventory()
        matches = [d for d in inv["devices"]
                   if d["hardware_identity_sha256"] == ident["hardware_identity_sha256"]]
        if len(matches) > 1:
            problems.append("multiple disks share the same stable identity")
    result = {
        "schema": "paw.ssd-identity.v1",
        "status": "BLOCKED" if problems else "PASS",
        "device": device,
        "enrolled_device_path": cfg.get("device_path") or "",
        "device_path_changed": bool(cfg.get("device_path")) and cfg.get("device_path") != device,
        "phase": phase,
        "identity_basis": ident["identity_basis"],
        "identity_strength": ident["identity_strength"],
        "serial": ident["serial"],
        "wwn": ident["wwn"],
        "model": ident["model"],
        "capacity_bytes": ident["capacity_bytes"],
        "by_id": ident["by_id"],
        "sysfs_path": ident["sysfs_path"],
        "partition_fingerprint": ident["partition_fingerprint"],
        "enrolled_serial": expected_serial,
        "enrolled_model": expected_model,
        "enrolled_capacity_bytes": expected_capacity,
        "hardware_identity_sha256": ident["hardware_identity_sha256"],
        "composite_identity_sha256": ident["composite_identity_sha256"],
        "device_name_used_as_identity": False,
        "problems": problems,
    }
    if problems:
        result["reason"] = "; ".join(problems)
    return result


def resolve(config_path: str) -> dict:
    """Resolve the enrolled disk to its current path by stable identity."""
    cfg = load_config(config_path)
    expected_hw = str(cfg.get("hardware_identity_sha256") or "")
    expected_serial = str(cfg.get("serial") or "")
    inv = inventory()
    matches = []
    for device in inv["devices"]:
        if expected_hw:
            if device["hardware_identity_sha256"] == expected_hw:
                matches.append(device)
        elif expected_serial and device["serial"] == expected_serial and \
                int(device["capacity_bytes"]) == int(cfg.get("capacity_bytes") or 0):
            matches.append(device)
    if len(matches) != 1:
        return {"status": "BLOCKED", "reason": "target identity is missing or ambiguous",
                "match_count": len(matches), "devices": [m["device_path"] for m in matches]}
    chosen = matches[0]
    return {"status": "PASS", "device_path": chosen["device_path"],
            "hardware_identity_sha256": chosen["hardware_identity_sha256"],
            "composite_identity_sha256": chosen["composite_identity_sha256"],
            "identity_basis": chosen["identity_basis"],
            "device_path_changed": chosen["device_path"] != cfg.get("device_path")}


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    p_ident = sub.add_parser("identity")
    p_ident.add_argument("device")
    p_inv = sub.add_parser("inventory")
    p_inv.add_argument("--boot-device", default="")
    p_inv.add_argument("--source-device", default="")
    p_verify = sub.add_parser("verify")
    p_verify.add_argument("--config", required=True)
    p_verify.add_argument("--device", required=True)
    p_verify.add_argument("--phase", choices=("prewrite", "postwrite"), default="prewrite")
    p_verify.add_argument("--check-unique", action="store_true")
    p_resolve = sub.add_parser("resolve")
    p_resolve.add_argument("--config", required=True)
    args = parser.parse_args()
    if args.command == "identity":
        ident = collect(args.device)
        print(json.dumps(ident, indent=2, ensure_ascii=False))
        return 0 if ident["sufficient"] else 2
    if args.command == "inventory":
        print(json.dumps(inventory(args.boot_device, args.source_device), indent=2, ensure_ascii=False))
        return 0
    if args.command == "resolve":
        result = resolve(args.config)
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return 0 if result["status"] == "PASS" else 2
    result = verify(args.config, args.device, args.phase, args.check_unique)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if result["status"] == "PASS" else 2


if __name__ == "__main__":
    sys.exit(main())
