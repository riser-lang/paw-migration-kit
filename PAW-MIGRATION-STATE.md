# PAW Migration State

Updated: 2026-11-12 UTC (PAW v2.8 pre-hardware acceptance)
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
| Full pre-hardware chain (12 GiB source → 240 GB target) | **PASS (virtual, CHAIN_PASS)** | `PAW3_CHAIN_RESULT=PASS`; independent SHA256; cloned target `ubuntu login:`; 39/39 fault suite |
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

**2026-11-12 final rerun: PASS.** The chain started at 11:32 CST and emitted
`PAW3_CHAIN_RESULT=PASS` at 12:39:59 CST. It passed `lab_target_blank`,
`live_boot`, `cpu`, `sata`, `source_os` (Ubuntu 24.04.5, kernel
`6.8.0-147-generic`, i915/r8169 present, source read-only), console font, rescue
SSH, 39/39 virtual fault tests, negative source identity, positive
`source_identity` on `exact 12 GiB capacity` (composite
`6704e246b06ce693f394c1fed0e2c0db1b99f7da697f2ab3454f470933fbbc66`), PAWDATA,
target enrollment, Memtest attestation, virtual hardware, network WARN (not a
chain gate), readiness, mixed stream, SSH interruption, wrong-serial rejection,
bootindex swap and correct authorization.

The destructive phase then passed: compressed transfer (12,884,901,888 source
bytes, 584,133,947 SSH payload bytes, 95.5% reduction), independent SHA256
`140081b5bdb716cac171d6d6a20e1487aa152e636b7ea793bbae3f701227ff6e`,
offline repair (GRUB by-id, cloud-style no debconf), GPT expansion of
`/dev/sdc2` to 239,997,885,952 bytes, preboot handoff and auto reboot. The
cloned target booted Ubuntu 24.04.5 and reached `ubuntu login:` on ttyS0; host
runner result `TARGET_BOOT_SEEN`, `target_boot=True` at 12:47:07 CST.

Earlier attempts remain documented as failures: the 02:45–03:01Z attempt passed
authorization but was killed by the 12 h outer timeout before clone; its fault
suite was 37/2 and led to the `blkid` fallback. A later rerun failed
`source_identity` because the disposable target still carried an old clone with
the same ext4 UUID; the chain now blanks only the serial-verified
`PAW-DST-123456` target before identity discovery. Neither failure is reported as
a PASS.

The final host reader initially missed the getty prompt because `login: ` has no
trailing newline; the prompt was real and the chain had already passed. A
harmless SysRq-H console line let the old line-oriented reader classify it, then
the reader was fixed to inspect the serial snapshot directly. This harness bug is
documented in the acceptance report; it does not change the PASS criteria.

Evidence:
`~/prehardware-20261111/console-main.log`,
`~/prehardware-20261111/share/state/chain.log`,
`~/prehardware-20261111/share/prehw-selftests/virtual-fault-injection-report.txt`,
`~/prehardware-20261111/screens/target-boot.ppm`,
`/tmp/prehw-main4.log`.

## Durable evidence

| Item | Path |
|---|---|
| P0 remediation | `reports/evidence/prehardware-20261111/p0-remediation-report.txt` (26/0) |
| P1 remediation | `reports/evidence/prehardware-20261111/p1-remediation-report.txt` (24/0, re-run 2026-11-12) |
| Memtest86+ | `reports/evidence/prehardware-20261111/memtest86-20261111.txt`; host artifacts under `~/prehardware-20261111/memtest-menu-3.0/` and `~/prehardware-20261111/memtest-full-3g/` |
| VLESS/network | `reports/evidence/prehardware-20261111/vless-network-test-report.txt` (25/0) |
| Full chain logs | `~/prehardware-20261111/console-main.log`, `/tmp/prehw-main4.log`, `/tmp/prehw-prepare4.log`, `~/prehardware-20261111/share/prehw-selftests/`; screenshot `screens/target-boot.ppm` |
| Chain 2026-11-12 | `reports/evidence/prehardware-20261111/chain-20261112/` (step summary + stream/verify/repair/expand JSON) |
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
