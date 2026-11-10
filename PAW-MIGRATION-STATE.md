# PAW Migration State

Updated: 2026-11-10 UTC (second takeover round)
Branch: `fix/v2.6.2-final-readiness`
Code HEAD covered by the final run: `91a79ea` (Prove the Chinese authorization panel
on fbcon and fix its three real test defects)
Main HEAD: `0d6aefd` (unchanged; development never restarted from `main`)
PR: #2 (Draft, not merged); #1 untouched

## Evidence mapping

The ISO, its SHA256 and every test count in this file come from Run `42795953493`
on code HEAD `91a79ea`. Any documentation commit after it changes no script,
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

## Final cloud evidence

- Run: <https://github.com/riser-lang/paw-migration-kit/actions/runs/42795953493>
  (HEAD `91a79ea`, success)
- Artifact ID: `13754343439`, `paw-live-build-test-results`, 1,030,664,775 bytes
- Artifact expiry: 2026-11-13 10:22:46 UTC
- ISO: `paw-live-amd64.iso`, 953,155,584 bytes
- ISO SHA256: `2edf88a09684ebbb88680c79a73a29ea77fbc794aa168243649b2b67b2fc20ed`
- ISO layout: `MBR isohybrid cyl-align-on GPT APM`
- Test totals: PAWDATA 12, fault injection 35, offline repair 15, network 17,
  finalize 36, TTY 56 (static 55 + PTY 15 with the aggregate row), CJK font 1,
  QEMU CJK 5 cases / 96 assertions — all 0 failed.
- Static: ShellCheck `--severity=error` clean, `bash -n` clean, Python compile PASS,
  PowerShell parse PASS, JSON/YAML/unit structure PASS, `PUBLIC-SAFETY=PASS`,
  `PUBLIC-HISTORY=PASS` (682 reachable Git objects), `ENTRYPOINTS=21 MISSING=0`.
- QEMU SeaBIOS + TCG (no KVM): boot reached the readiness gate, readiness
  `BLOCKED`, `clone_started=false`.

## Independently verified in this round

- ISO from Run `42778468039` was downloaded (1,009,075,181 bytes) and re-hashed:
  computed `17789c0444d6f8bac0ef24aa7d6a68871e1dfedb2d7b3fe0c50355288a6e0363`
  equals the uploaded sidecar; ISO `953,155,584` bytes.
- ISO from Run `42747871471` was downloaded and re-hashed the same way:
  `2295eb0a8d9d61b93be3e91cfeee735c42529ed3223cbf14593047104939336d` equals its sidecar.
- ISO from Run `42795953493` (the delivery artifact) was downloaded and re-hashed
  the same way; see `reports/evidence-v2.7/iso-identity-run-42795953493.txt`.
- Local `bash -n` over all shell scripts on the new workstation: PASS.
- Local TTY static assertions: 55 passed / 0 failed.
- Local `scripts/ci/check-public-safety.py`: `PUBLIC-SAFETY=PASS`.
- Three builds produced the same ISO byte size but different SHA256, so
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
   `13754343439` from Run `42795953493` before 2026-11-13 10:22:46 UTC).
2. Recompute ISO SHA256 and compare with `2edf88a0…bf2fc20ed`.
3. Write the TF card only after reviewing `docs/PAW-V2.7.1-USER-GUIDE-ZH.md` and
   `docs/PAW-V2.7-ROLLBACK-ZH.md`.
4. Perform physical boot, Memtest, SSD and Rescue checks; keep those results
   separate from cloud/virtual results.
