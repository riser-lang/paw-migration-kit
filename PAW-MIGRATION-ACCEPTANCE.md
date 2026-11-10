# PAW Migration Acceptance

Updated: 2026-11-10 UTC (clean VM takeover round)
Current branch: `vm/ds-clean-handover-20261110` — base `d640712`
Historical green run: `42804949796` — success — HEAD `bf1a705`
Historical branch: `fix/v2.6.2-final-readiness`

## A0. Current-branch P0-1 acceptance

- [x] Destructive write gate exists in `scripts/paw-font-gate.py` and rejects any
      report that is not same-boot `paw.console-font.v2` `PASS` with `fbcon`,
      `fbcon_bound=true`, primary 16x16 PSF2, actual/manifest SHA256 match and
      `setfont_exit_code=0`.
- [x] 8x16 vgacon fallback is `WARN`, not `PASS`, and the gate returns non-zero.
- [x] Missing font, corrupt font, manifest hash mismatch, `setfont` failure,
      missing/stale report, vgacon-as-fbcon, 8x16-as-primary and unbound fbcon all
      block.
- [x] `paw-final-confirm.sh` gates before the destructive authorization panel.
- [x] `paw-prepare-data-partition.sh` gates before any partition/format/mount write.
- [x] `paw-stream-clone.sh`, `paw-offline-repair.sh` and `paw-gpt-expand.sh` gate
      through `require_sim_or_enrollment`; read-only diagnostics remain available.
- [x] Fault injection: **26 assertions, 0 failed** locally.
- [x] New-branch GitHub Actions run `42825407549` at `4af304e`: **success**,
      including font-gate 26/26, CJK QEMU 25/25, PAWDATA 12/12, virtual 39/39,
      repair 19/19, network 17/17, finalize 36/36 and TTY 56/56. Earlier failures
      `42812469612`/`42817841755` are recorded; old `42804949796` remains historical.
- [~] Stage 2 Ubuntu 24.04 cloned-disk boot. **VIRTUAL_BOOT_PASS / BLOCK_CLONE_PATH_OPEN**;
      real QEMU/SeaBIOS boot from a 240GB target, GPT/ext4 expansion, real
      `grub-install`/`update-grub`/`update-initramfs`, second boot to login. The
      project clone ran in explicit `PAW_SIMULATION=1` (no host root/loop), so the
      production block-device/SSH clone path and full project offline repair remain
      open. Evidence: `reports/PAW-STAGE2-REAL-UBUNTU-BOOT-20261110.md`.
- [ ] Stage 3 full migration chain. **OPEN**.
- [ ] Stage 4 final ISO + downloaded-ISO SHA256 (never ZIP hash). **OPEN**.

## A. Historical cloud build acceptance (`bf1a705`)

- [x] Workflow runs on the v2.6.2 branch and completes successfully (`42804949796`).
- [x] Debian Live ISO `paw-live-amd64.iso` is produced (953,155,584 bytes).
- [x] Build-generated ISO SHA256 sidecar is uploaded:
      `d9fe28799f9c18d1ec69900b66ea0c71d70b232c5e62a0c4ab0e902fb95a4476`.
- [x] `artifacts/iso-identity.txt` gives ISO byte size and SHA256 directly in the
      build log, so a delivery check no longer needs the 1 GB artifact download.
- [x] Debian base signature/hash verification is PASS.
- [x] Tailscale and Xray provenance/digest checks are PASS.
- [x] Software package list and build provenance are present.
- [x] Artifact is retained for 3 days (expires 2026-11-13 11:27:18 UTC).
- [x] ISO from Run `42804949796` (the delivery artifact) was independently
      re-downloaded and re-hashed on the workstation: computed value equals the
      uploaded sidecar `d9fe28799f9c18d1ec69900b66ea0c71d70b232c5e62a0c4ab0e902fb95a4476`
      (953,155,584 bytes).
- [x] ISO from Run `42778468039` was independently re-downloaded and re-hashed:
      computed `17789c0444d6f8bac0ef24aa7d6a68871e1dfedb2d7b3fe0c50355288a6e0363`
      matched the uploaded sidecar exactly.
- [x] ISO from Run `42747871471` was independently re-downloaded and re-hashed:
      computed `2295eb0a8d9d61b93be3e91cfeee735c42529ed3223cbf14593047104939336d`
      matched the uploaded sidecar exactly.
- [x] ISO from Run `42795953493` was independently re-downloaded and re-hashed:
      computed `2edf88a09684ebbb88680c79a73a29ea77fbc794aa168243649b2b67b2fc20ed`
      matched the uploaded sidecar exactly.
- [ ] Two builds of the same code tree produce the same ISO SHA256. Runs
      `42747871471`, `42778468039`, `42795953493` and `42804949796` produced
      identical size (953,155,584) but four different SHA256 values; byte-for-byte
      reproducibility remains unproven.

## B. Virtual boot acceptance

- [x] SeaBIOS + QEMU TCG reaches the PAW readiness gate.
- [x] Readiness is `BLOCKED` when source/target/hardware prerequisites are absent.
- [x] `clone_started=false` on the fail-closed path.
- [x] Memtest86+ independent menu and binary are present.
- [x] This does not prove real ASUS motherboard boot.

## C. Virtual migration acceptance

- [x] PAWDATA auto-init succeeds on MBR Hybrid media.
- [x] PAWDATA auto-init succeeds on GPT Hybrid media.
- [x] Only the newly appended partition is formatted.
- [x] PAWDATA survives unmount/remount; ISO/BIOS Boot geometry preserved.
- [x] Memtest manual confirmation binds boot ID and target serial; status `OPERATOR_CONFIRMED`.
- [x] Missing/incomplete/error memory result blocks clone.
- [x] Rescue source identity passes with serial.
- [x] Rescue source identity passes without serial using composite identity.
- [x] Wrong root UUID/capacity/GPT/BIOS Boot is rejected by code/test.
- [x] Target serial/capacity mismatch is rejected before write.
- [x] Remote zstd stream records payload and actual restored bytes.
- [x] Raw fallback is explicit.
- [x] SSH interruption and short read leave `CLONE-INCOMPLETE`.
- [x] SHA256 mismatch fails and keeps marker.
- [x] Mixed data round-trip passes.
- [x] SMART FAIL and I/O timeout fail closed.
- [x] GPT and ext4 expansion pass on loop images.
- [x] Netplan compatibility test passes for `eth0`, `enp3s0`, `r8169`.
- [x] Offline repair and rollback test passes on a loop ext4 root.
- [x] First-boot gate rejects incomplete/wrong-target receipts in virtual flow.

Test totals (Run `42804949796`): PAWDATA 12/12; fault injection 39/39;
repair/rollback 15/15; network 17/17; finalize 36/36; TTY 56 (static 55 + PTY,
0 blocked); CJK font 1/1; QEMU CJK 5 cases / 96 assertions.

## C2. Operator console acceptance

- [x] No operator script reachable from the tty1 menu uses an implicit-stdin prompt.
- [x] All six operator scripts bind the interactive terminal through one helper.
- [x] Every panel carries explicit ASCII screen markers
      (`PAW-TTY1-FINAL-*`, `-MEMTEST-*`, `-TARGET-*`, `-RESCUE-*`, `-NETPHASE-*`,
      `-SOURCE-*`).
- [x] Input has a 300 s timeout; timeout and abort paths stop without writing.
- [x] `paw-data-prepare.sh` keeps the strict tty1 binding and cannot fall back.
- [x] A fallback binding is not recorded as a real tty1 session.
- [x] The Chinese authorization panel and its data-loss warning are proven on fbcon
      by the QEMU `final` case: the production `paw-final-confirm.sh` runs twice on
      tty1 (wrong suffix rejected, correct suffix accepted) and the screendump is
      matched against the shipped PSF glyphs, 25 assertions, 0 failed.
- [ ] The real ASUS screen still needs the same visual confirmation (see D).

## C3. Stage 2 partial evidence; Stage 3–4 open

- [x] Real Ubuntu 24.04 source disk with GPT, BIOS Boot, ext4, real GRUB and real
      initramfs (cloud image, raw, 3.5GB).
- [x] 240GB sparse target virtual disk.
- [~] Production clone program: `scripts/paw-stream-clone.sh` + `paw-stream-verify.sh`
      executed in explicit `PAW_SIMULATION=1`; not the real block/SSH path.
- [x] Independent SHA256 after clone: `987a7c33...289b7a09`, 3,758,096,384 bytes.
- [~] GPT/ext4 expansion, real GRUB install, real initramfs: actual Ubuntu guest
      commands executed; full project `paw-offline-repair.sh` against this target
      remains OPEN.
- [x] QEMU + SeaBIOS boot from the target disk; serial/login evidence (two boots).
- [ ] Full Live → menu → PAWDATA → hardware → network → Rescue → source → final
      authorization → clone → verify → repair → expand → first boot → reboot chain.
- [ ] Final ISO built, ISO artifact downloaded, ISO SHA256 recomputed from the ISO
      file (not the ZIP), Chinese guide and rollback guide updated.

## D. Real-world acceptance (still open)

- [ ] Real TF card written and verified.
- [ ] Real motherboard boots the TF card.
- [ ] Real SSD SMART and read scan.
- [ ] Real Tencent Rescue Mode SSH.
- [ ] Real full-disk clone and SHA256.
- [ ] Real PAW Ubuntu first boot and offline adaptation.
- [ ] Real Tailscale/Xray/Funnel/MCP/PAW acceptance.

These require the user's physical hardware and separate authorization. They must not
be marked complete from cloud/virtual results.

## E. Public repository acceptance

- [x] No private keys, tokens, credentials, real server IPs or personal paths in current committed files.
- [x] Reachable Git history scan passes (`PUBLIC-HISTORY=PASS`; current run 849 objects).
- [x] Final Actions log/report reviewed; raw `live-build.log` excluded from repository because it contains Debian mirror IPv4 addresses.
- [x] Repository visibility unchanged (Public).
- [x] Existing runs and artifacts not deleted.

## Overall

- Current branch P0-1: **PASS (local 26/26; CI Run `42825407549` green)**.
- Stage 2: **VIRTUAL_BOOT_PASS / BLOCK_CLONE_PATH_OPEN** (real boot and
  GRUB/initramfs/expansion evidence; production block clone and full project
  offline repair still open).
- Stage 3/4: **OPEN** (not started in this round).
- Historical cloud/virtual delivery (`bf1a705`): **READY_WITH_REAL_HARDWARE_UNVERIFIED**.
- Operator console binding: **CLOSED for static/PTY/CI and QEMU glyph rendering**
  (Run `42825407549`: TTY 56/56, CJK 25/25); real ASUS screen remains open.
- Production migration: **NOT STARTED**; old VPS remains authoritative.
