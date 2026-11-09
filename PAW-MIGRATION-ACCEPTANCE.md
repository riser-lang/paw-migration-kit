# PAW Migration Acceptance

Updated: 2026-11-09 UTC
Cloud-tested commit: `f18202b714cd2431733ff54e132c3083a4197aca`
Run: `42618901559` — success

## A. Cloud build acceptance

- [x] Workflow runs on the v2.6.2 branch and completes successfully.
- [x] Debian Live ISO `paw-live-amd64.iso` is produced (938,475,520 bytes).
- [x] Build-generated ISO SHA256 sidecar is uploaded: `8c8ffedd3a6eb84c56f1da84b3ee3a79df10b8e1e987099ad88d398e6854c4a7`.
- [x] Debian base signature/hash verification is PASS.
- [x] Tailscale and Xray provenance/digest checks are PASS.
- [x] Software package list and build provenance are present.
- [x] Artifact is retained for 3 days (expires 2026-11-12 12:48:02 UTC).
- [ ] ISO was independently re-downloaded and re-hashed on the cloud workstation. This was not done because the full artifact transfer was bandwidth-limited; user should re-hash after download.
- [ ] Two builds of the same code tree produce the same ISO SHA256. Two runs produced the same size but different SHA256; byte-for-byte reproducibility remains unproven.

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

Test totals: PAWDATA 12/12; fault injection 35/35; repair/rollback 15/15; network 17/17.

## D. Real-world acceptance (still open)

- [ ] Real TF card written and verified.
- [ ] Real motherboard boots the TF card.
- [ ] Real SSD SMART and read scan.
- [ ] Real Tencent Rescue Mode SSH.
- [ ] Real full-disk clone and SHA256.
- [ ] Real PAW Ubuntu first boot and offline adaptation.
- [ ] Real Tailscale/Xray/Funnel/MCP/PAW acceptance.

These require the user's physical hardware and separate authorization. They must not be marked complete from cloud/virtual results.

## E. Public repository acceptance

- [x] No private keys, tokens, credentials, real server IPs or personal paths in current committed files.
- [x] Reachable Git history scan passes.
- [x] Final Actions log/report reviewed; raw `live-build.log` excluded from repository because it contains Debian mirror IPv4 addresses.
- [x] Repository visibility unchanged (Public).
- [x] Existing runs and artifacts not deleted.

## Overall

- Cloud/virtual delivery: **READY_WITH_REAL_HARDWARE_UNVERIFIED**.
- Production migration: **NOT STARTED**; old VPS remains authoritative.
