# PAW Migration Blockers

Updated: 2026-11-09 UTC

| ID | Status | Blocker | Exit condition |
|---|---|---|---|
| P0-1 | VIRTUALLY_VERIFIED | Memtest86+ has a boot entry but no machine-verifiable capture | `OPERATOR_CONFIRMED` UI binds current Live boot ID and target serial; FAIL/WARN block clone; not claimed as cryptographic proof. Real physical run still open. |
| P0-2 | VIRTUALLY_VERIFIED | PAWDATA previously required manual command and only supported DOS/MBR | Auto-guided MBR/GPT initialization; only new partition formatted; remount persistence; 12/12 virtual tests. Real TF card still open. |
| P0-3 | VIRTUALLY_VERIFIED | Source discovery previously required a Virtio serial number | Composite identity uses pinned SSH host key fingerprint, root UUID, unique parent, 50 GiB, GPT layout, BIOS Boot and discovery time. Real Rescue still open. |
| P0-4 | VIRTUALLY_VERIFIED | Restored byte count was assumed; only all-zero data tested | Actual decompressed counter, mixed data, interruption/short-read, raw fallback and SHA; 35/35 fault tests. Real SSH still open. |
| P0-5 | VIRTUALLY_VERIFIED | Final authorization did not show full evidence nor re-identify source | Full Chinese summary, target suffix input, complete source/target re-identification before authorization. Real disk not used. |
| P1-1 | VIRTUALLY_VERIFIED | Netplan matched only `en*` | `e*` covers `eth0`, `enp3s0`, `en*`, r8169; networkd and cloud-init handling tested. Real NIC still open. |
| P1-2 | VIRTUALLY_VERIFIED | Offline repair simulation did not exercise adaptation | Loop ext4 adaptation and update-grub rollback 15/15. Real Ubuntu boot still open. |
| P1-3 | VIRTUALLY_VERIFIED | No virtual tests for Xray bad config, Tailscale wait, network failure | Xray/Rescue/Restored/Tailscale suite 17/17, mock only. Real network still open. |
| P1-4 | OPEN | Real hardware checks not performed | User must run on target hardware; reports remain unverified until then. |
| BUILD | PASS | Run `42618901559` success, artifact ID `13675072020` | ISO SHA256 and reports extracted; artifact expires 2026-11-12 12:48:02 UTC. |
| REPRO | OPEN | Two cloud builds of the same code tree produced the same ISO size but different SHA256 (`5daf...` vs `8c8f...`) | Byte-for-byte reproducibility not claimed; document and investigate before treating double-build as a release gate. |
| DELIVERY | PENDING_USER | Final real-world write/boot/migration and final guide review | User downloads artifact, re-hashes ISO, writes TF card, performs physical checks. |

## Hard boundaries

- Never stop, reboot, rescue, mount or otherwise touch the production VPS.
- Never write a physical disk or TF card in this cloud session.
- Never claim QEMU, mock SSH, loop devices or operator attestation as physical/cryptographic proof.
- Never upload real credentials, server addresses, UUIDs or private keys.
- `OPERATOR_CONFIRMED` is an operator observation, not a machine-verified PASS.
