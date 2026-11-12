#!/usr/bin/env python3
"""Scan reachable Git blob contents without printing matched secret values."""
import ipaddress
import re
import subprocess
import sys

root = sys.argv[1] if len(sys.argv) > 1 else "."
patterns = {
    "private key block": re.compile(rb"-----BEGIN (?:OPENSSH|RSA|EC|DSA|PRIVATE) KEY-----"),
    "IPv4 literal": re.compile(rb"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b"),
    "email address": re.compile(rb"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
    "personal path or account": re.compile(b"(?i)(?:C:/Users/|C:" + re.escape(bytes([92])) + b"Users" + re.escape(bytes([92])) + b"|sunao|VM-0-15-ubuntu)"),
    "GitHub token": re.compile(rb"\bgh[pousr]_[A-Za-z0-9_]{30,}\b"),
    "Tailscale auth key": re.compile(rb"tskey-[A-Za-z0-9_-]{20,}"),
    "COS secret field": re.compile(rb"(?i)(?:secret.?id|secret.?key)\s*[=:]\s*['\"]?[A-Za-z0-9+/=_-]{12,}"),
    "cloud credential": re.compile(rb"(?i)(?:AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16})"),
}
safe_ips = {b"127.0.0.1", b"0.0.0.0", b"255.255.255.255"}
safe_ips.update(f"192.0.2.{i}".encode() for i in range(256))
safe_ips.update(f"198.51.100.{i}".encode() for i in range(256))
safe_ips.update(f"203.0.113.{i}".encode() for i in range(256))
cgnat = ipaddress.ip_network("100.64.0.0/10")
def safe_ip(raw):
    if raw in safe_ips:
        return True
    try:
        ip = ipaddress.ip_address(raw.decode("ascii"))
    except ValueError:
        return False
    return ip.is_loopback or ip.is_unspecified or ip in cgnat
# One legacy test fixture used 1.2.3.4 as a fake DNS answer.  It is not a user
# or production address and the current tree uses 127.0.0.1; skip exactly that
# historical blob so every other object is still scanned.
known_safe_blobs = {
    "e7a262bc721378045dc093794d26174a38144c1a":
        "legacy fake getent fixture in run-vless-network-tests.sh; replaced with 127.0.0.1",
}
# Documented public infrastructure/package metadata tokens in raw CI evidence
# logs; see check-public-safety.py.  Each is matched exactly, never by path.
benign_evidence_tokens = {
    b"140.248.150.132": "public snapshot.debian.org CDN address",
    b"1.2.5.1": "Debian package version 1.2.5.1-3",
    b"2.11.1.0": "Debian package version 2.11.1.0.20170917-3",
    b"859eca24-9c9d-4339-8a5b-93d75d48b128": "GitHub runner temp-directory UUID",
    b"c998e451-09ad-44a4-959f-b97a9c4a1c3b": "GitHub runner temp-directory UUID",
    b"2e1fa2df-b5d9-4ff3-ab55-ac79705522f8": "GitHub runner temp-directory UUID",
    b"sshd@.service.wants": "systemd unit path, not an email address",
}
findings = []

objects = subprocess.run(
    ["git", "-C", root, "rev-list", "--objects", "--all"],
    check=True, stdout=subprocess.PIPE, text=True,
).stdout.splitlines()
seen = set()
batch = subprocess.Popen(
    ["git", "-C", root, "cat-file", "--batch"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
)
assert batch.stdin and batch.stdout
for entry in objects:
    parts = entry.split(" ", 1)
    oid = parts[0]
    path = parts[1] if len(parts) == 2 else "(unmapped blob)"
    if oid in seen:
        continue
    seen.add(oid)
    if oid in known_safe_blobs:
        continue
    batch.stdin.write((oid + "\n").encode())
    batch.stdin.flush()
    header = batch.stdout.readline().split()
    if len(header) != 3:
        continue
    size = int(header[2])
    data = batch.stdout.read(size)
    batch.stdout.read(1)
    if header[1] != b"blob":
        continue
    normalized_path = path.replace("\\", "/")
    if normalized_path.endswith(("scripts/ci/check-public-history.py",
                                  "scripts/ci/check-public-safety.py")):
        continue
    if size > 20_000_000 or b"\0" in data:
        continue
    for label, pattern in patterns.items():
        for match in pattern.finditer(data):
            if label == "IPv4 literal" and safe_ip(match.group(0)):
                continue
            if (normalized_path.startswith("reports/evidence/")
                    and normalized_path.endswith(".log")
                    and match.group(0) in benign_evidence_tokens):
                continue
            if label == "email address" and match.group(0) in (
                b"getty@tty1.service", b"serial-getty@ttyS0.service",
                b"not-a-uuid@example.test",
            ):
                continue
            line = data.count(b"\n", 0, match.start()) + 1
            findings.append(f"{label}: {path}:{line} blob={oid[:12]}")
batch.stdin.close()
if batch.wait() != 0:
    print("PUBLIC-HISTORY=ERROR; git object scan failed", file=sys.stderr)
    raise SystemExit(2)
if findings:
    print("PUBLIC-HISTORY=FAIL")
    print("\n".join(findings))
    raise SystemExit(1)
print(f"PUBLIC-HISTORY=PASS; scanned {len(seen)} reachable Git objects ({len(known_safe_blobs)} documented fixture exception); no configured sensitive markers found")
