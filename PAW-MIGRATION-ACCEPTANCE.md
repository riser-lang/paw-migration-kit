# PAW Migration Acceptance

Updated: 2026-11-11 UTC (Stage 3 close / Stage 4 ISO verified / target boot re-verified)
Current branch: `vm/ds-clean-handover-20261110`
Current code HEAD: `24c13f7`
Base: `d640712`
PR #2: Draft, not merged
Historical green run: `42804949796` on `bf1a705` (not current evidence)

## A0. P0-1 font fail-closed gate

- [x] `scripts/paw-font-gate.py` rejects any report that is not same-boot
      `paw.console-font.v2` `PASS` with `mode=fbcon`, `fbcon_bound=true`, primary
      16x16 PSF2, actual/manifest SHA256 match and `setfont_exit_code=0`.
- [x] 8x16 vgacon fallback is `WARN`, not `PASS`.
- [x] Missing/corrupt font, manifest mismatch, `setfont` failure, missing/stale
      report, vgacon-as-fbcon and unbound fbcon all block destructive writes.
- [x] `paw-final-confirm.sh`, `paw-prepare-data-partition.sh`,
      `paw-stream-clone.sh`, `paw-offline-repair.sh` and `paw-gpt-expand.sh`
      gate before destructive writes.
- [x] Fault injection: **26 assertions, 0 failed** locally.
- [x] CI Run `42825407549` at `4af304e`: success (gate 26/26, CJK 25/25,
      PAWDATA 12/12, virtual 39/39, repair 19/19, network 17/17, finalize 36/36,
      TTY 56/56).

## A1. Stage 2 virtual boot and Stage 3 full chain

- [x] Real Ubuntu 24.04 source disk image (GPT, BIOS Boot, ext4, GRUB).
- [x] 240 GiB sparse QEMU virtio target, serial `PAW-DST-123456`.
- [x] **Real production clone entry**, not simulation:
      `paw-stream-clone.sh` on `/dev/vdb`→`/dev/vdc` with
      `mode=remote-zstd-level1-thread1`, real loopback SSH server;
      `source_bytes=3,758,096,384`, `restored_bytes=3,758,096,384`.
- [x] `paw-stream-verify.sh` independent SHA256
      `efcae25cf0bcbe51ec9b842c097d641139a48825fd43191067ba6d3f9efcf2a9`,
      `independent_sha256_verified=true`.
- [x] Full production `paw-offline-repair.sh`: `simulation=false`, real
      `grub-install --target=i386-pc`, initramfs regenerated, backup retained.
- [x] Production `paw-gpt-expand.sh`: `/dev/vdc1` 256,623,230,464 bytes, ext4
      62,652,155 blocks; root-is-last guard active.
- [x] Production `paw-firstboot-check.sh`: `status=PASS`.
- [x] Production `paw-finalize-reboot.sh`: `reboot-status.json` atomically
      persisted and synced **before** `systemctl reboot`,
      `status_persisted_before_reboot=true`, `reboot_invoked=true`.
- [x] SeaBIOS (no direct kernel) booted the cloned target to
      `Ubuntu 24.04.5 LTS ubuntu ttyS0` / `ubuntu login:`; target kernel
      `6.8.0-147-generic`, not the Live kernel. Re-verified 2026-11-11T02:22Z
      with `target.img` as the only disk (`vda` `bootindex=1`, no
      `-kernel`/`-initrd`), `qemu_rc=0`; evidence
      `reports/evidence/stage3-target-standalone-boot-20261111.evidence.txt` SHA256
      `30bdea6c5715244290f742912e73d932648214c5001803b633306af1f7fbc332` (curated
      excerpt; host raw log SHA256
      `083ea333df9d89177767fc8ada81090ca1da382fa1bfde4758af74173ec63a08`).
- [x] All 26 steps are accounted for by real PASS logs or the independent boot
      verification. Evidence: `reports/PAW-STAGE3-RESUME-20261110.md`.

Stage 2 is therefore **CLOSED for the virtual block-device lab**; physical SSD
acceptance remains open (D).

## A2. Stage 4 final ISO and Chinese delivery

- [x] Final CI Run `42941005270` on `24c13f7` is green: success, 20m 12s,
      completed 2026-11-11T02:03:39Z.
- [x] Downloaded `paw-live-build-test-results` artifact `13822300189`
      (1,030,665,613 bytes, expires 2026-11-14 02:03:21 UTC), extracted
      `paw-live-amd64.iso` (953,155,584 bytes) and computed SHA256 from the ISO
      file: `822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09`.
- [x] Compared with the same run's `paw-live-amd64.iso.sha256` /
      `iso-identity.txt`: both match.
- [x] Wrote `PAW-V2.7.1-ISO-SHA256.txt` and updated `DELIVERY.md`, `README.md`,
      `docs/PAW-V2.7.1-USER-GUIDE-ZH.md`, `docs/PAW-V2.7.1-TEST-REPORT.md`,
      `docs/PAW-V2.7.1-BLOCKERS.md` and the Stage 4 report with the verified hash.
- [x] Kept physical media acceptance OPEN.

## B. Virtual boot acceptance

- [x] SeaBIOS + QEMU TCG reaches the PAW readiness gate.
- [x] Readiness is `BLOCKED` when prerequisites are absent; `clone_started=false`.
- [x] Memtest86+ independent menu and binary are present.
- [x] This does not prove real ASUS motherboard boot.

## C. Virtual migration acceptance

- [x] PAWDATA auto-init MBR and GPT, only the new partition formatted.
- [x] PAWDATA survives unmount/remount; ISO/BIOS Boot geometry preserved.
- [x] Memtest manual confirmation binds boot ID and target serial.
- [x] Missing/incomplete/error memory result blocks clone.
- [x] Rescue source identity passes with serial and with composite identity.
- [x] Wrong UUID/capacity/GPT/BIOS Boot rejected before write.
- [x] Target serial/capacity mismatch rejected before write.
- [x] Remote zstd stream records payload and actual restored bytes.
- [x] Raw fallback explicit; interruption/short read leaves `CLONE-INCOMPLETE`.
- [x] SHA256 mismatch fails and keeps marker; mixed data round-trip passes.
- [x] SMART FAIL and I/O timeout fail closed.
- [x] GPT/ext4 expansion and the root-is-last guard pass on loop images.
- [x] Netplan compatibility for `eth0`, `enp3s0`, `r8169`.
- [x] Offline repair and rollback pass on a loop ext4 root.
- [x] First-boot gate rejects incomplete/wrong-target receipts.
- [x] Real production chain on QEMU virtio block devices reaches target login.

Current Stage 4 Run `42941005270` (code `24c13f7`), all 0 failed: gate 26/26;
PAWDATA 12/12; fault injection 39/39; repair/rollback 19/19; network 17/17;
finalize 36/36; TTY 56/56 (static 55 + PTY, 0 blocked); CJK font 1/1; QEMU CJK
5 cases / 96 assertions. Historical Run `42804949796` (code `bf1a705`) had
repair/rollback 15/15 and remains historical evidence only.

## C2. Operator console acceptance

- [x] All six operator scripts bind tty1 through one helper.
- [x] Panels carry explicit ASCII markers; input has a 300 s timeout.
- [x] `paw-data-prepare.sh` keeps strict tty1 binding.
- [x] Chinese authorization panel and data-loss warning proven on fbcon by the
      QEMU `final` case (25 assertions).
- [ ] Real ASUS screen still needs visual confirmation (D).

## D. Real-world acceptance (still open)

- [ ] Real TF card written and re-hashed; media identity recorded.
- [ ] Real ASUS B85M-G Plus Legacy BIOS boot and full Chinese menu.
- [ ] Real SSD SMART and read scan; real memory/Memtest observation.
- [ ] Real Tencent Cloud Rescue Mode SSH and source identity.
- [ ] Real full-disk clone and independent SHA256.
- [ ] Real PAW Ubuntu first boot and offline adaptation.
- [ ] Real `systemctl reboot` on hardware.
- [ ] Real Tailscale/Xray/Funnel/MCP/PAW acceptance.

These require the user's physical hardware and separate authorization. Cloud and
virtual results must not be marked as physical completion.

## E. Public repository acceptance

- [x] No private keys, tokens, credentials, production IPs or personal paths in
      committed delivery documents.
- [x] Public-safety and public-history scans pass on the branch tip.
- [x] Raw `live-build.log` excluded from the repository (mirror IPv4 literals).
- [x] Repository visibility unchanged (Public).
- [x] Existing runs and artifacts not deleted.

## Overall

- P0-1 font gate: **PASS** (local 26/26; CI green).
- Stage 2 virtual block-device clone/boot: **PASS**; physical SSD **OPEN**.
- Stage 3 26-step migration chain: **PASS** in QEMU/virtual disks; the chain's
  own `target_boot` detector was cut by the outer scheduler, and the cloned
  target boot to `ubuntu login:` was re-verified by an independent
  QEMU/SeaBIOS run (`reports/evidence/stage3-target-standalone-boot-20261111.evidence.txt`).
- Stage 4 final ISO and Chinese docs: **PASS for cloud delivery**. ISO
  953,155,584 bytes, SHA256
  `822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09`,
  matching the same-run sidecar; physical media still OPEN.
- Physical delivery: **NOT STARTED**; old VPS remains authoritative.
