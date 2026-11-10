# PAW Migration Blockers

Updated: 2026-11-10 UTC (second takeover round)
Delivery run: `42804949796` (product head `bf1a705`)
Verification run: `42873432670` (`ac0813e`, tests-only changes)

| ID | Status | Blocker | Exit condition |
|---|---|---|---|
| P0-1 | VIRTUALLY_VERIFIED | Memtest86+ has a boot entry but no machine-verifiable capture | `OPERATOR_CONFIRMED` UI binds current Live boot ID and target serial; FAIL/WARN block clone; panel now actually reaches the console; not claimed as cryptographic proof. Real physical run still open. |
| P0-2 | VIRTUALLY_VERIFIED | PAWDATA previously required manual command and only supported DOS/MBR | Auto-guided MBR/GPT initialization; only new partition formatted; remount persistence; 12/12 virtual tests. Real TF card still open. |
| P0-3 | VIRTUALLY_VERIFIED | Source discovery previously required a Virtio serial number | Composite identity uses pinned SSH host key fingerprint, root UUID, unique parent, 50 GiB, GPT layout, BIOS Boot and discovery time; UUID prompt now has a Chinese console panel. Real Rescue still open. |
| P0-4 | VIRTUALLY_VERIFIED | Restored byte count was assumed; only all-zero data tested | Actual decompressed counter, mixed data, interruption/short-read, raw fallback and SHA; 39/39 fault tests. Real SSH still open. |
| P0-5 | VIRTUALLY_VERIFIED | Final authorization panel was invisible on the console even though its text existed | Panel now goes through the verified tty1 fd with timeout and markers, and a QEMU case proves the rendered Chinese panel and data-loss warning by PSF glyph matching (25 assertions). Real disk not used. |
| P1-1 | VIRTUALLY_VERIFIED | Netplan matched only `en*` | `e*` covers `eth0`, `enp3s0`, `en*`, r8169; networkd and cloud-init handling tested. Real NIC still open. |
| P1-2 | VIRTUALLY_VERIFIED | Offline repair simulation did not exercise adaptation | Loop ext4 adaptation and update-grub rollback 15/15, plus real `grub-install` in both host-side and chroot shape on a GPT loop disk and a QEMU boot of the repaired disk (see GRUB-REPAIR and BOOT-CHAIN), 28/28. Real Ubuntu boot still open. |
| P1-3 | VIRTUALLY_VERIFIED | No virtual tests for Xray bad config, Tailscale wait, network failure | Xray/Rescue/Restored/Tailscale suite 17/17, mock only. Real network still open. |
| P1-4 | OPEN | Real hardware checks not performed | User must run on target hardware; see `docs/PAW-V2.7-HARDWARE-CHECKLIST-ZH.md`; reports remain unverified until then. |
| BUILD | PASS | Run `42909076510` success (head `507b25a`), artifacts `13808328141` (`paw-live-build-test-results`, 1,007,613,856 bytes) and `13807334107` (`paw-test-reports`, 634,309 bytes) | ISO 930,086,912 bytes, SHA256 `43488236…a34fe39939f`; artifact retained 3 days. |
| PAYLOAD | CLOSED (ISO contains the reviewed sources) | `scripts/ci/verify-iso-payload.sh` reads the built ISO back, extracts `/live/filesystem.squashfs` and compares every payload file with the repository. Verification run `42873432670`: `Summary: 54 passed, 0 failed` — 31 `paw-*.sh`, 4 `paw-*.py`, the staged boot binaries, three config templates, the env template, nine systemd units, the mount unit, the network config and `isolinux/memtest.cfg`, plus a check that the ISO has no extra or missing `paw-*` script and that the generated font carries the PSF2 magic. | This closes "is the shipped ISO built from the reviewed tree?" for the code payload. It does **not** prove byte-reproducibility (REPRO stays OPEN) and says nothing about the hardware items. |
| REPRO | CLOSED (same builder image) | Cloud builds of the same code tree produced the same ISO size but different SHA256 twelve times (`2295eb0a…` … `a1fadaa1…`). The `double_build` probe narrowed it in four runs: 57,134,346 differing bytes with `/etc/nvme/hostid` as the first real difference (`42892095324`); 76,801 bytes and a single remaining entry `/var/cache/apt/pkgcache.bin` after removing build-host identifiers (`42897613270`); the cache reappeared because a later build step runs apt again (`42903949395`); then the hook wrote `/etc/apt/apt.conf.d/99-paw-no-cache` so apt never creates a cache file, and run `42909076510` reported `VERDICT: REPRO=IDENTICAL` — both builds 930,086,912 bytes, SHA256 `43488236…a34fe39939f`, `diff_raw_lines=0`, `differing_entries=0`. | Two consecutive builds on one `ubuntu-24.04` image are byte-identical, so the delivered ISO is now reproducible in the environment that produced it. Not claimed: reproducibility across runner image versions or across dates — that needs a second-day run. The delivery instructions still say to compare against the sidecar from the same run. |
| CONSOLE | CLOSED (QEMU/static) | Six operator scripts printed panels to the journal only (`StandardOutput=journal`) | Panels, prompts and markers use the tty1 binding; 55 static and 15 PTY assertions pass, and the authorization panel is proven on fbcon with glyph matching. Real ASUS screen still open (see P1-4). |
| GROWPART | CLOSED (virtual) | `growpart` assumed the root partition could grow; a layout whose root is not last would only fail at runtime | `paw-gpt-expand.sh` refuses before touching the GPT when a later partition exists, says nothing was changed, and the virtual suite proves the `sfdisk` table is identical afterwards (4 new assertions). |
| GRUB-REPAIR | CLOSED for both install shapes | Offline repair still replaces `grub-install` with a compiled stub inside its rollback fixture | Two loop cases run the real binary: host-side (`--boot-directory`) and chroot (`chroot ROOT grub-install --target=i386-pc --recheck LOOP`), asserting exit 0, copied `i386-pc` modules, MBR boot code with `0x55AA`, and an embedded core image. |
| BOOT-CHAIN | CLOSED (QEMU, ISO kernel) | Nothing proved that a disk GRUB installed into actually boots | QEMU SeaBIOS boots the repaired loop disk alone; the kernel version line, initrd processing, the initramfs stage and the absence of a kernel panic are all asserted. A real Ubuntu root booting to login is still unverified. |
| PTY-LOCAL | OPEN (environment) | The new Windows workstation has no `termios`, so `pty_tty_test.py` cannot run locally | CI runs it with `PAW_REQUIRE_PTY=1`; local status stays BLOCKED, never PASS. |
| DELIVERY | PENDING_USER | Final real-world write/boot/migration and guide review | User writes the TF card from the delivered ISO, re-hashes it, performs physical checks. |

## Hard boundaries

- Never stop, reboot, rescue, mount or otherwise touch the production VPS.
- Never write a physical disk or TF card in this cloud session.
- Never claim QEMU, mock SSH, loop devices or operator attestation as physical/cryptographic proof.
- Never upload real credentials, server addresses, UUIDs or private keys.
- `OPERATOR_CONFIRMED` is an operator observation, not a machine-verified PASS.
- A fallback tty binding (no console or redirected input) must never be reported as
  real tty1 hardware evidence.
