# PAW Migration Blockers

Updated: 2026-11-10 UTC (second takeover round)
Final green run: `42778468039` (HEAD `2c2a37d`)

| ID | Status | Blocker | Exit condition |
|---|---|---|---|
| P0-1 | VIRTUALLY_VERIFIED | Memtest86+ has a boot entry but no machine-verifiable capture | `OPERATOR_CONFIRMED` UI binds current Live boot ID and target serial; FAIL/WARN block clone; panel now actually reaches the console; not claimed as cryptographic proof. Real physical run still open. |
| P0-2 | VIRTUALLY_VERIFIED | PAWDATA previously required manual command and only supported DOS/MBR | Auto-guided MBR/GPT initialization; only new partition formatted; remount persistence; 12/12 virtual tests. Real TF card still open. |
| P0-3 | VIRTUALLY_VERIFIED | Source discovery previously required a Virtio serial number | Composite identity uses pinned SSH host key fingerprint, root UUID, unique parent, 50 GiB, GPT layout, BIOS Boot and discovery time; UUID prompt now has a Chinese console panel. Real Rescue still open. |
| P0-4 | VIRTUALLY_VERIFIED | Restored byte count was assumed; only all-zero data tested | Actual decompressed counter, mixed data, interruption/short-read, raw fallback and SHA; 35/35 fault tests. Real SSH still open. |
| P0-5 | VIRTUALLY_VERIFIED | Final authorization panel was invisible on the console even though its text existed | Panel now goes through the verified tty1 fd with timeout, markers and re-identification before authorization. Real disk not used. |
| P1-1 | VIRTUALLY_VERIFIED | Netplan matched only `en*` | `e*` covers `eth0`, `enp3s0`, `en*`, r8169; networkd and cloud-init handling tested. Real NIC still open. |
| P1-2 | VIRTUALLY_VERIFIED | Offline repair simulation did not exercise adaptation | Loop ext4 adaptation and update-grub rollback 15/15. Real Ubuntu boot still open. |
| P1-3 | VIRTUALLY_VERIFIED | No virtual tests for Xray bad config, Tailscale wait, network failure | Xray/Rescue/Restored/Tailscale suite 17/17, mock only. Real network still open. |
| P1-4 | OPEN | Real hardware checks not performed | User must run on target hardware; reports remain unverified until then. |
| BUILD | PASS | Run `42778468039` success, artifact ID `13744904698` | ISO 953,155,584 bytes, SHA256 `17789c04…6e0363`; artifact expires 2026-11-13 08:14:16 UTC. |
| REPRO | OPEN | Cloud builds of the same code tree produce the same ISO size but different SHA256 (`2295eb0a…` from `42747871471` vs `17789c04…` from `42778468039`) | Byte-for-byte reproducibility not claimed; investigate before treating a double build as a release gate. |
| CONSOLE | CLOSED (QEMU/static) | Six operator scripts printed panels to the journal only (`StandardOutput=journal`) | Panels, prompts and markers now use the tty1 binding; 55 static assertions and 15 PTY assertions pass in CI. Real ASUS screen still open (see B03). |
| PTY-LOCAL | OPEN (environment) | The new Windows workstation has no `termios`, so `pty_tty_test.py` cannot run locally | CI runs it with `PAW_REQUIRE_PTY=1`; local status stays BLOCKED, never PASS. |
| DELIVERY | PENDING_USER | Final real-world write/boot/migration and guide review | User downloads the artifact (or uses the already downloaded ISO), re-hashes it, writes the TF card, performs physical checks. |

## Hard boundaries

- Never stop, reboot, rescue, mount or otherwise touch the production VPS.
- Never write a physical disk or TF card in this cloud session.
- Never claim QEMU, mock SSH, loop devices or operator attestation as physical/cryptographic proof.
- Never upload real credentials, server addresses, UUIDs or private keys.
- `OPERATOR_CONFIRMED` is an operator observation, not a machine-verified PASS.
- A fallback tty binding (no console or redirected input) must never be reported as
  real tty1 hardware evidence.
