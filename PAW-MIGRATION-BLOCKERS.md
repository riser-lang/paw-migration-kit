# PAW Migration Blockers

Updated: 2026-11-12 UTC (PAW v2.8 pre-hardware acceptance)
Current branch: `vm/ds-prehardware-acceptance-20261111`
Current code HEAD: `9bc9580` (12 GiB chain PASS; source identity/getty fixes on top of `b9f5c5b`)
Base: `d640712`
PR #2: Draft, not merged

## Current blocker table

| ID | Status | Blocker | Exit condition / evidence |
|---|---|---|---|
| P0-MEMTEST | **CLOSED (virtual)**; physical OPEN | Memtest86+ menu entry vs. direct kernel boot | Real ISOLINUX release-ISO boot selected the `m` hotkey entry and reached `Memtest86+ v7.20`, `Status: Testing`, `Errors: 0`; separate full pass `Status: Pass`, `Pass: 1`, `Errors: 0`. Real ASUS DIMM run still `NEEDS_TEST`. |
| P0-AUTH | **CLOSED (virtual)** | Clone authorization could be journal-only / expiry mishandled | `paw-transaction.py`; wrong serial no receipt and 1 MiB target unchanged; correct serial `AUTHORIZED`; expiry only before clone; interrupt/verify/repair/expand gated. |
| P0-SOURCE-MOUNT | **CLOSED (virtual)** | Source could be mounted read-write or mount errors swallowed | `paw-source-mount-check.py` parses mountinfo; 7 scenarios fail closed; chain mounted source `ro`. |
| P1-REMEDIATION | **CLOSED (virtual/static)** | O_DIRECT, NTFS, GRUB/by-id, AHCI/r8169, SMART, firstboot, service identity | 24/24 P1 report; `paw-stream-verify.sh` `iflag=direct`; NTFS excluded; `grub-pc` by-id+debconf readback (cloud-style images recorded honestly); AHCI/r8169 hard `die`; SMART PASS/WARN/FAIL; firstboot split; identity isolation manifest. |
| PREHW-CHAIN | **CLOSED (virtual)**; physical OPEN | Previous attempts exposed two real failures: 37/2 fault suite due empty `lsblk FSTYPE`, and stale target clone reusing the source ext4 UUID | Final rerun emitted `PAW3_CHAIN_RESULT=PASS`, 39/39 fault suite, independent SHA256, clone/repair/expand/reboot, cloned target `ubuntu login:` (`TARGET_BOOT_SEEN`). Physical ASUS/TF/SSD/Rescue still OPEN. |
| SUPP3-VLESS | **CLOSED (simulated)**; production OPEN | Live-ephemeral vs. persistent Tailscale identity; VLESS URI leakage | 25/25 VLESS suites; Xray v26.3.27 SHA256 `8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed`; URI stdin-only; proxy loopback 10808/10809; `/proc/PID/environ` inheritance. Real Tailnet/VPS/Windows `NEEDS_TEST`. |
| SUPP4-PORTS | **DESIGN PASS**; production OPEN | Wuhan home broadband has no public IPv4 / no router port-forward | Policy refuses public IPv4 and router mapping; Serve (Tailnet) / Funnel (public edge) / GPT Tunnel outbound; cloud MCPs must not assume Tailscale 的 CGNAT 私有地址段; loopback-only 8800/10808/10809. Real Serve/Funnel/MCP/UDP `NEEDS_TEST`. |
| PHYSICAL | **OPEN** | Real TF/SSD/ASUS/Rescue not touched | User writes/re-hashes TF, boots ASUS Legacy BIOS, records SMART/scan/temp and Memtest, verifies Tencent Rescue source, then authorizes real clone. |
| REPRO | OPEN | Cloud ISO builds are not byte-reproducible | Always use the same build run's ISO sidecar; do not reuse a ZIP hash. |
| PTY-LOCAL | OPEN (environment) | Sandbox has no usable `/dev/ptmx` | CI runs with `PAW_REQUIRE_PTY=1`; local status remains BLOCKED. |

## Virtual disk disclaimer

The chain used QEMU `ich9-ahci` + `ide-hd`; Linux reports `ata`. This is a
disposable virtual AHCI/ATA substitute, not the physical ASUS SATA path. Source
and target are files under `~/prehardware-20261111/boot/`; no host block device
was written.

## Hard boundaries

- Never stop, reboot, rescue, mount or otherwise touch the production VPS.
- Never write a physical disk or TF card in this cloud session.
- Never claim QEMU, mock SSH, loop devices or operator attestation as physical or
  cryptographic proof.
- Never upload real credentials, server addresses, production UUIDs or keys.
- Never compute a delivery ISO hash from an artifact ZIP.
- Do not merge PR #2, change `main`, delete Artifacts or change repository
  visibility without a new explicit instruction.
