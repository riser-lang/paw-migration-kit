#!/usr/bin/env python3
"""Exercise the shared tty helper through a real pty.

The production service uses /dev/tty1.  This test substitutes a pty through
PAW_INTERACTIVE_TTY, injects bytes from the master side (the same direction as
a keyboard), and verifies that the helper reads/writes one fd and records the
resolved terminal and its holders.
"""
import json
import os
import pty
import select
import subprocess
import sys
import tempfile
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FAILED = 0
PASSED = 0


def say(ok: bool, label: str, detail: str = "") -> None:
    global FAILED, PASSED
    if ok:
        print(f"PASS {label}")
        PASSED += 1
    else:
        FAILED += 1
        print(f"FAIL {label} {detail}".rstrip())


def read_until(fd: int, needle: str, deadline: float) -> str:
    chunks = []
    while time.time() < deadline:
        remaining = max(0.0, deadline - time.time())
        ready, _, _ = select.select([fd], [], [], min(remaining, 0.2))
        if not ready:
            continue
        try:
            data = os.read(fd, 4096)
        except OSError:
            break
        if not data:
            break
        chunks.append(data.decode("utf-8", "replace"))
        if needle in "".join(chunks):
            break
    return "".join(chunks)


def run_case(name: str, serial: str, injected: bytes | None, timeout: str) -> dict:
    work = tempfile.mkdtemp(prefix=f"paw-pty-{name}-")
    reports = os.path.join(work, "reports")
    logs = os.path.join(work, "logs")
    os.makedirs(reports)
    os.makedirs(logs)
    try:
        master, slave = pty.openpty()
    except OSError as exc:
        print(f"BLOCKED pty unavailable: {exc}")
        return {"blocked": str(exc)}
    slave_name = os.ttyname(slave)
    session = os.path.join(reports, "tty-session.json")
    child = (
        'set -Eeuo pipefail\n'
        'source "$PAW_ROOT/scripts/paw-lib.sh"\n'
        'source "$PAW_ROOT/scripts/paw-tty-lib.sh"\n'
        'paw_tty_open || exit 9\n'
        'paw_tty_record menu shown "PAWDATA panel" "PAW-TTY1-MENU"\n'
        'printf "[PAW-TTY1-MENU]\\n" >&3\n'
        'paw_tty_say "PAW 首次启动 · PAWDATA 持久分区初始化"\n'
        'set +e\n'
        f'paw_tty_confirm_serial_suffix "{serial}"\n'
        'rc=$?\n'
        'set -e\n'
        'paw_tty_close\n'
        'exit "$rc"\n'
    )
    env = dict(os.environ)
    env.update(
        PAW_ROOT=ROOT,
        PAW_STATE_DIR=work,
        PAW_CONFIG_DIR=os.path.join(work, "configs"),
        PAW_REPORT_DIR=reports,
        PAW_LOG_DIR=logs,
        PAW_INTERACTIVE_TTY=slave_name,
        PAW_TTY_SESSION_FILE=session,
        PAW_TTY_SESSION_NAME="pty-test",
        PAW_INPUT_TIMEOUT=timeout,
    )
    proc = subprocess.Popen(
        ["bash", "-c", child],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        env=env,
        text=False,
    )
    os.close(slave)
    deadline = time.time() + 12
    output = read_until(master, "PAW-TTY1-PROMPT", deadline)
    if injected is not None:
        os.write(master, injected)
        output += read_until(master, "PAW-TTY1-INPUT-", deadline)
    try:
        proc.wait(timeout=8)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    # Drain whatever is left.
    while True:
        ready, _, _ = select.select([master], [], [], 0.1)
        if not ready:
            break
        try:
            data = os.read(master, 4096)
        except OSError:
            break
        if not data:
            break
        output += data.decode("utf-8", "replace")
    os.close(master)
    stderr = proc.stderr.read().decode("utf-8", "replace") if proc.stderr else ""
    document = {}
    if os.path.exists(session):
        with open(session, encoding="utf-8") as handle:
            document = json.load(handle)
    return {"work": work, "rc": proc.returncode, "output": output,
            "stderr": stderr, "session": document, "slave": slave_name}


def markers(session: dict) -> list[str]:
    return list(session.get("markers") or [])


def main() -> int:
    print("PAW tty helper pty interaction tests")

    result = run_case("ok", "PAW-SERIAL-123456", b"123456\n", "5")
    if "blocked" in result:
        print("BLOCKED local pty device unavailable; QEMU covers real tty1")
        return 77
    session = result["session"]
    say(result["rc"] == 0, "B2 正确序列号末六位被接受", f"rc={result['rc']} {result['stderr'][-200:]}")
    say("PAW-TTY1-INPUT-OK" in markers(session), "B2 写入 INPUT-OK 状态标记")
    say(session.get("tty_path") == result["slave"], "B2 状态文件记录实际输出 tty 为注入的 pty", session.get("tty_path", ""))
    say(session.get("menu_tty") == session.get("input_tty") == result["slave"],
        "B5 中文面板与序列号输入使用同一终端")
    say(int(session.get("max_holders", 99)) == 1,
        "B6 交互期间该终端只有一个非辅助进程持有者", f"max_holders={session.get('max_holders')}")
    say("PAW-TTY1-MENU" in result["output"] and "PAW-TTY1-PROMPT" in result["output"],
        "B1 面板与提示 ASCII 标记出现在终端输出")

    result = run_case("bad", "PAW-SERIAL-123456", b"000000\n", "5")
    session = result["session"]
    say(result["rc"] == 1, "B3 错误序列号被拒绝", f"rc={result['rc']}")
    say("PAW-TTY1-INPUT-BAD" in markers(session), "B3 写入 INPUT-BAD 状态标记")
    say("不匹配" in result["output"], "B3 输出中文错误原因")
    say(int(session.get("max_holders", 99)) == 1, "B3 拒绝路径仍只有一个终端持有者")

    result = run_case("timeout", "PAW-SERIAL-123456", None, "1")
    session = result["session"]
    say(result["rc"] == 2, "B4 无输入超时后安全停止", f"rc={result['rc']}")
    say("PAW-TTY1-INPUT-TIMEOUT" in markers(session), "B4 写入 INPUT-TIMEOUT 状态标记")
    say("已安全停止" in result["output"], "B4 输出中文安全停止说明")

    result = run_case("abort", "PAW-SERIAL-123456", b"", "5")
    session = result["session"]
    say(result["rc"] == 2, "B4b 输入流提前关闭时安全停止", f"rc={result['rc']}")
    say(bool({"PAW-TTY1-INPUT-ABORTED", "PAW-TTY1-INPUT-TIMEOUT"} & set(markers(session))),
        "B4b 写入 ABORTED/TIMEOUT 状态标记")

    print(f"Summary: {PASSED} passed, {FAILED} failed")
    return 0 if FAILED == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
