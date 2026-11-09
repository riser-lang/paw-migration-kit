#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
logf="$PAW_ROOT/logs/memtest86plus-serial.log"; out="$PAW_REPORT_DIR/memory-test.json"
if [[ ! -s "$logf" ]]; then write_status WARN 'Memtest86+ was not run or produced no serial log.' "$out"; exit 2; fi
if grep -Eiq 'errors[=: ]+[1-9]|FAIL|ERROR' "$logf"; then write_status FAIL 'Memtest86+ reported an error.' "$out"; exit 1; fi
if grep -Eiq 'PASS|completed.*0 errors|0 errors' "$logf"; then write_status PASS 'Completion evidence found; confirm full memory coverage.' "$out"; else write_status WARN 'No definitive completion summary.' "$out"; exit 2; fi
