# PAW Migration State

Updated: 2026-11-11 UTC (Stage 3 close / Stage 4 ISO verified / target boot re-verified)
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
- **Stage 3 (full 26-step migration chain): COMPLETE.** All steps 1–26 are
  covered by real PASS logs or the independent boot verification. The chain's
  own `target_boot` detector reported `False` only because the outer scheduler
  killed QEMU (`qemu_rc=-9`) after `chain_pass=True` while it waited for the
  reboot; a separate QEMU/SeaBIOS run (`target.img` as the only disk, `vda`
  `bootindex=1`, no `-kernel`/`-initrd`) re-verified
  `Ubuntu 24.04.5 LTS ubuntu ttyS0` / `ubuntu login:` with `qemu_rc=0`.
  Evidence: `reports/PAW-STAGE3-RESUME-20261110.md` and
  `reports/evidence/stage3-target-standalone-boot-20261111.evidence.txt`.
- **Stage 4 (final ISO / Chinese delivery docs): COMPLETE for cloud delivery.**
  Final CI Run `42941005270` on code HEAD `24c13f7` succeeded in 20m 12s.
  Artifact `13822300189` (`paw-live-build-test-results`, 1,030,665,613 bytes)
  was downloaded and the ISO was hashed **from the ISO file**, never from the
  ZIP: `paw-live-amd64.iso`, 953,155,584 bytes, SHA256
  `822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09`.
  The value matches the same-run sidecar and `iso-identity.txt`. Delivery docs
  and `PAW-V2.7.1-ISO-SHA256.txt` carry this value.
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
| Target second boot (09:42Z) | `evidence/stage3-target-second-boot.log` (cleaned capture) SHA256 `8fd245911592108c82df0cc9fb97c6266418a3259ee9c904eda2d2b1e70fa565`; raw `target-boot2.log` SHA256 `7a1b6e9649c20210dcd8472fe0a0e4bb7000d0cae72e09bc9b035a3367b4f16c` (extra trailing QEMU shutdown line) |
| Target boot re-verification (02:22Z) | `reports/evidence/stage3-target-standalone-boot-20261111.evidence.txt` (curated excerpt) SHA256 `30bdea6c5715244290f742912e73d932648214c5001803b633306af1f7fbc332`; host raw serial log SHA256 `083ea333df9d89177767fc8ada81090ca1da382fa1bfde4758af74173ec63a08`; host login PNG SHA256 `23626d20cabe9c94668c8ca21d7480d89737023e6bc78e140e914ebc3f94e94d`; verdict JSON and `.sha256` in the same directory |

The host evidence directory has a `SHA256SUMS`; `sha256sum -c` passed for all
eight files on 2026-11-11.

## Evidence mapping for cloud ISO

The old delivery ISO belongs to historical Run `42804949796` / HEAD `bf1a705`
(953,155,584 bytes, SHA256 `d9fe2879…fb95a4476`). It is **not** current-branch
evidence and must not be reused as the Stage 4 delivery ISO.

The Stage 4 delivery ISO comes from the green Run `42941005270` on code HEAD
`24c13f7`: `paw-live-amd64.iso`, 953,155,584 bytes, SHA256
`822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09`. A docs-only
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
- Byte-for-byte ISO reproducibility (still unproven; historical builds had
  equal size and different hashes).

No production VPS, physical disk or TF card was touched. No PR was merged and no
Artifact was deleted.

## Next actions

1. User copies the verified ISO to the delivery medium (or downloads it from
   Run `42941005270` before the artifact expiry), recomputes SHA256 and compares
   with `PAW-V2.7.1-ISO-SHA256.txt`.
2. User writes the TF card in DD/whole-disk mode and records the media identity.
3. User runs the physical checklist on the ASUS B85M-G Plus, then the real
   Tencent Cloud Rescue / SSD / reboot / PAW acceptance with separate
   authorization.
4. Keep QEMU, loop and mock results separate from physical PASS; do not merge
   PR #2, change `main`, delete Artifacts or touch the production VPS without a
   new explicit instruction.
