#!/usr/bin/env python3
"""Atomically replace a file with JSON read from stdin.

The temporary file is created in the destination directory, written with mode
0600, flushed and fsynced, renamed over the destination, and the directory is
fsynced so a crash cannot leave a half-written completion record.
"""
import json
import os
import sys
import tempfile


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: paw-atomic-write.py DEST", file=sys.stderr)
        return 2
    dest = os.path.abspath(sys.argv[1])
    raw = sys.stdin.buffer.read()
    if not raw.strip():
        print("refusing to write an empty JSON document", file=sys.stderr)
        return 2
    try:
        json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        print(f"refusing to write invalid JSON: {exc}", file=sys.stderr)
        return 2
    parent = os.path.dirname(dest) or "."
    if not os.path.isdir(parent):
        print(f"destination directory does not exist: {parent}", file=sys.stderr)
        return 2
    if os.path.isdir(dest):
        print(f"destination is a directory: {dest}", file=sys.stderr)
        return 2
    fd = -1
    tmp = ""
    try:
        fd, tmp = tempfile.mkstemp(prefix=".paw-atomic-", dir=parent)
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as handle:
            fd = -1
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, dest)
        tmp = ""
        dir_fd = os.open(parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except OSError as exc:
        print(f"atomic write failed: {exc}", file=sys.stderr)
        return 1
    finally:
        if fd >= 0:
            os.close(fd)
        if tmp:
            try:
                os.unlink(tmp)
            except OSError:
                pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
