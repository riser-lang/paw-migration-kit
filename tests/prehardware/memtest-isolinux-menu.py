#!/usr/bin/env python3
"""Boot the release ISO through SeaBIOS/ISOLINUX and select Memtest86+.

This is intentionally a real menu-selection test: the ISO is attached as a CD,
the QEMU console starts at the ISOLINUX menu, and the script sends Home + three
Down keys + Enter.  It fails unless the Memtest86+ banner appears in the serial
log.  No -kernel shortcut is used.
"""
from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import time

QEMU = os.environ.get(
    "PAW_QEMU",
    "/home/agentuser/tools/qemu-portable-20261110/sysroot/usr/bin/qemu-system-x86_64",
)
LIB = os.environ.get(
    "PAW_QEMU_LIB",
    "/home/agentuser/tools/qemu-portable-20261110/sysroot/usr/lib/x86_64-linux-gnu",
)
MOD = os.environ.get(
    "PAW_QEMU_MODULE_DIR",
    "/home/agentuser/tools/qemu-portable-20261110/sysroot/usr/lib/x86_64-linux-gnu/qemu",
)
DATA = os.environ.get(
    "PAW_QEMU_DATA",
    "/home/agentuser/tools/qemu-portable-20261110/share-merged",
)


class QMP:
    def __init__(self, path: str, timeout: float = 30.0) -> None:
        deadline = time.time() + timeout
        last = None
        while time.time() < deadline:
            try:
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.connect(path)
                break
            except OSError as exc:  # noqa: BLE001
                last = exc
                time.sleep(0.2)
        else:
            raise RuntimeError(f"cannot connect QMP socket {path}: {last}")
        self.file = self.sock.makefile("rwb", buffering=0)
        self._read()
        self.command("qmp_capabilities")

    def _read(self):
        while True:
            line = self.file.readline()
            if not line:
                raise RuntimeError("QMP socket closed")
            try:
                return json.loads(line.decode("utf-8"))
            except json.JSONDecodeError:
                continue

    def command(self, name: str, args=None):
        payload = {"execute": name}
        if args is not None:
            payload["arguments"] = args
        self.file.write((json.dumps(payload) + "\n").encode())
        while True:
            msg = self._read()
            if "event" in msg:
                continue
            if "error" in msg:
                raise RuntimeError(f"QMP {name} failed: {msg}")
            return msg.get("return")

    def hmp(self, command: str):
        return self.command("human-monitor-command", {"command-line": command})

    def key(self, value: str) -> None:
        self.hmp(f"sendkey {value}")
        time.sleep(0.15)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: memtest-isolinux-menu.py ISO WORKDIR", file=sys.stderr)
        return 2
    iso, work = sys.argv[1:]
    os.makedirs(work, exist_ok=True)
    serial_path = os.path.join(work, "serial.log")
    for name in ("qmp.sock", "serial.log", "menu.ppm", "memtest.ppm"):
        try:
            os.unlink(os.path.join(work, name))
        except FileNotFoundError:
            pass
    cmd = [
        QEMU, "-accel", "tcg,thread=multi", "-cpu", "Haswell", "-smp", "4", "-m", "3072",
        "-L", DATA, "-no-user-config", "-nodefaults", "-display", "none", "-vga", "std",
        "-monitor", "none", "-rtc", "base=utc", "-boot", "order=d,menu=off",
        "-cdrom", iso, "-serial", f"file:{serial_path}",
        "-qmp", f"unix:{work}/qmp.sock,server=on,wait=off", "-no-reboot",
    ]
    env = dict(os.environ)
    env["LD_LIBRARY_PATH"] = LIB
    env["QEMU_MODULE_DIR"] = MOD
    proc = subprocess.Popen(cmd, env=env, stdout=open(f"{work}/qemu.out", "wb"),
                            stderr=subprocess.STDOUT)
    qmp = QMP(f"{work}/qmp.sock")
    try:
        # ISOLINUX timeout is 5s.  At 7.5s the menu is still up; Home cancels
        # the countdown and selects the first entry, then three Down keys reach
        # the top-level Memtest86+ entry (Live, Live fail-safe, Utilities,
        # Memtest).  Enter starts it through the real `linux` directive.
        time.sleep(7.5)
        qmp.screenshot(f"{work}/menu.ppm")
        qmp.key("home")
        for _ in range(3):
            qmp.key("down")
        qmp.key("ret")
        time.sleep(45)
        qmp.screenshot(f"{work}/memtest.ppm")
    finally:
        try:
            qmp.command("quit")
        except Exception:  # noqa: BLE001
            pass
        try:
            proc.wait(timeout=20)
        except subprocess.TimeoutExpired:
            proc.kill()

    with open(serial_path, "rb") as handle:
        text = handle.read().decode("utf-8", "replace")
    banner = "Memtest86+ v7.20" in text
    testing = "Status: Testing" in text or "Pass:" in text
    zero_errors = "Errors: 0" in text
    print(f"ISO={iso}")
    print(f"SERIAL={serial_path}")
    print(f"MEMTEST_BANNER={banner} TESTING={testing} ZERO_ERRORS={zero_errors}")
    if banner and testing and zero_errors:
        print("RESULT=PASS")
        return 0
    print("RESULT=FAIL (menu selection did not reach a running Memtest86+ v7.20)")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
