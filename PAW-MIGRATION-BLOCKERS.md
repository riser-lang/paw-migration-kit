# PAW Migration Blockers

Updated: 2026-11-10 UTC (clean VM takeover round)
Current branch: `vm/ds-clean-handover-20261110` (base `d640712`)
Historical green run: `42804949796` (HEAD `bf1a705`; **not** current-branch evidence)

| ID | Status | Blocker | Exit condition |
|---|---|---|---|
| FONT-GATE | **CLOSED** | Destructive writes were not tied to a same-boot fbcon 16x16 PASS report; 8x16 fallback could be mistaken for success | `paw-font-gate.py` validates schema `paw.console-font.v2`, `status=PASS`, `mode=fbcon`, `fbcon_bound=true`, boot ID, primary font path, actual/manifest SHA256, `setfont_exit_code=0` and PSF2 geometry; destructive entry points call it. CI Run `42825407549`: 26/26 gate, 25/25 CJK, all green. Two earlier CI failures were fixed. |
| STAGE2 | PARTIAL_VIRTUAL_BOOT / BLOCK_CLONE_OPEN | Real Ubuntu 24.04 source disk, 240GB sparse target, project `paw-stream-clone.sh`/`paw-stream-verify.sh` (explicit simulation), independent SHA256, GPT/ext4 expansion, real `grub-install`/`update-grub`/`update-initramfs`, SeaBIOS boot and second boot to login are proven. Production block-device/SSH clone and full project `paw-offline-repair.sh` on this target are not. | Execute the production clone entry on block devices (or CI loop with a real target identity) plus full offline repair, then record the target boot. Evidence: `reports/PAW-STAGE2-REAL-UBUNTU-BOOT-20261110.md`. |
| STAGE3-4 | OPEN | Full migration chain and final ISO (download ISO artifact, recompute ISO SHA256, never ZIP hash) are not complete | Real entry-point integration test, final ISO build, ISO download/hash, Chinese guide and rollback guide. |
| P0-1 | VIRTUALLY_VERIFIED | Memtest86+ has a boot entry but no machine-verifiable capture | `OPERATOR_CONFIRMED` UI binds current Live boot ID and target serial; FAIL/WARN block clone; panel now actually reaches the console; not claimed as cryptographic proof. Real physical run still open. |
| P0-2 | VIRTUALLY_VERIFIED | PAWDATA previously required manual command and only supported DOS/MBR | Auto-guided MBR/GPT initialization; only new partition formatted; remount persistence; 12/12 virtual tests. Real TF card still open. |
| P0-3 | VIRTUALLY_VERIFIED | Source discovery previously required a Virtio serial number | Composite identity uses pinned SSH host key fingerprint, root UUID, unique parent, 50 GiB, GPT layout, BIOS Boot and discovery time; UUID prompt now has a Chinese console panel. Real Rescue still open. |
| P0-4 | VIRTUALLY_VERIFIED | Restored byte count was assumed; only all-zero data tested | Actual decompressed counter, mixed data, interruption/short-read, raw fallback and SHA; 39/39 fault tests. Real SSH still open. |
| P0-5 | VIRTUALLY_VERIFIED | Final authorization panel was invisible on the console even though its text existed | Panel now goes through the verified tty1 fd with timeout and markers, and a QEMU case proves the rendered Chinese panel and data-loss warning by PSF glyph matching (25 assertions). Real disk not used. |
| P1-1 | VIRTUALLY_VERIFIED | Netplan matched only `en*` | `e*` covers `eth0`, `enp3s0`, `en*`, r8169; networkd and cloud-init handling tested. Real NIC still open. |
| P1-2 | VIRTUALLY_VERIFIED | Offline repair simulation did not exercise adaptation | Loop ext4 adaptation and update-grub rollback 15/15. Real Ubuntu boot still open. |
| P1-3 | VIRTUALLY_VERIFIED | No virtual tests for Xray bad config, Tailscale wait, network failure | Xray/Rescue/Restored/Tailscale suite 17/17, mock only. Real network still open. |
| P1-4 | OPEN | Real hardware checks not performed | User must run on target hardware; see `docs/PAW-V2.7-HARDWARE-CHECKLIST-ZH.md`; reports remain unverified until then. |
| BUILD | PASS (historical) | Run `42804949796` success on `bf1a705`, artifact ID `13760370816` | ISO 953,155,584 bytes, SHA256 `d9fe2879…fb95a4476`; artifact expires 2026-11-13 11:27:18 UTC. Not current-branch/Stage-4 evidence. |
| REPRO | OPEN | Cloud builds of the same code tree produce the same ISO size but different SHA256 (`2295eb0a…`, `17789c04…`, `2edf88a0…`, `d9fe2879…`) | Byte-for-byte reproducibility not claimed; investigate before treating a double build as a release gate. |
| CONSOLE | CLOSED (QEMU/static) | Six operator scripts printed panels to the journal only (`StandardOutput=journal`) | Panels, prompts and markers use the tty1 binding; 55 static and 15 PTY assertions pass, and the authorization panel is proven on fbcon with glyph matching. Real ASUS screen still open (see P1-4). |
| GROWPART | CLOSED (virtual) | `growpart` assumed the root partition could grow; a layout whose root is not last would only fail at runtime | `paw-gpt-expand.sh` refuses before touching the GPT when a later partition exists, says nothing was changed, and the virtual suite proves the `sfdisk` table is identical afterwards (4 new assertions). |
| GRUB-REPAIR | CLOSED (loop + target boot) / OFFLINE-REPAIR OPEN | Historical repair fixture used a compiled `grub-install` stub; `run-repair-virtual-tests.sh` runs the real host binary on loop GPT, and the Stage 2 Ubuntu target executed real `grub-install --target=i386-pc`, `update-grub` and `update-initramfs` | Full project `paw-offline-repair.sh` against the cloned target still needs a real mount/chroot run. |
| PTY-LOCAL | OPEN (environment) | Current Linux sandbox has no usable `/dev/ptmx` (`out of pty devices`); the historical Windows workstation had no `termios` | CI runs it with `PAW_REQUIRE_PTY=1`; local status stays BLOCKED, never PASS. |
| CI-CURRENT | **CLOSED** | Current branch CI succeeded at `4af304e`: Run `42825407549`, artifact `13769479260`, test ISO 953,155,584 bytes SHA256 `c34cb137...e068fb`; two prior failures and one cancelled queued run are recorded | No action; future code changes need a new Run. |
| DELIVERY | PENDING_USER | Final real-world write/boot/migration and guide review | User writes the TF card from the delivered ISO, re-hashes it, performs physical checks. |

## Hard boundaries

- Never stop, reboot, rescue, mount or otherwise touch the production VPS.
- Never write a physical disk or TF card in this cloud session.
- Never claim QEMU, mock SSH, loop devices or operator attestation as physical/cryptographic proof.
- Never upload real credentials, server addresses, UUIDs or private keys.
- `OPERATOR_CONFIRMED` is an operator observation, not a machine-verified PASS.
- A fallback tty binding (no console or redirected input) must never be reported as
  real tty1 hardware evidence.
- An ISO SHA256 must be computed from the downloaded ISO, never from an artifact
  ZIP; a ZIP hash is not an ISO hash.
- Stage 2/3/4 must use virtual disks only; no real TF card, SSD, production VPS or
  production PAW data.
