# PAW v2.7.1 第 1 段实施计划（P0-A + P0-B）

日期：2026-11-10（本地）
基线：fix/v2.6.2-final-readiness @ 825ac38
范围：只做克隆后自动重启 + tty1 交互修复；不做 ISO 构建/哈希复核。

## P0-A 自动重启

新增 `scripts/paw-finalize-reboot.sh`，职责严格按顺序：
1. 读取并校验证据：stream-verify.json、offline-repair.json、gpt-expand.json、firstboot-check.json。
2. 校验 completion-data（status=PASS，checks 全 PASS）。
3. 原子写入 migration-completion.json（tmp + fsync + rename + 目录 fsync）。
4. 回读校验完成记录。
5. 原子消费 operator-authorization.json。
6. `sync`。
7. 中文成功提示 + 10 秒可取消倒计时（默认值 10，测试可缩短）。
8. 执行 `PAW_REBOOT_CMD`（默认 `systemctl reboot`）；失败则状态 NEEDS_MANUAL_ACTION。
取消：状态 CANCELLED，reboot_invoked=false。
前置失败：不进入倒计时，状态 BLOCKED/FAIL，reboot 调用次数 0。

新增 `scripts/paw-atomic-write.py`（JSON 原子写，0600，fsync 文件与目录）。
`paw-gpt-expand.sh` 增写 gpt-expand.json；`paw-firstboot-check.sh` 增写 firstboot-check.json。
`paw-final-confirm.sh` 末尾改为调用 finalizer，不再自己写完成记录。

## P0-B tty1

新增 `scripts/paw-tty-lib.sh`：
- 默认 `/dev/tty1`，显式 `exec 3<>/dev/tty1`，所有提示/读取走 fd3。
- 写 tty 会话状态 JSON：实际路径、rdev、每个阶段 tty1 持有者 PID/comm、ASCII 标记。
- 输入超时可配置；默认安全长超时（300s），测试缩短。

`paw-data-prepare.sh` auto：中文面板 + 序列号输入同一 fd3；成功/错误/超时分别写状态与 ASCII 标记。
`paw-console-menu.sh`：同样显式 fd3，菜单输入写状态。
unit：
- paw-data-init: TTYPath=/dev/tty1, stdin=tty, stdout/stderr=journal, Conflicts=getty@tty1, Before=console。
- paw-console: TTYPath=/dev/tty1, After=data-init, Conflicts=getty@tty1。
- paw-tailscale-join: 不再占用 tty；登录 URL 写报告，串口/journal 留日志。

## 证据矩阵

| 用例 | 方式 | 判定 |
|---|---|---|
| A1 全成功 | finalizer + mock reboot | status PASS，reboot=1 |
| A2 完成记录写失败 | receipt 指向不存在目录 | reboot=0，status FAIL |
| A3 SHA 失败 | stream-verify FAIL | reboot=0，status BLOCKED |
| A4 离线修复失败 | offline-repair FAIL | reboot=0 |
| A5 reboot 失败 | mock reboot exit 1 | 手动提示，status NEEDS_MANUAL_ACTION |
| A6 倒计时取消 | stdin 注入 c | reboot=0，status CANCELLED |
| A7 反向断言 | 所有失败路径 | reboot 计数必须 0 |
| B1 屏幕提示 | QEMU -vga std + screendump | 帧缓存 ASCII 标记 |
| B2 正确序列号 | QEMU sendkey | 状态文件 INPUT-OK |
| B3 错误序列号 | QEMU sendkey | 中文原因，INPUT-BAD |
| B4 无输入超时 | 缩短超时 | TIMEOUT，未分区 |
| B5 菜单同终端 | QEMU screendump + 状态 | menu_tty == input_tty |
| B6 单占用 | 状态文件 holders + unit 静态审计 | tty1 仅 1 个持有者 |

## 保护边界

只使用 loop 镜像/QEMU 虚拟盘；不触碰任何真实块设备、旧 VPS、网络配置、TF 卡、生产 PAW。
不合并 PR #2；不修改仓库可见性。

## 执行结果（2026-11-10 本地）

- P0-A finalize 故障注入：36/36 PASS（真实进程 + mock reboot，非真实重启）。
- P0-B 静态/结构：29/29 PASS；pty 因沙箱禁止 /dev/ptmx 标记 BLOCKED（QEMU 覆盖）。
- P0-B QEMU：ok 11/11、bad 7/7、timeout 6/6，共 24 项 PASS；screendump 字形匹配 399/399。
- 中文控制台字形：BLOCKED（vgacon 无 CJK 字体，见 docs/PAW-V2.7.1-BLOCKERS.md B01）。
- 未重跑原有 79 项 loop 套件（本机 sudo/losetup 不可用）；未构建 ISO（第 3 段）。
