# PAW Migration Blockers

Updated: 2026-11-11 UTC (Stage 3 close / Stage 4 ISO verified / target boot re-verified)
Current branch: `vm/ds-clean-handover-20261110`
Current code HEAD: `24c13f7`
Base: `d640712`
PR #2: Draft, not merged

## Current blocker table

| ID | Status | Blocker | Exit condition |
|---|---|---|---|
| FONT-GATE | **CLOSED** | Destructive writes were not tied to a same-boot fbcon 16x16 PASS report | `paw-font-gate.py` validates schema `paw.console-font.v2`, `status=PASS`, `mode=fbcon`, boot ID, primary font, actual/manifest SHA256, `setfont_exit_code=0` and PSF2 geometry; destructive entries call it. CI `42825407549`: 26/26 gate, CJK 25/25. |
| STAGE2 | **CLOSED (virtual block devices)** | Earlier clone round used `PAW_SIMULATION=1` | Stage 3 ran real `paw-stream-clone.sh`/`paw-stream-verify.sh` on QEMU virtio `/dev/vdb`→`/dev/vdc`, `mode=remote-zstd-level1-thread1`, real loopback SSH, full `paw-offline-repair.sh`, GPT/ext4 expansion and target boots. Physical SSD still OPEN under P1-4. |
| STAGE3 | **CLOSED** | Full 26-step chain not complete | All steps 1–26 are covered by real PASS logs or the independent boot verification; `auto_reboot` persisted+synced status before reboot. The chain's `target_boot` detector was cut by the outer scheduler (`qemu_rc=-9`); a separate QEMU/SeaBIOS run (`target.img` only, `vda` `bootindex=1`, no direct kernel) re-verified `ubuntu login:`. Evidence: `reports/PAW-STAGE3-RESUME-20261110.md`, `reports/evidence/stage3-target-standalone-boot-20261111.evidence.txt`. |
| STAGE4 | **CLOSED (cloud ISO verified)** | Final ISO artifact not yet downloaded/hashed; Chinese delivery docs not yet finalized | Green Run `42941005270` on `24c13f7` completed 2026-11-11T02:03:39Z; artifact `13822300189` downloaded (1,030,665,613 bytes); ISO `paw-live-amd64.iso` 953,155,584 bytes, SHA256 `822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09`, matching the same-run sidecar. Docs and `PAW-V2.7.1-ISO-SHA256.txt` updated. Physical media still P1-4/DELIVERY. |
| P0-1 | VIRTUALLY_VERIFIED / physical OPEN | Memtest86+ has a boot entry but no machine-verifiable capture | `OPERATOR_CONFIRMED` UI binds boot ID and target serial; real physical run still open. |
| P0-2 | VIRTUALLY_VERIFIED / physical OPEN | PAWDATA required manual command | Auto-guided MBR/GPT append and persistence, 12/12 virtual tests. Real TF card still open. |
| P0-3 | VIRTUALLY_VERIFIED / physical OPEN | Source discovery previously required a Virtio serial number | Composite identity with pinned SSH host key, root UUID, GPT layout and capacity; real Rescue still open. |
| P0-4 | VIRTUALLY_VERIFIED / physical OPEN | Restored byte count was assumed | Actual decompressed counter, mixed data, interruption/short-read and SHA; 39/39 fault tests. Real SSH still open. |
| P0-5 | VIRTUALLY_VERIFIED / physical OPEN | Authorization panel was journal-only | tty1 panel with timeout/markers; QEMU glyph-matching case, 25 assertions. Real screen still open. |
| P1-4 | OPEN | Real hardware checks not performed | Run on target ASUS/SSD/TF card per `docs/PAW-V2.7-HARDWARE-CHECKLIST-ZH.md`. |
| BUILD | **PASS** | Stage 4 ISO build not yet green | Run `42941005270` on `24c13f7` succeeded; artifact and ISO verified. Historical Run `42804949796`/`bf1a705` remains historical only. |
| REPRO | OPEN | Cloud builds produce equal ISO size but different SHA256 | Byte-for-byte reproducibility not claimed; always use the same run's sidecar. |
| CONSOLE | CLOSED (QEMU/static) | Operator panels went to journal only | tty1 binding plus 55 static, 15 PTY and QEMU glyph assertions; real ASUS screen still P1-4. |
| GROWPART | CLOSED (virtual) | Root partition might not be last | `paw-gpt-expand.sh` refuses before touching GPT; virtual test proves table unchanged afterwards. |
| GRUB-REPAIR | CLOSED (loop + real target boot) | Historical fixture used a stub | Real host `grub-install` on loop GPT, and real target `grub-install --target=i386-pc`, `update-grub`, `update-initramfs`; Stage 3 booted the result. |
| PTY-LOCAL | OPEN (environment) | Sandbox has no usable `/dev/ptmx` | CI runs with `PAW_REQUIRE_PTY=1`; local status stays BLOCKED. |
| CI-CURRENT | **PASS** | Run `42941005270` on `24c13f7` | Completed success in 20m 12s; gate 26/26, CJK 5 cases/96 assertions, PAWDATA 12/12, virtual 39/39, repair 19/19, network 17/17, finalize 36/36, TTY 56/56. |
| DELIVERY | PENDING_USER | Real-world write/boot/migration | User writes TF card, re-hashes ISO, performs physical checklist. |

## Stage 3 close details

- `stream-verify.json`: `efcae25cf0bcbe51ec9b842c097d641139a48825fd43191067ba6d3f9efcf2a9`,
  3,758,096,384 bytes, independent verification true.
- `offline-repair.json`: `status=PASS`, `simulation=false`, real `grub-install`.
- `gpt-expand.json`: partition 256,623,230,464 bytes, ext4 62,652,155 blocks;
  `grew=false` because the first attempt already grew the partition.
- `reboot-status.json`: `status=PASS`, `reboot_invoked=true`,
  `status_persisted_before_reboot=true`.
- Target boot log: `evidence/stage3-target-second-boot.log`, SHA256
  `8fd245911592108c82df0cc9fb97c6266418a3259ee9c904eda2d2b1e70fa565`.

## Hard boundaries

- Never stop, reboot, rescue, mount or otherwise touch the production VPS.
- Never write a physical disk or TF card in this cloud session.
- Never claim QEMU, mock SSH, loop devices or operator attestation as physical or
  cryptographic proof.
- Never upload real credentials, server addresses, production UUIDs or keys.
- Never compute a delivery ISO hash from an artifact ZIP.
- Keep Stage 2/3/4 on virtual disks only.
- Do not merge PR #2, change `main`, or delete existing Artifacts.
