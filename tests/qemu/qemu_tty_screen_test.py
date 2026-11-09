#!/usr/bin/env python3
"""Boot the injected Debian image in QEMU, drive tty1 with sendkey, and capture
the VGA text framebuffer plus screendump frames.  This is virtual-hardware
evidence only: no host block device is opened or written.
"""
import argparse
import glob
import gzip
import json
import os
import select
import shutil
import socket
import subprocess
import sys
import time

FAILED = 0
PASSED = 0


def say(ok, label, detail=""):
    global FAILED, PASSED
    if ok:
        print(f"PASS {label}")
        PASSED += 1
    else:
        print(f"FAIL {label} {detail}".rstrip())
        FAILED += 1


class Qemu:
    def __init__(self, args, work):
        self.args = args
        self.work = work
        self.sock_path = os.path.join(work, "monitor.sock")
        self.serial_path = os.path.join(work, "serial.log")
        self.vga_path = os.path.join(work, "vga.bin")
        for path in (self.sock_path, self.serial_path, self.vga_path):
            try:
                os.unlink(path)
            except OSError:
                pass
        env = dict(os.environ)
        env["LD_LIBRARY_PATH"] = args.qemu_lib + ":" + env.get("LD_LIBRARY_PATH", "")
        env["QEMU_MODULE_DIR"] = args.qemu_modules
        cmd = [
            args.qemu, "-L", args.qemu_data,
            "-machine", "pc,accel=tcg", "-m", "1024", "-smp", "2", "-nic", "none",
            "-kernel", args.kernel, "-initrd", args.initrd,
            "-append", args.cmdline,
            "-drive", f"file={args.image},format=raw,if=virtio",
            "-vga", "std", "-display", "none",
            "-monitor", f"unix:{self.sock_path},server=on,wait=off",
            "-serial", f"file:{self.serial_path}", "-no-reboot",
        ]
        self.proc = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.sock = None
        for _ in range(150):
            if self.proc.poll() is not None:
                raise RuntimeError("qemu exited: " + self.proc.stderr.read().decode(errors="replace")[-1000:])
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

    def _drain_until_prompt(self, deadline=10):
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
                return buf
        return buf

    def hmp(self, command, quiet=True):
        self.sock.sendall((command + "\n").encode())
        return self._drain_until_prompt()

    def vga_text(self):
        try:
            os.unlink(self.vga_path)
        except OSError:
            pass
        self.hmp(f'pmemsave 0xb8000 4000 "{self.vga_path}"')
        for _ in range(20):
            if os.path.exists(self.vga_path) and os.path.getsize(self.vga_path) == 4000:
                break
            time.sleep(0.05)
        with open(self.vga_path, "rb") as handle:
            data = handle.read()
        if len(data) != 4000:
            return ""
        rows = []
        for row in range(25):
            cells = []
            for col in range(80):
                byte = data[(row * 80 + col) * 2]
                cells.append(chr(byte) if 32 <= byte < 127 else " ")
            rows.append("".join(cells).rstrip())
        return "\n".join(rows)

    def screenshot(self, name):
        path = os.path.join(self.work, name)
        self.hmp(f'screendump {path}')
        for _ in range(20):
            if os.path.exists(path) and os.path.getsize(path) > 1000:
                return path
            time.sleep(0.1)
        return path if os.path.exists(path) else ""

    def send(self, text):
        for ch in text:
            key = "ret" if ch == "\n" else ch
            self.hmp(f"sendkey {key}")
            time.sleep(0.06)
        time.sleep(0.3)

    def wait_text(self, needle, timeout, interval=1.0):
        end = time.time() + timeout
        last = ""
        while time.time() < end:
            last = self.vga_text()
            if needle in last:
                return last
            if self.proc.poll() is not None:
                break
            time.sleep(interval)
        return last

    def poweroff(self):
        if self.proc.poll() is None:
            try:
                self.hmp("system_powerdown")
            except OSError:
                pass
            try:
                self.proc.wait(timeout=60)
            except subprocess.TimeoutExpired:
                try:
                    self.hmp("quit")
                except OSError:
                    pass
                try:
                    self.proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    self.proc.kill()
        if self.sock:
            self.sock.close()


def load_psf(path):
    raw = gzip.open(path, "rb").read()
    if raw[:2] == b"\x36\x04":
        charsize = raw[3]
        glyphs = [raw[4 + i * charsize:4 + (i + 1) * charsize] for i in range(256)]
        width, height = 8, charsize
    elif raw[:4] == b"\x72\xb5\x4a\x86":
        header = raw[:32]
        headersize = int.from_bytes(header[8:12], "little")
        length = int.from_bytes(header[16:20], "little")
        charsize = int.from_bytes(header[20:24], "little")
        height = int.from_bytes(header[24:28], "little")
        width = int.from_bytes(header[28:32], "little")
        glyphs = [raw[headersize + i * charsize:headersize + (i + 1) * charsize]
                  for i in range(length)]
    else:
        raise ValueError("unsupported PSF")
    return width, height, glyphs


def read_ppm(path):
    with open(path, "rb") as handle:
        data = handle.read()
    if not data.startswith(b"P6"):
        return None, None, None
    fields = []
    idx = 2
    while len(fields) < 3:
        while idx < len(data) and data[idx] in b" \t\r\n":
            idx += 1
        if idx < len(data) and data[idx:idx + 1] == b"#":
            while idx < len(data) and data[idx] not in b"\r\n":
                idx += 1
            continue
        start = idx
        while idx < len(data) and data[idx] not in b" \t\r\n":
            idx += 1
        fields.append(int(data[start:idx]))
    idx += 1
    width, height, _ = fields
    return width, height, data[idx:]


def screenshot_match(ppm_path, vga_text, font_paths):
    width, height, pixels = read_ppm(ppm_path)
    if not width or not pixels:
        return 0.0, "invalid PPM"
    rows = vga_text.splitlines()
    while len(rows) < 25:
        rows.append("")
    best_ratio = 0.0
    best_detail = "no font candidate matched"
    for font_path in font_paths:
        try:
            fw, fh, glyphs = load_psf(font_path)
        except (OSError, ValueError):
            continue
        for cell_w, xoff in ((9, 0), (8, 40), (8, 0)):
            matched = 0
            total = 0
            for row in range(min(25, height // 16)):
                line = rows[row] if row < len(rows) else ""
                for col in range(min(80, (width - xoff) // cell_w)):
                    ch = line[col] if col < len(line) else " "
                    code = ord(ch)
                    if code < 33 or code >= len(glyphs):
                        continue
                    total += 1
                    glyph = glyphs[code]
                    on_sum = on_n = off_sum = off_n = 0
                    for gy in range(min(fh, 16)):
                        for gx in range(min(fw, 8)):
                            x = xoff + col * cell_w + gx
                            y = row * 16 + gy
                            if x >= width or y >= height:
                                continue
                            pos = (y * width + x) * 3
                            lum = sum(pixels[pos:pos + 3]) / 3.0
                            bit = (glyph[gy] >> (7 - gx)) & 1 if gy < len(glyph) else 0
                            if bit:
                                on_sum += lum; on_n += 1
                            else:
                                off_sum += lum; off_n += 1
                    if on_n == 0:
                        continue
                    contrast = (on_sum / on_n) - (off_sum / off_n if off_n else 0)
                    if contrast > 30:
                        matched += 1
            ratio = matched / total if total else 0.0
            if ratio > best_ratio:
                best_ratio = ratio
                best_detail = f"{matched}/{total} ASCII cells matched with {os.path.basename(font_path)} cell={cell_w} xoff={xoff}"
    return best_ratio, best_detail

def dump_guest(image, guest_path):
    proc = subprocess.run(["debugfs", "-R", f"cat {guest_path}", image],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    text = proc.stdout.decode("utf-8", "replace").strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--case", required=True)
    ap.add_argument("--image", required=True)
    ap.add_argument("--kernel", required=True)
    ap.add_argument("--initrd", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--send", default="")
    ap.add_argument("--timeout", type=int, default=90)
    ap.add_argument("--qemu", default=os.path.expanduser("~/paw-qemu/sysroot/usr/bin/qemu-system-x86_64"))
    ap.add_argument("--qemu-lib", default=os.path.expanduser("~/paw-qemu/sysroot/usr/lib/x86_64-linux-gnu"))
    ap.add_argument("--qemu-modules", default=os.path.expanduser("~/paw-qemu/sysroot/usr/lib/x86_64-linux-gnu/qemu"))
    ap.add_argument("--qemu-data", default=os.path.expanduser("~/paw-qemu/qemu-data"))
    ap.add_argument("--font", default="/usr/share/consolefonts/Lat15-VGA16.psf.gz")
    ap.add_argument("--font-glob", default="/usr/share/consolefonts/*VGA16.psf.gz")
    args = ap.parse_args()
    font_paths = sorted(set(glob.glob(args.font_glob) + [args.font]))
    os.makedirs(args.out, exist_ok=True)
    work = args.out
    base_cmd = (
        "root=/dev/vda rw console=tty1 console=ttyS0,115200n8 nomodeset loglevel=4 "
        f"paw.case={args.case} paw.timeout={args.timeout} "
        "systemd.mask=boot-efi.mount systemd.mask=cloud-init.target "
        "systemd.mask=cloud-init.service systemd.mask=cloud-init-local.service "
        "systemd.mask=cloud-config.service systemd.mask=cloud-final.service "
        "systemd.mask=systemd-networkd-wait-online.service "
        "systemd.mask=NetworkManager-wait-online.service "
        "systemd.mask=unattended-upgrades.service systemd.mask=paw-preflight.service "
        "systemd.mask=ssh.service systemd.mask=ssh.socket "
        "systemd.mask=serial-getty@ttyS" + "0.service systemd.mask=e2scrub_reap.service"
    )
    qargs = argparse.Namespace(**vars(args))
    qargs.cmdline = base_cmd
    try:
        qemu = Qemu(qargs, work)
    except RuntimeError as exc:
        print(f"BLOCKED qemu could not start: {exc}")
        return 77
    result = {"case": args.case, "markers": {}, "status": "FAIL"}
    try:
        text = qemu.wait_text("PAW-TTY1-PROMPT", 150)
        prompt_ok = "PAW-TTY1-PROMPT" in text
        say(prompt_ok, f"{args.case}: PAWDATA prompt appeared on tty1", text[-300:])
        result["markers"]["prompt"] = prompt_ok
        if prompt_ok:
            shot = qemu.screenshot(f"screen-{args.case}-prompt.ppm")
            with open(os.path.join(work, f"screen-{args.case}-prompt.txt"), "w", encoding="utf-8") as handle:
                handle.write(text)
            ratio, detail = screenshot_match(shot, text, font_paths)
            result["screenshot_match"] = {"ratio": ratio, "detail": detail}
            say(ratio >= 0.80, f"{args.case}: screendump frame renders the tty1 text",
                f"ratio={ratio:.2f} {detail}")
        if args.send:
            qemu.send(args.send + "\n")
        if args.case == "ok":
            text = qemu.wait_text("PAW-TTY1-INPUT-OK", 30)
            ok = "PAW-TTY1-INPUT-OK" in text
            say(ok, "ok: correct serial suffix accepted on tty1", text[-300:])
            result["markers"]["input_ok"] = ok
            if ok:
                qemu.screenshot("screen-ok-accepted.ppm")
            text = qemu.wait_text("PAW-MENU-TTY1", 180)
            menu_ok = "PAW-MENU-TTY1" in text
            say(menu_ok, "ok: PAW console menu appeared after PAWDATA on the same tty1 (ASCII marker; CJK glyphs need a console font)", text[-400:])
            result["markers"]["menu"] = menu_ok
            if menu_ok:
                qemu.screenshot("screen-ok-menu.ppm")
                with open(os.path.join(work, "screen-ok-menu.txt"), "w", encoding="utf-8") as handle:
                    handle.write(text)
                qemu.send("7\n")
                text = qemu.wait_text("data-init.json", 30)
                reports_ok = "data-init.json" in text
                say(reports_ok, "ok: menu keyboard input opened the report listing on tty1", text[-400:])
                result["markers"]["menu_input"] = reports_ok
                if reports_ok:
                    qemu.screenshot("screen-ok-reports.ppm")
                    ratio, detail = screenshot_match(os.path.join(work, "screen-ok-menu.ppm"), text, font_paths)
                    result["menu_screenshot_match"] = {"ratio": ratio, "detail": detail}
        elif args.case == "bad":
            text = qemu.wait_text("PAW-TTY1-INPUT-BAD", 30)
            bad_ok = "PAW-TTY1-INPUT-BAD" in text
            say(bad_ok, "bad: wrong serial suffix stopped on tty1", text[-300:])
            result["markers"]["input_bad"] = bad_ok
            if bad_ok:
                qemu.screenshot("screen-bad.ppm")
            no_ok = "PAW-TTY1-INPUT-OK" not in text
            say(no_ok, "bad: no INPUT-OK marker after rejection")
            result["markers"]["input_ok"] = not no_ok
        elif args.case == "timeout":
            text = qemu.wait_text("PAW-TTY1-INPUT-TIMEOUT", 30)
            timeout_ok = "PAW-TTY1-INPUT-TIMEOUT" in text
            say(timeout_ok, "timeout: no-input timeout stopped safely on tty1", text[-300:])
            result["markers"]["input_timeout"] = timeout_ok
            if timeout_ok:
                qemu.screenshot("screen-timeout.ppm")
    finally:
        qemu.poweroff()
        with open(os.path.join(work, "serial.log"), "r", encoding="utf-8", errors="replace") as handle:
            serial = handle.read()
        result["serial_tail"] = serial[-4000:]
        for name, guest in (("data_init", "/opt/paw-migration/tests/virtual/state/reports/data-init.json"),
                            ("console_menu", "/opt/paw-migration/tests/virtual/state/reports/console-menu.json")):
            result[name] = dump_guest(args.image, guest)
        data = result.get("data_init")
        menu = result.get("console_menu")
        if data:
            say(data.get("tty_path") == "/dev/tty1",
                f"{args.case}: status file records actual output tty /dev/tty1", str(data.get("tty_path")))
            if args.case in ("ok", "bad", "timeout"):
                say(data.get("menu_tty") == "/dev/tty1" and data.get("input_tty") == "/dev/tty1",
                    f"{args.case}: menu and serial input share /dev/tty1")
            say(int(data.get("max_holders", 99)) == 1,
                f"{args.case}: tty1 has exactly one non-helper holder during interaction",
                f"max_holders={data.get('max_holders')} events={data.get('events')}")
            result["tty_status"] = data
        else:
            say(False, f"{args.case}: tty status file is readable", "missing data-init.json")
        if args.case == "ok":
            if menu:
                details = [e.get("detail", "") for e in menu.get("events", [])]
                say(menu.get("tty_path") == "/dev/tty1", "ok: console menu status records /dev/tty1",
                    str(menu.get("tty_path")))
                say(any("choice=7" in str(item) for item in details),
                    "ok: menu keyboard choice 7 recorded on tty1", str(details[-4:]))
                say(int(menu.get("max_holders", 99)) == 1,
                    "ok: console menu tty1 has exactly one non-helper holder",
                    f"max_holders={menu.get('max_holders')}")
            else:
                say(False, "ok: console menu status file is readable", "missing console-menu.json")
        result["status"] = "PASS" if FAILED == 0 else "FAIL"
        with open(os.path.join(work, "result.json"), "w", encoding="utf-8") as handle:
            json.dump(result, handle, ensure_ascii=False, indent=2)
    print(f"Summary: {PASSED} passed, {FAILED} failed")
    return 0 if FAILED == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
