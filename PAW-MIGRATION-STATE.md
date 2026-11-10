# PAW Migration State

Updated: 2026-11-10 UTC (second takeover round)
Branch: `fix/v2.6.2-final-readiness`
Code HEAD covered by the final run: `bf1a705` (Refuse to expand a root partition that
is not the last one)
Main HEAD: `0d6aefd` (unchanged; development never restarted from `main`)
PR: #2 (Draft, not merged); #1 untouched

## Evidence mapping

The ISO, its SHA256 and every test count in this file come from Run `42804949796`
on code HEAD `bf1a705`. Any documentation commit after it changes no script,
workflow or package, so the ISO and test evidence still apply; such a commit is
checked locally with `scripts/ci/check-public-safety.py` instead of consuming
another full build, because a rebuild would produce a different ISO hash (the
build is not byte-reproducible) and would only make the delivered hash ambiguous.

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

## Final cloud evidence

- Run: <https://github.com/riser-lang/paw-migration-kit/actions/runs/42804949796>
  (HEAD `bf1a705`, success)
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

- Real TF card write and read-back.
- Real ASUS motherboard/SeaBIOS boot, real keyboard and display.
- Real SSD SMART/read scan/temperature.
- Real Tencent Cloud Rescue Mode SSH.
- Real full-disk clone and real PAW migration.
- Physical Memtest86+ run and operator observation.
- Local PTY execution on the Windows workstation (no `termios`); CI covers it.

These remain open until the user performs them on hardware. No production VPS was
accessed; no physical disk or TF card was written.

## Immediate next steps for the user

1. Use the ISO at `delivery/paw-live-amd64.iso` (or download Artifact
   `13760370816` from Run `42804949796` before 2026-11-13 11:27:18 UTC).
2. Recompute ISO SHA256 and compare with `d9fe2879…fb95a4476`.
3. Follow `docs/PAW-V2.7-HARDWARE-CHECKLIST-ZH.md` step by step; it lists the exact
   screen text each step must show and what to do when it does not.
4. Keep physical results separate from cloud/virtual results.
