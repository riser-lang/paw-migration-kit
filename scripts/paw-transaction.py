#!/usr/bin/env python3
"""PAW migration transaction state machine (authorization is not a 6h lease).

The authorization timestamp limits *starting* a migration.  Once a clone has
started, the same transaction must remain usable for verification, offline
repair and GPT/ext4 expansion without re-authorizing or re-transmitting.

The transaction is deliberately bound to immutable source/target fields.  A
copy of an old authorization file cannot be reused for another target or
source, and a terminal transaction cannot start a second clone.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import sys
import uuid
from pathlib import Path

SCHEMA = "paw.migration-transaction.v1"
TERMINAL = {"COMPLETE", "FAILED"}
STATES = {
    "PREPARED", "AUTHORIZED", "CLONING", "CLONE_INCOMPLETE", "CLONE_VERIFIED",
    "REPAIRING", "REPAIRED", "EXPANDING", "READY_TO_BOOT", "COMPLETE",
    "FAILED", "NEEDS_MANUAL_ACTION",
}
STAGE_STATES = {
    "authorization": {"AUTHORIZED"},
    "clone": {"AUTHORIZED"},
    "clone-verify": {"CLONING", "CLONE_INCOMPLETE"},
    "repair": {"CLONE_VERIFIED", "NEEDS_MANUAL_ACTION"},
    "expand": {"REPAIRED", "EXPANDING", "NEEDS_MANUAL_ACTION"},
    "finalize": {"READY_TO_BOOT"},
    "complete": {"READY_TO_BOOT"},
}
EVENT_FROM = {
    "CLONE_STARTED": {"AUTHORIZED", "CLONE_INCOMPLETE"},
    "CLONE_INCOMPLETE": {"CLONING"},
    "CLONE_VERIFIED": {"CLONING", "CLONE_INCOMPLETE"},
    "REPAIR_STARTED": {"CLONE_VERIFIED", "NEEDS_MANUAL_ACTION"},
    "REPAIRED": {"REPAIRING"},
    "EXPAND_STARTED": {"REPAIRED"},
    "READY_TO_BOOT": {"EXPANDING"},
    "COMPLETE": {"READY_TO_BOOT"},
    "FAILED": STATES,
    "NEEDS_MANUAL_ACTION": STATES - {"COMPLETE", "FAILED"},
}
EVENT_TO = {
    "CLONE_STARTED": "CLONING",
    "CLONE_INCOMPLETE": "CLONE_INCOMPLETE",
    "CLONE_VERIFIED": "CLONE_VERIFIED",
    "REPAIR_STARTED": "REPAIRING",
    "REPAIRED": "REPAIRED",
    "EXPAND_STARTED": "EXPANDING",
    "READY_TO_BOOT": "READY_TO_BOOT",
    "COMPLETE": "COMPLETE",
    "FAILED": "FAILED",
    "NEEDS_MANUAL_ACTION": "NEEDS_MANUAL_ACTION",
}


class TransactionError(SystemExit):
    def __init__(self, code: str, detail: str):
        self.code = code
        self.detail = detail
        super().__init__(f"{code}: {detail}")


def now_utc(explicit: str | None) -> dt.datetime:
    if explicit:
        value = dt.datetime.fromisoformat(explicit)
        if value.tzinfo is None:
            raise TransactionError("INVALID_NOW", "--now must include a timezone")
        return value.astimezone(dt.timezone.utc)
    return dt.datetime.now(dt.timezone.utc)


def iso(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).isoformat()


def load_json(path: str, code: str) -> dict:
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError) as exc:
        raise TransactionError(code, f"{path}: {exc}") from exc
    if not isinstance(data, dict):
        raise TransactionError(code, f"{path}: not a JSON object")
    return data


def write_json(path: str, data: dict) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + f".tmp.{os.getpid()}")
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(tmp, 0o600)
    os.replace(tmp, target)


def require(condition: bool, code: str, detail: str) -> None:
    if not condition:
        raise TransactionError(code, detail)


def validate_sha(value: str) -> str:
    value = str(value or "").lower()
    require(bool(re.fullmatch(r"[0-9a-f]{64}", value)), "INVALID_SHA256", "expected 64 lowercase hex characters")
    return value


def source_snapshot(config: dict) -> dict:
    keys = ("device_path", "root_uuid", "model", "serial", "capacity_bytes",
            "composite_identity_sha256", "ssh_host_key_fingerprint")
    missing = [k for k in keys[:6] if config.get(k) in (None, "")]
    require(not missing, "SOURCE_BINDING_MISSING", f"source.json missing {missing}")
    return {
        "device_path": str(config.get("device_path")),
        "root_uuid": str(config.get("root_uuid")).lower(),
        "model": str(config.get("model") or ""),
        "serial": str(config.get("serial") or ""),
        "capacity_bytes": int(config.get("capacity_bytes")),
        "composite_identity_sha256": str(config.get("composite_identity_sha256")),
        "ssh_host_key_fingerprint": str(config.get("ssh_host_key_fingerprint") or ""),
    }


def target_snapshot(config: dict) -> dict:
    required = ("device_path", "model", "capacity_bytes")
    missing = [k for k in required if config.get(k) in (None, "")]
    require(not missing, "TARGET_BINDING_MISSING", f"target-ssd.json missing {missing}")
    require(bool(config.get("approved")), "TARGET_NOT_APPROVED", "target enrollment is not approved")
    hardware = str(config.get("hardware_identity_sha256") or "").lower()
    composite = str(config.get("composite_identity_sha256") or "").lower()
    serial = str(config.get("serial") or "")
    require(bool(serial or hardware or composite), "TARGET_BINDING_MISSING",
            "target-ssd.json has no serial or stable identity hash")
    if hardware:
        hardware = validate_sha(hardware)
    if composite:
        composite = validate_sha(composite)
    return {
        "device_path": str(config.get("device_path")),
        "model": str(config.get("model") or ""),
        "serial": serial,
        "capacity_bytes": int(config["capacity_bytes"]),
        "wwn": str(config.get("wwn") or "").lower(),
        "by_id": list(config.get("by_id") or []),
        "sysfs_path": str(config.get("sysfs_path") or ""),
        "identity_basis": str(config.get("identity_basis") or ("serial" if serial else "")),
        "hardware_identity_sha256": hardware,
        "composite_identity_sha256": composite,
    }


def binding_matches(transaction: dict, source: dict, target: dict) -> None:
    expected_source = transaction.get("source") or {}
    expected_target = transaction.get("target") or {}
    for key in ("device_path", "root_uuid", "capacity_bytes", "composite_identity_sha256"):
        require(expected_source.get(key) == source.get(key), "SOURCE_CHANGED",
                f"source {key} differs from the authorized transaction")
    if expected_target.get("hardware_identity_sha256") or target.get("hardware_identity_sha256"):
        for key in ("hardware_identity_sha256", "composite_identity_sha256"):
            require(expected_target.get(key) == target.get(key), "TARGET_CHANGED",
                    f"target {key} differs from the authorized transaction")
    else:
        for key in ("device_path", "serial", "capacity_bytes"):
            require(expected_target.get(key) == target.get(key), "TARGET_CHANGED",
                    f"target {key} differs from the authorized transaction")


def auth_matches(transaction: dict, authorization: dict) -> None:
    require(authorization.get("status") in ("AUTHORIZED", "CONSUMED"), "AUTH_NOT_ACTIVE",
            "authorization is not active")
    require(authorization.get("migration_id") == transaction.get("migration_id"), "AUTH_MIGRATION_MISMATCH",
            "authorization migration_id does not match transaction")
    require(authorization.get("authorization_id") == transaction.get("authorization_id"), "AUTH_ID_MISMATCH",
            "authorization_id does not match transaction")
    target = transaction.get("target", {})
    auth_hw = str(authorization.get("target_hardware_identity_sha256") or "")
    if target.get("hardware_identity_sha256") or auth_hw:
        require(auth_hw == target.get("hardware_identity_sha256"), "AUTH_TARGET_MISMATCH",
                "authorization target hardware identity does not match transaction")
        require(str(authorization.get("target_composite_identity_sha256") or "") ==
                target.get("composite_identity_sha256"), "AUTH_TARGET_MISMATCH",
                "authorization target composite identity does not match transaction")
    else:
        require(authorization.get("target_serial") == target.get("serial"), "AUTH_TARGET_MISMATCH",
                "authorization target serial does not match transaction")
    require(authorization.get("source_composite_identity_sha256") ==
            transaction.get("source", {}).get("composite_identity_sha256"), "AUTH_SOURCE_MISMATCH",
            "authorization source identity does not match transaction")


def load_transaction(path: str) -> dict:
    data = load_json(path, "TRANSACTION_MISSING")
    require(data.get("schema") == SCHEMA, "TRANSACTION_SCHEMA", "unsupported transaction schema")
    require(data.get("state") in STATES, "TRANSACTION_STATE", "unknown transaction state")
    require(bool(re.fullmatch(r"[0-9a-f-]{36}", str(data.get("migration_id", "")))), "TRANSACTION_ID",
            "migration_id is missing")
    return data


def cmd_init(args) -> int:
    authorization = load_json(args.authorization, "AUTH_MISSING")
    source = source_snapshot(load_json(args.source_config, "SOURCE_CONFIG_MISSING"))
    target = target_snapshot(load_json(args.target_config, "TARGET_CONFIG_MISSING"))
    now = now_utc(args.now)
    require(authorization.get("status") == "AUTHORIZED", "AUTH_NOT_ACTIVE", "authorization is not active")
    migration_id = str(authorization.get("migration_id") or "")
    authorization_id = str(authorization.get("authorization_id") or "")
    require(bool(re.fullmatch(r"[0-9a-f-]{36}", migration_id)), "AUTH_MIGRATION_ID",
            "authorization has no migration_id")
    require(bool(re.fullmatch(r"[0-9a-f-]{36}", authorization_id)), "AUTH_AUTHORIZATION_ID",
            "authorization has no authorization_id")
    if target.get("hardware_identity_sha256"):
        require(authorization.get("target_hardware_identity_sha256") == target["hardware_identity_sha256"],
                "AUTH_TARGET_MISMATCH", "authorization target hardware identity does not match enrollment")
        require(authorization.get("target_composite_identity_sha256") == target["composite_identity_sha256"],
                "AUTH_TARGET_MISMATCH", "authorization target composite identity does not match enrollment")
    else:
        require(authorization.get("target_serial") == target["serial"], "AUTH_TARGET_MISMATCH",
                "authorization target serial does not match enrollment")
        require(authorization.get("target_device") == target["device_path"], "AUTH_TARGET_MISMATCH",
                "authorization target device does not match enrollment")
    require(authorization.get("source_composite_identity_sha256") == source["composite_identity_sha256"],
            "AUTH_SOURCE_MISMATCH", "authorization source identity does not match enrollment")
    expires = dt.datetime.fromisoformat(str(authorization.get("expires_at", "")))
    require(expires.tzinfo is not None, "AUTH_EXPIRY_INVALID", "authorization expiry has no timezone")
    if Path(args.transaction).exists():
        existing = load_transaction(args.transaction)
        # Re-running final-confirm before any clone is idempotent, but only for
        # the exact same authorization and binding.
        require(existing.get("migration_id") == migration_id and
                existing.get("authorization_id") == authorization_id and
                existing.get("state") in ("PREPARED", "AUTHORIZED"),
                "TRANSACTION_EXISTS", "an active or terminal transaction already exists")
        auth_matches(existing, authorization)
        binding_matches(existing, source, target)
        return 0
    transaction = {
        "schema": SCHEMA,
        "migration_id": migration_id,
        "authorization_id": authorization_id,
        "state": "AUTHORIZED",
        "created_at": iso(now),
        "updated_at": iso(now),
        "authorized_at": authorization.get("authorized_at"),
        "authorization_expires_at": iso(expires),
        "source": source,
        "target": target,
        "source_bytes": source["capacity_bytes"],
        "target_bytes": target["capacity_bytes"],
        "clone_started_at": None,
        "clone_incomplete_at": None,
        "clone_completed_at": None,
        "sha256": None,
        "bytes_verified": None,
        "repair_started_at": None,
        "repaired_at": None,
        "expand_started_at": None,
        "ready_at": None,
        "completed_at": None,
        "failed_phase": None,
        "failure_reason": None,
    }
    write_json(args.transaction, transaction)
    print(json.dumps({"status": "PASS", "state": transaction["state"],
                      "migration_id": migration_id, "authorization_id": authorization_id},
                     separators=(",", ":")))
    return 0


def cmd_assert(args) -> int:
    transaction = load_transaction(args.transaction)
    authorization = load_json(args.authorization, "AUTH_MISSING")
    source = source_snapshot(load_json(args.source_config, "SOURCE_CONFIG_MISSING"))
    target = target_snapshot(load_json(args.target_config, "TARGET_CONFIG_MISSING"))
    auth_matches(transaction, authorization)
    binding_matches(transaction, source, target)
    state = transaction["state"]
    allowed = STAGE_STATES[args.stage]
    if args.stage == "repair" and state == "NEEDS_MANUAL_ACTION":
        require(transaction.get("failed_phase") == "repair", "STATE_NOT_REPAIRABLE",
                "manual-action state is not a repair failure")
    if args.stage == "expand" and state == "NEEDS_MANUAL_ACTION":
        require(transaction.get("failed_phase") == "expand", "STATE_NOT_EXPANDABLE",
                "manual-action state is not an expansion failure")
    require(state in allowed, "STATE_NOT_ALLOWED", f"stage {args.stage} not allowed in state {state}")
    if state == "AUTHORIZED":
        # The six-hour limit applies only before the clone starts.  Once
        # CLONING is entered, later stages deliberately ignore this timestamp.
        now = now_utc(args.now)
        expires = dt.datetime.fromisoformat(transaction["authorization_expires_at"])
        require(now <= expires, "AUTHORIZATION_EXPIRED_BEFORE_CLONE",
                f"authorization expired at {iso(expires)}; no clone has started")
    if args.stage == "clone" and state == "CLONE_INCOMPLETE":
        require(os.environ.get("PAW_RESUME_INCOMPLETE") == "I_HAVE_VERIFIED_INCOMPLETE_MARKER",
                "RESUME_NOT_ARMED", "incomplete clone requires explicit resume arm")
    if args.stage in ("repair", "expand"):
        require(transaction.get("sha256") and transaction.get("bytes_verified") is not None,
                "VERIFY_BEFORE_REPAIR_REQUIRED", "no verified clone transaction")
        verify = load_json(args.stream_verify, "STREAM_VERIFY_MISSING")
        require(verify.get("status") == "PASS", "STREAM_VERIFY_NOT_PASS", "stream verify is not PASS")
        require(verify.get("independent_sha256_verified") is True, "STREAM_VERIFY_NOT_INDEPENDENT",
                "stream verify does not prove independent read-back")
        require(verify.get("sha256") == transaction.get("sha256"), "STREAM_VERIFY_SHA_MISMATCH",
                "verification hash differs from transaction")
        require(int(verify.get("bytes_verified", -1)) == int(transaction.get("bytes_verified")),
                "STREAM_VERIFY_BYTES_MISMATCH", "verification byte count differs from transaction")
    print(json.dumps({"status": "PASS", "state": state, "stage": args.stage,
                      "expiry_enforced": state == "AUTHORIZED"}, separators=(",", ":")))
    return 0


def cmd_event(args) -> int:
    transaction = load_transaction(args.transaction)
    event = args.event
    require(event in EVENT_TO, "UNKNOWN_EVENT", event)
    require(transaction["state"] in EVENT_FROM[event], "EVENT_STATE",
            f"{event} not allowed from {transaction['state']}")
    now = now_utc(args.now)
    if event == "CLONE_STARTED":
        if transaction["state"] == "AUTHORIZED":
            expires = dt.datetime.fromisoformat(transaction["authorization_expires_at"])
            require(now <= expires, "AUTHORIZATION_EXPIRED_BEFORE_CLONE",
                    f"authorization expired at {iso(expires)}; clone was not started")
        elif transaction["state"] == "CLONE_INCOMPLETE":
            require(os.environ.get("PAW_RESUME_INCOMPLETE") == "I_HAVE_VERIFIED_INCOMPLETE_MARKER",
                    "RESUME_NOT_ARMED", "incomplete clone requires explicit resume arm")
        transaction["clone_started_at"] = iso(now)
    elif event == "CLONE_INCOMPLETE":
        transaction["clone_incomplete_at"] = iso(now)
    elif event == "CLONE_VERIFIED":
        transaction["sha256"] = validate_sha(args.sha256)
        require(args.bytes_verified is not None and int(args.bytes_verified) >= 0,
                "INVALID_BYTES", "--bytes-verified required")
        transaction["bytes_verified"] = int(args.bytes_verified)
        transaction["clone_completed_at"] = iso(now)
        transaction["verified_at"] = iso(now)
    elif event == "REPAIR_STARTED":
        transaction["repair_started_at"] = iso(now)
        transaction["failed_phase"] = None
        transaction["failure_reason"] = None
    elif event == "REPAIRED":
        transaction["repaired_at"] = iso(now)
    elif event == "EXPAND_STARTED":
        transaction["expand_started_at"] = iso(now)
    elif event == "READY_TO_BOOT":
        transaction["ready_at"] = iso(now)
    elif event == "COMPLETE":
        transaction["completed_at"] = iso(now)
    elif event in ("FAILED", "NEEDS_MANUAL_ACTION"):
        transaction["failed_phase"] = args.phase or transaction.get("failed_phase")
        transaction["failure_reason"] = args.reason or "unspecified"
    transaction["state"] = EVENT_TO[event]
    transaction["updated_at"] = iso(now)
    write_json(args.transaction, transaction)
    print(json.dumps({"status": "PASS", "event": event, "state": transaction["state"]},
                     separators=(",", ":")))
    return 0


def cmd_show(args) -> int:
    transaction = load_transaction(args.transaction)
    print(json.dumps({k: transaction.get(k) for k in
                      ("migration_id", "authorization_id", "state", "source", "target",
                       "authorization_expires_at", "sha256", "bytes_verified",
                       "failed_phase", "failure_reason")}, indent=2, sort_keys=True))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    init = sub.add_parser("init")
    init.add_argument("--transaction", required=True)
    init.add_argument("--authorization", required=True)
    init.add_argument("--source-config", required=True)
    init.add_argument("--target-config", required=True)
    init.add_argument("--now")
    init.set_defaults(func=cmd_init)

    assert_p = sub.add_parser("assert")
    assert_p.add_argument("--transaction", required=True)
    assert_p.add_argument("--authorization", required=True)
    assert_p.add_argument("--source-config", required=True)
    assert_p.add_argument("--target-config", required=True)
    assert_p.add_argument("--stream-verify", default="")
    assert_p.add_argument("--stage", required=True, choices=sorted(STAGE_STATES))
    assert_p.add_argument("--now")
    assert_p.set_defaults(func=cmd_assert)

    event = sub.add_parser("event")
    event.add_argument("--transaction", required=True)
    event.add_argument("--event", required=True)
    event.add_argument("--sha256", default="")
    event.add_argument("--bytes-verified", type=int)
    event.add_argument("--phase", default="")
    event.add_argument("--reason", default="")
    event.add_argument("--now")
    event.set_defaults(func=cmd_event)

    show = sub.add_parser("show")
    show.add_argument("--transaction", required=True)
    show.set_defaults(func=cmd_show)

    args = parser.parse_args()
    try:
        return args.func(args)
    except TransactionError as exc:
        print(json.dumps({"status": "BLOCKED", "code": exc.code, "detail": exc.detail},
                         ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
