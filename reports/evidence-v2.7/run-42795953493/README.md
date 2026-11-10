# Run 42795953493 evidence (text only)

These files are copied verbatim from the uploaded GitHub Actions artifact
`paw-live-build-test-results` (artifact ID `13754343439`, 1,030,664,775 bytes,
expires 2026-11-13 10:22:46 UTC) of run
<https://github.com/riser-lang/paw-migration-kit/actions/runs/42795953493>
on code HEAD `91a79ea`.

Nothing here is retyped by hand: the numbers quoted in
`docs/PAW-V2.7.1-TEST-REPORT.md` and `PAW-MIGRATION-STATE.md` are the numbers in
these reports.

| File | What it proves |
|---|---|
| `iso-system-area.txt` | ISO layout is `MBR isohybrid cyl-align-on GPT APM` (Legacy BIOS bootable) |
| `debian-base-verification.txt` | Debian Live base image signature, official hash and SHA256 |
| `software-manifest.txt` | Tailscale/Xray provenance and binary digests |
| `software-packages.txt` | Installed package list (top-level) |
| `build-provenance.txt` | Build inputs and toolchain provenance |
| `qemu-smoke-report.txt` | SeaBIOS + TCG boot reaches the readiness gate (fail-closed, no clone) |
| `qemu-cjk-test-report.txt` | QEMU CJK suite: 5 cases / 96 assertions, per-case evidence |
| `pawdata-virtual-test-report.txt` | PAWDATA layout/persistence, 12/12 |
| `virtual-fault-injection-report.txt` | Clone byte counting, interruptions, raw fallback, 35/35 |
| `repair-virtual-test-report.txt` | Offline repair/rollback on loop ext4, 15/15 |
| `network-virtual-test-report.txt` | Network staging, Xray/Tailscale mocks, 17/17 |
| `finalize-virtual-test-report.txt` | Finalize and reboot gate, 36/36 |
| `tty-virtual-test-report.txt` | tty1 binding: static 55 + PTY 15, 0 blocked |

Deliberately absent from the repository:

- `software-packages.lock` — the version column contains dotted numbers with three
  separators, which the public-safety scan classifies as IPv4 literals, so
  committing it fails the check. It is kept in the local delivery folder instead.
- `live-build.log` — contains Debian mirror IPv4 addresses.
- `qemu-cjk/` screenshots, `result.json`, `serial.log` — binary/verbose output and
  synthetic UUIDs; retained only in the artifact and the local delivery folder.

Synthetic test identities used by the `final` case (fake disk `vdz`, fake serial
`QEMU-123456`, constructed UUID, fake SSH host fingerprint) exist only inside the
test fixture and are not real credentials or addresses.

## Scope reminder

Everything in this folder comes from QEMU, loop devices and mocks. No production
VPS, physical disk or TF card was touched. Real hardware items remain unverified.
