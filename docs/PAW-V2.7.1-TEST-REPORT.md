# PAW v2.7.1 第一段测试报告（本轮）

执行日期：2026-11-10
分支：`fix/v2.6.2-final-readiness`
本轮基线：`572588132f86a4632702589ef20ac398c068248f`
本轮代码 HEAD：`364429e`（最终以 `git log` 为准）
PR #2：保持 Draft，未合并。

本报告严格区分：

1. **真实执行的本机测试**（真实进程/真实虚拟磁盘/QEMU 虚拟硬件）
2. **GitHub Actions 测试**（run ID 单独列出）
3. **QEMU 虚拟显示器测试**（不是 ASUS 实机）
4. **静态检查**（不冒充运行测试）
5. **BLOCKED**（本机工具沙箱限制，不是 PASS）
6. **真实硬件尚未验证**（OPEN）

## 1. 结论摘要

| 项目 | 本机 | GitHub Actions | 备注 |
|---|---|---|---|
| ShellCheck | PASS（0.9.0，severity=error） | 见 CI 表 | 全量脚本 |
| Bash 语法 | PASS | 见 CI 表 | `bash -n` |
| Python compile | PASS | 见 CI 表 | 所有 `.py` |
| PowerShell 语法 | 未执行（无 pwsh） | 见 CI 表 | CI 专用 |
| Public safety | PASS | 见 CI 表 | 无密钥/凭据/二进制 |
| Public history | PASS | 见 CI 表 | 543 objects |
| Finalize 36 项 | **36 passed / 0 failed** | 见 CI 表 | 未改 finalizer 核心 |
| TTY 静态检查 | **35 passed / 0 failed / 1 blocked** | 见 CI 表 | 新增 6 项字体断言 |
| PTY 交互 | **BLOCKED**（本机 `/dev/ptmx` 不可用） | 见 CI 表 | CI `PAW_REQUIRE_PTY=1` |
| CJK 字体校验 | **PASS**（480 映射，385 非 ASCII 全覆） | 见 CI 表 | PSF2/PSF1 |
| QEMU CJK 显示器/键盘 | **4 cases / 71 assertions / 0 failed** | 见 CI 表 | 真实 QEMU + PSF 字形匹配 |
| PAWDATA 12 项 | BLOCKED（本机无 root/loop） | 见 CI 表 | CI sudo loop |
| 克隆/故障注入 35 项 | BLOCKED（同上） | 见 CI 表 | CI sudo loop |
| 离线修复 15 项 | BLOCKED（同上） | 见 CI 表 | CI sudo loop |
| 网络 17 项 | BLOCKED（同上） | 见 CI 表 | CI sudo loop |
| 真实 ASUS 显示器/键盘 | 未执行 | 未执行 | **OPEN** |

**第一段整体状态：PARTIAL**（中文 QEMU 已通过；实机/最终发布 ISO 未验收）。

## 2. 本机环境与 sudo/losetup 根因

日期：2026-11-10 02:15 UTC。

```
id -un                         → agentuser
id                             → uid=1002(agentuser) gid=1003(agentuser)
sudo -n true                   → rc=1
sudo -n id                     → rc=1
/proc/self/status              → NoNewPrivs: 1, CapEff: 0000000000000000
父 node 进程                   → NoNewPrivs: 0
systemd-detect-virt            → kvm
/proc/1/cgroup                 → 0::/init.scope
/dev/loop-control, /dev/loop0  → 存在
losetup --find                 → /dev/loop0, rc=0
losetup --find --show <8MiB>   → Permission denied, rc=1
```

每条命令 stderr 都有 `landlock-run: partial enforcement (older Landlock ABI)`。
根因：DSH bash 工具的 Landlock wrapper 给子进程设置 `NoNewPrivs=1`，并清空有效
capability。`sudo` 是 setuid，NNP 使其无法提权；loop attach 需要 `CAP_SYS_ADMIN`。
**不是容器**（KVM、init.scope），**不是 sudoers 配置**（调度方直接执行 NNP=0 时
`sudo -n id` 成功），**不是 /dev/loop-control 缺失**。

因此本机：

- 不修改宿主安全策略、不绕过沙箱；
- root/loop/PTY 测试如实标 BLOCKED；
- 需要 root 的测试全部交给 GitHub Actions runner。

完整原始输出：`/home/agentuser/paw-sudo-evidence.txt`（本机证据，不提交）。

## 3. 中文控制台显示方案（实际采用）

- 主路径：**fbcon + GNU Unifont 16x16 PSF2**，`setfont -C /dev/tty1`。
- 后备：8x16 PSF1（仅无 `/dev/fb0` 的 vgacon；复杂汉字压缩，非主路径）。
- 字体生成：`scripts/paw-build-cjk-font.py`，输入 `unifont.hex`，只用标准库。
- 槽位：95 ASCII + 385 运行时非 ASCII = 480 Unicode 映射；512 槽。
- 空格固定在 VGA 槽 32（否则内核填空格显示 `@`）。
- 生成器在超过 512 槽或缺少任一运行字符时 **构建失败**，不会静默缺字。
- 字体版本：Debian trixie 快照 `unifont 1:15.1.01-1`（CI 软件锁为准；
  本地验证 15.1.01）。

为什么不是 fbterm：fbterm 需要占有 tty1/fb0，并把 PAW 菜单放进它创建的 pty，
会改变现有“同一 `/dev/tty1` fd + 单一占用”的已验证路径；而且旧 cloud 测试内核
没有 DRM，无法先验证。fbcon 保持原 tty1/keyboard 路径，且可逐像素证明中文。

## 4. QEMU 虚拟显示器与键盘（本机真实执行）

命令（单例示例）：

```bash
python3 tests/qemu/qemu_cjk_screen_test.py \
  --case ok --image case-ok.img \
  --kernel .../vmlinuz-6.12.94+deb13-amd64 \
  --initrd .../paw-test-initrd.img \
  --font .../paw-cjk-16x16.psf --out .../cjk-out --timeout 60
```

环境：

- QEMU 8.2.2（sysroot），TCG，SeaBIOS 1.16.3，`-machine pc`，2 GiB，2 vCPU。
- `-vga std`，`-display none`，QEMU monitor `screendump` + `sendkey`。
- Debian generic 6.12.94+deb13-amd64 内核；bochs-drm，`/dev/fb0` 1280x800。
- 一次性 ext4 测试盘，注入生产 PAW 脚本/字体/服务 + QEMU 专用 lsblk/wrapper；
  不打开任何宿主块设备。
- 串口只写 `serial.log`，键盘只走 QEMU `sendkey`。

结果：**4 cases passed, 0 failed；71 assertions passed, 0 failed**。

| 用例 | 断言 | 关键证据 |
|---|---|---|
| ok | 26 | 中文面板/序列号提示；`123456` 键盘输入；`INPUT-OK`；中文接受行；中文菜单；`7` 打开报告；`max_holders=1`；`menu_tty=input_tty=/dev/tty1` |
| bad | 17 | `000000`；`INPUT-BAD`；中文“序列号末六位不匹配…没有写入任何分区”；无 `INPUT-OK`；单一占用 |
| timeout | 17 | 5 秒无输入；`INPUT-TIMEOUT`；中文“等待输入超过 5 秒…没有写入任何分区”；无 `INPUT-OK`；单一占用 |
| render | 11 | 真实 `paw-finalize-reboot.sh` + mock reboot；中文“迁移成功/完成记录已原子写入/系统将在 5 秒后自动重启/自动重启命令已下发”；`reboot-status=PASS`、`reboot_invoked=true` |

字形证明：

- 不是 OCR。`tests/qemu/psf_fb.py` 把 screendump 的每个 16x16 单元格与
  **随镜像发布的 PSF 位图**逐位比较，再拼回文字。
- 每例 `match_ratio ≥ 0.995`（仅光标/半格允许 1 个 inexact cell）。
- 断言的是完整中文句子，不是单个字；例如
  `错误：序列号末六位不匹配，已安全停止，没有写入任何分区。`
- 屏幕证据（本机，不提交二进制）：
  `~/paw-fb/cjk-out/{ok,bad,timeout,render}/screen-*.ppm`、
  `screen-*.txt`、`result.json`、`serial.log`。

**边界**：这是 QEMU 虚拟 VGA + PS/2 键盘，不是 ASUS B85M-G Plus 实机；
真实显示器时序、USB 键盘、i915/CSM 仍需现场验收。

## 5. CJK 字体独立校验（本机真实执行）

命令：

```bash
PAW_ARTIFACT_DIR=$PWD/artifacts \
PAW_UNIFONT_HEX=/tmp/unifont.../unifont.hex \
PAW_UNIFONT_VERSION=15.1.01-local \
scripts/ci/run-cjk-font-tests.sh
```

结果：

```
PASS PSF2 16x16 512 glyphs, 480 Unicode mappings, space slot 32
PASS every non-ASCII runtime character is covered (384 unique)
PASS fallback PSF1 8x16 512 glyphs, 8196 bytes
Summary: 1 passed, 0 failed
```

（384 unique 是脚本中实际字符；385 包含 U+FFFD 缺字符号。）

## 6. Finalize / TTY 回归（本机真实执行）

### 6.1 Finalize

```bash
PAW_ARTIFACT_DIR=$PWD/artifacts scripts/ci/run-finalize-virtual-tests.sh
```

**36 passed, 0 failed**。覆盖：全成功、receipt 写失败、SHA256 失败、离线修复失败、
GPT/ext4 失败、firstboot 失败、reboot 命令失败（`NEEDS_MANUAL_ACTION`）、
倒计时取消、不重复重启、完成数据不完整、结构调用顺序。

### 6.2 TTY 静态 + PTY

```bash
PAW_ARTIFACT_DIR=$PWD/artifacts scripts/ci/run-tty-virtual-tests.sh
```

- 静态：**35 passed, 0 failed**（原 29 + 6 项字体/构建断言）。
- PTY：**BLOCKED**（本机 `/dev/ptmx` → `out of pty devices`）。
- 不把 BLOCKED 写成 PASS；CI 用 `PAW_REQUIRE_PTY=1`，不可用即 FAIL。

## 7. GitHub Actions 完整回归

工作流：`.github/workflows/build-live-and-test.yml`
运行：**Run ID `42741425053`**（首次，HEAD `376c35d`；后续修复提交 `364429e`
会触发最终 Run，最终 Run ID 以交付说明为准）
URL：https://github.com/riser-lang/paw-migration-kit/actions/runs/42741425053

> 说明：本轮新增 CJK 步骤后，第一次运行用于发现 CI 环境差异；最终交付必须引用
> **最新 HEAD 的成功 Run**，不能引用旧的 Run #44。

CI 实际计数（完成后填入，取自 Artifact/日志，不手写猜测）：

| 套件 | 实际结果 |
|---|---|
| ShellCheck / Bash / Python / PowerShell / Public safety / Public history | 待填 |
| Debian 签名 / Xray / Tailscale | 待填 |
| ISO 构建 / SeaBIOS+TCG | 待填 |
| PAWDATA 12 项 | 待填 |
| 克隆/故障注入 35 项 | 待填 |
| 离线修复 15 项 | 待填 |
| 网络 17 项 | 待填 |
| Finalize 36 项 | 待填 |
| TTY 静态 35 项 + PTY | 待填 |
| CJK 字体校验 | 待填 |
| QEMU CJK 4 例/71 断言 | 待填 |

## 8. 未执行 / BLOCKED / OPEN

| 项 | 状态 | 原因 |
|---|---|---|
| 本机 PAWDATA/克隆/修复/网络 loop 套件 | BLOCKED | 工具沙箱 NNP=1、CapEff=0，无法 sudo/losetup |
| 本机 PTY | BLOCKED | `/dev/ptmx` 不可用 |
| 真实 ASUS 显示器/键盘 | OPEN | 只有 QEMU |
| 真实 `systemctl reboot` | OPEN | 只用 mock/注入 |
| 最终发布 ISO / 写 TF 卡 | OPEN | 本轮不做最终发布 |
| 真实旧 VPS / 生产 PAW / COS / 网络设备 | 未触碰 | 绝对保护边界 |

## 9. 证据文件

本机（不提交二进制）：

- `~/paw-fb/cjk-out/*/screen-*.ppm`、`result.json`、`serial.log`
- `~/paw-sudo-evidence.txt`
- `artifacts/finalize-virtual-test-report.txt`
- `artifacts/tty-virtual-test-report.txt`
- `artifacts/cjk-font-test-report.txt`

仓库报告（提交）：

- `docs/PAW-V2.7.1-REPAIR-REPORT.md`
- `docs/PAW-V2.7.1-TEST-REPORT.md`
- `docs/PAW-V2.7.1-BLOCKERS.md`
- `docs/PAW-V2.7.1-USER-GUIDE-ZH.md`
