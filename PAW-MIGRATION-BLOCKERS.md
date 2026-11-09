# PAW Migration Blockers

Updated: 2026-11-09 UTC

| ID | Status | Blocker | Exit condition |
|---|---|---|---|
| P0-1 | CODE_DONE / VERIFYING | Memtest86+ has a boot entry but no operator-confirmation receipt; memory gate can never pass | Chinese confirmation UI binds current Live boot ID and target serial; status is `OPERATOR_CONFIRMED`, never claimed as machine proof; incomplete/errors block clone |
| P0-2 | CODE_DONE / VERIFYING | PAWDATA requires manual command and only supports DOS/MBR | Auto-guided initialization at boot; MBR and GPT Hybrid; only the newly appended partition is formatted; persistence verified after remount |
| P0-3 | CODE_DONE / VERIFYING | Source discovery requires a Virtio serial number | Composite identity works without serial: pinned SSH host key fingerprint, root UUID, unique parent disk, 50 GiB, GPT layout, BIOS Boot, discovery time |
| P0-4 | CODE_DONE / VERIFYING | Restored byte count is assumed; only all-zero compression tests | Actual decompressed counter; progress truthful; interruption/short-read leaves `CLONE-INCOMPLETE`; mixed-data test |
| P0-5 | CODE_DONE / VERIFYING | Final authorization does not show full evidence nor re-identify source before authorization | Full Chinese summary; target suffix input; complete source and target re-identification immediately before authorization |
| P1-1 | CODE_DONE / VERIFYING | Netplan matches only `en*` | Covers `eth*`, `en*`, Realtek r8169, DHCP, cloud-init, legacy `net.ifnames=0` |
| P1-2 | CODE_DONE / VERIFYING | Offline repair simulation does not exercise adaptation; no `grub-install` | Loop ext4 fixture exercises netplan/machine-id/SSH keys/initramfs/GRUB; backup and rollback verified |
| P1-3 | CODE_DONE / VERIFYING | No virtual tests for Xray bad config, Tailscale auth wait, network failure | Tests record expected fail-closed behavior; simulated network clearly labeled |
| P1-4 | OPEN | Real hardware checks not performed | User runs on target hardware; reports remain unverified until then |
| BUILD | IN_PROGRESS | Run `42605312024` on branch `fix/v2.6.2-final-readiness` | New workflow run success; ISO SHA256 and reports downloaded and checked |
| DELIVERY | PENDING | Final package and instructions not assembled | ISO, SHA256, software manifest, provenance, reports, rollback/use guide complete |

## Hard boundaries

- Never stop, reboot, rescue, mount or otherwise touch the production VPS.
- Never write a physical disk or TF card in this cloud session.
- Never claim QEMU, mock SSH, loop devices or operator attestation as physical/cryptographic proof.
- Never upload real credentials, server addresses, UUIDs or private keys.
