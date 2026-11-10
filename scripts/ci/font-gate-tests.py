#!/usr/bin/env python3
"""Fault-injection suite for the PAW console-font fail-closed gate.

Runs without root or a real framebuffer.  It exercises both the production
report writer (paw-console-font.sh) through a pty and the production gate
(paw-font-gate.py), then proves that each destructive entry point calls the gate.
"""
from __future__ import annotations

import argparse
import json
import os
import pty
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "scripts/ci/make-font-gate-fixture.py"
GATE = ROOT / "scripts/paw-font-gate.py"
FONT_SCRIPT = ROOT / "scripts/paw-console-font.sh"


def run(cmd: list[str], env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd, cwd=ROOT, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )


def run_gate(
    report: Path,
    manifest: Path,
    font: Path,
    *,
    tty: str = "/dev/tty1",
    boot_id: str,
) -> subprocess.CompletedProcess[str]:
    return run(
        [
            sys.executable,
            str(GATE),
            "--report",
            str(report),
            "--manifest",
            str(manifest),
            "--expected-font",
            str(font),
            "--expected-tty",
            tty,
            "--boot-id",
            boot_id,
        ]
    )


def make_fake_bin(case: Path, setfont_rc: int) -> Path:
    fake = case / "fakebin"
    fake.mkdir()
    setfont = fake / "setfont"
    setfont.write_text(
        "#!/bin/sh\n"
        "printf '%s\\n' \"$*\" >\"${FAKE_SETFONT_LOG:-/dev/null}\"\n"
        f"exit {setfont_rc}\n",
        encoding="utf-8",
    )
    kbd_mode = fake / "kbd_mode"
    kbd_mode.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    setfont.chmod(0o755)
    kbd_mode.chmod(0o755)
    return fake


def run_font_script(
    case: Path,
    fixture: dict,
    *,
    fb_present: bool,
    setfont_rc: int,
    corrupt: bool = False,
    manifest_zero: bool = False,
    missing_font: bool = False,
) -> tuple[subprocess.CompletedProcess[str], dict | None, str]:
    fonts = case / "fonts"
    shutil.copytree(fixture["outdir"], fonts)
    font = fonts / "paw-cjk-16x16.psf"
    manifest = fonts / "paw-cjk-font.json"
    report = case / "reports" / "console-font.json"
    (case / "reports").mkdir(parents=True, exist_ok=True)
    if corrupt:
        raw = bytearray(font.read_bytes())
        raw[-1] ^= 0xFF
        font.write_bytes(raw)
    if manifest_zero:
        doc = json.loads(manifest.read_text(encoding="utf-8"))
        doc["primary_font_sha256"] = "0" * 64
        manifest.write_text(json.dumps(doc), encoding="utf-8")
    if missing_font:
        font.unlink()

    fbdev = case / "fbdev"
    fbsys = case / "fbsys"
    vt = case / "vtconsole"
    if fb_present:
        fbdev.write_text("", encoding="utf-8")
        fbsys.mkdir()
        (fbsys / "name").write_text("test-fbcon\n", encoding="utf-8")
        (fbsys / "virtual_size").write_text("1024,768\n", encoding="utf-8")
        (vt / "vtcon1").mkdir(parents=True)
        (vt / "vtcon1/name").write_text("(M) frame buffer device\n", encoding="utf-8")
        (vt / "vtcon1/bind").write_text("1\n", encoding="utf-8")
    else:
        fbdev = case / "no-such-fbdev"
        fbsys = case / "no-such-fbsys"
        vt = case / "no-such-vtconsole"

    fake = make_fake_bin(case, setfont_rc)
    master = slave = None
    try:
        master, slave = pty.openpty()
        tty_name = os.ttyname(slave)
    except OSError:
        # Some agent/CI sandboxes deny /dev/ptmx.  The production script only
        # needs a character device and the fake setfont never writes to it, so
        # /dev/tty1 is a valid local fallback.
        tty_name = os.environ.get("PAW_TEST_TTY", "/dev/tty1")
        if not os.path.exists(tty_name):
            raise
    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{fake}:{env.get('PATH', '/usr/bin:/bin')}",
            "PAW_ROOT": str(ROOT),
            "PAW_INTERACTIVE_TTY": tty_name,
            "PAW_FONT_DIR": str(fonts),
            "PAW_FONT_MANIFEST": str(manifest),
            "PAW_REPORT_DIR": str(case / "reports"),
            "PAW_STATE_DIR": str(case / "state"),
            "PAW_CONSOLE_FONT_REPORT": str(report),
            "PAW_FBCON_DEVICE": str(fbdev),
            "PAW_FB_SYSFS_DIR": str(fbsys),
            "PAW_VTCONSOLE_DIR": str(vt),
            "PAW_FONT_WAIT_SECONDS": "1",
            "FAKE_SETFONT_LOG": str(case / "setfont.log"),
        }
    )
    result = run(["bash", str(FONT_SCRIPT)], env)
    if master is not None:
        os.close(master)
    if slave is not None:
        os.close(slave)
    document = None
    if report.is_file():
        document = json.loads(report.read_text(encoding="utf-8"))
    return result, document, tty_name


def expect(condition: bool, label: str, report: list[str], failures: list[str]) -> None:
    if condition:
        report.append(f"PASS {label}")
    else:
        report.append(f"FAIL {label}")
        failures.append(label)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("artifacts"))
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    work = ROOT / "tests/virtual/font-gate-run"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    result = run([sys.executable, str(FIXTURE), str(work / "fixture")])
    if result.returncode != 0:
        print(result.stdout, result.stderr, sep="\n")
        return 2
    fixture = json.loads(result.stdout)
    boot_id = fixture["boot_id"]
    report: list[str] = [
        "PAW console-font fail-closed gate fault injection",
        f"Executed: {sys.argv[0]}",
    ]
    failures: list[str] = []

    # 1. Valid production writer output on fbcon must pass the production gate.
    case = work / "case-pass"
    proc, document, tty = run_font_script(case, fixture, fb_present=True, setfont_rc=0)
    expect(proc.returncode == 0 and document is not None, "PASS fixture: setfont exits 0", report, failures)
    expect(
        document is not None
        and document.get("status") == "PASS"
        and document.get("mode") == "fbcon"
        and document.get("fbcon_bound") is True,
        "PASS report records fbcon 16x16",
        report,
        failures,
    )
    gate = run_gate(
        case / "reports/console-font.json",
        case / "fonts/paw-cjk-font.json",
        case / "fonts/paw-cjk-16x16.psf",
        tty=tty,
        boot_id=boot_id,
    )
    expect(gate.returncode == 0, "PASS report opens the write gate", report, failures)

    # 2. vgacon fallback must be WARN and must not open the gate.
    case = work / "case-fallback"
    proc, document, tty = run_font_script(case, fixture, fb_present=False, setfont_rc=0)
    expect(proc.returncode == 0, "fallback writer exits 0 for diagnostics", report, failures)
    expect(
        document is not None
        and document.get("status") == "WARN"
        and document.get("mode") == "vgacon-fallback",
        "8x16 fallback is WARN, not PASS",
        report,
        failures,
    )
    gate = run_gate(
        case / "reports/console-font.json",
        case / "fonts/paw-cjk-font.json",
        case / "fonts/paw-cjk-16x16.psf",
        tty=tty,
        boot_id=boot_id,
    )
    expect(gate.returncode == 2, "WARN fallback is refused by the write gate", report, failures)

    # 3. Missing font.
    case = work / "case-missing-font"
    proc, document, tty = run_font_script(
        case, fixture, fb_present=True, setfont_rc=0, missing_font=True
    )
    expect(proc.returncode == 1 and document is not None and document.get("status") == "FAIL",
           "missing font writes FAIL and exits non-zero", report, failures)
    gate = run_gate(
        case / "reports/console-font.json",
        case / "fonts/paw-cjk-font.json",
        case / "fonts/paw-cjk-16x16.psf",
        tty=tty,
        boot_id=boot_id,
    )
    expect(gate.returncode == 2, "missing font is refused by the write gate", report, failures)

    # 4. Corrupt font bytes.
    case = work / "case-corrupt-font"
    proc, document, tty = run_font_script(
        case, fixture, fb_present=True, setfont_rc=0, corrupt=True
    )
    expect(proc.returncode == 1 and document is not None and document.get("status") == "FAIL",
           "corrupt font writes FAIL and exits non-zero", report, failures)
    gate = run_gate(
        case / "reports/console-font.json",
        case / "fonts/paw-cjk-font.json",
        case / "fonts/paw-cjk-16x16.psf",
        tty=tty,
        boot_id=boot_id,
    )
    expect(gate.returncode == 2, "corrupt font is refused by the write gate", report, failures)

    # 5. Manifest hash mismatch.
    case = work / "case-hash-mismatch"
    proc, document, tty = run_font_script(
        case, fixture, fb_present=True, setfont_rc=0, manifest_zero=True
    )
    expect(proc.returncode == 1 and document is not None and document.get("status") == "FAIL",
           "manifest hash mismatch writes FAIL", report, failures)
    gate = run_gate(
        case / "reports/console-font.json",
        case / "fonts/paw-cjk-font.json",
        case / "fonts/paw-cjk-16x16.psf",
        tty=tty,
        boot_id=boot_id,
    )
    expect(gate.returncode == 2, "manifest hash mismatch is refused by the gate", report, failures)

    # 6. setfont failure.
    case = work / "case-setfont-fail"
    proc, document, tty = run_font_script(case, fixture, fb_present=True, setfont_rc=1)
    expect(proc.returncode == 1 and document is not None and document.get("status") == "FAIL",
           "setfont failure writes FAIL", report, failures)
    gate = run_gate(
        case / "reports/console-font.json",
        case / "fonts/paw-cjk-font.json",
        case / "fonts/paw-cjk-16x16.psf",
        tty=tty,
        boot_id=boot_id,
    )
    expect(gate.returncode == 2, "setfont failure is refused by the gate", report, failures)

    # 7-13. Direct gate mutations.
    base_report = work / "fixture/console-font.json"
    base_manifest = work / "fixture/paw-cjk-font.json"
    base_font = work / "fixture/paw-cjk-16x16.psf"
    base_doc = json.loads(base_report.read_text(encoding="utf-8"))

    def mutate(name: str, change) -> tuple[Path, dict]:
        document = dict(base_doc)
        change(document)
        path = work / f"gate-{name}.json"
        path.write_text(json.dumps(document), encoding="utf-8")
        return path, document

    gate = run_gate(work / "does-not-exist.json", base_manifest, base_font, boot_id=boot_id)
    expect(gate.returncode == 2, "missing report is refused", report, failures)

    path, _ = mutate("stale-boot", lambda d: d.update(boot_id="stale-boot-id"))
    gate = run_gate(path, base_manifest, base_font, boot_id=boot_id)
    expect(gate.returncode == 2, "stale boot_id report is refused", report, failures)

    path, _ = mutate("warn", lambda d: d.update(status="WARN"))
    gate = run_gate(path, base_manifest, base_font, boot_id=boot_id)
    expect(gate.returncode == 2, "WARN status is refused", report, failures)

    path, _ = mutate("vgacon", lambda d: d.update(mode="vgacon-fallback"))
    gate = run_gate(path, base_manifest, base_font, boot_id=boot_id)
    expect(gate.returncode == 2, "vgacon mode is refused even with PASS status", report, failures)

    path, _ = mutate("no-fbcon", lambda d: d.update(fbcon_bound=False))
    gate = run_gate(path, base_manifest, base_font, boot_id=boot_id)
    expect(gate.returncode == 2, "unbound fbcon is refused", report, failures)

    path, _ = mutate("setfont", lambda d: d.update(setfont_exit_code=1))
    gate = run_gate(path, base_manifest, base_font, boot_id=boot_id)
    expect(gate.returncode == 2, "non-zero setfont report is refused", report, failures)

    path, _ = mutate("fallback-font", lambda d: d.update(font=str(work / "fixture/paw-cjk-8x16.psf")))
    gate = run_gate(path, base_manifest, base_font, boot_id=boot_id)
    expect(gate.returncode == 2, "8x16 font path is refused as primary", report, failures)

    gate = run_gate(base_report, work / "missing-manifest.json", base_font, boot_id=boot_id)
    expect(gate.returncode == 2, "missing manifest is refused", report, failures)

    # Static integration: every destructive entry path must call the gate.
    static_files = {
        "scripts/paw-final-confirm.sh": "require_console_font_pass",
        "scripts/paw-prepare-data-partition.sh": "require_console_font_pass",
        "scripts/paw-lib.sh": "require_console_font_pass",
    }
    for relative, needle in static_files.items():
        text = (ROOT / relative).read_text(encoding="utf-8")
        expect(needle in text, f"{relative} calls the font gate", report, failures)
    unit = (ROOT / "boot/paw-console-font.service").read_text(encoding="utf-8")
    before_lines = [line.strip() for line in unit.splitlines() if line.strip().startswith("Before=")]
    expect(
        bool(before_lines)
        and "paw-data-init.service" in before_lines[0]
        and "paw-console.service" in before_lines[0],
        "font unit is ordered before PAWDATA and console menu",
        report,
        failures,
    )

    assertions = sum(1 for line in report if line.startswith(("PASS ", "FAIL ")))
    report.append(f"Summary: {assertions} assertions, {len(failures)} failed")
    (out / "font-gate-test-report.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
    print("\n".join(report))
    shutil.rmtree(work, ignore_errors=True)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
