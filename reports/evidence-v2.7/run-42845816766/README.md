# Run 42845816766 evidence (text only)

Copied verbatim from the new text-only artifact `paw-test-reports` (ID `13779373807`,
18,689 bytes, expires 2026-11-13 16:01:12 UTC) of run
<https://github.com/riser-lang/paw-migration-kit/actions/runs/42845816766>
on head `e4ec96c`.

This run added no product change; it exists because the previous evidence copies needed
a 1 GB artifact. The run uploads a text bundle next to the ISO bundle now, and this
folder was copied from it in seconds instead of tens of minutes.

| File | What it proves |
|---|---|
| `repair-virtual-test-report.txt` | Offline repair 28/28: host-side real `grub-install`, chroot real `grub-install`, and the QEMU boot chain of the repaired disk |
| `virtual-fault-injection-report.txt` | Clone/fault suite 39/39 with the GPT-expansion guard |
| `qemu-cjk-test-report.txt` + `qemu-cjk-*.log` | QEMU CJK 5 cases / 96 assertions, one log per case |
| `pawdata-virtual-test-report.txt` | PAWDATA 12/12 |
| `network-virtual-test-report.txt` | Network staging 17/17 |
| `finalize-virtual-test-report.txt` | Finalize/reboot gate 36/36 |
| `tty-virtual-test-report.txt`, `pty-tty-test.log` | tty1 binding: static 55 + PTY 15 |
| `cjk-font-test-report.txt` | CJK font 1/1 |
| `qemu-smoke-report.txt` | SeaBIOS + TCG boot reaches the readiness gate |
| `iso-identity.txt`, `iso-system-area.txt` | ISO bytes/hash as built, and the hybrid layout |
| `debian-base-verification.txt`, `software-manifest.txt`, `software-packages.txt`, `build-provenance.txt` | Base image, tool provenance and package inventory |
| `test-summary.txt` | The uploaded aggregate summary |

Deliberately absent (unchanged reason): `software-packages.lock` (version column reads as
IPv4 literals to the safety scan), `live-build.log` (mirror addresses).

Scope reminder: QEMU, loop devices, bind mounts and mocks only. No production VPS,
physical disk or TF card was touched.
