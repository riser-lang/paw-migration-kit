# PAW Migration State

Updated: 2026-11-10 UTC (clean VM takeover round)
Current branch: `vm/ds-clean-handover-20261110`
Current base: `d64071251bb3075d9cb26a967dfcba6cf139250a` (latest remote
development branch, "Prove the real grub-install on a loop GPT disk instead of a
stub")
Historical evidence branch: `fix/v2.6.2-final-readiness`
Historical code HEAD covered by the last green run: `bf1a705`
Main HEAD: `0d6aefd` (unchanged; development never restarted from `main`)
PR: #2 (Draft, not merged); #1 untouched

## Current clean-takeover status

- Old PAW workspace/isolation was explicitly deleted after the fresh clone and local
  gate tests passed. Exact deleted list, retained tools and freed space:
  `reports/DS-CLEAN-ENVIRONMENT-TAKEOVER.md`.
- The new clone is `/home/agentuser/paw-migration-kit`; no old worktree or local
  modification was reused. Branch `vm/ds-clean-handover-20261110` starts at
  `d640712`.
- P0-1 is implemented: only a same-boot `paw.console-font.v2` report with
  `status=PASS`, `mode=fbcon`, `fbcon_bound=true`, the primary 16x16 PSF2,
  actual/manifest SHA256 match and `setfont_exit_code=0` opens destructive writes.
  The 8x16 vgacon fallback is `WARN` and is refused. Missing/corrupt/hash-mismatch/
  load-failure/missing/stale reports are `FAIL`/blocked. Read-only diagnostics stay
  available.
- Local gate fault injection: **26 assertions, 0 failed**. Local finalize **36/36**;
  TTY static **55/0** with 1 PTY case BLOCKED (no `/dev/ptmx`); ShellCheck/Bash/
  Python/public safety/public history PASS.
- **New-branch CI is green.** Run `42825407549` at `4af304e` succeeded:
  font-gate 26/26, CJK QEMU 25/25, PAWDATA 12/12, virtual 39/39, repair 19/19,
  network 17/17, finalize 36/36 and TTY 56/56 with 0 blocked. It followed two
  real failures (`42812469612` font-slot overflow; `42817841755` misreading
  `(M) frame buffer device`), both fixed in `d5f1a85`/`4572280`; queued Run
  `42824906347` was cancelled after the shared concurrency group blocked it.
  The green Run `42804949796` belongs to `bf1a705` and remains historical.
- The current bash channel has `NoNewPrivs=1`; `sudo -n` and loop attach remain
  unavailable locally. Root/loop tests must run in CI; local status is BLOCKED,
  never PASS.

## Evidence mapping

The ISO, its SHA256 and every test count in this file come from Run `42804949796`
on code HEAD `bf1a705`. Any documentation commit after it changes no script,
workflow or package, so the ISO and test evidence still apply; such a commit is
checked locally with `scripts/ci/check-public-safety.py` instead of consuming
another full build, because a rebuild would produce a different ISO hash (the
build is not byte-reproducible) and would only make the delivered hash ambiguous.

## Phase

- Phase 1: clean VM takeover, fresh GitHub clone, P0-1 font gate — **complete**
  locally and in CI Run `42825407549`; two real CI regressions were fixed.
- Phase 2: clone of a real Ubuntu 24.04 disk and QEMU/SeaBIOS boot from the target
  disk — **VIRTUAL_BOOT_PASS / BLOCK_CLONE_PATH_OPEN**. Actual QEMU/SeaBIOS boot,
  GPT/ext4 expansion, real GRUB/initramfs and a second seedless boot are proven;
  the project clone ran in explicit `PAW_SIMULATION=1`, and the production
  block/SSH clone plus full project offline repair remain OPEN. Evidence:
  `reports/PAW-STAGE2-REAL-UBUNTU-BOOT-20261110.md`.
- Phase 3: full migration chain with real program entry points — **OPEN**.
- Phase 4: final ISO, downloaded-artifact ISO SHA256, Chinese guide/rollback —
  **OPEN**.
- Historical cloud build (`42804949796`) and the historical virtual matrix remain
  valid for `bf1a705` only; they do not certify the new branch or Stage 2–4.

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

The authorization panel now also has pixel-level evidence: QEMU case `final` runs the
production `paw-final-confirm.sh` twice on tty1 (wrong suffix rejected, correct
suffix accepted) and matches the screendump against the shipped PSF glyphs
(25 assertions).

## GPT expansion guard

`growpart` can only take free space that follows a partition. A cloned layout whose
root partition sits before another partition could never be expanded, and the only
symptom would have been a cryptic `growpart` failure after `sgdisk
--move-second-header` had already modified the GPT.

`paw-gpt-expand.sh` now compares the root partition's `lsblk` START offset with the
highest partition offset on the disk and refuses *before* touching anything, with a
message that names the collision and states that nothing was changed. The virtual
suite builds a two-partition GPT loop, expects the refusal, checks both message
claims, and asserts the `sfdisk` dump is byte-identical afterwards.

## Historical cloud evidence (not current-branch evidence)

- Run: <https://github.com/riser-lang/paw-migration-kit/actions/runs/42804949796>
  (HEAD `bf1a705`, success; historical branch only)
- Artifact ID: `13760370816`, `paw-live-build-test-results`, 1,030,665,391 bytes
- Artifact expiry: 2026-11-13 11:27:18 UTC
- ISO: `paw-live-amd64.iso`, 953,155,584 bytes
- ISO SHA256: `d9fe28799f9c18d1ec69900b66ea0c71d70b232c5e62a0c4ab0e902fb95a4476`
- ISO layout: `MBR isohybrid cyl-align-on GPT APM`
- Test totals: PAWDATA 12, fault injection 39, offline repair 15, network 17,
  finalize 36, TTY 56 (static 55 + PTY 15 with the aggregate row), CJK font 1,
  QEMU CJK 5 cases / 96 assertions — all 0 failed.
- Static: ShellCheck `--severity=error` clean, `bash -n` clean, Python compile PASS,
  PowerShell parse PASS, JSON/YAML/unit structure PASS, `PUBLIC-SAFETY=PASS`,
  `PUBLIC-HISTORY=PASS` (728 reachable Git objects), `ENTRYPOINTS=21 MISSING=0`.
- QEMU SeaBIOS + TCG (no KVM): boot reached the readiness gate, readiness
  `BLOCKED`, `clone_started=false`.

## Independently verified in this round

- ISO from Run `42804949796` (the delivery artifact) was downloaded and re-hashed:
  see `reports/evidence-v2.7/iso-identity-run-42804949796.txt`.
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
- Local `scripts/ci/check-public-history.py`: `PUBLIC-HISTORY=PASS` on the current
  branch tip, which contains only documentation and the copied run reports on top of
  the code HEAD.
- Local Python source compile over `scripts/**/*.py` and `tests/qemu/*.py`: PASS.
- `scripts/windows-static-check.ps1` was **not** run locally: the workstation has
  Windows PowerShell 5.1 but no `pwsh`, so that parse check remains CI-only
  (`PowerShell parse PASS (1 files)` in the run log).
- Local `scripts/ci/check-public-safety.py` is the exact file CI executes, which is
  why documentation-only commits after the code HEAD are validated this way instead
  of spending another full build that would change the ISO hash.
- Four builds produced the same ISO byte size but different SHA256 values, so
  byte-for-byte reproducibility is still unproven.

## Not verified

- Stage 2 production block/SSH clone path and full project offline repair on the
  cloned target (virtual boot and real GRUB/initramfs already proven).
- Stage 3 full migration chain.
- Stage 4 final release ISO and physical media. The candidate test ISO from Run
  `42825407549` was downloaded and re-hashed from the ISO file (953,155,584 bytes,
  `c34cb137...e068fb`), not from the ZIP.
- Real TF card write and read-back.
- Real ASUS motherboard/SeaBIOS boot, real keyboard and display.
- Real SSD SMART/read scan/temperature.
- Real Tencent Cloud Rescue Mode SSH.
- Real full-disk clone and real PAW migration.
- Physical Memtest86+ run and operator observation.
- Local PTY execution on the Windows workstation (no `termios`); CI covers it.

These remain open until the user performs them on hardware. No production VPS was
accessed; no physical disk or TF card was written.

## Immediate next steps

1. Finish the P0-2 docs commit on `vm/ds-clean-handover-20261110`; record the new
   workflow_dispatch Run ID/HEAD. Do not reuse `42804949796` as current evidence.
2. Close the remaining Stage 2 gap: execute the production block/SSH clone entry
   and full `paw-offline-repair.sh` against the cloned target, then boot it again.
   The virtual Ubuntu boot, GPT/ext4 expansion, real GRUB/initramfs and seedless
   second boot are already evidenced; do not repeat them as stubs.
3. Only after Stage 2 and the full chain pass, build the final ISO, download the
   ISO artifact and recompute its SHA256 (never a ZIP hash), then update the
   Chinese guide and rollback guide.
4. Keep physical results separate from cloud/virtual results; real ASUS/TF/SSD/
   Tencent Rescue remain OPEN and require separate authorization.
