#!/usr/bin/env python3
"""Convert one user-supplied VLESS URI into the approved RAM-only Xray config.

The URI is read from stdin, never argv, and no value is printed on error.
Only the URI's public connection fields are retained; no private key is accepted.
"""
import json
import os
import sys
import urllib.parse
import uuid as uuidlib


def fail(code: str) -> "NoReturn":
    raise SystemExit(code)


def main() -> int:
    uri = sys.stdin.read().strip()
    if not uri.startswith("vless://") or len(uri) > 8192:
        fail("VLESS_URI_INVALID")
    try:
        parsed = urllib.parse.urlsplit(uri)
        uuid = urllib.parse.unquote(parsed.username or "")
        host = parsed.hostname or ""
        port = parsed.port
    except ValueError:
        fail("VLESS_URI_INVALID")
    try:
        uuidlib.UUID(uuid)
    except ValueError:
        fail("VLESS_UUID_INVALID")
    if not host or not port or not 1 <= port <= 65535:
        fail("VLESS_URI_INVALID")
    if any(c in host for c in " \t\r\n/\\"):
        fail("VLESS_HOST_INVALID")
    query = urllib.parse.parse_qs(parsed.query, strict_parsing=False)
    get = lambda k, default="": (query.get(k) or [default])[0]
    security = get("security", "none").lower()
    network = get("type", "tcp").lower()
    if security not in ("reality", "tls", "none"):
        fail("VLESS_SECURITY_UNSUPPORTED")
    if network not in ("tcp", "ws", "grpc"):
        fail("VLESS_TRANSPORT_UNSUPPORTED")
    stream = {"network": network, "security": security}
    if security == "reality":
        pbk, sni, sid, fp = get("pbk"), get("sni") or get("serverName"), get("sid"), get("fp", "chrome")
        if not pbk or not sni:
            fail("VLESS_REALITY_FIELDS_MISSING")
        stream["realitySettings"] = {"serverName": sni, "fingerprint": fp,
                                     "publicKey": pbk, "shortId": sid}
    elif security == "tls":
        stream["tlsSettings"] = {"serverName": get("sni") or host,
                                 "fingerprint": get("fp", "chrome")}
    if network == "ws":
        stream["wsSettings"] = {"path": get("path", "/"), "headers": {"Host": get("host", host)}}
    elif network == "grpc":
        stream["grpcSettings"] = {"serviceName": get("serviceName", "")}
    user = {"id": uuid, "encryption": "none"}
    flow = get("flow")
    if flow:
        user["flow"] = flow
    config = {
        "log": {"loglevel": "warning"},
        "inbounds": [
            {"listen": "127.0.0.1", "port": 10808, "protocol": "socks",
             "settings": {"auth": "noauth", "udp": True}},
            {"listen": "127.0.0.1", "port": 10809, "protocol": "http"},
        ],
        "outbounds": [
            {"protocol": "vless",
             "settings": {"vnext": [{"address": host, "port": port, "users": [user]}]},
             "streamSettings": stream},
            {"protocol": "freedom", "tag": "direct"},
        ],
    }
    path = sys.argv[1]
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(config, handle, indent=2)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
    print(json.dumps({"status": "PASS", "host": host, "port": port,
                      "security": security, "transport": network}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
