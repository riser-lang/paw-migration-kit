# PAW Migration Acceptance

Updated: 2026-11-10 UTC (second takeover round)
Final green run: `42795953493` — success — HEAD `91a79ea`
Branch: `fix/v2.6.2-final-readiness`

## A. Cloud build acceptance

- [x] Workflow runs on the v2.6.2 branch and completes successfully (`42795953493`).
- [x] Debian Live ISO `paw-live-amd64.iso` is produced (953,155,584 bytes).
- [x] Build-generated ISO SHA256 sidecar is uploaded:
      `2edf88a09684ebbb88680c79a73a29ea77fbc794aa168243649b2b67b2fc20ed`.
- [x] `artifacts/iso-identity.txt` gives ISO byte size and SHA256 directly in the
      build log, so a delivery check no longer needs the 1 GB artifact download.
- [x] Debian base signature/hash verification is PASS.
- [x] Tailscale and Xray provenance/digest checks are PASS.
- [x] Software package list and build provenance are present.
- [x] Artifact is retained for 3 days (expires 2026-11-13 10:22:46 UTC).
- [x] ISO from Run `42795953493` (the delivery artifact) was independently
      re-downloaded and re-hashed on the workstation: computed value equals the
      uploaded sidecar `2edf88a09684ebbb88680c79a73a29ea77fbc794aa168243649b2b67b2fc20ed`
      (953,155,584 bytes).
- [x] ISO from Run `42778468039` was independently re-downloaded and re-hashed:
      computed `17789c0444d6f8bac0ef24aa7d6a68871e1dfedb2d7b3fe0c50355288a6e0363`
      matched the uploaded sidecar exactly.
- [x] ISO from Run `42747871471` was independently re-downloaded and re-hashed:
      computed `2295eb0a8d9d61b93be3e91cfeee735c42529ed3223cbf14593047104939336d`
      matched the uploaded sidecar exactly.
- [ ] Two builds of the same code tree produce the same ISO SHA256. Runs
      `42747871471`, `42778468039` and `42795953493` produced identical size
      (953,155,584) but three different SHA256 values; byte-for-byte
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

Test totals (Run `42795953493`): PAWDATA 12/12; fault injection 35/35;
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
- [x] Reachable Git history scan passes (`PUBLIC-HISTORY=PASS`, 682 objects).
- [x] Final Actions log/report reviewed; raw `live-build.log` excluded from repository because it contains Debian mirror IPv4 addresses.
- [x] Repository visibility unchanged (Public).
- [x] Existing runs and artifacts not deleted.

## Overall

- Cloud/virtual delivery: **READY_WITH_REAL_HARDWARE_UNVERIFIED**.
- Operator console binding: **CLOSED for static/PTY/CI and for QEMU glyph rendering**;
  real screen open.
- Production migration: **NOT STARTED**; old VPS remains authoritative.
