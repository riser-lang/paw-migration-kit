#!/usr/bin/env python3
"""Copy a byte stream while atomically recording the exact payload length."""
import argparse
import os
from pathlib import Path
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--count-file", required=True)
args = parser.parse_args()
count_path = Path(args.count_file)
temporary = count_path.with_name(count_path.name + ".tmp")
count = 0
try:
    with sys.stdout.buffer as output:
        while True:
            chunk = sys.stdin.buffer.read(1024 * 1024)
            if not chunk:
                break
            output.write(chunk)
            count += len(chunk)
        output.flush()
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="ascii") as handle:
        handle.write(f"{count}\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, count_path)
except (BrokenPipeError, OSError):
    try:
        temporary.unlink()
    except FileNotFoundError:
        pass
    raise
