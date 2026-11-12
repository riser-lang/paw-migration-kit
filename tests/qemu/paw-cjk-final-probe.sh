#!/usr/bin/env bash
# Test-only probe: run the production final-authorization script on tty1 with
# synthetic receipts, so QEMU can prove the Chinese authorization panel and the
# data-loss warning reach the framebuffer console.  Nothing is cloned: after the
# authorization is accepted the production script stops at the Rescue identity
# step, which has no endpoint in this guest.  No host or real disk is touched.
set -Eeuo pipefail
exec >/dev/tty1 2>&1

export PAW_ROOT=/opt/paw-migration
base=/opt/paw-migration/tests/final
export PAW_STATE_DIR="$base/state"
export PAW_CONFIG_DIR="$base/state/configs"
export PAW_REPORT_DIR="$base/state/reports"
export PAW_LOG_DIR="$base/state/logs"
# The production font unit writes its same-boot report into the virtual state
# selected by /etc/paw-migration.env; the final-confirm fixture keeps its own
# receipts in $base/state, so point the gate at the real boot report.
export PAW_FONT_GATE_REPORT=/opt/paw-migration/tests/virtual/state/reports/console-font.json
export PAW_INTERACTIVE_TTY=/dev/tty1
export PAW_INPUT_TIMEOUT=90
export PAW_TTY_SESSION_NAME=final-confirm
# The disposable target is a loop device in this fixture.  Opt the identity
# inventory into loop visibility explicitly; real systems never set this.
export PAW_IDENTITY_INCLUDE_LOOP=1
mkdir -p "$PAW_CONFIG_DIR" "$PAW_REPORT_DIR" "$PAW_LOG_DIR"

case_name=final
for arg in $(cat /proc/cmdline); do
  case "$arg" in
    paw.case=*) case_name="${arg#*=}" ;;
    paw.timeout=*) export PAW_INPUT_TIMEOUT="${arg#*=}" ;;
  esac
done

modprobe loop 2>/dev/null || true
for _ in $(seq 1 50); do [[ -e /dev/loop-control ]] && break; sleep 0.1; done
udevadm settle 2>/dev/null || true

# PAWDATA stand-in: a loop ext4 labelled PAWDATA, mounted for paw-data-check.
data_img="$base/pawdata.img"
rm -f "$data_img"
truncate -s 512M "$data_img"
mke2fs -q -F -t ext4 -L PAWDATA "$data_img"
data_loop="$(losetup -f --show "$data_img")"
pawdata_mount=/run/paw-final-pawdata
mkdir -p "$pawdata_mount"
mount "$data_loop" "$pawdata_mount"
export PAW_MOUNTPOINT_OVERRIDE="$pawdata_mount"

# Target-SSD stand-in: a loop device.  The lsblk shim reports a deterministic
# serial for it, so the authorization suffix is stable and never a real disk.
target_img="$base/target.img"
rm -f "$target_img"
truncate -s 1024M "$target_img"
target_loop="$(losetup -f --show "$target_img")"
export PAW_QEMU_LOOP_DEV="$target_loop"

boot_id="$(cat /proc/sys/kernel/random/boot_id)"
target_serial="$(lsblk -dn -o SERIAL "$target_loop" | xargs)"
target_bytes="$(blockdev --getsize64 "$target_loop")"
source_bytes=268435456
# Build the canonical UUID from integers so no UUID literal is committed.
root_uuid="$(printf '%08x-%04x-4%03x-8%03x-%012x' \
  $((0x11223344)) $((0x5566)) $((0x777)) $((0x888)) $((0x999999999999)))"
composite="$(printf 'a%.0s' {1..64})"
host_fp="SHA256:$(printf 'A%.0s' {1..43})"

printf 'PAW-CJK-FINAL-SETUP case=%s target=%s serial=%s bytes=%s boot=%s\n' \
  "$case_name" "$target_loop" "$target_serial" "$target_bytes" "$boot_id" >/dev/ttyS0

python3 - "$PAW_REPORT_DIR/live-readiness.json" <<'PY'
import json,sys
checks={"pawdata":"PASS","hardware":"PASS","memory":"PASS","source":"PASS","target":"PASS","network":"PASS"}
with open(sys.argv[1],"w",encoding="utf-8") as handle:
    json.dump({"schema":"paw.live-readiness.v1","status":"READY_FOR_OPERATOR",
               "clone_started":False,"checks":checks},handle,indent=2)
PY

python3 - "$PAW_CONFIG_DIR/source.json" "$PAW_CONFIG_DIR/target-ssd.json" \
  "$target_serial" "$target_bytes" "$target_loop" "$source_bytes" "$root_uuid" \
  "$composite" "$host_fp" <<'PY'
import json,sys
source_path,target_path,serial,capacity,device,source_bytes,uuid,composite,host_fp=sys.argv[1:]
source={"schema":"paw.source.v1","source_mode":"rescue","device_path":"/dev/vdz",
        "root_partition":"/dev/vdz2","partition_number":2,"model":"QEMU virtual source",
        "capacity_bytes":int(source_bytes),
        "serial":"","root_uuid":uuid,"serial_available":False,"partition_layout":"gpt",
        "composite_identity_sha256":composite,"ssh_host_key_fingerprint":host_fp,
        "identity_strength":"composite_no_serial","ssh_host":"rescue.invalid","ssh_port":22}
target={"schema":"paw.target-ssd.v1","device_path":device,"model":"QEMU virtual loop media",
        "serial":serial,"capacity_bytes":int(capacity),"registered_at":"2026-11-10T00:00:00+00:00"}
for path,document in ((source_path,source),(target_path,target)):
    with open(path,"w",encoding="utf-8") as handle: json.dump(document,handle,indent=2)
PY

python3 - "$PAW_REPORT_DIR/paw-hardware-health-report.json" "$PAW_REPORT_DIR/memtest-attestation.json" \
  "$target_serial" "$boot_id" <<'PY'
import json,sys
health_path,memtest_path,serial,boot=sys.argv[1:]
health={"schema":"paw.hardware-health.v1","status":"PASS","target_serial":serial,"boot_id":boot,
        "memory_status":"OPERATOR_CONFIRMED","checks":{"cpu":"PASS","memory":"OPERATOR_CONFIRMED",
        "ssd_smart":"PASS","ssd_read_scan":"PASS","temperature":"PASS","network":"PASS"}}
memtest={"schema":"paw.memtest-attestation.v1","status":"OPERATOR_CONFIRMED","result":"PASS",
         "boot_id":boot,"target_serial":serial,"passes":1,"errors":0,
         "trust_level":"operator_attestation_not_cryptographic"}
for path,document in ((health_path,health),(memtest_path,memtest)):
    with open(path,"w",encoding="utf-8") as handle: json.dump(document,handle,indent=2)
PY

# Attempt 1 expects a wrong suffix (rejected), attempt 2 the correct one.
for attempt in 1 2; do
  printf 'PAW-CJK-FINAL-ATTEMPT=%s\n' "$attempt" >/dev/ttyS0
  set +e
  /opt/paw-migration/scripts/paw-final-confirm.sh
  rc=$?
  set -e
  printf 'PAW-CJK-FINAL-RC=%s attempt=%s\n' "$rc" "$attempt" >/dev/ttyS0
done
printf 'PAW-CJK-FINAL-DONE\n' >/dev/ttyS0
# Keep the guest alive so the harness can take a final screendump.
sleep 300
