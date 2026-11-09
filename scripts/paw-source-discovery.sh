#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need lsblk; log INFO 'Read-only source discovery.'
lsblk -e7 -b -o NAME,PATH,TYPE,SIZE,MODEL,SERIAL,TRAN,RO,FSTYPE,UUID,MOUNTPOINTS
[[ -r "$PAW_CONFIG_DIR/source.json" ]] || { log WARN 'Source is not enrolled; clone remains disabled.'; exit 2; }
grep -q '"source_mode": "rescue"' "$PAW_CONFIG_DIR/source.json" || die 'Source is not in Rescue Mode.'
