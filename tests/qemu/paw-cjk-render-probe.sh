#!/usr/bin/env bash
# Test-only: run the production finalizer on tty1 with a mock reboot and a
# short countdown, so QEMU can prove the Chinese completion prompt renders.
set -Eeuo pipefail
exec >/dev/tty1 2>&1
export PAW_ROOT=/opt/paw-migration
export PAW_STATE_DIR=/opt/paw-migration/tests/finalize/state
export PAW_CONFIG_DIR="$PAW_STATE_DIR/configs"
export PAW_REPORT_DIR="$PAW_STATE_DIR/reports"
export PAW_LOG_DIR="$PAW_STATE_DIR/logs"
export PAW_INTERACTIVE_TTY=/dev/tty1
export PAW_REBOOT_COUNTDOWN_SECONDS=5
export PAW_REBOOT_CMD=/bin/true
mkdir -p "$PAW_CONFIG_DIR" "$PAW_REPORT_DIR" "$PAW_LOG_DIR"
cat >"$PAW_REPORT_DIR/stream-verify.json" <<'JSON'
{"status":"PASS","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","bytes_verified":1024,"independent_sha256_verified":true}
JSON
printf '{"status":"PASS"}\n' >"$PAW_REPORT_DIR/offline-repair.json"
printf '{"status":"PASS","before_bytes":100,"after_bytes":200}\n' >"$PAW_REPORT_DIR/gpt-expand.json"
printf '{"status":"PASS","clone_sha256":"%s"}\n' "$(printf 'a%.0s' {1..64})" >"$PAW_REPORT_DIR/firstboot-check.json"
cat >"$PAW_STATE_DIR/completion.json" <<'JSON'
{"schema":"paw.migration-completion.v2","status":"PASS","checks":{"clone":"PASS","sha256":"PASS","offline_repair":"PASS","gpt_ext4_expand":"PASS","firstboot":"PASS"}}
JSON
cat >"$PAW_REPORT_DIR/operator-authorization.json" <<'JSON'
{"status":"AUTHORIZED","target_serial":"QEMU-123456","target_device":"/dev/loop0"}
JSON
chmod 0600 "$PAW_REPORT_DIR/operator-authorization.json"
echo 'PAW-CJK-RENDER-START' >/dev/ttyS0
set +e
/opt/paw-migration/scripts/paw-finalize-reboot.sh \
  --completion-data "$PAW_STATE_DIR/completion.json" \
  --receipt "$PAW_REPORT_DIR/migration-completion.json" \
  --authorization "$PAW_REPORT_DIR/operator-authorization.json"
rc=$?
set -e
echo "PAW-CJK-FINALIZE-RC=$rc" >/dev/ttyS0
echo "PAW-CJK-RENDER-READY" >/dev/ttyS0
sleep 300
