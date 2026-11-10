# Run 42857316370 evidence (text and decoded screens)

Copied from the text artifact `paw-test-reports` (ID `13785706107`, 567,106 bytes,
expires 2026-11-13 17:09:40 UTC) of run
<https://github.com/riser-lang/paw-migration-kit/actions/runs/42857316370> on head
`adb3e16`.

This run added `artifacts/qemu-cjk/**` to the text artifact, so the screendumps travelled
with the reports. Totals are unchanged: repair 28/28 (boot chain included), fault
injection 39, PAWDATA 12, network 17, finalize 36, TTY 56, CJK 5 cases / 96 assertions.

What is here: the report files, the PTY log, the per-case QEMU logs and the 25 decoded
screens in `decoded-screens/` (`<case>-screen-<name>.txt`), which are the cell-by-cell
decodes the suite compared against the PSF glyphs.

What is deliberately NOT here:

- `qemu-cjk/<case>/screen-*.ppm` — 73 MB of raw framebuffers; five of them were
  transcoded to PNG and live in the delivery folder `screens/`.
- `qemu-cjk/<case>/serial.log` and `result.json` — verbatim CI logs containing
  systemd lines that look like e-mail addresses and a canonical UUID from the kernel
  command line. The public-safety gate refuses those, so they are excluded, not edited.

Scope reminder: QEMU, loop devices, bind mounts and mocks only. No production VPS,
physical disk or TF card was touched.
