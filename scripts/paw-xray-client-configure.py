#!/usr/bin/env python3
"""Build a minimal Xray v26.3.27 Reality client config from a NUL-delimited stdin record."""
import json
import os
from pathlib import Path
import re
import sys
import uuid

if len(sys.argv) != 2:
    raise SystemExit("output path required")
values = sys.stdin.buffer.read().split(b"\0")
if len(values) != 9:
    raise SystemExit("invalid input record")
address, port, user_id, flow, server_name, fingerprint, public_key, short_id = [
    value.decode("utf-8") for value in values[:-1]
]
if not re.fullmatch(r"[A-Za-z0-9.-]+", address):
    raise SystemExit("invalid server address")
if not port.isdecimal() or not 1 <= int(port) <= 65535:
    raise SystemExit("invalid server port")
try:
    uuid.UUID(user_id)
except (ValueError, AttributeError):
    raise SystemExit("invalid VLESS UUID")
if flow not in ("", "xtls-rprx-vision"):
    raise SystemExit("unsupported flow")
if not re.fullmatch(r"[A-Za-z0-9.-]+", server_name):
    raise SystemExit("invalid serverName")
if not re.fullmatch(r"[A-Za-z0-9_-]+", fingerprint):
    raise SystemExit("invalid fingerprint")
if not re.fullmatch(r"[A-Za-z0-9_-]{20,64}", public_key):
    raise SystemExit("invalid Reality client publicKey")
if not re.fullmatch(r"(?:[0-9a-fA-F]{2}){1,8}", short_id):
    raise SystemExit("shortId must be 2-16 even-length hexadecimal characters")

config = {
    "log": {"loglevel": "warning"},
    "inbounds": [
        {"listen": "127.0.0.1", "port": 10808, "protocol": "socks", "settings": {"auth": "noauth", "udp": True}},
        {"listen": "127.0.0.1", "port": 10809, "protocol": "http"},
    ],
    "outbounds": [
        {
            "protocol": "vless",
            "settings": {"vnext": [{"address": address, "port": int(port), "users": [{"id": user_id, "encryption": "none", **({"flow": flow} if flow else {})}]}]},
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {"serverName": server_name, "fingerprint": fingerprint, "publicKey": public_key, "shortId": short_id},
            },
        },
        {"protocol": "freedom", "tag": "direct"},
    ],
}
path = Path(sys.argv[1])
with path.open("w", encoding="utf-8") as handle:
    json.dump(config, handle, separators=(",", ":"))
os.chmod(path, 0o600)
