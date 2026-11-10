# Run 42816492016 evidence (text only)

Copied verbatim from artifact `paw-live-build-test-results` (ID `13765554334`,
1,030,666,472 bytes, expires 2026-11-13 12:51:02 UTC) of run
<https://github.com/riser-lang/paw-migration-kit/actions/runs/42816492016>
on head `b4bfd84`.

This run added the chroot shape of the real `grub-install` test. The production
payload is identical to the delivery run `42804949796`, so the delivered ISO stays at
SHA256 `d9fe2879…fb95a4476`. This run's rebuilt ISO was re-hashed anyway:
`35f0baff2c0496ad9e3d945c9a31c53841c7fa5cce2209eff66a19127a04b185`, matching its
sidecar, and is the sixth distinct hash of the same 953,155,584 bytes.

| File | What it proves |
|---|---|
| `repair-virtual-test-report.txt` | Offline repair 22/22: host-side real `grub-install`, chroot real `grub-install`, modules copied, MBR `0x55AA`, embedded core image |
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

Scope reminder: everything here comes from QEMU, loop devices, bind mounts and mocks.
No production VPS, physical disk or TF card was touched, and no real target was
repaired or booted.
