# PAW Migration State

Updated: 2026-11-11 UTC (PAW v2.8 pre-hardware acceptance)
Current branch: `vm/ds-prehardware-acceptance-20261111`
Current code HEAD: `a5c423f` (source_os/gpt-expand fixes on top of `b9f5c5b`)
Base: `d64071251bb3075d9cb26a967dfcba6cf139250a`
PR: #2 (Draft, not merged); #1 untouched
Main HEAD: `0d6aefd` (unchanged)

## Current status at a glance

| Area | Status | Evidence |
|---|---|---|
| P0-1 Memtest86+ ISOLINUX menu | **PASS (QEMU/SeaBIOS)** | real release ISO boot, hotkey `m` + Enter, `Memtest86+ v7.20`, `Status: Testing`, `Errors: 0`; full pass `Status: Pass`, `Pass: 1`, `Errors: 0` |
| P0-2 authorization/transaction | **PASS (virtual)** | `paw-transaction.py` state machine; wrong serial no receipt, correct serial AUTHORIZED, interrupt/verify/repair/expand gates |
| P0-3 source read-only mount gate | **PASS (virtual)** | `paw-source-mount-check.py`; 7 mount scenarios fail closed; real source mounted `ro` in chain |
| P1 remediation | **PASS (virtual/static)** | 24/24 P1 report (re-run this segment); O_DIRECT, NTFS exclusion, GRUB/by-id, AHCI/r8169, SMART, firstboot, identity isolation |
| Supplement 3 VLESS/Tailscale | **PASS (simulated)** | 25/25 VLESS report; Xray v26.3.27 SHA256 pinned; loopback-only proxy; ephemeral vs persistent identity |
| Supplement 4 Wuhan home broadband | **Design PASS; production NEEDS_TEST** | `configs/home-port-policy.json`, `paw-port-audit.sh`; no public IPv4/router port-forward; Serve/Funnel/GPT Tunnel design |
| Full pre-hardware chain (12 GiB source → 240 GB target) | **RE-RUN IN PROGRESS**; no CHAIN_PASS yet | QEMU/SeaBIOS ATA/AHCI virtual disks |
| Physical ASUS/TF/SSD/Rescue/production | **OPEN / NEEDS_TEST** | not touched in this session |

The 12 GiB source is a real Ubuntu 24.04.5 cloud root filesystem (`6.8.0-147-generic`,
i915/r8169 modules present) on a GPT disk with a BIOS Boot partition and a
`cloudimg-rootfs` ext4 root. It is intentionally smaller than the final physical
50 GiB source so the TCG chain can finish in a useful time; the chain code itself
is capacity-agnostic and the lab now passes the expected source size explicitly.

## What was done in this round

- Reviewed and tested the 12 inherited local changes instead of discarding them;
  no inherited work was reverted.
- Split the in-guest fault suites from live Rescue RAM files (private mount
  namespace + early execution), so a passing suite can no longer delete the
  chain's `/run/paw-network` endpoint/key.
- Bound virtual fault-injection clones to a real P0 transaction state and reset
  that state between re-run cases.
- Made the lab source capacity explicit (`PAW_EXPECTED_SOURCE_BYTES`) instead of
  hard-coding 50 GiB; the systemd unit is templated from the actual source file.
- Built a bootable Ubuntu source (GPT/BIOS Boot/ext4/GRUB config/kernel/initrd,
  i915/r8169) and verified it read-only from the guest.
- Ran the full chain on `ich9-ahci` with QEMU `ide-hd` devices (reported `ata`,
  explicitly classified `virtual_ata_ahci_not_physical_sata`).

## Full-chain result

The 2026-11-12T02:45–03:01Z attempt used the rebuilt 12 GiB Ubuntu source and
passed `live_boot`, `cpu`, `sata`, `source_os` (24.04), console font, rescue
SSH, source identity, PAWDATA, target enrollment, Memtest attestation, virtual
hardware, readiness, mixed-data stream, SSH interruption and wrong-serial
authorization. It then passed `final_authorization_correct` at 03:00Z and was
killed by the 12 h outer timeout before the clone/verify/repair/expand stages
ran. **That attempt is not a CHAIN_PASS.** The in-guest fault suite in the same
attempt reported 37 passed / 2 failed: the non-last-root refusal was emitted as
`Root partition is not ext4.` because `lsblk` returned an empty FSTYPE for the
fresh loop partition. The guard now falls back to `blkid`, retries the probe and
prints the detected type; the guest is rebuilt and the chain is being rerun.

Evidence for the failed/incomplete attempt:
`~/prehardware-20261111/console-main.log`,
`~/prehardware-20261111/share/state/chain.log`,
`~/prehardware-20261111/share/prehw-selftests/virtual-fault-injection-report.txt`.

## Durable evidence

| Item | Path |
|---|---|
| P0 remediation | `reports/evidence/prehardware-20261111/p0-remediation-report.txt` (26/0) |
| P1 remediation | `reports/evidence/prehardware-20261111/p1-remediation-report.txt` (24/0, re-run 2026-11-12) |
| Memtest86+ | `reports/evidence/prehardware-20261111/memtest86-20261111.txt`; host artifacts under `~/prehardware-20261111/memtest-menu-3.0/` and `~/prehardware-20261111/memtest-full-3g/` |
| VLESS/network | `reports/evidence/prehardware-20261111/vless-network-test-report.txt` (25/0) |
| Full chain logs | `~/prehardware-20261111/console-main.log`, `/tmp/prehw-main10.log`, `~/prehardware-20261111/share/prehw-selftests/` |
| Acceptance report | `reports/PAW-PREHARDWARE-ACCEPTANCE-20261111.md` |

## Hard boundaries still in force

- No production VPS modification/stop/restart; no Rescue Mode; no production
  disk read or real clone.
- No production PAW/Tailscale/Funnel/Xray/Nginx/443/firewall/COS changes.
- No real TF card, SSD, ASUS motherboard or physical Memtest run in this session.
- No Artifact deletion, no repository visibility change, no PR merge.
- QEMU `ata`/`ich9-ahci` is a virtual AHCI substitute, not physical SATA proof.
- `OPERATOR_CONFIRMED` is attestation, not cryptographic proof.

## Next actions (require user hardware/authorization)

1. Write the verified release ISO to the TF/USB medium and re-hash it.
2. Boot the ASUS B85M-G Plus in Legacy BIOS, confirm the Chinese console and the
   Memtest86+ menu visually.
3. Record real SSD SMART/read-scan/temperature and real DIMM Memtest result.
4. Perform Tencent Cloud Rescue read-only source identity verification, then the
   real clone with separate authorization.
5. On the real PAW Ubuntu, complete persistent Tailscale login, Serve/Funnel,
   GPT Tunnel and the three cloud MCP checks.
6. Validate Wuhan home broadband UDP 41641/3478, CGNAT/double NAT and DERP
   fallback on site.
