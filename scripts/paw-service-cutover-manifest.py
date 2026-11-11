#!/usr/bin/env python3
"""Build a secret-free old/new service identity isolation manifest."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path


def sha_file(path: Path) -> str | None:
    if not path.is_file():
        return None
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def key_fingerprint(path: Path) -> str | None:
    # The caller supplies ssh-keygen output; this function only hashes the
    # public key file for a stable, non-secret comparison.
    return sha_file(path)


def enabled_units(root: Path) -> list[str]:
    names = set()
    for wants in (root / "etc/systemd/system").glob("*.wants"):
        for unit in wants.glob("*.service"):
            names.add(unit.name)
    return sorted(names)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-config", required=True)
    parser.add_argument("--target-root", required=True)
    parser.add_argument("--old-hostname", default="")
    parser.add_argument("--old-machine-id", default="")
    parser.add_argument("--old-ssh-fingerprint", default="")
    parser.add_argument("--old-services-json", default="[]")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    source = json.load(open(args.source_config, encoding="utf-8"))
    root = Path(args.target_root)
    new_machine = (root / "etc/machine-id").read_text(encoding="utf-8").strip() if (root / "etc/machine-id").is_file() else ""
    new_hostname = (root / "etc/hostname").read_text(encoding="utf-8").strip() if (root / "etc/hostname").is_file() else ""
    new_ssh = key_fingerprint(root / "etc/ssh/ssh_host_ed25519_key.pub")
    old_services = json.loads(args.old_services_json or "[]")
    new_services = enabled_units(root)
    old_machine_sha = hashlib.sha256(args.old_machine_id.encode()).hexdigest() if args.old_machine_id else None
    new_machine_sha = hashlib.sha256(new_machine.encode()).hexdigest() if new_machine else None
    checks = {
        "machine_id_changed": bool(old_machine_sha and new_machine_sha and old_machine_sha != new_machine_sha),
        "ssh_host_key_changed": bool(args.old_ssh_fingerprint and new_ssh and args.old_ssh_fingerprint != new_ssh),
        "hostname_preserved": bool(args.old_hostname and new_hostname and args.old_hostname == new_hostname),
        "tailscale_state_not_copied": not (root / "var/lib/tailscale/tailscaled.state").exists(),
    }
    required = ("machine_id_changed", "ssh_host_key_changed", "tailscale_state_not_copied")
    status = "PASS" if all(checks[k] for k in required) else "REVIEW"
    document = {
        "schema": "paw.service-cutover-manifest.v1",
        "status": status,
        "old": {
            "hostname": args.old_hostname,
            "machine_id_sha256": old_machine_sha,
            "ssh_host_key_sha256": args.old_ssh_fingerprint or None,
            "enabled_services": old_services,
            "source_device": source.get("device_path"),
            "source_composite_identity_sha256": source.get("composite_identity_sha256"),
        },
        "new": {
            "hostname": new_hostname,
            "machine_id_sha256": new_machine_sha,
            "ssh_host_key_sha256": new_ssh,
            "enabled_services": new_services,
        },
        "isolation_checks": checks,
        "shared_identity_avoided": {
            "machine_id": checks["machine_id_changed"],
            "ssh_host_keys": checks["ssh_host_key_changed"],
            "tailscale_node_state": checks["tailscale_state_not_copied"],
        },
        "note": "Only SHA256 digests and unit names are recorded; no host keys, tokens or machine-id values are stored.",
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_name(out.name + f".tmp.{os.getpid()}")
    tmp.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.chmod(tmp, 0o600)
    os.replace(tmp, out)
    print(json.dumps({"status": status, "checks": checks}, separators=(",", ":")))
    return 0 if status == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
