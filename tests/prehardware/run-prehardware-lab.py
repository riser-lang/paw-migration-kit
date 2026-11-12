#!/usr/bin/env python3
"""QEMU host driver for the PAW Stage 3 integration lab.

Runs the disposable guest under TCG (this host has no /dev/kvm), injects
keyboard input on the emulated tty1 through QMP, captures screenshots, and
keeps the full serial log across the guest-initiated reboot into the cloned
target.
"""
import argparse
import json
import os
import queue
import socket
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone

QEMU = os.environ.get(
    "QEMU_BIN",
    "/home/agentuser/tools/qemu-portable-20261110/sysroot/usr/bin/qemu-system-x86_64",
)
QEMU_LIB = os.environ.get(
    "QEMU_LIB",
    "/home/agentuser/tools/qemu-portable-20261110/sysroot/usr/lib/x86_64-linux-gnu",
)
QEMU_MODULE = os.environ.get(
    "QEMU_MODULE_DIR",
    "/home/agentuser/tools/qemu-portable-20261110/sysroot/usr/lib/x86_64-linux-gnu/qemu",
)
QEMU_DATA = os.environ.get(
    "QEMU_DATA_DIR",
    "/home/agentuser/tools/qemu-portable-20261110/share-merged",
)


def log(msg):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)


class QMP:
    def __init__(self, path, timeout=60):
        deadline = time.time() + timeout
        last = None
        while time.time() < deadline:
            try:
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.connect(path)
                break
            except OSError as exc:
                last = exc
                time.sleep(0.2)
        else:
            raise RuntimeError(f"cannot connect QMP socket {path}: {last}")
        self.file = self.sock.makefile("rwb", buffering=0)
        self._read_json()
        self.command("qmp_capabilities")

    def _read_json(self):
        while True:
            line = self.file.readline()
            if not line:
                raise RuntimeError("QMP socket closed")
            try:
                return json.loads(line.decode("utf-8"))
            except json.JSONDecodeError:
                continue

    def command(self, name, args=None):
        payload = {"execute": name}
        if args is not None:
            payload["arguments"] = args
        self.file.write((json.dumps(payload) + "\n").encode())
        while True:
            msg = self._read_json()
            if "event" in msg:
                continue
            if "error" in msg:
                raise RuntimeError(f"QMP {name} failed: {msg}")
            return msg.get("return")

    def hmp(self, command):
        return self.command("human-monitor-command", {"command-line": command})

    def key(self, value):
        self.hmp(f"sendkey {value}")

    def type_text(self, text, delay=0.18):
        for ch in text:
            self.key(ch)
            time.sleep(delay)

    def qom_find_by_serial(self, serial):
        listing = self.command("qom-list", {"path": "/machine/peripheral-anon"})
        for item in listing or []:
            name = item.get("name", "")
            if not name.startswith("device["):
                continue
            path = f"/machine/peripheral-anon/{name}"
            try:
                got = self.command("qom-get", {"path": path, "property": "serial"})
            except Exception:
                continue
            if got == serial:
                return path
        return None

    def swap_boot_to_target(self, guest_serial="PAW-LAB-ROOT"):
        path = self.qom_find_by_serial(guest_serial)
        if not path:
            raise RuntimeError("could not locate lab guest block device by serial")
        self.command("qom-set", {"path": path, "property": "bootindex", "value": 4})
        value = self.command("qom-get", {"path": path, "property": "bootindex"})
        if value != 4:
            raise RuntimeError(f"bootindex change did not stick: {value}")
        log(f"swapped {path} bootindex to 4; target bootindex 2 now wins on reset")

    def remove_usb_media(self):
        """Unplug the emulated USB stick and prove QEMU dropped the device."""
        try:
            self.command("device_del", {"id": "usb-media"})
        except RuntimeError as exc:
            # A second call after the device is gone is not a failure.
            if "not found" not in str(exc).lower():
                raise
        for _ in range(30):
            if self.qom_find_by_serial("PAW-MEDIA-123456") is None:
                log("USB media device removed from the guest block layer")
                return True
            time.sleep(0.25)
        raise RuntimeError("USB media device is still present after device_del")

    def screenshot(self, path):
        try:
            self.command("screendump", {"filename": path})
            return True
        except Exception as exc:  # noqa: BLE001 - evidence capture must not kill the run
            log(f"screendump failed: {exc}")
            return False

    def quit(self):
        try:
            self.command("quit")
        except Exception:
            pass


class SerialTail(threading.Thread):
    def __init__(self, path, log_path):
        super().__init__(daemon=True)
        self.path = path
        self.log_path = log_path
        self.lines = queue.Queue()
        self.stop = False
        self.sock = None
        self.logf = open(log_path, "ab", buffering=0)

    def run(self):
        deadline = time.time() + 60
        while time.time() < deadline:
            try:
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.connect(self.path)
                break
            except OSError:
                time.sleep(0.2)
        else:
            self.logf.write(b"PAW3-HOST: serial socket connect failed\n")
            return
        self.sock.settimeout(0.5)
        buf = b""
        while not self.stop:
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                continue
            except OSError:
                break
            if not chunk:
                break
            self.logf.write(chunk)
            self.logf.flush()
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                self.lines.put(line.decode("utf-8", "replace").rstrip("\r"))
        if buf:
            self.lines.put(buf.decode("utf-8", "replace"))

    def snapshot(self):
        try:
            with open(self.log_path, "rb") as handle:
                return handle.read().decode("utf-8", "replace")
        except OSError:
            return ""

    def finish(self):
        self.stop = True
        try:
            if self.sock:
                self.sock.close()
        except OSError:
            pass
        self.logf.close()


def qemu_cmd(args, devices=True):
    cmd = [
        QEMU,
        "-accel", "tcg,thread=multi",
        "-cpu", "Haswell",
        "-smp", "4",
        "-m", str(getattr(args, "memory", 4096)),
        "-L", QEMU_DATA,
        "-no-user-config",
        "-nodefaults",
        "-display", "none",
        "-vga", "std",
        "-monitor", "none",
        "-rtc", "base=utc",
        "-boot", "order=c,menu=off",
        "-serial", f"unix:{args.work}/serial.sock,server=on,wait=off",
        "-qmp", f"unix:{args.work}/qmp.sock,server=on,wait=off",
        "-monitor", f"unix:{args.work}/mon.sock,server=on,wait=off",
    ]
    for spec in getattr(args, "fw_cfg", []):
        cmd += ["-fw_cfg", spec]
    if devices:
        media_image = getattr(args, "usb_media", None) or f"{args.work}/boot/tf32.img"
        if args.mode == "main":
            # Acceptance path: the live system boots like the physical target —
            # from a removable USB Mass Storage device on a real xHCI controller.
            # There is deliberately no virtio guest disk in this path.
            cmd += [
                "-device", "qemu-xhci,id=usb0",
                "-drive", f"file={media_image},if=none,id=media,format=raw,cache=unsafe",
                "-device", "usb-storage,id=usb-media,drive=media,bus=usb0.0,removable=on,bootindex=0,serial=PAW-MEDIA-123456",
            ]
        else:
            cmd += [
                "-drive", f"file={args.work}/boot/guest.img,if=none,id=vda,format=raw,cache=unsafe",
                "-device", "virtio-blk-pci,drive=vda,bootindex=1,serial=PAW-LAB-ROOT",
                "-drive", f"file={args.work}/boot/media32.img,if=none,id=media,format=raw,cache=unsafe",
                "-device", "virtio-scsi-pci,id=scsi0",
                "-device", "scsi-hd,drive=media,bus=scsi0.0,removable=on,bootindex=3,serial=PAW-MEDIA-123456",
            ]
        cmd += [
            "-device", "ich9-ahci,id=sata",
            "-drive", f"file={args.work}/boot/source50.raw,if=none,id=src,format=raw,cache=unsafe",
            # Source is disk 5: after the USB is unplugged the cloned target
            # (bootindex 2) must win, never the still-bootable source image.
            "-device", "ide-hd,drive=src,bus=ide.0,bootindex=5,serial=PAW-SRC-123456",
            "-drive", f"file={args.work}/boot/target240.img,if=none,id=dst,format=raw,cache=unsafe,discard=unmap,detect-zeroes=unmap",
            "-device", "ide-hd,drive=dst,bus=ide.1,bootindex=2,serial=PAW-DST-123456",
            "-netdev", "user,id=n0",
            "-device", "e1000,netdev=n0",
            "-virtfs", f"local,path={args.work}/share,mount_tag=hostshare,security_model=none,readonly=off",
        ]
    if getattr(args, "direct_kernel", False):
        append = "root=/dev/vda2 rw console=tty1 console=ttyS0,115200n8"
        if args.append_extra:
            append += " " + args.append_extra
        cmd += [
            "-kernel", f"{args.work}/iso/live/vmlinuz",
            "-initrd", args.initrd or f"{args.work}/boot/initrd.img",
            "-append", append,
        ]
    elif args.mode == "prepare":
        cmd += [
            "-kernel", f"{args.work}/iso/live/vmlinuz",
            "-initrd", f"{args.work}/boot/initrd.img",
            "-append", "root=/dev/vda2 rw console=tty1 console=ttyS0,115200n8",
        ]
    return cmd


def run_prepare(args):
    os.makedirs(f"{args.work}/share", exist_ok=True)
    for p in ("serial.sock", "qmp.sock"):
        try:
            os.unlink(f"{args.work}/{p}")
        except FileNotFoundError:
            pass
    env = dict(os.environ)
    env["LD_LIBRARY_PATH"] = QEMU_LIB
    env["QEMU_MODULE_DIR"] = QEMU_MODULE
    log_path = f"{args.work}/console-prepare.log"
    open(log_path, "wb").close()
    proc = subprocess.Popen(qemu_cmd(args, devices=True), env=env,
                            stdout=open(f"{args.work}/qemu-prepare.out", "wb"),
                            stderr=subprocess.STDOUT)
    tail = SerialTail(f"{args.work}/serial.sock", log_path)
    tail.start()
    deadline = time.time() + args.timeout
    result = "TIMEOUT"
    while time.time() < deadline:
        text = tail.snapshot()
        if "PAW_PREHW_GRUB_INSTALL=PASS" in text:
            result = "GRUB_INSTALL_PASS"
            # poweroff follows immediately; give it a few seconds
            try:
                proc.wait(timeout=60)
            except subprocess.TimeoutExpired:
                pass
            break
        if proc.poll() is not None:
            # The guest may power off in the same second the marker is written;
            # classify by the marker in the captured serial log, not by the
            # QEMU exit race.
            result = "GRUB_INSTALL_PASS" if "PAW_PREHW_GRUB_INSTALL=PASS" in text else "QEMU_EXIT"
            break
        time.sleep(1)
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=20)
        except subprocess.TimeoutExpired:
            proc.kill()
    tail.finish()
    log(f"prepare boot result={result} qemu_rc={proc.returncode}")
    print(tail.snapshot()[-4000:])
    return 0 if result == "GRUB_INSTALL_PASS" else 1


def run_main(args):
    os.makedirs(f"{args.work}/share", exist_ok=True)
    os.makedirs(f"{args.work}/screens", exist_ok=True)
    for p in ("serial.sock", "qmp.sock"):
        try:
            os.unlink(f"{args.work}/{p}")
        except FileNotFoundError:
            pass
    env = dict(os.environ)
    env["LD_LIBRARY_PATH"] = QEMU_LIB
    env["QEMU_MODULE_DIR"] = QEMU_MODULE
    log_path = f"{args.work}/console-main.log"
    open(log_path, "wb").close()
    proc = subprocess.Popen(qemu_cmd(args, devices=True), env=env,
                            stdout=open(f"{args.work}/qemu-main.out", "wb"),
                            stderr=subprocess.STDOUT)
    tail = SerialTail(f"{args.work}/serial.sock", log_path)
    tail.start()
    qmp = QMP(f"{args.work}/qmp.sock")
    result = "TIMEOUT"
    target_boot_seen = False
    chain_pass = False
    final_phase = False
    prompts_done = set()
    media_removed = False
    deadline = time.time() + args.timeout
    target_deadline = None
    while time.time() < deadline:
        if proc.poll() is not None:
            result = "QEMU_EXIT"
            break
        try:
            lines = []
            while True:
                lines.append(tail.lines.get_nowait())
        except queue.Empty:
            pass
        for line in lines:
            if "PAW3_CHAIN_BEGIN" in line:
                log("guest chain started")
            if "PAW_MEDIA_REMOVAL_REQUIRED" in line and not media_removed:
                # The finalizer blocks its reboot until the block layer proves
                # the live USB is gone.  Unplug it for real now; the guest keeps
                # running from its toram copy of the live root.
                log("guest requested observable USB removal; unplugging emulated USB stick")
                time.sleep(2.0)
                qmp.screenshot(f"{args.work}/screens/media-before-removal.ppm")
                qmp.remove_usb_media()
                media_removed = True
                with open(f"{args.work}/share/usb-device-removed", "w", encoding="utf-8") as handle:
                    handle.write("QMP device_del usb-media; PAW-MEDIA-123456 no longer present\n")
                qmp.screenshot(f"{args.work}/screens/media-after-removal.ppm")
                log("USB media removed; finalizer may now observe PAW-LIVE disappearance")
            if "PAW3_PROMPT=" in line:
                name = line.split("PAW3_PROMPT=", 1)[1].strip()
                if name in prompts_done:
                    continue
                prompts_done.add(name)
                time.sleep(8.0)  # give the guest time to chvt 1 and open /dev/tty1 before typing
                shot = f"{args.work}/screens/{name}-before.ppm"
                qmp.screenshot(shot)
                if name == "swap_bootindex":
                    # Historical guest builds asked the host to mutate bootindex.
                    # The USB acceptance path never rewrites boot priority; it
                    # removes the live medium and leaves the target at bootindex 2.
                    log("legacy swap_bootindex prompt ignored (no bootindex faking)")
                    continue
                if name == "pawdata_serial_suffix":
                    value = "123456"
                elif name == "final_wrong_serial":
                    value = "000000"
                elif name == "final_correct_serial":
                    value = "123456"
                    final_phase = True
                else:
                    log(f"unknown prompt {name}; no input sent")
                    continue
                log(f"prompt {name}: sending {value}")
                qmp.type_text(value)
                qmp.key("ret")
                time.sleep(2.0)
                qmp.screenshot(f"{args.work}/screens/{name}-after.ppm")
            if "PAW3_STEP=" in line:
                log("STEP " + line.split("PAW3_STEP=", 1)[1])
            if "PAW3_CHAIN_RESULT=PASS" in line:
                chain_pass = True
                log("guest chain PASS marker seen; waiting for cloned target boot")
                target_deadline = time.time() + args.target_timeout
            if "PAW3_STEP=auto_reboot STATUS=PASS" in line and target_deadline is None:
                target_deadline = time.time() + args.target_timeout
            # The cloned target is the only system in this lab that reaches a
            # real getty login prompt; the live guest autologins on ttyS0.
            # Accept the login line even if the guest script was cut off by the
            # real reboot after it had already emitted every report step.
            if (final_phase or target_deadline is not None) and "login:" in line:
                target_boot_seen = True
        # getty writes its final "login: " prompt without a trailing newline, so
        # the line queue can legitimately hold it in SerialTail's partial buffer.
        # Check the captured stream itself; otherwise a real login prompt is
        # never classified until unrelated console output supplies a newline.
        snap = tail.snapshot()
        if "PAW_MEDIA_REMOVAL_REQUIRED" in snap and not media_removed:
            log("guest requested observable USB removal (snapshot); unplugging emulated USB stick")
            time.sleep(1.0)
            qmp.remove_usb_media()
            media_removed = True
            with open(f"{args.work}/share/usb-device-removed", "w", encoding="utf-8") as handle:
                handle.write("QMP device_del usb-media; PAW-MEDIA-123456 no longer present\n")
            qmp.screenshot(f"{args.work}/screens/media-after-removal.ppm")
        if ((final_phase or target_deadline is not None)
                and "login:" in snap):
            target_boot_seen = True
        if final_phase and target_deadline and time.time() > target_deadline and not target_boot_seen:
            result = "TARGET_BOOT_TIMEOUT"
            break
        if target_boot_seen:
            time.sleep(3)
            qmp.screenshot(f"{args.work}/screens/target-boot.ppm")
            result = "TARGET_BOOT_SEEN"
            break
        if "PAW3_CHAIN_RESULT=FAIL" in tail.snapshot():
            result = "CHAIN_FAIL"
            break
        time.sleep(0.5)
    if proc.poll() is None:
        qmp.quit()
        try:
            proc.wait(timeout=30)
        except subprocess.TimeoutExpired:
            proc.terminate()
    tail.finish()
    text = tail.snapshot()
    with open(f"{args.work}/console-main.log", "w", encoding="utf-8") as handle:
        handle.write(text)
    log(f"main result={result} chain_pass={chain_pass} target_boot={target_boot_seen} qemu_rc={proc.returncode}")
    return 0 if result in ("TARGET_BOOT_SEEN",) else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", required=True)
    ap.add_argument("--mode", choices=("prepare", "main"), required=True)
    ap.add_argument("--timeout", type=int, default=7200)
    ap.add_argument("--target-timeout", type=int, default=900)
    ap.add_argument("--memory", type=int, default=4096,
                    help="guest RAM MiB (host has ~6 GiB free; 4096 is the supported ceiling)")
    ap.add_argument("--direct-kernel", action="store_true",
                    help="boot vmlinuz/initrd directly instead of the guest GRUB")
    ap.add_argument("--initrd", default=None,
                    help="override initrd path for --direct-kernel")
    ap.add_argument("--append-extra", default="",
                    help="extra kernel command line words for --direct-kernel")
    ap.add_argument("--fw-cfg", action="append", default=[],
                    help="QEMU -fw_cfg NAME,FILE specification (repeatable)")
    ap.add_argument("--usb-media", default=None,
                    help="raw 32 GB USB Mass Storage image for --mode main (default WORK/boot/tf32.img)")
    args = ap.parse_args()
    os.makedirs(f"{args.work}/share", exist_ok=True)
    if args.mode == "prepare":
        return run_prepare(args)
    return run_main(args)


if __name__ == "__main__":
    sys.exit(main())
