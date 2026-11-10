# Run 42810087226 evidence (text only)

Copied verbatim from artifact `paw-live-build-test-results` (ID `13763731974`,
1,030,666,564 bytes, expires 2026-11-13 12:10:39 UTC) of run
<https://github.com/riser-lang/paw-migration-kit/actions/runs/42810087226>
on head `d640712`.

This run changed only the CI suite (real `grub-install` on a loop GPT disk). The
production payload is identical to the delivery run `42804949796`, so the delivered
ISO stays at SHA256 `d9fe2879…fb95a4476`; this run's rebuilt ISO was still re-hashed
for the record and is a fifth distinct hash of the same size.

| File | What it proves |
|---|---|
| `repair-virtual-test-report.txt` | Offline repair 19/19, including the four real-`grub-install` assertions |
| `virtual-fault-injection-report.txt` | Clone/fault suite 39/39 with the GPT-expansion guard |
| `qemu-cjk-test-report.txt` | QEMU CJK 5 cases / 96 assertions |
| `pawdata-virtual-test-report.txt` | PAWDATA 12/12 |
| `network-virtual-test-report.txt` | Network staging 17/17 |
| `finalize-virtual-test-report.txt` | Finalize/reboot gate 36/36 |
| `tty-virtual-test-report.txt` | tty1 binding: static 55 + PTY 15 |
| `cjk-font-test-report.txt` | CJK font 1/1 |
| `qemu-smoke-report.txt` | SeaBIOS + TCG boot reaches the readiness gate |
| `iso-system-area.txt` | ISO layout `MBR isohybrid cyl-align-on GPT APM` |
| `debian-base-verification.txt`, `software-manifest.txt`, `software-packages.txt`, `build-provenance.txt` | Base image, tool provenance and package inventory |

Deliberately absent (same as the other run folders): `software-packages.lock`
(version column reads as IPv4 literals to the safety scan), `live-build.log` (mirror
addresses), screenshots/serial logs (binary plus synthetic UUIDs).

Scope reminder: everything here comes from QEMU, loop devices and mocks. No
production VPS, physical disk or TF card was touched.
