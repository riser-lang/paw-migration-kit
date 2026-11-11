# PAW Migration State

Updated: 2026-11-11 UTC (Stage 3 close / Stage 4 delivery round)
Current branch: `vm/ds-clean-handover-20261110`
Current code HEAD: `24c13f7` — "Stage 3 lab harness: direct kernel/initrd, fw_cfg,
target login detection"
Base: `d64071251bb3075d9cb26a967dfcba6cf139250a` (remote development branch)
PR: #2 (Draft, not merged); #1 untouched
Main HEAD: `0d6aefd` (unchanged)

## Current status at a glance

- **Stage 1 (clean takeover / P0-1 font gate): COMPLETE.** P0-1 fail-closed font
  gate is implemented and covered by 26 local assertions plus green branch CI.
- **Stage 2 (Ubuntu clone and boot): CLOSED in the virtual block-device lab.**
  The earlier 2026-11-10 round proved SeaBIOS boot, GPT/ext4 expansion, real
  GRUB/initramfs and a seedless second boot, but its clone used
  `PAW_SIMULATION=1`. The Stage 3 continuation then ran the **real**
  `paw-stream-clone.sh` / `paw-stream-verify.sh` path against QEMU virtio block
  devices (`/dev/vdb` source, `/dev/vdc` target) over a real loopback SSH server,
  with `mode=remote-zstd-level1-thread1` and no simulation flag, plus the full
  `paw-offline-repair.sh`, GPT/ext4 expansion and two target boots. Real physical
  SSD/TF card remain OPEN.
- **Stage 3 (full 26-step migration chain): COMPLETE.** All steps 1–26 have real
  PASS logs, including the last three that were still open at the previous kill:
  `auto_reboot` (status persisted and synced before `systemctl reboot`) and
  `target_second_boot` (SeaBIOS from the cloned target to
  `Ubuntu 24.04.5 LTS ubuntu ttyS0` / `ubuntu login:`).
  Evidence: `reports/PAW-STAGE3-RESUME-20261110.md`.
- **Stage 4 (final ISO / Chinese delivery docs): IN PROGRESS.** Final CI Run
  `42941005270` was dispatched from code HEAD `24c13f7`. The tested ISO artifact
  must be downloaded and hashed **from the ISO file**, never from the ZIP. The
  resulting SHA256 goes into `PAW-V2.7.1-ISO-SHA256.txt`, `DELIVERY.md`, the
  Chinese guide/rollback/test documents and the final Stage 4 report.
- **Physical acceptance: OPEN.** Real ASUS B85M-G Plus boot, real TF card write
  and read-back, real SSD SMART/scan/temperature, real Tencent Cloud Rescue,
  real `systemctl reboot` on hardware, physical Memtest86+ observation and the
  real migration itself are not performed in this cloud session.

## Stage 3 evidence (durable)

Primary report: `reports/PAW-STAGE3-RESUME-20261110.md`.

| Item | Evidence |
|---|---|
| 26-step chain | `resume-run17.log`, `main-run2.log`, `console-main.log` under `~/paw-stage34-20261110/`; host evidence JSON under `~/paw-stage34-20261110/evidence/` |
| Clone mode / bytes | `paw-stream-clone.sh` log: `mode=remote-zstd-level1-thread1`, `source_bytes=3758096384`, `ssh_stream_bytes=591462695`, `restored_bytes=3758096384` |
| Independent SHA256 | `stream-verify.json`: `efcae25cf0bcbe51ec9b842c097d641139a48825fd43191067ba6d3f9efcf2a9`, 3,758,096,384 bytes, `independent_sha256_verified=true` |
| Offline repair | `offline-repair.json`: `status=PASS`, `simulation=false`, `grub_install=i386-pc`, backup under guest `/opt/paw-migration/tests/stage3/state/backups/` |
| GPT/ext4 | `gpt-expand.json`: `/dev/vdc1`, 256,623,230,464 bytes, ext4 62,652,155 blocks; `grew=false` is honest because the partition was already grown by the first attempt |
| First boot | `firstboot-check.json`: `status=PASS`, clone verify PASS, `CLONE-INCOMPLETE` absent |
| Auto reboot | `reboot-status.json`: `status=PASS`, `reboot_invoked=true`, `status_persisted_before_reboot=true`; `scripts/paw-finalize-reboot.sh` writes this atomically and `sync`s before issuing the command |
| Target second boot | `evidence/stage3-target-second-boot.log` (cleaned capture) SHA256 `8fd245911592108c82df0cc9fb97c6266418a3259ee9c904eda2d2b1e70fa565`; raw `target-boot2.log` SHA256 `7a1b6e9649c20210dcd8472fe0a0e4bb7000d0cae72e09bc9b035a3367b4f16c` (extra trailing QEMU shutdown line) |

The host evidence directory has a `SHA256SUMS`; `sha256sum -c` passed for all
eight files on 2026-11-11.

## Evidence mapping for cloud ISO

The old delivery ISO belongs to historical Run `42804949796` / HEAD `bf1a705`
(953,155,584 bytes, SHA256 `d9fe2879…fb95a4476`). It is **not** current-branch
evidence and must not be reused as the Stage 4 delivery ISO.

The Stage 4 ISO must come from the green run on code HEAD `24c13f7`. A docs-only
commit after the code HEAD can describe that ISO but cannot change its hash. ISO
builds are not byte-reproducible across runs (same size, different SHA256), so the
sidecar from the **same Run** is authoritative.

## What remains OPEN

- Real TF card write and read-back; final media identity check.
- Real ASUS motherboard/SeaBIOS boot, keyboard and display.
- Real SSD SMART/read scan/temperature.
- Real Tencent Cloud Rescue Mode SSH and production source identity.
- Real full-disk clone, real offline repair and production PAW migration.
- Physical Memtest86+ run and operator observation.
- Real `systemctl reboot` on the target hardware.
- Byte-for-byte ISO reproducibility (still unproven; four historical builds had
  equal size and different hashes).

No production VPS, physical disk or TF card was touched. No PR was merged and no
Artifact was deleted.

## Next actions

1. Watch Run `42941005270` on `24c13f7` to green.
2. Download artifact `paw-live-build-test-results`, extract
   `paw-live-amd64.iso`, compute SHA256 from the ISO file, compare with the same
   run's `paw-live-amd64.iso.sha256` and `iso-identity.txt`.
3. Record artifact ID/size/expiry and ISO bytes/SHA256 in
   `PAW-V2.7.1-ISO-SHA256.txt`, `DELIVERY.md`, `README.md`, the Chinese guide,
   test report, blockers/acceptance and final Stage 4 report.
4. Keep physical items OPEN with the user checklist; do not convert QEMU/loop
   results into hardware PASS.
