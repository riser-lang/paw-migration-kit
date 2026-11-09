#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
report="$out/tty-virtual-test-report.txt"
mkdir -p "$out"
passed=0; failed=0; blocked=0
pass(){ printf 'PASS %s\n' "$1" >>"$report"; passed=$((passed+1)); }
fail(){ printf 'FAIL %s\n' "$1" >>"$report"; failed=$((failed+1)); }
blocked_note(){ printf 'BLOCKED %s\n' "$1" >>"$report"; blocked=$((blocked+1)); }
has(){ grep -Eq "$2" "$1"; }

printf 'PAW tty1 binding and single-owner virtual tests\n' >"$report"
printf 'Executed: %s\n' "$(date -u +%FT%TZ)" >>"$report"

data="$root/boot/paw-data-init.service"
console="$root/boot/paw-console.service"
tailscale="$root/boot/paw-tailscale-join.service"

has "$data" '^TTYPath=/dev/tty1$' && pass 'B1 paw-data-init TTYPath=/dev/tty1' || fail 'B1 paw-data-init TTYPath 不是 /dev/tty1'
has "$console" '^TTYPath=/dev/tty1$' && pass 'B5 paw-console TTYPath=/dev/tty1' || fail 'B5 paw-console TTYPath 不是 /dev/tty1'
has "$data" '^StandardInput=tty$' && has "$console" '^StandardInput=tty$' && pass 'B1 两个交互单元都使用控制终端 stdin' || fail 'B1 交互单元 stdin 配置错误'
has "$data" '^Conflicts=getty@tty1\.service$' && pass 'B6 paw-data-init 显式压制 getty@tty1' || fail 'B6 paw-data-init 未压制 getty@tty1'
has "$console" '^Conflicts=getty@tty1\.service$' && pass 'B6 paw-console 显式压制 getty@tty1' || fail 'B6 paw-console 未压制 getty@tty1'
has "$data" '^Before=.*paw-console\.service' && pass 'B6 paw-data-init 排在 paw-console 之前' || fail 'B6 缺少 Before=paw-console'
has "$console" '^After=.*paw-data-init\.service' && pass 'B6 paw-console 排在 paw-data-init 之后' || fail 'B6 缺少 After=paw-data-init'
has "$data" '^After=.*getty@tty1\.service' && has "$console" '^After=.*getty@tty1\.service' && pass 'B6 getty 停止顺序被显式约束' || fail 'B6 缺少 getty 停止顺序'

other_owner=0
for unit in "$root"/boot/*.service; do
  [[ "$unit" == "$data" || "$unit" == "$console" ]] && continue
  if grep -Eq '^TTYPath=' "$unit"; then other_owner=1; fail "B6 其它单元占用终端：$(basename "$unit")"; fi
done
((other_owner == 0)) && pass 'B6 除 data-init/console 外没有其它单元声明 TTYPath'
! grep -Rqs '^TTYPath=/dev/console$' "$root/boot" && pass 'B6 没有单元再把交互终端指向 /dev/console' || fail 'B6 仍存在 TTYPath=/dev/console'
! grep -q '^TTYPath=' "$tailscale" && pass 'B6 paw-tailscale-join 不再占用 tty1' || fail 'B6 tailscale-join 仍占用 tty'

grep -q 'PAW_INTERACTIVE_TTY:-/dev/tty1' "$root/scripts/paw-tty-lib.sh" && pass 'B1 tty 库默认 /dev/tty1' || fail 'B1 tty 库默认不是 /dev/tty1'
grep -q 'exec 3<>"\$PAW_TTY_DEV"' "$root/scripts/paw-tty-lib.sh" && pass 'B1 交互读写使用同一个显式 fd' || fail 'B1 未显式打开交互 fd'
grep -q 'read -r -t "\$PAW_TTY_TIMEOUT" -u 3' "$root/scripts/paw-tty-lib.sh" && pass 'B4 输入超时走同一个 fd3' || fail 'B4 输入超时未绑定 fd3'
for marker in PAW-TTY1-MENU PAW-TTY1-PROMPT PAW-TTY1-INPUT-OK PAW-TTY1-INPUT-BAD PAW-TTY1-INPUT-TIMEOUT PAW-MENU-TTY1; do
  grep -Rqs "$marker" "$root/scripts" && pass "B1 ASCII 屏幕标记存在：$marker" || fail "B1 缺少 ASCII 标记：$marker"
done
grep -q 'paw_tty_confirm_serial_suffix' "$root/scripts/paw-data-prepare.sh" && pass 'B5 PAWDATA 面板与序列号输入共用同一实现' || fail 'B5 PAWDATA 未共用 tty 确认函数'
grep -q 'paw_tty_record menu shown' "$root/scripts/paw-data-prepare.sh" && pass 'B5 PAWDATA 面板阶段写入 tty 状态' || fail 'B5 PAWDATA 未记录面板阶段'
grep -q 'paw_tty_record menu shown' "$root/scripts/paw-console-menu.sh" && pass 'B5 中文控制台菜单写入 tty 状态' || fail 'B5 控制台菜单未记录 tty 状态'
! grep -Eq '^[^#]*read -r -p ' "$root/scripts/paw-data-prepare.sh" "$root/scripts/paw-console-menu.sh" && pass 'B5 交互脚本不再使用隐式 stdin 提示' || fail 'B5 仍存在隐式 stdin 交互'
! grep -q '/dev/console' "$root/scripts/paw-data-prepare.sh" "$root/scripts/paw-console-menu.sh" && pass 'B1 交互脚本不引用 /dev/console' || fail 'B1 交互脚本仍引用 /dev/console'
grep -q 'journal+console' "$data" && pass 'B1 串口/journal 仍保留诊断日志' || fail 'B1 缺少串口诊断日志'
grep -q 'login_url' "$root/scripts/paw-tailscale-join.sh" && pass 'B6 Tailscale 登录链接改为报告文件，不抢终端' || fail 'B6 Tailscale 登录链接仍写终端'
grep -q 'export PAW_DATA_CONFIRM_SUFFIX' "$root/scripts/paw-data-prepare.sh" && pass 'B5 已确认的序列号末六位复用给分区助手，避免第二次隐式提示' || fail 'B5 分区助手可能再次提示'
grep -q 'PAW_DATA_CONFIRM_SUFFIX' "$root/scripts/paw-prepare-data-partition.sh" && pass 'B5 分区助手支持复用 tty1 已确认值' || fail 'B5 分区助手未复用确认值'

printf 'Static tty assertions: %s passed, %s failed\n' "$passed" "$failed" >>"$report"

set +e
PAW_ROOT="$root" python3 "$root/scripts/ci/pty_tty_test.py" >"$out/pty-tty-test.log" 2>&1
pty_rc=$?
set -e
cat "$out/pty-tty-test.log" >>"$report"
if ((pty_rc == 0)); then
  pass 'B2/B3/B4/B5/B6 pty 真实交互测试全部通过'
elif ((pty_rc == 77)); then
  if [[ ${PAW_REQUIRE_PTY:-0} == 1 ]]; then
    fail 'B2-B6 pty 设备不可用，但 PAW_REQUIRE_PTY=1 要求真实执行'
  else
    blocked_note 'B2-B6 本机沙箱禁止 /dev/ptmx；pty 行为测试未能本地执行，真实 tty1 由 QEMU 用例覆盖'
  fi
else
  fail "B2-B6 pty 交互测试失败，退出码 $pty_rc"
fi

printf 'Summary: %s passed, %s failed, %s blocked\n' "$passed" "$failed" "$blocked" >>"$report"
cat "$report"
((failed == 0))
