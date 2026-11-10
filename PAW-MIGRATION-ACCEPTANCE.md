# PAW Migration Acceptance

Updated: 2026-11-10 UTC (second takeover round)
Delivery run: `42804949796` — success — product head `bf1a705`
Verification run: `42873432670` — success — `ac0813e` (tests-only changes)
Branch: `fix/v2.6.2-final-readiness`

## A. Cloud build acceptance

- [x] Workflow runs on the v2.6.2 branch and completes successfully (`42804949796`).
- [x] Debian Live ISO `paw-live-amd64.iso` is produced (953,155,584 bytes).
- [x] Build-generated ISO SHA256 sidecar is uploaded:
      `d9fe28799f9c18d1ec69900b66ea0c71d70b232c5e62a0c4ab0e902fb95a4476`.
- [x] `artifacts/iso-identity.txt` gives ISO byte size and SHA256 directly in the
      build log, so a delivery check no longer needs the 1 GB artifact download.
- [x] Debian base signature/hash verification is PASS.
- [x] Tailscale and Xray provenance/digest checks are PASS.
- [x] Software package list and build provenance are present.
- [x] The built ISO carries the reviewed payload: `iso-payload-report.txt`
      `Summary: 54 passed, 0 failed` on run `42873432670`, with no extra or missing
      `paw-*` script inside the image.
- [x] The delivered folder verifies itself: `DELIVERY=PASS (24 checks)` with
      `scripts/verify-delivery.ps1` on Windows PowerShell 5.1, plus a negative test
      where one tampered file yields `DELIVERY=FAIL` and exit code 1.
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
- [x] ISO from Run `42810087226` (verification run, not delivered) was independently
      re-downloaded and re-hashed: computed
      `aff7a8075a3347d63ab2de7991b1d1fca78ae6017a7db16adb0b974c4b178d65` matched its
      uploaded sidecar and the build-side value in the run log.
- [x] ISO from Run `42795953493` was independently re-downloaded and re-hashed:
      computed `2edf88a09684ebbb88680c79a73a29ea77fbc794aa168243649b2b67b2fc20ed`
      matched the uploaded sidecar exactly.
- [ ] Two builds of the same code tree produce the same ISO SHA256. Runs
      `42747871471`, `42778468039`, `42795953493`, `42804949796`, `42810087226`,
      `42816492016`, `42838392058`, `42845816766` and `42873432670` produced identical size (953,155,584)
      but twelve different SHA256 values; byte-for-byte reproducibility remains unproven.

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
- [x] The real `grub-install --target=i386-pc` installs BIOS GRUB on a loop GPT disk
      host-side (modules copied, MBR `0x55AA` boot code, embedded core image).
- [x] The chroot shape used by the production repair path
      (`chroot ROOT grub-install --target=i386-pc --recheck LOOP`) also succeeds on a
      loop GPT disk (modules copied into the fixture `/boot`, MBR `0x55AA`).
- [x] A repaired loop disk boots: QEMU SeaBIOS starts it alone, GRUB loads the kernel,
      the initrd is processed and the initramfs stage is reached without a panic. A
      real Ubuntu root booting to login is still unverified.
- [x] First-boot gate rejects incomplete/wrong-target receipts in virtual flow.

Test totals (Run `42873432670`): PAWDATA 12/12; fault injection 39/39;
repair/rollback 28/28 (real `grub-install` host-side and chroot, plus a QEMU boot of the repaired disk); network 17/17; finalize 36/36; TTY 56 (static 55 + PTY,
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
- [x] Reachable Git history scan passes (`PUBLIC-HISTORY=PASS`, 1041 objects).
- [x] Final Actions log/report reviewed; raw `live-build.log` excluded from repository because it contains Debian mirror IPv4 addresses.
- [x] Repository visibility unchanged (Public).
- [x] Existing runs and artifacts not deleted.

## Overall

- Cloud/virtual delivery: **READY_WITH_REAL_HARDWARE_UNVERIFIED**.
- Operator console binding: **CLOSED for static/PTY/CI and for QEMU glyph rendering**;
  real screen open.
- Production migration: **NOT STARTED**; old VPS remains authoritative.
