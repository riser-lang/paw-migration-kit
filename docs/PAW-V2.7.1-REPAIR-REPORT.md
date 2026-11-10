# PAW v2.7.1 第一段遗留问题修复报告

执行日期：2026-11-10
分支：`fix/v2.6.2-final-readiness`
本轮基线（开始时远端 HEAD）：`572588132f86a4632702589ef20ac398c068248f`
本轮实现提交：`376c35d00a943941e64ff2b38c627e9657a47cc9`
PR #2：保持 **Draft**，未合并。
最终发布 ISO：**未构建/未发布**（本轮只做修复与回归，CI 构建的是测试用 Live ISO）。

## 1. 本轮做了什么

只处理第一段遗留问题，不重写已经通过的 finalize / tty1 核心逻辑：

1. **P0 中文控制台字体**：新增 GNU Unifont 16x16 PSF2 字体栈，在 fbcon
   （内核 framebuffer 控制台）上加载，保留 `/dev/tty1` 单一 fd 和原键盘路径。
2. **P0 完整 CI 回归**：工作流补齐 CJK 字体校验、CJK QEMU 显示器/键盘套件，
   并把第一段全部测试放进同一次 `workflow_dispatch` 运行。
3. **P0 sudo / losetup 矛盾调查**：确认是本机工具层 Landlock 沙箱设置
   `NoNewPrivs=1` 导致，不是容器限制，也不是 sudo 配置错误；root 虚拟磁盘测试
   改由 GitHub Actions runner 执行。
4. **P1 回归**：Finalize 36 项、TTY 静态检查、PTY（CI 强制）、QEMU tty1 全部保留。
5. **报告**：新增/更新 REPAIR / TEST / BLOCKERS / USER-GUIDE 四份文档。

没有执行真实克隆、没有触碰旧 VPS/生产 PAW/真实 TF 卡/真实硬盘，没有修改
Tailscale、Funnel、Xray、Nginx、443、防火墙、COS，没有删除历史 Artifact，
没有修改仓库可见性，没有合并 PR #2。

## 2. P0 中文控制台：方案与实现

### 2.1 先验证显示环境，再选方案

实际检查结果（证据见 TEST-REPORT）：

| 环境 | 内核 | `/dev/fb0` | 结论 |
|---|---|---|---|
| 旧 QEMU 测试盘（cloud 内核） | 6.12.115+deb13.1-cloud-amd64 | 无 | `CONFIG_DRM is not set`，`FB_VESA/UVESA` 关闭，SeaBIOS 下只有 EFI FB；vgacon 只能 8x16 ASCII |
| 本轮本地 QEMU | 6.12.94+deb13-amd64（generic） | `bochs-drmdrmfb` 1280x800 | SeaBIOS + `-vga std` 可走 bochs DRM → fbcon |
| CI Live ISO 内核 | Debian generic `linux-image-amd64` | 由 bochs DRM 提供（CI QEMU 验证） | `DRM_BOCHS=m`、`DRM_FBDEV_EMULATION=y`、`FRAMEBUFFER_CONSOLE=y`、`FB_VESA=y` |
| ASUS B85M-G Plus Legacy BIOS | 同上 generic | 预期 i915 KMS 提供 fb0；VESA FB 为后备 | **仍需现场验收** |

关键结论：

- vgacon 的字库是 8 像素宽、256/512 槽，不能靠“装一个大字体”显示中文。
- 当前 QEMU 的 cloud 内核完全没有 DRM/VESA framebuffer，不能用于验证 fbterm；
  必须换 generic 内核并真正启动 fbcon。
- ASUS B85M-G Plus 的 Haswell iGPU 在 Legacy BIOS 下由 i915 KMS 提供 framebuffer；
  Debian generic 内核同时编入 `FB_VESA`，作为极端后备。现场仍需确认。

### 2.2 方案比较

| 方案 | 评估 | 结论 |
|---|---|---|
| A. fbterm + CJK 字体 | fbterm 要自己占有 `/dev/tty1` 和 `/dev/fb0`，菜单必须运行在它创建的 pty 上；会改变现有“同一个 `/dev/tty1` fd”与单一占用证明，且测试内核无 DRM 时无法启动验证 | 未采用 |
| B. fbcon + 自建 PSF 字体 | 内核 framebuffer console 仍是 `/dev/tty1` 文本控制台，键盘/read/fd3 路径完全不变；16x16 字形可读；QEMU 可逐像素验证 | **采用** |
| C. 轻量图形界面 | 需要 SDL/Qt/DPI、键盘事件和 tty 抢占，资源与 Legacy BIOS 风险更高；本轮无需引入 | 未采用 |

### 2.3 实际字体方案

- 字形来源：Debian `unifont` 包的 `unifont.hex`（GNU Unifont，手工 16x16 位图）。
- 生成器：`scripts/paw-build-cjk-font.py`（仅 Python 标准库，不依赖 FreeType/PIL）。
- 产物：
  - `paw-cjk-16x16.psf`：PSF2，512 槽，16x16，**480 个 Unicode 映射**
    （95 个可打印 ASCII + 385 个运行时非 ASCII 字符）。
  - `paw-cjk-8x16.psf`：PSF1，512 槽，8x16，仅用于没有 `/dev/fb0` 的 vgacon
    应急后备；复杂汉字会被横向压缩，文档明确标注不是主路径。
- 槽位布局：ASCII 保持标准 VGA 位置（**空格必须在 32 槽**，否则内核填空格会显示
  成 `@`）；CJK 使用 0–31 和 127–511 的空闲槽。生成器在超过 512 槽时**构建失败**，
  不会静默缺字。
- 覆盖范围：生成时扫描 ISO 内全部 `paw-*.sh` / `paw-*.py` 的非 ASCII 字符；
  缺字即失败。当前 385 个非 ASCII 字符全部覆盖。
- 加载：`boot/paw-console-font.service` → `scripts/paw-console-font.sh`
  - `After=systemd-vconsole-setup.service`，`Before=paw-data-init.service paw-console.service paw-preflight.service getty@tty1.service`
  - 不声明 `TTYPath=`，不抢占交互终端；只 `setfont -C /dev/tty1 <font>`
  - 有 `/dev/fb0` 时加载 16x16，没有时加载 8x16 并记录 `mode=vgacon-fallback`
  - 写 `/run/paw-migration/reports/console-font.json`（模式、fb 名称/分辨率、
    字体 SHA256、setfont 退出码）；串口/journal 保留诊断日志
- 字体包版本：Debian trixie 快照 `unifont 1:15.1.01-1`（CI 的
  `software-packages.lock` 为准；本地验证用 15.1.01）。

### 2.4 ISO 构建集成

- `configs/live-build/package-lists/paw.list.chroot` 增加 `kbd`、`unifont`。
- `scripts/build-debian-live.sh`：
  - 复制字体生成器与 `paw-console-font.sh`；
  - 复制 `paw-console-font.service` 并 enable；
  - 新增 `0550-paw-console-font.hook.chroot`：在 chroot 内用同一快照的
    `unifont.hex` 生成两个 PSF 与 manifest；
  - 复制后 `chmod 0755` 所有 PAW 脚本，避免 checkout 权限位导致 unit 无法执行。
- 字体产物不提交仓库（二进制），由构建生成；`check-public-safety.py` 保持 PASS。

## 3. P0 GitHub Actions 完整回归

工作流：`.github/workflows/build-live-and-test.yml`
运行：**Run ID `42741425053`**（HEAD `376c35d`）
结果：见 `docs/PAW-V2.7.1-TEST-REPORT.md` 的“CI 实际结果”一节（以该 Run 的
日志/Artifact 为准）。

本轮工作流新增：

- `Validate generated CJK console font`：真实解析 PSF2/PSF1、空格槽、Unicode 表、
  全量运行时字符覆盖。
- `Run framebuffer CJK tty1 display and keyboard suite`：从真实 ISO 的 squashfs
  生成一次性 ext4 测试盘，用 ISO 内核/initrd、SeaBIOS + TCG + `-vga std` 启动，
  跑 ok / bad / timeout / render 四例，QEMU `sendkey` 注入键盘，`screendump` +
  PSF 字形逐像素匹配（不使用 OCR）。
- 保留原有 ShellCheck、Bash 语法、Python compile、PowerShell parse、Public safety、
  Public history、Debian 签名、Xray/Tailscale 校验、ISO 构建、SeaBIOS/TCG smoke、
  PAWDATA 12 项、克隆/故障注入 35 项、离线修复 15 项、网络 17 项、Finalize 36 项、
  TTY 静态检查、PTY（`PAW_REQUIRE_PTY=1`，不可用即失败）。
- 新增 `Summarize real test counts` 步骤，打印每份报告真实计数；缺报告会显式
  打印 `MISSING`。

## 4. P0 sudo / losetup 矛盾调查结论

**结论：本机工具执行通道（DSH bash 工具的 Landlock 沙箱）设置了
`PR_SET_NO_NEW_PRIVS=1` 并清空有效 capability；不是容器限制，不是 sudoers 配置
错误，也不是宿主 KVM 的 loop 设备缺失。**

证据（2026-11-10 02:15 UTC，详见 TEST-REPORT）：

```
id -un → agentuser
id     → uid=1002(agentuser) gid=1003(agentuser)
sudo -n true → sudo: The "no new privileges" flag is set ... rc=1
/proc/self/status → NoNewPrivs: 1, CapEff: 0000000000000000
父 node 进程     → NoNewPrivs: 0（工具 wrapper 给每条 bash 命令加了 NNP）
systemd-detect-virt → kvm
/proc/1/cgroup   → 0::/init.scope（无 docker/容器 cgroup）
/dev/loop-control、/dev/loop0 均存在
losetup --find → /dev/loop0（读查询可用）
losetup --find --show <8MiB file> → Permission denied（attach 需要 CAP_SYS_ADMIN）
```

每条命令 stderr 都出现 `landlock-run: partial enforcement (older Landlock ABI)`，
说明是工具层 Landlock wrapper；wrapper 为了让 Landlock 生效必须设置 NNP=1。
一旦设置 NNP 就不可逆，setuid `sudo` 无法再提权；同时有效 capability 为空，
`losetup` attach 必然失败。

因此：

- **没有**修改宿主安全策略、没有尝试绕过沙箱。
- 本机只把 loop/root 测试标记为 **BLOCKED（环境）**，不冒充 PASS。
- 需要 root 的虚拟磁盘测试全部交给 GitHub Actions runner；CI 的
  `run-pawdata`/`run-virtual`/`run-repair`/`run-network` 使用 `sudo` 真实执行
  loop 测试。
- 调度方在 2026-11-10 00:50 直接执行时 `NoNewPrivs: 0`、`sudo -n id` 成功，
  与上述结论一致：差异来自执行通道，不是主机配置。

## 5. P1 回归结论

- Finalize：本机 36 passed / 0 failed；未改 finalizer 逻辑。
- TTY 静态：本机 55 passed / 0 failed（本地 pty 不可用 → PTY 项 BLOCKED）；
  CI 以 `PAW_REQUIRE_PTY=1` 强制 PTY。
- QEMU tty1：CI 5 例 96 断言全过（Run `42795953493`，含授权面板用例）。
- 中文字体加入后，交互仍使用 `paw-tty-lib.sh` 的 `exec 3<>/dev/tty1`、`read -u 3`；
  状态文件仍记录 `tty_path=/dev/tty1`、`menu_tty=input_tty=/dev/tty1`、
  `max_holders=1`。
- Tailscale 登录仍写报告文件，不占用交互终端；串口/journal 诊断日志保留。

## 6. 交付边界

本轮**没有**：

- 执行第二段开发；
- 构建“最终发布 ISO”（CI 构建的是测试 Live ISO）；
- 写入真实 TF 卡或任何真实硬盘；
- 访问/修改旧 VPS、生产 PAW、Tailscale/Funnel/Xray/Nginx/443/防火墙/COS；
- 删除历史 GitHub Artifact；
- 修改仓库 Public/Private；
- 合并 PR #2。

真实 ASUS 主板显示器/键盘、真实 `systemctl reboot`、最终发布 ISO 哈希与现场
验收仍是 **OPEN**，见 `PAW-V2.7.1-BLOCKERS.md`。
