# Run 42941005270 evidence (text only)

Copied verbatim from the uploaded artifact `paw-live-build-test-results`
(ID `13822300189`, 1,030,665,613 bytes, expires 2026-11-14 02:03:21 UTC) of run
<https://github.com/riser-lang/paw-migration-kit/actions/runs/42941005270>
on code HEAD `24c13f7` (`24c13f731bfd6c8a70f2331eb0abe30686c29975`).

The artifact ZIP SHA256 recorded during download was
`f4c5c3eae5c08a1dcd3d1f1720acbd25ce5c5178d9d58595ccb40c9ee98f95ea`; it is
**not** the ISO hash. The extracted `paw-live-amd64.iso` is 953,155,584 bytes
with SHA256 `822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09`,
matching both `paw-live-amd64.iso.sha256` and `iso-identity.txt` in this folder.

| File | What it proves |
|---|---|
| `iso-system-area.txt` | ISO layout `MBR isohybrid cyl-align-on GPT APM` |
| `iso-identity.txt` | Build-side ISO byte count and SHA256 |
| `debian-base-verification.txt` | Debian Live base signature, official hash and SHA256 |
| `software-manifest.txt` | Tailscale/Xray provenance and binary digests |
| `software-packages.txt` | Installed package list (top-level) |
| `build-provenance.txt` | Build inputs and toolchain provenance |
| `qemu-smoke-report.txt` | SeaBIOS + TCG boot reaches the readiness gate (fail-closed) |
| `qemu-cjk-test-report.txt` | QEMU CJK: 5 cases / 96 assertions (26+17+17+11+25) |
| `pawdata-virtual-test-report.txt` | PAWDATA layout/persistence 12/12 |
| `virtual-fault-injection-report.txt` | Clone/fault suite 39/39 |
| `repair-virtual-test-report.txt` | Offline repair/rollback 19/19 |
| `network-virtual-test-report.txt` | Network staging 17/17 |
| `finalize-virtual-test-report.txt` | Finalize/reboot gate 36/36 |
| `tty-virtual-test-report.txt` | tty1 binding: static 55 + PTY 15, aggregate 56/56 |
| `cjk-font-test-report.txt` | Generated CJK console font 1/1 |

Gate and static-check summaries are in the run log, not this artifact:
font-gate **26 assertions, 0 failed**; shellcheck/bash/Python/PowerShell/JSON/
YAML/public-safety/history all PASS.

Deliberately absent, same reasons as the previous run folder:
`software-packages.lock` (version column reads as IPv4 literals to the safety
scan), `live-build.log` (mirror addresses), `paw-live-amd64.iso` (large binary),
and the QEMU CJK serial logs (synthetic UUIDs / keyboard input).

Scope reminder: everything here comes from QEMU, loop devices and mocks. No
production VPS, physical disk or TF card was touched.
