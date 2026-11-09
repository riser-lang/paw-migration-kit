#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need mountpoint; need findmnt; need blkid; need df
mount_dir="${PAW_MOUNTPOINT_OVERRIDE:-/var/lib/paw-migration}"
min_free="${PAW_STATE_MIN_FREE_BYTES:-67108864}"
[[ "$min_free" =~ ^[0-9]+$ ]] || die 'Invalid PAWDATA free-space threshold.'
if ! mountpoint -q "$mount_dir"; then
  write_status WARN 'PAWDATA is absent; state would be volatile and clone remains blocked.' "$PAW_REPORT_DIR/paw-data-health.json"
  log WARN 'PAWDATA mount missing.'; exit 2
fi
source_dev="$(findmnt -n -o SOURCE --target "$mount_dir")"
fs_type="$(findmnt -n -o FSTYPE --target "$mount_dir")"
label="$(blkid -s LABEL -o value "$source_dev" 2>/dev/null || true)"
[[ "$fs_type" == ext4 && "$label" == PAWDATA ]] || { write_status FAIL 'PAWDATA mount source or filesystem does not match the expected ext4 label.' "$PAW_REPORT_DIR/paw-data-health.json"; die 'PAWDATA filesystem identity mismatch.'; }
free_bytes="$(df -B1 --output=avail "$mount_dir" | tail -n1 | tr -d ' ')"
[[ "$free_bytes" =~ ^[0-9]+$ ]] || die 'Could not read PAWDATA free space.'
if ((free_bytes < min_free)); then
  write_status WARN "PAWDATA free space is below the required minimum (${min_free} bytes)." "$PAW_REPORT_DIR/paw-data-health.json"
  log WARN 'PAWDATA free space is insufficient; clone remains blocked.'; exit 2
fi
probe="$mount_dir/.paw-write-test.$$"
if ! (umask 077; : >"$probe") 2>/dev/null; then
  write_status FAIL 'PAWDATA is not writable.' "$PAW_REPORT_DIR/paw-data-health.json"
  die 'PAWDATA write probe failed.'
fi
rm -f "$probe"; sync
write_status PASS 'PAWDATA label, ext4 mount, write check and free-space threshold passed.' "$PAW_REPORT_DIR/paw-data-health.json"
log INFO 'PAWDATA mount and free-space gate passed.'
