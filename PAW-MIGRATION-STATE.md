# PAW Migration State

更新：2026-11-15。每次新对话必须重新核对GitHub；本文件是快照，不是实时状态。

## 当前分支
- 分支：vm/ds-final-prehardware-remediation-20261112
- 最新已验收运行时代码：`02d02c79fa3035ad3089f474566ca917e5d2482a`（新增 `firmware-realtek` 及 50GiB→目标盘容量参数化）
- 上一轮运行时代码基线：`7ec4dbf3d14fb7e23aa213f7f9021d24c569913a`（240GB 基线 Run `43398893910` / Run `43402874795`）
- baseline：`vm/ds-prehardware-acceptance-20261111` @ `d7cb1e56028c0a4b5cd621e7dc02d17bd2cb8c32`
- `main`：`0d6aefd093984a65f40d19e1fae584dee623b8e9`（未修改）
- 文档提交会在运行时提交之后更新，以上 `02d02c79...` 为当前最新经 CI 与 120GB 链验收的运行时代码。

## 目标硬件（已更新为 Dell OptiPlex 3020M Micro）
- 主板 / 芯片组：Dell `0WWRRC` / Intel `H81`
- CPU / 核显：Intel Core `i5-4670T`（Haswell x86_64，4C4T，2.30–3.30GHz）/ Intel HD Graphics 4600
- 内存：16GB（8GB+8GB Micron + Samsung，1333MHz；DDR3/DDR3L 与真实 Memtest 待实机确认）
- 目标盘：标称 120GB SSD（精确字节容量与实际型号/接口待实机 `blockdev --getsize64` / `lsblk` 确认）
- 启动介质：32GB TF 卡 + USB 读卡器

## 最新 Actions
- 常规 CI + Live ISO 构建（`build-live-and-test.yml`）：**Run #130（`43615851949`）**
  - URL：https://github.com/riser-lang/paw-migration-kit/actions/runs/43615851949
  - 运行时代码 SHA：`02d02c79fa3035ad3089f474566ca917e5d2482a`
  - 结果：**`success`**（全 24 步通过：静态/安全检查、Debian 基线签名校验、ISO 构建与 `firmware-realtek` chroot+squashfs 双重校验、CJK 字体 416 字形、SeaBIOS 启动、CJK QEMU 25/25、PAWDATA 12/12、Fault-injection 43/43、Offline repair 27/27、Network 28/28、P0 59/59、P1 24/24、SSD identity、VLESS 25/25、Finalize 36/36、TTY 56/56）
- 50GiB → 120GB 完整虚拟迁移链（`.github/workflows/prehardware-50g.yml`）：**Run #18（`43618362793`）**
  - URL：https://github.com/riser-lang/paw-migration-kit/actions/runs/43618362793
  - 代码 SHA 与 ISO 来源：`02d02c79fa3035ad3089f474566ca917e5d2482a` / Run `43615851949`（输入参数 `target_bytes=120000000000`）
  - 结果：**`success`**（`chain-50g` 耗时 `3h23m49s`，`runner_rc=0`，Host runner 观测 `main result=TARGET_BOOT_SEEN chain_pass=True target_boot=True`；`verify-chain-evidence.py` `PASS`）
  - Artifact：`paw-50g-chain-evidence`（ID `14129979760`，`35,068,330` bytes）
  - 关键实测指标：
    - `source_bytes=53687091200`（50 GiB），`target_bytes=120000000000`
    - `root_partition_before_bytes=52612283904` → `root_partition_after_bytes=118925192704`（`partition_grew=true`）
    - `filesystem_before_blocks=12844795` → `filesystem_after_blocks=29034470`（`block_size=4096`，`filesystem_grew=true`）
    - 目标盘剩余可用空间：`27559444` blocks（`112883482624` bytes ≈ 105.13 GiB），`gpt_verified=true`
    - 独立 SHA256 回读核验（`target-O_DIRECT-4MiB`）：`491eb86f24ca8a8304505fdd504e58becd0c7409080dffde90e68062f06db0b1`（53,687,091,200 bytes 一致）
    - 自动重启与目标系统登录：`auto_reboot PASS` 后观测到 `Ubuntu 24.04.5 LTS ubuntu ttyS0` 与 `ubuntu login:`
- 历史 240GB 基线对照：`prehardware-50g.yml` Run #17（`43402874795` / `7ec4dbf3d14fb7e23aa213f7f9021d24c569913a`）已 `success`（Artifact `14035420490`）。

## 最新已校验 Release ISO（来自 Run 43615851949）
- Artifact：`paw-live-build-test-results`，ID `14123560276`，ZIP 精确大小 `1030677538` bytes（`7z t` PASS）
- `paw-live-amd64.iso`：`953155584` bytes
- 独立复算 SHA256：`71012766e4a23b540182c6952c244768d4a9c1c9c88a9e0e289d5d5ca6e6364c`（与 `paw-live-amd64.iso.sha256`、`iso-identity.txt`、Run `43618362793` 独立复算结果完全一致）
- `firmware-realtek`：`20250410-2`（`all`），`INSTALLED_AND_VERIFIED_IN_ISO_SQUASHFS`，chroot 与 ISO `/live/filesystem.squashfs` 均已验证含 36 个 `/usr/lib/firmware/rtl_nic/*.fw` 文件。
- 本地验证路径：`C:\PAW-Release\run-43615851949\paw-live-amd64.iso`
- 实体32GB TF卡已于2026-11-15使用Run `43615851949`新版ISO重刷，Rufus 4.15.2396 DD Image mode；只读回读逐字节比较953,155,476/953,155,584 bytes一致，108 bytes差异位于FAT元数据区；安全弹出成功。详见 `PAW-CURRENT-HANDOFF.md` 记录0015。当前待Dell实机首次启动验收。

## 已有虚拟成果与边界
- 50GiB → 120GB（`120000000000` bytes）完整虚拟链路已在 QEMU/TCG 下端到端通过，但 **不等于** 真实 Dell OptiPlex 3020M 或真实 120GB SSD 通过。
- `firmware-realtek` 已进入 Live rootfs 与 squashfs，但真实 Dell 主板网卡 PCI ID、驱动绑定与固件加载 **必须** 在实机首次启动后通过 `lspci -nnk` 和 `dmesg` 确认，不得事前臆断为特定 RTL 型号。
- 实机 SSD 识别遵循无预设序列号原则（交互式扫描展示并绑定实际检测身份）。
- 真实 VPS Rescue、Tailnet、Exit Node、MCP 切换、120GB SSD 实机 SMART/只读、16GB DDR3/DDR3L Memtest、HD4600、TF 卡/读卡器、Dell Legacy BIOS 均仍待实机现场验证。

## 真实硬件/生产待测
Dell OptiPlex 3020M Legacy BIOS/CSM、真实 32GB TF/读卡器启动与 PAWDATA 持久化、HD4600 中文控制台、16GB DDR3/DDR3L Memtest86+、实机网卡 PCI ID/驱动/固件加载、120GB SSD 精确容量（必须 >= `53687091200` bytes）与 SMART/温度/只读扫描、腾讯云 Rescue SSH、50GiB 持续传输、中国移动家宽 WAN/IPv6/CGNAT、真实 Tailscale/VLESS/Exit Node、GPT/Claude/Spark MCP 接管、旧 VPS gateway-only。

## 保护边界
不修改/停止/重启旧 VPS；不进入生产 Rescue；不读生产整盘；不改生产 PAW/MCP/Tailscale/Funnel/Xray/Nginx/443/防火墙/COS；不未经明确授权写入真实 TF 卡或 SSD；不删历史 Artifact；不改 `main`；不合并 PR #2。真实克隆和破坏性操作必须另获用户明确授权。
