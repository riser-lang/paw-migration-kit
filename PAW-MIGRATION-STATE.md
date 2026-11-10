# PAW Migration State

Updated: 2026-11-10 UTC (second takeover round)
Branch: `fix/v2.6.2-final-readiness`

Two heads matter, and neither is `main`:

- **Product head / delivery ISO**: `bf1a705` — every production script inside the
  delivered ISO comes from this commit.
- **Latest verification head**: `6554c06` — adds CI suites (real `grub-install`
  host-side and in chroot, a QEMU boot of a repaired disk), a text-only evidence
  artifact, and the delivery self-check script. No production script or ISO input
  changed.

`main` HEAD stays `0d6aefd`; development never restarted from `main`.
PR #2 is a Draft and is not merged; PR #1 was not touched.

## Evidence mapping

The delivered ISO, its SHA256 and all runtime test counts come from Run
`42804949796` on product head `bf1a705`. Runs `42810087226` (`d640712`), `42816492016` (`b4bfd84`), `42838392058` (`daef72f`)
`42845816766` (`e4ec96c`) and `42851716734` (`6554c06`) re-ran the whole matrix with the new GRUB suites and are green too; they rebuilt the
ISO from an identical product payload, which is why they report the same byte size and
different SHA256 values (builds are not byte-reproducible).

The delivery ISO is therefore kept from Run `42804949796`: shipping a fresh hash for
an unchanged payload would only make verification ambiguous. Documentation commits
after the heads are checked locally with the same scripts CI runs
(`check-public-safety.py`, `check-public-history.py`, `bash -n`, Python compile, TTY
static assertions).

## Phase

- Phase 1: repository and environment takeover — complete.
- Phase 2: P0 blockers — implemented and virtually verified.
- Phase 3: P1 adaptation — implemented and virtually verified; real hardware pending.
- Phase 4: cloud build — PASS.
- Phase 5: expanded virtual test matrix — PASS.
- Phase 6: public security audit and delivery package — complete for the
  cloud/virtual scope; real hardware still unverified.

## Operator console binding

`paw-console.service` runs with `StandardOutput=journal`. Six operator scripts still
printed their panels with bare `printf`, so the panels reached the journal and never
the physical console: final authorization (including the data-loss warning), Memtest
confirmation, target-SSD candidate list and serial, Rescue public key and host-key
fingerprint, network phase meaning, and the Rescue source UUID prompt.

Fixed by `paw_tty_open_optional()` plus `paw_tty_say/paw_tty_prompt/paw_tty_read/
paw_tty_read_secret` with a 300 s timeout and explicit ASCII markers. Fallback to
inherited stdio is used only when no console is present or input is redirected, is
logged, and is never recorded as a tty1 session. `paw-data-prepare.sh` keeps the
strict binding.

The authorization panel also has pixel-level evidence: QEMU case `final` runs the
production `paw-final-confirm.sh` twice on tty1 (wrong suffix rejected, correct
suffix accepted) and matches the screendump against the shipped PSF glyphs
(25 assertions).

## GPT expansion guard

`growpart` can only take free space that follows a partition. A cloned layout whose
root partition sits before another partition could never be expanded, and the only
symptom would have been a cryptic `growpart` failure after `sgdisk
--move-second-header` had already modified the GPT.

`paw-gpt-expand.sh` now compares the root partition's `lsblk` START offset with the
highest partition offset on the disk and refuses *before* touching anything, naming
the collision and stating that nothing was changed. The virtual suite builds a
two-partition GPT loop, expects the refusal, checks both message claims, and asserts
the `sfdisk` dump is byte-identical afterwards.

## Real GRUB install evidence

The offline-repair *rollback* fixture replaces `grub-install` with a compiled stub, so
"GRUB repair" only had simulated evidence. Two loop cases now exercise the real binary:

1. **Host side** — a loop GPT disk with a BIOS boot partition plus an ext4 root, then
   `grub-install --target=i386-pc --boot-directory=... /dev/loopN`. Asserts: exit 0,
   `i386-pc` modules copied, MBR boot code with a valid `0x55AA` signature, and a
   non-empty embedded core image in the BIOS boot partition.
2. **Chroot variant** — the same disk shape with `/boot`, a minimal `grub.cfg`, and
   host binaries/GRUB modules supplied through read-only bind mounts, then the command
   form the production script uses inside the repaired root:
   `chroot ROOT grub-install --target=i386-pc --recheck /dev/loopN`. Asserts: exit 0,
   modules copied into the fixture `/boot`, MBR boot code with `0x55AA`.

Together these prove both install shapes install BIOS GRUB on a GPT loop disk with the
real binary. Neither replaces a real target disk, and a real first boot from a repaired
disk is still unverified.

## Repaired-disk boot chain evidence

Installing GRUB correctly is not the same as booting from it, so the repair suite now
closes the last link: a 320 MiB loop GPT disk gets the ISO kernel and initrd in `/boot`
with a minimal `grub.cfg`, GRUB is installed host-side, and QEMU SeaBIOS then boots
**that disk alone** (no ISO attached, IDE interface).

Assertions (all PASS in Run `42838392058`): the ISO kernel and initrd were located, GRUB
installed with exit 0, the kernel version line appeared on `ttyS0` (GRUB executed the
kernel), the kernel processed the initrd, no kernel panic occurred, and the boot reached
the initramfs stage.

Earlier attempts are recorded, not hidden: `42821382664` booted a virtio disk that
SeaBIOS did not enumerate and swallowed the `grub-install` exit code; `42827723019`
added the diagnostics and then reported a false negative because `quiet` suppressed the
two kernel lines even though the serial log showed the `(initramfs)` prompt;
`42833112745` passed five of six assertions because kernel 6.12 does not print
"Unpacking initramfs".

Scope: the fixture is a stand-in for a repaired target disk. It proves the boot chain
with the real GRUB and a real kernel; it does not prove that a repaired real Ubuntu root
boots to a login prompt.

## Final cloud evidence

- Delivery run: <https://github.com/riser-lang/paw-migration-kit/actions/runs/42804949796>
  (product head `bf1a705`, success)
- Verification run: <https://github.com/riser-lang/paw-migration-kit/actions/runs/42810087226>
  (`6554c06`, success, repair suite 28/28)
- Delivery artifact: `13760370816`, `paw-live-build-test-results`, 1,030,665,391 bytes,
  expires 2026-11-13 11:27:18 UTC
- Verification artifacts (run 17): `13782402242` `paw-test-reports` 18,576 bytes, and
  `13781194823` `paw-live-build-test-results` 1,030,666,224 bytes, expires 2026-11-13 16:34:11 UTC
- ISO: `paw-live-amd64.iso`, 953,155,584 bytes
- ISO SHA256: `d9fe28799f9c18d1ec69900b66ea0c71d70b232c5e62a0c4ab0e902fb95a4476`
- ISO layout: `MBR isohybrid cyl-align-on GPT APM`
- Test totals (verification run): PAWDATA 12, fault injection 39, offline repair **28**,
  network 17, finalize 36, TTY 56 (static 55 + PTY 15 with the aggregate row),
  CJK font 1, QEMU CJK 5 cases / 96 assertions — all 0 failed.
- Static: ShellCheck `--severity=error` clean, `bash -n` clean, Python compile PASS,
  PowerShell parse PASS, JSON/YAML/unit structure PASS, `PUBLIC-SAFETY=PASS`,
  `PUBLIC-HISTORY=PASS` (940 reachable Git objects), `ENTRYPOINTS=21 MISSING=0`.
- QEMU SeaBIOS + TCG (no KVM): boot reached the readiness gate, readiness
  `BLOCKED`, `clone_started=false`.

## Independently verified in this round

- ISO from Run `42804949796` (the delivery artifact) was downloaded (1,030,665,391
  bytes) and re-hashed to
  `d9fe28799f9c18d1ec69900b66ea0c71d70b232c5e62a0c4ab0e902fb95a4476`, matching its
  sidecar; the delivered copy was re-hashed again after the move.
- ISO from Run `42795953493` was downloaded (1,030,664,775 bytes) and re-hashed to
  `2edf88a09684ebbb88680c79a73a29ea77fbc794aa168243649b2b67b2fc20ed`, matching its
  sidecar.
- ISO from Run `42778468039` was downloaded (1,009,075,181 bytes) and re-hashed to
  `17789c0444d6f8bac0ef24aa7d6a68871e1dfedb2d7b3fe0c50355288a6e0363`, matching its
  sidecar.
- ISO from Run `42747871471` was downloaded and re-hashed to
  `2295eb0a8d9d61b93be3e91cfeee735c42529ed3223cbf14593047104939336d`, matching its
  sidecar.
- Local `bash -n` over all shell scripts on the new workstation: PASS (0 failures).
- Local TTY static assertions: 55 passed / 1 failed, the failure being the PTY case
  that cannot run on Windows (`ModuleNotFoundError: No module named 'termios'`).
- Local `scripts/ci/check-public-safety.py`: `PUBLIC-SAFETY=PASS`.
- Local `scripts/ci/check-public-history.py`: `PUBLIC-HISTORY=PASS` on the branch tip.
- Local Python source compile over `scripts/**/*.py` and `tests/qemu/*.py`: PASS.
- `scripts/windows-static-check.ps1` was **not** run locally: the host has Windows
  PowerShell 5.1 but no `pwsh`, so that parse check remains CI-only.
- Nine builds produced the same ISO byte size but different SHA256 values, so
  byte-for-byte reproducibility is still unproven.

## Not verified

- Real TF card write and read-back.
- Real ASUS motherboard/SeaBIOS boot, real keyboard and display.
- Real SSD SMART/read scan/temperature.
- Real Tencent Cloud Rescue Mode SSH.
- Real full-disk clone and real PAW migration.
- Physical Memtest86+ run and operator observation.
- A real system boot (Ubuntu root to login) from a disk repaired by the offline repair path.
- Local PTY execution on the Windows workstation (no `termios`); CI covers it.

These remain open until the user performs them on hardware. No production VPS was
accessed; no physical disk or TF card was written.

## Delivery package self-check

`scripts/verify-delivery.ps1` (Windows PowerShell 5.1, because the host has no `pwsh`)
verifies the delivered folder: ISO size against 953,155,584, ISO SHA256 against
`paw-live-amd64.iso.sha256`, and every line of `SHA256SUMS.txt`.

Verified on this workstation, on the real folder: `DELIVERY=PASS (23 checks)`. A
negative test was run too — one tampered file in a copied folder produced
`DELIVERY=FAIL` and exit code 1, so the checker is not a rubber stamp.

The one-page entry point is `docs/PAW-START-HERE-ZH.md`: hash check first, then the three
actions that touch only the TF card, then the decisions that need the user.

## Immediate next steps for the user

1. Use the ISO at `delivery/paw-live-amd64.iso` (or download Artifact `13760370816`
   from Run `42804949796` before 2026-11-13 11:27:18 UTC).
2. Recompute ISO SHA256 and compare with `d9fe2879…fb95a4476`.
3. Follow `docs/PAW-V2.7-HARDWARE-CHECKLIST-ZH.md` step by step; it lists the exact
   screen text each step must show and what to do when it does not.
4. Keep physical results separate from cloud/virtual results.
