# PAW Migration State

Updated: 2026-11-10 UTC (second takeover round)
Branch: `fix/v2.6.2-final-readiness`
Branch HEAD: `2c2a37d` (Bind the Rescue source-UUID prompt to the verified tty1 path)
Main HEAD: `0d6aefd` (unchanged; development never restarted from `main`)
PR: #2 (Draft, not merged); #1 untouched

## Phase

- Phase 1: repository and environment takeover — complete.
- Phase 2: P0 blockers — implemented and virtually verified.
- Phase 3: P1 adaptation — implemented and virtually verified; real hardware pending.
- Phase 4: cloud build — PASS.
- Phase 5: expanded virtual test matrix — PASS.
- Phase 6: public security audit and delivery package — current; operator console
  binding defect found and fixed in this round.

## Operator console binding (this round)

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

## Final cloud evidence

- Run: <https://github.com/riser-lang/paw-migration-kit/actions/runs/42778468039>
  (HEAD `2c2a37d`, success, 20m37s)
- Artifact ID: `13744904698`, `paw-live-build-test-results`, 1,009,075,181 bytes
- Artifact expiry: 2026-11-13 08:14:16 UTC
- ISO: `paw-live-amd64.iso`, 953,155,584 bytes
- ISO SHA256: `17789c0444d6f8bac0ef24aa7d6a68871e1dfedb2d7b3fe0c50355288a6e0363`
- ISO layout: `MBR isohybrid cyl-align-on GPT APM`
- Test totals: PAWDATA 12, fault injection 35, offline repair 15, network 17,
  finalize 36, TTY 56 (static 55 + PTY 15 with the aggregate row), CJK font 1,
  QEMU CJK 4 cases / 71 assertions — all 0 failed.
- Static: ShellCheck `--severity=error` clean, `bash -n` clean, Python compile PASS,
  PowerShell parse PASS, JSON/YAML/unit structure PASS, `PUBLIC-SAFETY=PASS`,
  `PUBLIC-HISTORY=PASS` (627 reachable Git objects), `ENTRYPOINTS=21 MISSING=0`.
- QEMU SeaBIOS 1.16 + TCG (no KVM): boot reached the readiness gate, readiness
  `BLOCKED`, `clone_started=false`.

## Independently verified in this round

- ISO from Run `42747871471` was downloaded through an explicit proxy and re-hashed:
  computed `2295eb0a8d9d61b93be3e91cfeee735c42529ed3223cbf14593047104939336d`
  equals the uploaded sidecar; ISO `953,155,584` bytes.
- Local `bash -n` over all shell scripts on the new workstation: PASS.
- Local TTY static assertions: 55 passed / 0 failed.
- Two builds produced the same ISO byte size but different SHA256, so
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

1. Download Artifact `13744904698` from Run `42778468039` before
   2026-11-13 08:14:16 UTC (or use the ISO already downloaded to the workstation).
2. Recompute ISO SHA256 and compare with `17789c04…6e0363`.
3. Write the TF card only after reviewing `docs/PAW-V2.7.1-USER-GUIDE-ZH.md` and
   `docs/PAW-V2.7-ROLLBACK-ZH.md`.
4. Perform physical boot, Memtest, SSD and Rescue checks; keep those results
   separate from cloud/virtual results.
