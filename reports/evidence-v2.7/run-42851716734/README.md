# Run 42851716734 evidence (text only)

Copied verbatim from the text-only artifact `paw-test-reports` (ID `13782402242`,
18,576 bytes, expires 2026-11-13 16:34:22 UTC) of run
<https://github.com/riser-lang/paw-migration-kit/actions/runs/42851716734> on head
`6554c06`.

This run validates the delivery self-check tooling: it is the first run that includes
`scripts/verify-delivery.ps1` in the PowerShell parse gate, which reports
`PowerShell parse PASS (2 files)` and `POWERSHELL_PARSE_ERRORS=0`.

Suite totals are unchanged from the previous verification run (repair 28/28 including the
boot chain, fault injection 39, PAWDATA 12, network 17, finalize 36, TTY 56, CJK 5 cases /
96 assertions), and `PUBLIC-HISTORY=PASS` scanned 940 objects.

Scope reminder: QEMU, loop devices, bind mounts and mocks only. No production VPS,
physical disk or TF card was touched.
