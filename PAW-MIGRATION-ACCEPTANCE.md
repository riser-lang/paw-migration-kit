# PAW Migration Acceptance

Updated: 2026-11-09 UTC

## A. Cloud build acceptance

- [ ] Workflow runs on the v2.6.2 branch and completes successfully.
- [ ] Debian Live ISO `paw-live-amd64.iso` is produced.
- [ ] ISO SHA256 matches the uploaded sidecar file.
- [ ] Debian base signature/hash verification is PASS.
- [ ] Tailscale and Xray provenance/digest checks are PASS.
- [ ] Software package lock and build provenance are present.
- [ ] Artifacts are retained for 3 days.

## B. Virtual boot acceptance

- [ ] SeaBIOS + QEMU TCG reaches the PAW readiness gate.
- [ ] Readiness is `BLOCKED` when source/target/hardware prerequisites are absent.
- [ ] `clone_started=false` on the fail-closed path.
- [ ] Memtest86+ independent menu and binary are present.
- [ ] This does not prove real ASUS motherboard boot.

## C. Virtual migration acceptance

- [ ] PAWDATA auto-init succeeds on MBR Hybrid media.
- [ ] PAWDATA auto-init succeeds on GPT Hybrid media.
- [ ] Only the newly appended partition is formatted.
- [ ] PAWDATA survives unmount/remount.
- [ ] Memtest manual confirmation binds boot ID and target serial; status `OPERATOR_CONFIRMED`.
- [ ] Missing/incomplete/error memory result blocks clone.
- [ ] Rescue source identity passes with serial.
- [ ] Rescue source identity passes without serial using composite identity.
- [ ] Wrong root UUID/capacity/GPT/BIOS Boot is rejected.
- [ ] Target serial/capacity mismatch is rejected before write.
- [ ] Remote zstd stream records payload and restored bytes.
- [ ] Raw fallback is explicit.
- [ ] SSH interruption leaves `CLONE-INCOMPLETE`.
- [ ] SHA256 mismatch fails and keeps marker.
- [ ] Mixed data round-trip passes.
- [ ] SMART FAIL and I/O timeout fail closed.
- [ ] GPT and ext4 expansion pass on loop images.
- [ ] Netplan compatibility test passes for `eth0`, `enp3s0`, `r8169`.
- [ ] Offline repair and rollback test passes on a loop ext4 root.
- [ ] First-boot gate rejects incomplete/wrong-target receipts.

## D. Real-world acceptance (must stay open in this environment)

- [ ] Real TF card written and verified.
- [ ] Real motherboard boots the TF card.
- [ ] Real SSD SMART and read scan.
- [ ] Real Tencent Rescue Mode SSH.
- [ ] Real full-disk clone and SHA256.
- [ ] Real PAW Ubuntu first boot and offline adaptation.
- [ ] Real Tailscale/Xray/Funnel/MCP/PAW acceptance.

## E. Public repository acceptance

- [ ] No private keys, tokens, credentials, real server IPs or personal paths in current files.
- [ ] Full reachable Git history scan passes.
- [ ] Actions logs reviewed for secret leakage.
- [ ] Repository visibility unchanged.
- [ ] Existing runs and artifacts not deleted.
