# PAW Migration Acceptance

Updated: 2026-11-11 UTC (PAW v2.8 pre-hardware acceptance)
Current branch: `vm/ds-prehardware-acceptance-20261111`
Current code HEAD: `a5c423f` (source_os/gpt-expand fixes on top of `b9f5c5b`)
Base: `d640712`
PR #2: Draft, not merged

## A0. P0 remediation

- [x] Memtest86+ uses the real ISOLINUX menu entry (`linux`, not `kernel`) and a
      pinned v7.20 binary; release-ISO SeaBIOS boot reached `Status: Testing`
      with `Errors: 0`, and a separate full run reached `Status: Pass`,
      `Pass: 1`, `Errors: 0`.
- [x] `paw-transaction.py` implements
      `PREPARED/AUTHORIZED/CLONING/CLONE_INCOMPLETE/CLONE_VERIFIED/REPAIRING/
      REPAIRED/EXPANDING/READY_TO_BOOT/COMPLETE/FAILED/NEEDS_MANUAL_ACTION`.
- [x] Expiry is enforced only before clone start; interrupted clone can still be
      verified/repaired/expanded under a valid authorization.
- [x] Wrong target serial returns no receipt and leaves the first 1 MiB of the
      target unchanged; correct `123456` proceeds only after source/target
      re-identification.
- [x] Source mount gate fails closed on read-write mounts, `findmnt` errors and
      malformed mountinfo; virtual source mounted read-only.
- [x] P0 suites: **26 passed, 0 failed**.
- [ ] Physical Memtest86+ observation on the ASUS DIMM (D).

## A1. P1 remediation

- [x] O_DIRECT independent target readback (`iflag=direct`) and recorded method.
- [x] NTFS/Windows Microsoft basic data disks excluded from target discovery.
- [x] Noninteractive GRUB/initramfs; `GRUB_DISABLE_OS_PROBER=true`.
- [x] initramfs module check for AHCI/r8169/filesystem.
- [x] fstab/GRUB UUID checks after repair.
- [x] HD4600 i915 classified, not treated as a physical i915 proof.
- [x] BIOS media-order guard; auto reboot blocked while PAW media is present.
- [x] firstboot split (`actual_first_boot_performed=false` pre-boot).
- [x] SMART PASS/WARN/FAIL semantics; FAIL never becomes PASS.
- [x] AHCI/r8169 hard block; `grub-pc` by-id + debconf readback; lab honestly
      records `grub-pc_not_installed` when absent.
- [x] Service identity isolation (machine-id/SSH host key/Tailscale state).
- [x] P1 suites: **23 passed, 0 failed**.

## A2. Full pre-hardware chain

- [x] Lab source rebuilt from the Ubuntu 24.04.5 cloud rootfs; `source_os` now
      reads `PRETTY_NAME=Ubuntu 24.04.5 LTS`, `VERSION_ID=24.04` from
      `/etc/os-release` and falls back to `/usr/lib/os-release`.
- [x] `source_os` no longer silently claims a version when os-release is
      missing; it emits WARN and defers to the later composite identity check.
- [x] `paw-gpt-expand.sh` reads the filesystem type via `blkid` when `lsblk`
      briefly returns an empty FSTYPE, so a non-last-root refusal reports the
      real collision reason.
- [ ] Full chain has **not** reached `CHAIN_PASS` in this segment yet. The
      previous attempt passed authorization and was killed by the outer timeout
      before clone; the rerun is in progress.

## A3. Supplement 3 — VLESS/Tailscale dual phase

- [x] Live phase: direct Tailscale first; VLESS temporary exit only after an
      explicit Chinese wizard choice and direct failure.
- [x] Xray v26.3.27 pinned SHA256
      `8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed`.
- [x] VLESS URI read from stdin only; no history/ordinary log; config 0600 tmpfs.
- [x] SOCKS5 10808 / HTTP 10809 bound to loopback only.
- [x] tailscaled proxy inherited via drop-in and `/proc/<MainPID>/environ`, not
      just the current shell.
- [x] Ephemeral Live identity separated from persistent Ubuntu identity; offline
      repair clears target `var/lib/tailscale`.
- [x] 25/25 simulated VLESS/network tests.
- [ ] Real Tailnet, VPS/VLESS, Windows peer, Exit Node (D).

## A4. Supplement 4 — Wuhan home broadband

- [x] No public IPv4 request and no router port-forward in the policy.
- [x] Management via Tailscale; SSH Tailnet/LAN only.
- [x] 443 via Serve (Tailnet) / Funnel (public edge, home side outbound).
- [x] PAW Gateway 8800 loopback/Tailnet; Xray 10808/10809 loopback.
- [x] Cloud MCPs do not assume Tailscale 的 CGNAT 私有地址段; use Funnel/existing GPT Tunnel.
- [x] Negative audit on the development host found 30 listeners and 13
      violations (11 unknown public/wildcard + 2 SSH policy); this is not a
      production PAW result.
- [ ] Real Serve/Funnel, cloud MCP, UDP 41641/3478, CGNAT/double NAT and DERP
      fallback (D).

## A5. Public repository safety

- [x] No private keys, tokens, credentials, production IPs or user account
      names in committed delivery documents; lab evidence redacts the host LAN
      address as `LAN_REDACTED`.
- [x] No production VPS/Tailscale/Funnel/Xray/Nginx/443/firewall/COS change.
- [x] No Artifact deletion and no repository visibility change.
- [x] PR #2 remains draft and unmerged; `main` unchanged.

## D. Real-world acceptance (still open)

- [ ] Real TF card written, read back and re-hashed; media identity recorded.
- [ ] Real ASUS B85M-G Plus Legacy BIOS boot and full Chinese menu.
- [ ] Real SSD SMART/read scan/temperature; real DIMM Memtest observation.
- [ ] Real Tencent Cloud Rescue Mode SSH and production source identity.
- [ ] Real full-disk clone and independent SHA256.
- [ ] Real PAW Ubuntu first boot/offline adaptation.
- [ ] Real `systemctl reboot` on hardware.
- [ ] Real Tailscale/Xray/Funnel/MCP/PAW acceptance.
- [ ] Wuhan home broadband UDP/CGNAT/DERP checks.

These require the user's physical hardware and separate authorization. Virtual,
loop, mock and QEMU results must not be marked as physical PASS.

## Overall

- P0 remediation: **PASS (virtual)**; physical Memtest/Rescue/SSD **OPEN**.
- P1 remediation: **PASS (virtual/static)**.
- Full 12 GiB pre-hardware chain: **RE-RUN IN PROGRESS**; no CHAIN_PASS claimed.
- Supplement 3: **PASS (simulated)**; real Tailnet/VPS **NEEDS_TEST**.
- Supplement 4: **DESIGN PASS**; production ports/Serve/Funnel/MCP **NEEDS_TEST**.
- Physical delivery/migration: **NOT STARTED**; old VPS remains authoritative.
