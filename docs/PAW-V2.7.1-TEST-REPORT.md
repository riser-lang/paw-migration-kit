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
| Public history | PASS | 见 CI 表 | 728 objects |
| Finalize 36 项 | **36 passed / 0 failed** | 见 CI 表 | 未改 finalizer 核心 |
| TTY 静态检查 | **55 passed / 0 failed** | 见 CI 表 | 6 个操作员脚本 + 字体断言 |
| PTY 交互 | **BLOCKED**（Windows Python 无 `termios`） | 见 CI 表 | CI `PAW_REQUIRE_PTY=1`，15 passed |
| CJK 字体校验 | **PASS**（480 映射，385 非 ASCII 全覆） | 见 CI 表 | PSF2/PSF1 |
| QEMU CJK 显示器/键盘 | **5 cases / 96 assertions / 0 failed** | 见 CI 表 | 真实 QEMU + PSF 字形匹配 |
| PAWDATA 12 项 | BLOCKED（本机无 root/loop） | 见 CI 表 | CI sudo loop |
| 克隆/故障注入 39 项 | BLOCKED（同上） | 见 CI 表 | CI sudo loop |
| 离线修复 28 项 | BLOCKED（同上） | 见 CI 表 | CI sudo loop |
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

结果：**5 cases passed, 0 failed；96 assertions passed, 0 failed**。

| 用例 | 断言 | 关键证据 |
|---|---|---|
| ok | 26 | 中文面板/序列号提示；`123456` 键盘输入；`INPUT-OK`；中文接受行；中文菜单；`7` 打开报告；`max_holders=1`；`menu_tty=input_tty=/dev/tty1` |
| bad | 17 | `000000`；`INPUT-BAD`；中文“序列号末六位不匹配…没有写入任何分区”；无 `INPUT-OK`；单一占用 |
| timeout | 17 | 5 秒无输入；`INPUT-TIMEOUT`；中文“等待输入超过 5 秒…没有写入任何分区”；无 `INPUT-OK`；单一占用 |
| render | 11 | 真实 `paw-finalize-reboot.sh` + mock reboot；中文“迁移成功/完成记录已原子写入/系统将在 5 秒后自动重启/自动重启命令已下发”；`reboot-status=PASS`、`reboot_invoked=true` |
| final | 25 | 生产 `paw-final-confirm.sh` 在 tty1 跑两次：错后缀 → `FINAL-BAD`+中文拒绝；正确后缀 → `FINAL-OK`+中文确认；面板逐行字形匹配（标题/源系统/组合身份/主机指纹/目标 SSD 行+运行时序列号/数据来源/整盘数据损失警告/输入提示）；会话 `tty_path=/dev/tty1`、BAD+OK 标记、无 getty/login 占用 |

字形证明：

- 不是 OCR。`tests/qemu/psf_fb.py` 把 screendump 的每个 16x16 单元格与
  **随镜像发布的 PSF 位图**逐位比较，再拼回文字。
- 每例 `match_ratio ≥ 0.995`（仅光标/半格允许 1 个 inexact cell）。
- 断言的是完整中文句子，不是单个字；例如
  `错误：序列号末六位不匹配，已安全停止，没有写入任何分区。`
- 屏幕证据（CI，不提交二进制）：
  `qemu-cjk-{ok,bad,timeout,render,final}/screen-*.ppm`、
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
交付运行：**Run ID `42804949796`**（产品 HEAD `bf1a705`，2026-11-10T11:08:06Z 触发，
全部步骤 success）
URL：https://github.com/riser-lang/paw-migration-kit/actions/runs/42804949796

最新全绿验证运行：**Run ID `42873432670`**（HEAD `ac0813e`，仅改 CI/工作流与交付自检脚本）
— 修复套件 28 项，且 CI 首次把 `scripts/verify-delivery.ps1` 纳入 PowerShell 语法门禁
（`PowerShell parse PASS (2 files)`）。
URL：https://github.com/riser-lang/paw-migration-kit/actions/runs/42873432670
该 Run 同时上传 `paw-test-reports`（18 KB 文本报告），使证据核对不必再下载 1 GB。

> 说明：本轮新增 CJK 步骤后，第一次运行（`42741425053`）用于发现 CI 环境差异；
> 新增"中文授权面板"用例后又用 `42784672282` / `42788769956` / `42792565444`
> 三轮真实失败把夹具与断言修到正确（见 10.4），不是 flaky 重跑。交付引用**最新
> HEAD 的成功 Run**。下表全部取自 Run `42804949796` 的日志与 Artifact，未手写猜测。

CI 实际计数（Run `42804949796`，HEAD `bf1a705`）：

| 套件 | 实际结果 |
|---|---|
| ShellCheck / Bash / Python / PowerShell / Public safety / Public history | PASS。ShellCheck `--severity=error` 无命中；`bash -n` 全通过；`Python source compile PASS`；`PowerShell parse PASS (1 files)`；`JSON, workflow YAML, and systemd unit structure PASS`；`PUBLIC-SAFETY=PASS`；`PUBLIC-HISTORY=PASS`（扫描 1041 个可达 Git 对象）；`ENTRYPOINTS=21 MISSING=0 POWERSHELL_PARSE_ERRORS=0 BADBLOCKS_WRITE_FLAGS=0 FORMAT_COMMANDS=0` |
| Debian 签名 / Xray / Tailscale | PASS。Debian Live `13.7.0-amd64-standard`：分离签名 PASS（Debian CD key `DF9B9C49EAA9298432589D76DA87E80D6294BE9B`）、manifest hash PASS、SHA256 `040a44f3…c14e17ec`；Tailscale 1.104.5（签名 stable 仓库）；Xray v26.3.27，archive SHA2-256 `23cd9af9…`；二进制 SHA256 记录在 `software-manifest.txt` |
| ISO 构建 / SeaBIOS+TCG | PASS。ISO `953,155,584` bytes，SHA256 `d9fe2879…fb95a4476`；`System area summary: MBR isohybrid cyl-align-on GPT APM`；QEMU SeaBIOS + TCG（未用 KVM）启动到 readiness gate，按缺失实机条件保持 `BLOCKED`，`clone_started=false` |
| PAWDATA 12 项 | `Summary: 12 passed, 0 failed` |
| 克隆/故障注入 39 项 | `Summary: 39 passed, 0 failed` |
| 离线修复 28 项 | `Summary: 28 passed, 0 failed` |
| 网络 17 项 | `Summary: 17 passed, 0 failed` |
| Finalize 36 项 | `Summary: 36 passed, 0 failed` |
| TTY 静态 55 项 + PTY | `Static tty assertions: 55 passed, 0 failed`；`Summary: 15 passed, 0 failed`（PTY，`PAW_REQUIRE_PTY=1`）；套件合计 `56 passed, 0 failed, 0 blocked` |
| CJK 字体校验 | `Summary: 1 passed, 0 failed`；PSF2 512 槽 / 480 映射 / 384 个非 ASCII 运行时字符全覆盖 |
| QEMU CJK 5 例/96 断言 | `Cases: 5 passed, 0 failed, 0 blocked`；五例断言 26 + 17 + 17 + 11 + 25 = 96，0 failed（第五例为中文授权面板） |

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

## 10. 第二轮接管补充（操作员控制台绑定）

执行环境与第一段不同：本轮接手的工作站是 **Windows 11**（i5-12450H、15.7 GiB、
Python 3.11、Git Bash 5.3.9），没有 WSL、没有 QEMU、没有可用的 sudo/loop，
因此本机只能做静态与实际脚本语法检查；**需要 root/loop/PTY/QEMU 的执行仍全部
交给 GitHub Actions**。

### 10.1 本轮发现并修复的缺陷

`paw-console.service` 使用 `StandardOutput=journal`。五个操作员脚本仍用裸 `printf`
写面板，因此面板只进日志、**不上屏幕**：

- `paw-final-confirm.sh`：整块授权面板（含数据损失警告、源盘组合身份、固定主机
  指纹、目标序列号）不可见，屏幕上只有"输入最后 6 位"这一句；
- `paw-memtest-confirm.sh`：三选一说明与登记摘要不可见；
- `paw-target-discovery.sh`：候选磁盘清单和序列号不可见，却要求"按屏幕显示的
  序列号输入"；
- `paw-rescue-key-prepare.sh`：一次性公钥与候选主机指纹不可见，操作员无法粘贴；
- `paw-network-phase-select.sh`：R/U 含义不可见；
- `paw-source-discovery.sh`：根分区 UUID 只有一个裸提示，无任何说明。

修复：`paw-tty-lib.sh` 增加 `paw_tty_open_optional()`（有控制台且继承流是 tty 时
绑定 `/dev/tty1`；否则回退到继承 stdin/stdout，并在回退时不写 tty1 会话记录，
以免把 CI 截图当成实机证据）；六个脚本改为 `paw_tty_say/paw_tty_prompt/
paw_tty_read/paw_tty_read_secret`，带 300 秒输入超时与 ASCII 屏幕标记；
`paw-data-prepare.sh` 保持严格绑定、不允许回退。`paw_tty_read_secret()` 用于不回显
的 UUID 输入。

### 10.2 本轮验证

| 项 | 本机（Windows） | CI Run `42804949796` |
|---|---|---|
| `bash -n` 全部脚本 | PASS（0 语法错误） | PASS |
| TTY 静态断言 | **55 passed / 0 failed** | `Static tty assertions: 55 passed, 0 failed` |
| PTY 真实交互 | **BLOCKED**：Windows Python 无 `termios`，`pty_tty_test.py` 无法导入 | `Summary: 15 passed, 0 failed`（`PAW_REQUIRE_PTY=1`） |
| TTY 套件合计 | 55 passed / 1 failed（失败项是上述 PTY 环境限制） | `56 passed, 0 failed, 0 blocked` |
| 其余全套（PAWDATA/克隆/修复/网络/finalize/CJK/QEMU） | 未执行（无 root/loop/QEMU） | 全部 PASS，计数见第 7 节 |

本机 PTY 的失败**不是代码失败**，也不冒充通过；结论以 CI 的 root/PTY 执行为准。

### 10.3 ISO 独立复核（本轮实际执行）

四次构建的 ISO 都在工作站上实际下载、解压、重算哈希：

| Run | Artifact | 下载字节 | ISO 字节 | 计算 SHA256 | 与侧车 |
|---|---|---|---|---|---|
| `42804949796`（交付件） | `13760370816` | 1,030,665,391 | 953,155,584 | `d9fe28799f9c18d1ec69900b66ea0c71d70b232c5e62a0c4ab0e902fb95a4476` | 一致 |
| `42795953493`（对照） | `13754343439` | 1,030,664,775 | 953,155,584 | `2edf88a09684ebbb88680c79a73a29ea77fbc794aa168243649b2b67b2fc20ed` | 一致 |
| `42810087226`（验证运行，未交付） | `13763731974` | 1,030,666,564 | 953,155,584 | `aff7a8075a3347d63ab2de7991b1d1fca78ae6017a7db16adb0b974c4b178d65` | 一致 |
| `42778468039`（对照） | `13744904698` | 1,009,075,181 | 953,155,584 | `17789c0444d6f8bac0ef24aa7d6a68871e1dfedb2d7b3fe0c50355288a6e0363` | 一致 |
| `42747871471`（对照） | `13731684896` | 1,009,073,518 | 953,155,584 | `2295eb0a8d9d61b93be3e91cfeee735c42529ed3223cbf14593047104939336d` | 一致 |

- 下载方式：`gh run download` 在该网络下 20 分钟无字节写入（疑似代理卡住），
  改用 GitHub API artifact zip 端点 + `curl --proxy` 后完成。
- 十一次 ISO 字节数相同但 SHA256 各不相同，**字节级可复现仍未证明**；核对哈希必须
  使用同一 Run 的侧车文件。

### 10.4 中文授权面板的像素级证据（新增，第五例）

上一轮的控制台修复只有静态断言与 PTY 证据，授权面板没有截图级证明。本轮新增
QEMU 用例 `final`：

- `tests/qemu/paw-cjk-final-probe.sh`：测试专用探针，由 `paw.final=1` 内核参数
  触发，写一套合成但完整的收据（readiness / source / target / hardware /
  memtest），创建带 `PAWDATA` 标签的 loop ext4 与 loop 目标盘，然后在 tty1 上
  真实运行**生产脚本** `paw-final-confirm.sh` 两次：先错后缀（必须拒绝），再正确
  后缀（必须接受）。不做任何克隆：授权通过后生产脚本停在 Rescue 身份复核，
  该环境没有端点。
- 断言：授权面板标记与标题、源系统行、源盘组合身份、固定主机指纹、目标 SSD 行
  （含运行时序列号）、数据来源、**完整的整盘数据损失警告**、输入提示；随后
  `FINAL-BAD` + 中文拒绝文案，`FINAL-OK` + 中文确认文案；会话文件记录
  `tty_path=/dev/tty1`、BAD/OK 两个标记，且持有者只有探针外壳与授权脚本本身，
  **没有任何 getty/login 进程抢占 tty1**。
- 结果：`Cases: 5 passed, 0 failed`，本例 **25 断言全过**。

该用例并非一次写成，三轮 CI 都以真实失败暴露了问题，全部按缺陷修复后重跑：

| Run | 失败项 | 根因 | 修复 |
|---|---|---|---|
| `42784672282` | 面板未出现，两次都是 rc=1 | 合成 `source.json` 缺 `partition_number`，生产脚本按设计在面板之前就拒绝 | 补齐字段 |
| `42788769956` | `max_holders=2` | 探针单元本身 `StandardInput=tty`，驱动外壳也持有 tty1；2 个持有者是测试夹具形态，不是抢占 | 断言改为"至多这两个进程且无 getty/login" |
| `42792565444` | 面板末行文本缺失 | 截图在中间行出现时立刻返回，末行还没画完（竞态） | 改为等最后一行再断言 |

三次失败都保留在流程记录中，不隐藏、不重跑掩盖。

### 10.5 GPT 扩容守卫（本轮新增，Run `42804949796`）

`growpart` 只能吃掉分区**之后**的空白。若克隆出来的根分区后面还有分区，扩容根本
不可能成功，而旧代码会先执行 `sgdisk --move-second-header`（已经改了 GPT），再让
`growpart` 抛出难以理解的错误。

现在 `paw-gpt-expand.sh` 在**动任何东西之前**比较根分区与磁盘上最大的分区起始
偏移；若根分区不是最后一个就拒绝，并明确写出"后面的分区会冲突"和"没有改动任何
内容"；只有 `lsblk` 拿不到 START 时才记一条 WARN 跳过守卫（不静默）。

虚拟套件新增一个双分区 GPT loop：断言拒绝、断言两句话都在、并断言拒绝前后
`sfdisk` 导出的分区表**逐字节相同**（证明没有发生 GPT 手术）。故障注入套件因此从
35 项增到 **39 项**。

该守卫第一版有一处断言写错（用 `lsblk` 的 START 与 `sfdisk` 字段比较，与守卫本身
无关），Run `42801453637` 以 38 passed / 1 failed 暴露；改为整表比较后 Run
`42804949796` 39 passed / 0 failed。

### 10.6 真实 GRUB 安装（本轮新增，Run `42810087226`）

离线修复套件原先在 fixture 里用编译出来的 `grub-install` stub 顶替真实二进制，
所以"GRUB 修复"只有模拟证据。现在修复套件额外造一块 96 MiB 的 **loop GPT 盘**：
分区 1 是 BIOS boot（`ef02`，1 MiB），分区 2 是 ext4 根，然后用**真实**二进制
在宿主机侧执行：

```
grub-install --target=i386-pc --boot-directory=<挂载点>/boot --recheck /dev/loopN
```

四项断言（全部 PASS）：

1. `grub-install` 退出码 0；
2. `boot/grub/i386-pc/normal.mod` 存在（模块真的被拷进去）；
3. MBR 前 440 字节非零且偏移 510–511 是 `55 AA`（引导代码真的写进了 MBR）；
4. BIOS boot 分区里有非零的 core.img 内容（真的嵌入成功）。

范围说明：这证明**真实二进制**能在 GPT loop 盘上装 BIOS GRUB（宿主侧形态）。

#### 10.6.1 chroot 形态（Run `42816492016`）

生产脚本是在修好的根里执行 `chroot "$mount_root" grub-install ...`，与宿主侧形态
不同。新增用例复现该形态：160 MiB loop GPT 盘（BIOS boot + ext4 根），fixture 内
准备 `/boot`、最小 `grub.cfg`，宿主机二进制与 GRUB 模块通过**只读 bind mount** 提供
（代表真实目标上已安装的软件包），然后在 chroot 内执行同一命令形态。三项断言：

1. chroot 内 `grub-install` 退出码 0；
2. `i386-pc` 模块被拷进 fixture 的 `/boot`；
3. MBR 前 440 字节非零且签名 `55 AA`。

两项合计后修复套件 22 项全过。仍未证明的是"真实目标盘被修复后真的能启动"——
那必须实机，见 10.7 的启动链补强。

### 10.7 修复盘的启动链（Run `42838392058`）

把 GRUB 写对，不等于能从它启动。新增用例走完最后一环：320 MiB loop GPT 盘，
把 **ISO 自带的 kernel 与 initrd** 放进 `/boot` 并写最小 `grub.cfg`，宿主侧装入
GRUB，然后让 **QEMU SeaBIOS 只从这块盘启动**（不挂 ISO、IDE 接口），读串口日志。

六项断言（Run `42838392058` 全部 PASS）：

1. 能从 ISO 定位 kernel 与 initrd；
2. 真实 `grub-install` 退出码 0；
3. 串口出现 `Linux version`（GRUB 真的把 kernel 拉起来了）；
4. kernel 处理了 initrd（`Unpacking initramfs` / `Freeing initrd memory` / `Trying to unpack rootfs image`）；
5. 没有 `Kernel panic`；
6. 启动到达 initramfs 阶段（`Run /init as init process` 或 `(initramfs)` 提示）。

过程中三次失败都保留在记录里，没有掩盖：

- `42821382664`：用 virtio 盘，SeaBIOS 没枚举到，且我把 `grub-install` 的退出码
  用 `|| true` 吞掉了 —— 无法定位问题；
- `42827723019`：加诊断（单独断言安装退出码、改用 IDE、失败时把串口与安装日志写进
  报告）后，日志证明**盘确实启动到了 `(initramfs)`**，但命令行里的 `quiet` 把两条
  断言要找的 kernel 行压掉了，属于断言误报；
- `42833112745`：去掉 `quiet` 后 6 项过 5 项，只因 6.12 内核不再打印
  `Unpacking initramfs` 而失败。

范围说明：fixture 是"被修好的目标盘"的替身，证明的是**启动链**（真实 GRUB + 真实
内核）；不等于真实 Ubuntu 根能启动到登录界面。

