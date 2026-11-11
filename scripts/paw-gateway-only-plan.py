#!/usr/bin/env python3
"""Classify old VPS units for a gateway-only recovery plan. Read-only design."""
import argparse
import datetime as dt
import json
import os
import re

GATEWAY = {
    "ssh.service", "ssh.socket", "xray.service", "xray@.service",
    "tailscaled.service", "systemd-networkd.service", "systemd-resolved.service",
    "cron.service", "rsyslog.service", "unattended-upgrades.service",
}
BUSINESS_HINTS = re.compile(
    r"paw|mcp|claude|gpt|spark|nginx|funnel|cos|upload|poll|worker|bot|api|scheduler|timer", re.I)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--old-manifest", required=True)
    ap.add_argument("--new-manifest", default="")
    ap.add_argument("--output", required=True)
    args = ap.parse_args()
    old = json.load(open(args.old_manifest, encoding="utf-8"))
    new = json.load(open(args.new_manifest, encoding="utf-8")) if args.new_manifest else {}
    old_units = old.get("old", {}).get("enabled_services", [])
    new_units = set(new.get("new", {}).get("enabled_services", []))
    rows = []
    for unit in old_units:
        if unit in GATEWAY:
            action, reason = "KEEP", "gateway/SSH/Xray/network prerequisite"
        elif BUSINESS_HINTS.search(unit):
            action, reason = "DISABLE", "business/MCP/Nginx/Funnel/COS/API identity must not duplicate"
        else:
            action, reason = "REVIEW", "not on the approved gateway allow-list"
        rows.append({"unit": unit, "action": action, "reason": reason,
                     "also_on_new_target": unit in new_units})
    overlap = [r for r in rows if r["also_on_new_target"] and r["action"] != "DISABLE"]
    status = "PASS" if not overlap else "REVIEW"
    doc = {
        "schema": "paw.gateway-only-plan.v1",
        "status": status,
        "execute_on_production": False,
        "allowed_gateway_units": sorted(GATEWAY),
        "rows": rows,
        "duplicate_business_units": [r["unit"] for r in rows if r["also_on_new_target"]],
        "steps": [
            "Operator confirms the old VPS is in normal Ubuntu, not Rescue Mode.",
            "Disable every DISABLE/REVIEW business unit before enabling Xray.",
            "Keep SSH and Xray/VLESS only; do not start PAW MCP/GPT MCP/Claude MCP/Spark MCP/Nginx/Funnel/COS jobs.",
            "Optionally keep tailscaled only as an Exit Node after confirming no duplicate PAW business identity.",
            "Re-check reachability from PAW Live before Tailscale login.",
        ],
        "rollback": "Re-enable the previous unit list from the VPS provider console; this plan never edits the production VPS.",
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    tmp = args.output + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(doc, handle, indent=2, ensure_ascii=False)
    os.chmod(tmp, 0o600)
    os.replace(tmp, args.output)
    print(json.dumps({"status": status, "units": len(rows), "duplicates": len(overlap)}, separators=(",", ":")))
    return 0 if status == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
