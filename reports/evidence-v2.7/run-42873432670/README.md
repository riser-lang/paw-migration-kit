# Run 42873432670 evidence

Copied from the text artifact `paw-test-reports` (ID `13791479365`, 567,751 bytes) of run
<https://github.com/riser-lang/paw-migration-kit/actions/runs/42873432670> on head
`ac0813e`.

This is the first run with the ISO payload verification: `iso-payload-report.txt` shows
`Summary: 54 passed, 0 failed`, meaning the built ISO carries byte-identical copies of all
31 `paw-*.sh`, 4 `paw-*.py`, the staged boot binaries, three config templates, the env
template, nine systemd units, the mount unit, the network config and `isolinux/memtest.cfg`,
with no extra or missing `paw-*` scripts inside the image.

Everything else is unchanged and green: repair 28/28 (boot chain included), fault injection
39, PAWDATA 12, network 17, finalize 36, TTY 56, CJK 5 cases / 96 assertions.

Path to green (nothing hidden): the step failed twice first — exit 126 because the script
was committed from Windows without the exec bit, then exit 2 because `unsquashfs` cannot
create device nodes as a non-root user, then one assertion failed only because GNU
`sha256sum` prefixes output with a backslash when the file name contains one (the mount
unit is `var-lib-paw\x2dmigration.mount`).

Excluded on purpose: `qemu-cjk/**/*.ppm` (binaries; five are transcoded into the delivery
folder) and `*serial.log` / `result.json` (verbatim logs with email-looking systemd lines
and a kernel-cmdline UUID, which the public-safety gate refuses).
