#!/usr/bin/env python3
"""Drive the real PAW tty1 flow on a framebuffer console and prove CJK pixels.

Unlike the older vgacon test, this test requires a framebuffer-capable Debian
kernel (fbcon).  It takes QEMU screendumps, decodes each cell against the exact
shipped PSF glyph bitmaps, and matches complete Chinese strings.  No OCR is
used.  Keyboard input goes only through the QEMU monitor sendkey channel.
"""
from __future__ import annotations

import argparse
import json
import os
import select
import shutil
import socket
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from psf_fb import Psffont, compact, decode, screen_text  # noqa: E402

FAILED = 0
PASSED = 0
RESULTS: list[dict] = []


def say(ok: bool, label: str, detail: str = "") -> None:
    global FAILED, PASSED
    RESULTS.append({"ok": bool(ok), "label": label, "detail": detail})
    if ok:
        print(f"PASS {label}")
        PASSED += 1
    else:
        print(f"FAIL {label} {detail}".rstrip())
        FAILED += 1


class Qemu:
    def __init__(self, args, work: str):
        self.args = args
        self.work = work
        self.sock_path = os.path.join(work, "monitor.sock")
        self.serial_path = os.path.join(work, "serial.log")
        for path in (self.sock_path, self.serial_path):
            try:
                os.unlink(path)
            except OSError:
                pass
        masks = " ".join(
            "systemd.mask=" + name
            for name in (
                "boot-efi.mount",
                "systemd-fsck-root.service",
                "systemd-remount-fs.service",
                "systemd-networkd-wait-online.service",
                "NetworkManager-wait-online.service",
                "ssh.service",
                "ssh.socket",
                "serial-getty@ttyS0.service",
            )
        )
        if args.case == "render":
            masks += " systemd.mask=paw-data-init.service systemd.mask=paw-console.service paw.render=1"
        if args.case == "final":
            # The authorization panel probe replaces both boot-time units.
            masks += " systemd.mask=paw-data-init.service systemd.mask=paw-console.service paw.final=1"
        cmdline = (
            "root=/dev/vda rw console=tty1 console=ttyS0,115200n8 fbcon=nodefer "
            f"paw.case={args.case} paw.timeout={args.timeout} loglevel=5 {masks}"
        )
        cmd = [args.qemu]
        if args.qemu_data and os.path.isdir(args.qemu_data):
            cmd += ["-L", args.qemu_data]
        cmd += [
            "-machine", "pc,accel=tcg", "-m", "2048", "-smp", "2", "-nic", "none",
            "-kernel", args.kernel, "-initrd", args.initrd, "-append", cmdline,
            "-drive", f"file={args.image},format=raw,if=virtio",
            "-vga", "std", "-display", "none",
            "-monitor", f"unix:{self.sock_path},server=on,wait=off",
            "-serial", f"file:{self.serial_path}", "-no-reboot",
        ]
        env = dict(os.environ)
        if args.qemu_lib and os.path.isdir(args.qemu_lib):
            env["LD_LIBRARY_PATH"] = args.qemu_lib + ":" + env.get("LD_LIBRARY_PATH", "")
        if args.qemu_modules and os.path.isdir(args.qemu_modules):
            env["QEMU_MODULE_DIR"] = args.qemu_modules
        self.proc = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.sock = None
        for _ in range(300):
            if self.proc.poll() is not None:
                raise RuntimeError("qemu exited: " + self.proc.stderr.read().decode(errors="replace")[-1200:])
            try:
                sock = socket.socket(socket.AF_UNIX)
                sock.connect(self.sock_path)
                self.sock = sock
                break
            except OSError:
                time.sleep(0.2)
        if self.sock is None:
            raise RuntimeError("qemu monitor did not appear")
        self.sock.settimeout(10)
        self._drain_until_prompt()

    def _drain_until_prompt(self, deadline: float = 10) -> bytes:
        buf = b""
        end = time.time() + deadline
        while time.time() < end:
            ready, _, _ = select.select([self.sock], [], [], 0.2)
            if not ready:
                continue
            try:
                chunk = self.sock.recv(65536)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
            if buf.rstrip().endswith(b"(qemu)"):
                break
        return buf

    def hmp(self, command: str) -> bytes:
        self.sock.sendall((command + "\n").encode())
        return self._drain_until_prompt()

    def screenshot(self, name: str) -> str:
        path = os.path.join(self.work, name)
        try:
            os.unlink(path)
        except OSError:
            pass
        self.hmp(f"screendump {path}")
        for _ in range(50):
            if os.path.exists(path) and os.path.getsize(path) > 1000:
                return path
            time.sleep(0.05)
        return path if os.path.exists(path) else ""

    def send(self, text: str, delay: float = 0.08) -> None:
        for ch in text:
            key = "ret" if ch == "\n" else ch
            self.hmp(f"sendkey {key}")
            time.sleep(delay)
        time.sleep(0.3)

    def serial(self) -> str:
        try:
            return open(self.serial_path, encoding="utf-8", errors="replace").read()
        except OSError:
            return ""

    def wait_screen(self, needle: str, timeout: float, font: Psffont, out_prefix: str) -> tuple[dict, str]:
        end = time.time() + timeout
        last: dict = {"lines": [], "match_ratio": 0.0}
        while time.time() < end:
            shot = self.screenshot(out_prefix + ".ppm")
            if shot:
                try:
                    last = decode(shot, font)
                except (OSError, ValueError):
                    last = {"lines": [], "match_ratio": 0.0}
                text = screen_text(last)
                if compact(needle) in compact(text):
                    with open(out_prefix + ".txt", "w", encoding="utf-8") as handle:
                        handle.write(text + "\n")
                    return last, text
            if self.proc.poll() is not None:
                break
            time.sleep(0.7)
        with open(out_prefix + ".txt", "w", encoding="utf-8") as handle:
            handle.write(screen_text(last) + "\n")
        return last, screen_text(last)

    def poweroff(self) -> None:
        if self.proc.poll() is None:
            try:
                self.hmp("system_powerdown")
            except OSError:
                pass
            try:
                self.proc.wait(timeout=25)
            except subprocess.TimeoutExpired:
                try:
                    self.hmp("quit")
                except OSError:
                    pass
                try:
                    self.proc.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    self.proc.kill()
        if self.sock:
            self.sock.close()


def dump_guest_json(image: str, guest_path: str):
    # The disposable test guest is powered off by QEMU, not unmounted by
    # systemd; replay its ext4 journal before reading the atomic status files.
    subprocess.run(["e2fsck", "-fy", image], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    proc = subprocess.run(["debugfs", "-R", f"cat {guest_path}", image],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    text = proc.stdout.decode("utf-8", "replace").strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


def check_cjk(decoded: dict, strings: list[str], prefix: str) -> None:
    ratio = float(decoded.get("match_ratio", 0.0))
    say(ratio >= 0.995, f"{prefix}: framebuffer cells match shipped PSF glyphs",
        f"ratio={ratio:.4f} exact={decoded.get('exact_cells')} inexact={decoded.get('inexact_cells')}")
    text = screen_text(decoded)
    for value in strings:
        say(compact(value) in compact(text), f"{prefix}: 中文屏幕显示「{value[:24]}…」",
            text[-300:])


def run_case(args, font: Psffont) -> None:
    out = os.path.join(args.out, args.case)
    os.makedirs(out, exist_ok=True)
    try:
        qemu = Qemu(args, out)
    except RuntimeError as exc:
        print(f"FAIL {args.case}: qemu could not start: {exc}")
        say(False, f"{args.case}: qemu started", str(exc))
        return
    result = {"case": args.case, "status": "FAIL", "assertions": RESULTS}
    try:
        if args.case == "final":
            decoded, text = qemu.wait_screen("PAW-TTY1-FINAL-PANEL", 300, font,
                                             os.path.join(out, "screen-final-panel"))
            panel_ok = "PAW-TTY1-FINAL-PANEL" in text
            say(panel_ok, "final: authorization panel reached fbcon",
                text[-500:] + "\nSERIAL TAIL:\n" + qemu.serial()[-2000:])
            if not panel_ok:
                result["serial_tail"] = qemu.serial()[-8000:]
                return
            # The probe announces the synthetic target identity on the serial
            # console; the panel must show that same runtime value, so the
            # suffix typed below is derived from what the guest really reports.
            serial = ""
            for line in qemu.serial().splitlines():
                if "PAW-CJK-FINAL-SETUP" in line:
                    for field in line.split():
                        if field.startswith("serial="):
                            serial = field.split("=", 1)[1]
            suffix = serial[-6:] if len(serial) >= 6 else ""
            say(len(suffix) == 6,
                "final: guest reported a >=6 character synthetic target serial",
                serial or "(none)")

            # Wait for the last panel line, not the middle one: the screenshot
            # must already contain every line that check_cjk asserts below.
            decoded, text = qemu.wait_screen("如确认覆盖", 30, font,
                                             os.path.join(out, "screen-final-panel-cjk"))
            expected = [
                "PAW 最终迁移授权(请完整阅读后再确认)",
                "源系统:Rescue Mode",
                "源盘组合身份:",
                "固定 SSH 主机指纹:",
                "目标 SSD:设备=",
                "数据来源:固定 SSH 主机指纹的 Rescue Mode 整盘流",
                "数据损失:目标 SSD 的整盘内容将被源盘覆盖,目标盘原有分区和数据会全部丢失.",
                "如确认覆盖,请输入目标 SSD 序列号最后 6 位:",
            ]
            if serial:
                expected.append(f"目标序列号:{serial}")
            check_cjk(decoded, expected, "final-panel")

            # Attempt 1 must be rejected: wrong suffix.
            qemu.send("000000\n")
            decoded, text = qemu.wait_screen("PAW-TTY1-FINAL-BAD", 60, font,
                                             os.path.join(out, "screen-final-bad"))
            say("PAW-TTY1-FINAL-BAD" in text, "final: wrong suffix rejected on tty1", text[-400:])
            decoded, text = qemu.wait_screen("确认值与目标 SSD 序列号不匹配", 20, font,
                                             os.path.join(out, "screen-final-bad-cjk"))
            check_cjk(decoded, ["错误:确认值与目标 SSD 序列号不匹配,已安全停止,没有写入任何数据."],
                      "final-bad")
            say("PAW-TTY1-FINAL-OK" not in text, "final: no acceptance marker after rejection")

            # Attempt 2 must be accepted: correct suffix.
            decoded, text = qemu.wait_screen("PAW-TTY1-FINAL-PANEL", 150, font,
                                             os.path.join(out, "screen-final-panel2"))
            say("PAW-TTY1-FINAL-PANEL" in text, "final: panel reappeared for the second attempt")
            qemu.send((suffix or "123456") + "\n")
            decoded, text = qemu.wait_screen("PAW-TTY1-FINAL-OK", 60, font,
                                             os.path.join(out, "screen-final-ok"))
            say("PAW-TTY1-FINAL-OK" in text, "final: correct suffix accepted on tty1", text[-400:])
            decoded, text = qemu.wait_screen("开始整盘覆盖迁移", 20, font,
                                             os.path.join(out, "screen-final-ok-cjk"))
            check_cjk(decoded, ["输入已确认;开始整盘覆盖迁移,请不要断电."], "final-ok")
            qemu.poweroff()
            session = dump_guest_json(
                args.image, "/opt/paw-migration/tests/final/state/reports/final-confirm.json")
            if session:
                say(session.get("tty_path") == "/dev/tty1",
                    "final: authorization session records /dev/tty1", str(session.get("tty_path")))
                markers = [str(item) for item in session.get("markers", [])]
                say("PAW-TTY1-FINAL-BAD" in markers and "PAW-TTY1-FINAL-OK" in markers,
                    "final: both rejection and acceptance markers were recorded",
                    str([m for m in markers if m.startswith("PAW-TTY1-FINAL")]))
                # This driver is a shell that keeps tty1 on fd0 (StandardInput=tty)
                # while it runs the script twice, so two holders is the expected
                # test-harness shape, not a competing terminal owner.  What must
                # not happen is a login/getty process taking tty1 over.
                holders = []
                for event in session.get("events", []):
                    holders.extend(event.get("holders", []))
                comms = sorted({str(item.get("comm", "")) for item in holders})
                say(int(session.get("max_holders", 99)) <= 2,
                    "final: only the probe shell and the authorization script hold tty1",
                    f"max_holders={session.get('max_holders')}")
                say(not any(name in ("getty", "agetty", "login") for name in comms),
                    "final: no login or getty process competes for tty1", str(comms))
                result["final_session"] = session
            else:
                say(False, "final: authorization session file is readable",
                    "missing final-confirm.json")
            result["serial_tail"] = qemu.serial()[-8000:]
            return
        if args.case == "render":
            decoded, text = qemu.wait_screen("PAW 迁移成功", 300, font,
                                             os.path.join(out, "screen-complete"))
            say(compact("PAW 迁移成功") in compact(text),
                "render: finalizer Chinese success text reached fbcon", text[-500:])
            decoded, text = qemu.wait_screen("[PAW-REBOOT] PASS", 30, font,
                                             os.path.join(out, "screen-complete-pass"))
            say("[PAW-REBOOT] PASS" in text, "render: finalizer completed with mock reboot", text[-500:])
            check_cjk(decoded, [
                "PAW 迁移成功:克隆,独立 SHA256 校验,离线修复,GPT/ext4 扩容和重启前交接检查全部通过.",
                "完成记录已原子写入并同步到磁盘.",
                "系统将在 5 秒后自动重启进入正式 Ubuntu;按 C 取消自动重启.",
                "自动重启命令已成功下发",
            ], "render-complete")
            qemu.poweroff()
            status = dump_guest_json(args.image,
                                     "/opt/paw-migration/tests/finalize/state/reports/reboot-status.json")
            if status:
                say(status.get("status") == "PASS", "render: reboot status is PASS", str(status.get("status")))
                say(status.get("reboot_invoked") is True, "render: mock reboot was invoked exactly once")
                say(status.get("reboot_command") == "/bin/true", "render: test used the mock reboot command")
                result["reboot_status"] = status
            else:
                say(False, "render: reboot status file is readable", "missing reboot-status.json")
            result["serial_tail"] = qemu.serial()[-8000:]
            return
        decoded, text = qemu.wait_screen("PAW-TTY1-PROMPT", 210, font, os.path.join(out, "screen-prompt"))
        prompt_ok = "PAW-TTY1-PROMPT" in text
        say(prompt_ok, f"{args.case}: PAWDATA prompt reached on fbcon",
            text[-500:] + "\nSERIAL TAIL:\n" + qemu.serial()[-2000:])
        if not prompt_ok:
            result["serial_tail"] = qemu.serial()[-8000:]
            return
        decoded, text = qemu.wait_screen("请输入该设备序列号最后", 15, font,
                                         os.path.join(out, "screen-prompt-cjk"))
        serial = qemu.serial()
        say("Console font loaded: fbcon" in serial,
            f"{args.case}: kernel font service reports fbcon 16x16 load", serial[-800:])
        say("bochs-drmdrmfb" in serial or "bochs" in serial,
            f"{args.case}: framebuffer device is bochs-drm", serial[-500:])
        check_cjk(decoded, [
            "PAW 首次启动 - PAWDATA 持久分区初始化",
            "只针对当前启动本系统的可移动设备;不会碰其他磁盘.",
            "将只追加一个新的 PAWDATA 分区并格式化该新分区;ISO 启动分区不会被格式化.",
            "请输入该设备序列号最后 6 位以继续:",
            "序列号:QEMU-123456",
        ], args.case)

        if args.case == "ok":
            qemu.send("123456\n")
            decoded, text = qemu.wait_screen("PAW-TTY1-INPUT-OK", 40, font, os.path.join(out, "screen-accepted"))
            say("PAW-TTY1-INPUT-OK" in text, "ok: correct serial suffix accepted on tty1", text[-400:])
            decoded, text = qemu.wait_screen("输入已确认", 15, font, os.path.join(out, "screen-accepted-cjk"))
            check_cjk(decoded, ["输入已确认;开始追加 PAWDATA 分区(仅新分区会被格式化)."], "ok-accepted")
            decoded, text = qemu.wait_screen("PAW-MENU-TTY1", 150, font, os.path.join(out, "screen-menu"))
            say("PAW-MENU-TTY1" in text, "ok: Chinese console menu appeared on the same tty1", text[-400:])
            decoded, text = qemu.wait_screen("PAW 迁移准备控制台", 20, font, os.path.join(out, "screen-menu-cjk"))
            decoded, text = qemu.wait_screen("登记 Memtest86+ 人工确认结果", 15, font, os.path.join(out, "screen-menu-items"))
            check_cjk(decoded, [
                "PAW 迁移准备控制台(v2.7)",
                "登记 Memtest86+ 人工确认结果",
                "初始化/修复 PAWDATA 持久分区",
                "最终中文授权并开始迁移",
            ], "ok-menu")
            qemu.send("7\n")
            decoded, text = qemu.wait_screen("data-init.json", 40, font, os.path.join(out, "screen-reports"))
            say("data-init.json" in text, "ok: menu keyboard choice 7 opened the report listing", text[-400:])
            # Flush the guest's ext4 writes: debugfs reads the image file
            # directly, so QEMU must be gone before status JSON is trusted.
            qemu.poweroff()
            menu = None
            for _ in range(20):
                menu = dump_guest_json(args.image, "/opt/paw-migration/tests/virtual/state/reports/console-menu.json")
                details = [event.get("detail", "") for event in (menu or {}).get("events", [])]
                if any("choice=7" in str(item) for item in details):
                    break
                time.sleep(0.5)
            if menu:
                details = [event.get("detail", "") for event in menu.get("events", [])]
                say(menu.get("tty_path") == "/dev/tty1", "ok: console menu status records /dev/tty1",
                    str(menu.get("tty_path")))
                say(any("choice=7" in str(item) for item in details),
                    "ok: menu choice 7 recorded on tty1", str(details[-4:]))
                say(int(menu.get("max_holders", 99)) == 1,
                    "ok: console menu has exactly one non-helper tty1 holder",
                    f"max_holders={menu.get('max_holders')}")
            else:
                say(False, "ok: console menu status file is readable", "missing console-menu.json")
        elif args.case == "bad":
            qemu.send("000000\n")
            decoded, text = qemu.wait_screen("PAW-TTY1-INPUT-BAD", 40, font, os.path.join(out, "screen-bad"))
            say("PAW-TTY1-INPUT-BAD" in text, "bad: wrong serial suffix stopped on tty1", text[-400:])
            decoded, text = qemu.wait_screen("错误:序列号末六位不匹配", 15, font, os.path.join(out, "screen-bad-cjk"))
            check_cjk(decoded, ["错误:序列号末六位不匹配,已安全停止,没有写入任何分区."], "bad")
            say("PAW-TTY1-INPUT-OK" not in text, "bad: no INPUT-OK marker after rejection")
        elif args.case == "timeout":
            decoded, text = qemu.wait_screen("PAW-TTY1-INPUT-TIMEOUT", 45, font, os.path.join(out, "screen-timeout"))
            say("PAW-TTY1-INPUT-TIMEOUT" in text, "timeout: no-input timeout stopped safely on tty1", text[-400:])
            decoded, text = qemu.wait_screen("错误:等待输入超过 5 秒", 15, font, os.path.join(out, "screen-timeout-cjk"))
            check_cjk(decoded, ["错误:等待输入超过 5 秒,已安全停止,没有写入任何分区."], "timeout")
            say("PAW-TTY1-INPUT-OK" not in text, "timeout: no INPUT-OK marker after timeout")

        qemu.poweroff()
        data = dump_guest_json(args.image, "/opt/paw-migration/tests/virtual/state/reports/data-init.json")
        if data:
            say(data.get("tty_path") == "/dev/tty1",
                f"{args.case}: status file records actual output tty /dev/tty1", str(data.get("tty_path")))
            say(data.get("menu_tty") == "/dev/tty1" and data.get("input_tty") == "/dev/tty1",
                f"{args.case}: PAWDATA panel and serial input share /dev/tty1")
            say(int(data.get("max_holders", 99)) == 1,
                f"{args.case}: tty1 has exactly one non-helper holder",
                f"max_holders={data.get('max_holders')} events={data.get('events')}")
            result["data_init"] = data
        else:
            say(False, f"{args.case}: data-init status file is readable", "missing data-init.json")
        result["serial_tail"] = qemu.serial()[-8000:]
    finally:
        qemu.poweroff()
        result["status"] = "PASS" if FAILED == 0 else "FAIL"
        result["assertions"] = RESULTS
        with open(os.path.join(out, "result.json"), "w", encoding="utf-8") as handle:
            json.dump(result, handle, ensure_ascii=False, indent=2)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--case", required=True, choices=["ok", "bad", "timeout", "render", "final"])
    ap.add_argument("--image", required=True)
    ap.add_argument("--kernel", required=True)
    ap.add_argument("--initrd", required=True)
    ap.add_argument("--font", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--timeout", type=int, default=60)
    ap.add_argument("--qemu", default=os.environ.get(
        "PAW_QEMU_BIN", os.path.expanduser("~/paw-qemu/sysroot/usr/bin/qemu-system-x86_64")))
    ap.add_argument("--qemu-lib", default=os.environ.get(
        "PAW_QEMU_LIB", os.path.expanduser("~/paw-qemu/sysroot/usr/lib/x86_64-linux-gnu")))
    ap.add_argument("--qemu-modules", default=os.environ.get(
        "PAW_QEMU_MODULES", os.path.expanduser("~/paw-qemu/sysroot/usr/lib/x86_64-linux-gnu/qemu")))
    default_qemu_data = os.environ.get("PAW_QEMU_DATA")
    if default_qemu_data is None:
        candidate = os.path.expanduser("~/paw-qemu/qemu-data")
        default_qemu_data = candidate if os.path.isdir(candidate) else ""
    ap.add_argument("--qemu-data", default=default_qemu_data)
    args = ap.parse_args()
    if not os.path.exists(args.qemu):
        args.qemu = shutil.which("qemu-system-x86_64") or args.qemu
    if args.qemu_data and not os.path.isdir(args.qemu_data):
        args.qemu_data = ""
    font = Psffont(args.font)
    say(font.width == 16 and font.height == 16, "font under test is 16x16",
        f"{font.width}x{font.height} chars={font.charcount}")
    run_case(args, font)
    print(f"Summary: {PASSED} passed, {FAILED} failed")
    return 0 if FAILED == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
