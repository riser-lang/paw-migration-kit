# Run 42804949796 evidence (text only)

Copied verbatim from the uploaded artifact `paw-live-build-test-results`
(ID `13760370816`, 1,030,665,391 bytes, expires 2026-11-13 11:27:18 UTC) of run
<https://github.com/riser-lang/paw-migration-kit/actions/runs/42804949796>
on code HEAD `bf1a705`.

| File | What it proves |
|---|---|
| `iso-system-area.txt` | ISO layout `MBR isohybrid cyl-align-on GPT APM` |
| `debian-base-verification.txt` | Debian Live base signature, official hash and SHA256 |
| `software-manifest.txt` | Tailscale/Xray provenance and binary digests |
| `software-packages.txt` | Installed package list (top-level) |
| `build-provenance.txt` | Build inputs and toolchain provenance |
| `qemu-smoke-report.txt` | SeaBIOS + TCG boot reaches the readiness gate (fail-closed) |
| `qemu-cjk-test-report.txt` | QEMU CJK: 5 cases / 96 assertions |
| `pawdata-virtual-test-report.txt` | PAWDATA layout/persistence 12/12 |
| `virtual-fault-injection-report.txt` | Clone/fault suite 39/39, including the four GPT-expansion guard assertions |
| `repair-virtual-test-report.txt` | Offline repair/rollback 15/15 |
| `network-virtual-test-report.txt` | Network staging 17/17 |
| `finalize-virtual-test-report.txt` | Finalize/reboot gate 36/36 |
| `tty-virtual-test-report.txt` | tty1 binding: static 55 + PTY 15 |

Deliberately absent (same reasons as the previous run folder): `software-packages.lock`
(version column reads as IPv4 literals to the safety scan), `live-build.log` (mirror
addresses), screenshots/serial logs (binary plus synthetic UUIDs).

Scope reminder: everything here comes from QEMU, loop devices and mocks. No
production VPS, physical disk or TF card was touched.
