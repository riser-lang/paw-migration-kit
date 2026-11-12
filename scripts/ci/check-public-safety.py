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

# These are public GPT partition-type GUIDs (BIOS boot, Linux filesystem,
# EFI system, Windows basic data), not credentials or machine identifiers.
allowed_partition_guids = {
    b"21686148-6449-6e6f-744e-656564454649",
    b"0fc63daf-8483-4772-8e79-3d69d8477de4",
    b"c12a7328-f81f-11d2-ba4b-00a0c93ec93b",
    b"ebd0a0a2-b9e5-4433-87c0-68b6b72699c7",
}
# Two release assets are intentionally committed binaries; accept them only
# while their pinned SHA256 still matches, so tampering is still reported.
pinned_binaries = {
    "boot/bin/xray": "8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed",
    "configs/memtest86+/memtest86+x64.bin": "487bfe56b84f2016b12f393641f1acb765ef0b648c71ea9a2e3d42b62411f71f",
}
# Raw CI logs are preserved verbatim.  A few tokens in them are public
# infrastructure or package metadata, not credentials: the snapshot.debian.org
# CDN address, Debian package version strings that look like IPv4 literals,
# run-scoped GitHub temp-directory UUIDs and the sshd@.service.wants path.
# Secrets, private keys, tokens and every other address/UUID still fail.
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
for path in root.rglob("*"):
    if not path.is_file() or ".git" in path.parts or "__pycache__" in path.parts or path.suffix == ".pyc":
        continue
    if path.name in {"check-public-safety.py", "check-public-history.py"}:
        continue
    rel = path.relative_to(root)
    # Ignored test-runtime state is not committed and can contain loop-device
    # names and transient state; it is never part of the public tree.
    if rel.parts[:2] == ("tests", "virtual"):
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
            if (rel.as_posix().startswith("reports/evidence/") and rel.suffix == ".log"
                    and match.group(0) in benign_evidence_tokens):
                continue
            line = data.count(b"\n", 0, match.start()) + 1
            findings.append(f"{label}: {path.relative_to(root)}:{line}")
if findings:
    print("PUBLIC-SAFETY=FAIL")
    print("\n".join(findings))
    raise SystemExit(1)
print("PUBLIC-SAFETY=PASS; no keys, credentials, UUIDs, user IPv4 literals, email addresses, personal paths, or binary payloads found")
