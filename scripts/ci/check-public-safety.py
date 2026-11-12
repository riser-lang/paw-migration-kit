#!/usr/bin/env python3
import hashlib
import ipaddress
import re
import sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
patterns = {
    "private key block": re.compile(rb"-----BEGIN (?:OPENSSH|RSA|EC|DSA|PRIVATE) KEY-----"),
    "canonical UUID": re.compile(rb"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b"),
    "IPv4 literal": re.compile(rb"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b"),
    "email address": re.compile(rb"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
    "personal path or account": re.compile(b"(?i)(?:C:/" + b"Users/|C:" + re.escape(bytes([92])) + b"Users" + re.escape(bytes([92])) + b"|sun" + b"ao|VM-0-15-" + b"ubuntu)"),
    "Tailscale auth key": re.compile(rb"tskey-[A-Za-z0-9_-]{20,}"),
    "COS secret field": re.compile(rb"(?i)(?:secret.?id|secret.?key)\s*[=:]\s*['\"]?[A-Za-z0-9+/=_-]{12,}"),
}
def safe_ip(raw):
    try:
        ip = ipaddress.ip_address(raw.decode("ascii"))
    except ValueError:
        return False
    return ip.is_loopback or ip.is_unspecified

allowed_partition_guids = {
    b"21686148-6449-6e6f-744e-656564454649",
    b"0fc63daf-8483-4772-8e79-3d69d8477de4",
}
# Two release assets are intentionally committed binaries; accept them only
# while their pinned SHA256 still matches, so tampering is still reported.
pinned_binaries = {
    "boot/bin/xray": "8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed",
    "configs/memtest86+/memtest86+x64.bin": "487bfe56b84f2016b12f393641f1acb765ef0b648c71ea9a2e3d42b62411f71f",
}
findings = []
for path in root.rglob("*"):
    if not path.is_file() or ".git" in path.parts or "__pycache__" in path.parts or path.suffix == ".pyc":
        continue
    if path.name in {"check-public-safety.py", "check-public-history.py"}:
        continue
    try:
        data = path.read_bytes()
    except OSError as exc:
        findings.append(f"unreadable file: {path.relative_to(root)} ({exc})")
        continue
    if b"\0" in data:
        rel = path.relative_to(root).as_posix()
        expected = pinned_binaries.get(rel)
        if expected and hashlib.sha256(data).hexdigest() == expected:
            continue
        findings.append(f"binary file must not be committed: {rel}")
        continue
    for label, pattern in patterns.items():
        for match in pattern.finditer(data):
            if label == "IPv4 literal" and safe_ip(match.group(0)):
                continue
            if label == "email address" and match.group(0) in (b"getty@tty1.service", b"serial-getty@ttyS0.service"):
                continue
            if label == "canonical UUID" and match.group(0).lower() in allowed_partition_guids:
                continue
            line = data.count(b"\n", 0, match.start()) + 1
            findings.append(f"{label}: {path.relative_to(root)}:{line}")
if findings:
    print("PUBLIC-SAFETY=FAIL")
    print("\n".join(findings))
    raise SystemExit(1)
print("PUBLIC-SAFETY=PASS; no keys, credentials, UUIDs, user IPv4 literals, email addresses, personal paths, or binary payloads found")
