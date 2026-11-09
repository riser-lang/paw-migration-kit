#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
log INFO 'Live environment preflight; read-only.'
[[ -d /run/live ]] || log WARN 'Live-system marker /run/live not found.'
for c in uname awk grep lsblk ip; do need "$c"; done
[[ "$(uname -m)" == x86_64 ]] || die 'Unsupported architecture (x86_64 required).'
mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"; ((mem_kb >= 2048000)) || die "Insufficient RAM: ${mem_kb}kB"
[[ -r /sys/firmware/efi/fw_platform_size ]] && firmware=UEFI || firmware=Legacy_or_unknown
ip -brief address || true; lsblk -e7 -o NAME,TYPE,SIZE,MODEL,SERIAL,TRAN,FSTYPE,MOUNTPOINTS || true
log INFO "architecture=x86_64 firmware=$firmware memory_kb=$mem_kb"
