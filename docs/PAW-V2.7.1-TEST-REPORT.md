# PAW v2.7.1 第 1 段测试报告（P0-A 自动重启 / P0-B tty1）

执行日期：2026-11-10（本地）
分支：`fix/v2.6.2-final-readiness`
基线：`825ac38c7ec86ec667b17e33294aa78561eb2b1c`
本段关键提交：`b141e74`、`e5aebad`、`986b3ef`、`48583cf`（最终以 `git log` 为准）
PR #2：保持 Draft，未合并。

## 1. 范围与执行方式

本段只做两件事：

- P0-A：克隆完成后，仅在所有门禁通过时原子写完成记录、`sync`、中文提示、可取消倒计时、自动 reboot。
- P0-B：把 PAWDATA 交互和中文控制台显式绑定到 `/dev/tty1`，串口只保留日志，并证明 tty1 单一占用。

执行方式分三层，报告中逐项标明：

1. **真实执行（虚拟文件/真实进程）**：`run-finalize-virtual-tests.sh` 启动真实
   `paw-finalize-reboot.sh` 进程，使用真实原子写、真实倒计时、真实 mock reboot 命令。
2. **真实执行（QEMU 虚拟硬件）**：`run-tty-qemu-tests.sh` 用 QEMU TCG、`-vga std`、
   `screendump`、VGA 文本帧缓存 `pmemsave`、`sendkey` 键盘注入，启动 Debian 13
   loop 镜像，不使用真实硬盘/串口输入。
3. **静态/结构检查**：systemd unit 指令、脚本调用顺序、ASCII 标记存在性。静态检查
   不冒充运行时测试，单独计数。

未执行真实克隆、未重启真实机器、未触碰旧 VPS/生产 PAW/TF 卡/真实块设备。

## 2. P0-A 结果

命令：

```bash
PAW_ARTIFACT_DIR="$PWD/artifacts" scripts/ci/run-finalize-virtual-tests.sh
```

真实结果：**36 passed, 0 failed**（日志：`artifacts/finalize-virtual-test-report.txt`）。

| 用例 | 注入 | 结果 | 关键判定 |
|---|---|---|---|
| A1 全成功 | 四个 PASS 证据 + 可写完成记录 | PASS | 状态 `PASS`，reboot 调用 1 次，完成记录 0600，授权变 `CONSUMED`，无原子写临时文件 |
| A2 完成记录写失败 | receipt 指向不存在目录 | PASS | 返回非 0，状态 `FAIL`，reboot 0 次，无倒计时 |
| A3 SHA256 失败 | `stream-verify.json` 为 FAIL/未独立校验 | PASS | 状态 `BLOCKED`，reboot 0 次，无倒计时 |
| A4 离线修复失败 | `offline-repair.json` 为 FAIL | PASS | 状态 `BLOCKED`，reboot 0 次，无倒计时 |
| A4b GPT/ext4 扩容失败 | `gpt-expand.json` 为 FAIL | PASS | 状态 `BLOCKED`，reboot 0 次 |
| A4c 首次启动检查失败 | `firstboot-check.json` 为 FAIL | PASS | 状态 `BLOCKED`，reboot 0 次 |
| A5 reboot 命令失败 | mock reboot 退出码 9 | PASS | 状态 `NEEDS_MANUAL_ACTION`，输出中文手动重启提示和 `systemctl reboot` |
| A6 倒计时取消 | 向 stdin 注入 `c` | PASS | 状态 `CANCELLED`，`reboot_invoked=false`，输出“已取消自动重启，请手动重启” |
| A7 反向断言 | 汇总以上失败/取消路径 | PASS | reboot 总调用次数 = 0 |
| A8 完成数据不完整 | checks 缺少步骤 | PASS | 状态 `BLOCKED`，reboot 0 次 |
| A9 成功路径重跑 | 已完成 PASS 再运行 | PASS | 不重复 reboot（仍为 1 次） |
| A0 结构检查 | 检查 `paw-final-confirm.sh` | PASS | finalizer 在 firstboot 之后调用；旧的非原子完成记录写入已移除 |

实现要点：

- 新增 `scripts/paw-atomic-write.py`：同目录临时文件、0600、`fsync(file)`、
  `os.replace`、`fsync(dir)`；空/invalid JSON 拒绝写入。
- 新增 `scripts/paw-finalize-reboot.sh`：独立复核 4 份证据 + completion data；
  原子写完成记录并回读；原子消费授权；`sync`；中文成功提示；默认 10 秒倒计时；
  可注入 `PAW_REBOOT_CMD`，默认 `systemctl reboot`；取消/失败状态分开记录。
- `paw-gpt-expand.sh` 增写 `gpt-expand.json`；`paw-firstboot-check.sh` 增写
  `firstboot-check.json`；`paw-final-confirm.sh` 末尾改为调用 finalizer。

说明：这是**故障注入 + mock reboot**，不是真实重启。默认 `systemctl reboot`
未被本段在宿主机执行（会违反“不重启真实机器”的边界）；默认路径由代码和
单元测试的注入开关覆盖，真实硬件重启留给第 3 段/实机验收。

## 3. P0-B 结果

### 3.1 静态与结构检查

命令：

```bash
PAW_ARTIFACT_DIR="$PWD/artifacts" scripts/ci/run-tty-virtual-tests.sh
```

真实结果：**29 passed, 0 failed, 1 blocked**（日志：`artifacts/tty-virtual-test-report.txt`）。

覆盖：

- `paw-data-init.service`、`paw-console.service` 均为 `TTYPath=/dev/tty1`。
- 两个单元均 `Conflicts=getty@tty1.service`，且 `After=getty@tty1.service`。
- data-init `Before=paw-console.service`，console `After=paw-data-init.service`。
- 除这两个单元外，`boot/*.service` 没有其它 `TTYPath=`；`/dev/console` 不再作为交互终端。
- `paw-tailscale-join` 不再占用 tty，登录 URL 写入报告文件。
- 交互脚本使用 `exec 3<>$PAW_TTY_DEV`、`read ... -u 3`，不再使用隐式 stdin 提示。
- 屏幕 ASCII 标记：`PAW-TTY1-MENU`、`PAW-TTY1-PROMPT`、`PAW-TTY1-INPUT-OK/BAD/TIMEOUT`、`PAW-MENU-TTY1`。
- data-init 把已确认的序列号末六位复用给分区助手，避免第二次隐式提示。

**BLOCKED（本机）**：pty 行为测试因当前沙箱禁止 `/dev/ptmx`（`out of pty devices`）
未能本地执行；同一套 `paw-tty-lib.sh` 由下面的 QEMU 真实 tty1 用例覆盖。
CI 中该套件以 `PAW_REQUIRE_PTY=1` 运行，pty 不可用会直接失败，不会静默跳过。

### 3.2 QEMU 虚拟显示器 + 键盘注入

命令：

```bash
PAW_ARTIFACT_DIR="$PWD/artifacts" tests/qemu/run-tty-qemu-tests.sh
```

环境：QEMU 8.2.2 TCG，`-machine pc`，1 GiB，2 vCPU，`-vga std`，
测试盘构建自已提交 `986b3ef`；之后的 `48583cf` 只修正非 simulation 分支的长度展开和
安全检查字面量，QEMU 用例走 simulation，不经过该修正分支。
Debian 13 一次性 ext4 测试盘（loop 镜像内再建 512 MiB GPT 虚拟盘）。
不是最终 PAW ISO，也不是真实 ASUS 主板。

真实结果：**3 cases passed, 0 failed, 0 blocked**；
断言 **24 passed, 0 failed**（日志：`artifacts/qemu-tty/qemu-tty-test-report.txt`）。

| 用例 | 注入方式 | 结果 | 关键证据 |
|---|---|---|---|
| B1/B2/B5/B6 正确 | `sendkey 1..6 + ret` | PASS 11/11 | 提示/接受/菜单均出现在 VGA 帧缓存；状态文件 `tty_path=/dev/tty1`；`menu_tty=input_tty=/dev/tty1`；`max_holders=1` |
| B3 错误 | `sendkey 000000 + ret` | PASS 7/7 | `PAW-TTY1-INPUT-BAD`；无 `INPUT-OK`；状态记录同一 tty1；`max_holders=1` |
| B4 超时 | 不注入，`paw.timeout=5` | PASS 6/6 | 5 秒后 `PAW-TTY1-INPUT-TIMEOUT`；安全停止；`max_holders=1` |

证据链：

- `screendump` 生成 720x400 PPM；用宿主 `Lat15-VGA16` 字体做**逐像素 8x16 字形匹配**，
  正确/错误/超时三例均为 `399/399` 个非空格 ASCII 单元匹配（ratio 1.0），
  不使用 OCR，不依赖中文识别。
- 同时通过 QEMU monitor `pmemsave 0xb8000 4000` 读取 VGA 文本帧缓存，直接得到
  `[PAW-TTY1-MENU]`、`[PAW-TTY1-PROMPT]`、`[PAW-TTY1-INPUT-OK/BAD/TIMEOUT]`、
  `[PAW-MENU-TTY1]` 等 ASCII 行。
- 输入只走 QEMU `sendkey`（键盘通道），没有走串口；串口仅保存 systemd/脚本日志。
- 服务自身在 `init / menu / prompt / accepted|rejected|timeout / close` 各阶段写
  `data-init.json` / `console-menu.json`，记录解析后的实际 tty、`menu_tty`、
  `input_tty`、每个阶段 `/proc/*/fd` 中指向 tty1 的非辅助进程 PID/comm 与
  `max_holders`。三例 `max_holders` 均为 1。

本机证据副本：`~/paw-segment1-evidence/artifacts/`（不提交，避免二进制/日志进入仓库）。

产物（本机 `artifacts/qemu-tty/`）：

- `ok/screen-ok-prompt.ppm`、`ok/screen-ok-accepted.ppm`、
  `ok/screen-ok-menu.ppm`、`ok/screen-ok-reports.ppm`
- `bad/screen-bad.ppm`、`bad/screen-bad-prompt.ppm`
- `timeout/screen-timeout.ppm`、`timeout/screen-timeout-prompt.ppm`
- 每例的 `vga.bin`、`screen-*.txt`、`serial.log`、`result.json`

### 3.3 中文显示限制（必须明确）

当前 PAW ISO 的包列表没有 CJK 控制台字体/终端（只有 `systemd`/内核 vgacon），
QEMU 的 VGA 文本控制台只能渲染 ASCII；中文 UTF-8 字节没有对应字形，屏幕上显示为空白。
因此：

- **tty1 绑定、提示出现、键盘输入、菜单结构、单一占用**：真实 QEMU PASS。
- **中文字形的视觉渲染**：**BLOCKED**。不是本段 tty 绑定失败，而是现有 ISO 缺少
  CJK 控制台字体栈；不能把 ASCII 标记说成中文渲染通过。
- 为降低现场不可操作性，界面额外输出 ASCII 键位行
  `[PAW-MENU-KEYS] 1 Memtest 2 PAWDATA 3 RescueSSH ...` 和
  `[PAW-TTY1-PROMPT] Enter the last 6 characters ...`。

## 4. 未执行 / BLOCKED 汇总

| 项 | 状态 | 原因 / 后续 |
|---|---|---|
| 本机 pty 交互测试 | BLOCKED | 沙箱禁止 `/dev/ptmx`；QEMU tty1 用例覆盖；CI 以 `PAW_REQUIRE_PTY=1` 强制执行 |
| 中文控制台字形渲染 | BLOCKED | ISO 包列表无 CJK 控制台字体；需第 3 段加入字体/fbterm 或自定义 PSF 方案，不能靠 OCR 冒充 |
| 真实 ASUS 主板显示器/键盘 | 未执行 | 本段只用 QEMU 虚拟显示器；实机验收需第 3 段/现场 |
| 真实 `systemctl reboot` | 未执行 | 保护边界禁止重启真实机器；只测试注入的 mock reboot 与默认命令配置 |
| 最终 ISO 构建与哈希复核 | 未执行 | 明确属于第 3 段 |
| 原有 79 项 loop/虚拟测试 | 未在本机重跑 | 本机沙箱下 `sudo` 不可用（`no_new_privs`），`losetup` 类套件无法运行；改动路径已由本段 36+29+24 项断言覆盖，完整回归由 CI 执行 |
| 真实克隆/旧 VPS/生产 PAW/TF 卡 | 未执行 | 绝对保护边界 |

## 5. 结论

- P0-A 的代码路径、门禁、原子写、取消、失败人工介入、反向“不重启”断言均已真实执行通过。
- P0-B 的 tty1 绑定、显式 fd、键盘注入、屏幕/帧缓存证据、单一占用均已真实 QEMU 通过。
- 中文**字形**渲染是当前 ISO 的独立 BLOCKER，已在
  `docs/PAW-V2.7.1-BLOCKERS.md` 记录，不能用 ASCII 标记冒充。
- PR #2 保持 Draft，未合并；本段未构建新 ISO。
