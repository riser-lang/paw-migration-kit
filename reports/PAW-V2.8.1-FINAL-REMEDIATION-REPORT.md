# PAW v2.8.1 最终整改报告（预硬件）

日期：2026-11-12（UTC）
分支：`vm/ds-final-prehardware-remediation-20261112`
范围：**仅 QEMU/TCG 虚拟块设备、模拟网络端点与本地 9p 证据传输**
裁决：**不 READY（虚拟预硬件；2 项未关闭）**
边界：未触碰真实 ASUS/TF/SSD、未登录生产 VPS、未合并 PR、未改 main。

## 1. 三项专项结论

| 专项 | 结果 | 关键证据 |
|---|---|---|
| PAWDATA 创建 + 同介质二次启动 | **PASS（虚拟）** | 仅新增 `/dev/sdc3`（start=2004992, size=60495008），token SHA256 两轮相同 `b7a649...914290`；第二轮 `already mounted and healthy; no partition change was made`。`reports/evidence/pawdata-persistence-20261112/` |
| exit=32 真实失败点 | **PASS（已定位）** | 不是 mount/umount；是 `lsblk -dn -o TYPE tmpfs` 返回 32，`set -e` 在介质识别阶段退出。修复：可写 USB、Guest `blockdev --getro=0` 硬门禁、阶段日志。`reports/PAW-PAWDATA-EXIT32-ROOT-CAUSE.md` |
| CJK 五场景夹具 | **PASS（CI）** | run `43206559080`：`Cases: 5 passed, 0 failed, 0 blocked`，Summary 25/25；证据 `reports/evidence/final-iso-20261112/qemu-cjk-test-report.txt`。只修夹具，未追求 512 槽全覆盖。 |

## 2. 任务书第十节：15 个问题

| # | 问题 | 状态 | 证据（路径/行） | commit |
|---:|---|---|---|---|
| 1 | 是否修复了实际阻塞问题 | **PASS** | `reports/PAW-PAWDATA-EXIT32-ROOT-CAUSE.md`；两轮 PAWDATA 证据；CJK finalizer 夹具 | `e15a818` |
| 2 | 原有功能/代码是否保留 | **PASS** | `scripts/windows-static-check.ps1` 21 个入口齐全；原网络/SSD/救援脚本仍在 | `690ce8f` |
| 3 | Haswell 4 核 CPU 是否被正确识别 | **PASS（虚拟）** | `PAW3_STEP=cpu ... model=Intel Core Processor (Haswell) cores=4`；`final-20261112/evidence/pawdata-special/boot1/console-main.log` | `e15a818` |
| 4 | ICH9 AHCI 6 口 SATA 是否工作 | **PASS（虚拟）** | `PAW3_STEP=sata ... controller=ich9-ahci ... kernel_driver=ahci`；同上 boot1 console | `e15a818` |
| 5 | USB Mass Storage 真实启动 | **PASS（虚拟）** | `tran=usb rm=1 serial=PAW-MEDIA-123456 booted_from_usb_mass_storage=true`；同上 boot1 console | `e15a818` |
| 6 | 中文界面五场景（成功/正常/失败/超时/渲染） | **PASS（CI）** | run `43206559080`：5/5 case、25/25 check；`qemu-cjk-test-report.txt` | `fe6100e` |
| 7 | 50GiB→240GB 完整迁移 | **PARTIAL** | 50GiB source/SATA 与 PAWDATA 步骤 PASS；完整 clone/目标启动仅在 12GiB 链路 PASS。`fullchain2.log`（50GiB source）、`prehardware-20261111/console-main.log`（12GiB 全链） | `e15a818` / `9bc9580` |
| 8 | 独立 SHA256 与 O_DIRECT 回读 | **PASS（12GiB 虚拟）** | `sha256_verify ... independent_sha256_verified=true`；`paw-stream-verify.sh` `iflag=direct`；`prehardware-20261111/console-main.log` | `9bc9580` |
| 9 | 目标盘能否独立启动 | **PASS（12GiB 虚拟）** | `PAW3_CHAIN_RESULT=PASS` 后出现 `ubuntu login:`；`prehardware-20261111/console-main.log` | `9bc9580` |
| 10 | SSD 只读扫描是否不写盘 | **PASS（虚拟/静态）** | `paw-ssd-read-scan.sh` 仅 `badblocks -sv`（无 `-w/-n`）；`reports/PAW-V2.8.1-SSD-HEALTH-TEST-REPORT.md` | `e15a818` |
| 11 | Tailscale 设备名合法化/身份一致 | **PASS（模拟）；真实 NEEDS_TEST** | 25/25 VLESS 套件；非法 hostname、临时节点 fail-closed；`reports/PAW-V2.8.1-NETWORK-CUTOVER-REPORT.md` | `50ceb16` |
| 12 | VLESS 重启后残留代理清理 | **PASS（模拟）；真实 NEEDS_TEST** | 双 drop-in + Xray 清理、直连失败回滚；28/28 网络套件；同上网络报告 | `50ceb16` |
| 13 | 旧 VPS 作为 Exit Node | **NEEDS_TEST** | 仅 `paw-tailscale-exit-node.sh plan/status` 模拟；未登录生产 VPS；同上网络报告 | `50ceb16` |
| 14 | Claude/Gemini Spark/GPT 路径保留 | **NEEDS_TEST** | `reports/PAW-SERVICE-CUTOVER-MANIFEST.md` 保留 MCP 名称并禁用旧机重复业务；未做真实端到端 | `0e59cc2` |
| 15 | 最新 ISO 构建与 SHA256 | **PASS** | run `43206559080`；953,155,584 字节；SHA256 `bc37eb...b0fe`；本地复算与 sidecar 一致 | `fe6100e` |

## 3. 修复清单

| 提交 | 内容 | 验证 |
|---|---|---|
| `1c18a4a`（前序） | 移除 USB `readonly=on` | 本轮两次启动 `blockdev --getro=0` |
| `e15a818` | PAWDATA 阶段日志、RO 门禁、有界只读扫描、每轮干净介质 | 两轮专项 + 阶段日志 |
| `73ceb4f` | CJK render 夹具注入 `PAW_FINALIZE_TEST_MODE=1` 与 preboot handoff | CI CJK suite |
| `8a0936c` | 公开仓库历史中生产 VPS IPv4 脱敏（重写本分支 4 个提交并 force-push） | `check-public-history.py` PASS |
| `690ce8f` | Windows 静态检查认可 `run_logged mkfs` 新形式 | CI 静态检查 PASS |
| `cdf3d58` | 两轮 PAWDATA 证据、USB/根因报告更新 | 本报告证据目录 |
| `fe6100e` | CJK render 期望改为实际 finalizer 文案 `自动重启命令已下发` | CI 5/5 |

## 4. ISO 与 Artifact

| 项 | 值 |
|---|---|
| 工作流 | `build-live-and-test.yml`，run `43206559080`（HEAD `fe6100e`；运行时文件 `690ce8f`） |
| ISO | `paw-live-amd64.iso`，953,155,584 字节 |
| SHA256 | `bc37ebaebe469e40b61b0f7c841fee95690b68ccbaf4dfa73d5414fea3a9b0fe` |
| Artifact | `paw-live-build-test-results`，1,030,653,110 字节；本地目录 `~/final-20261112/artifact-ci5/` |
| 独立复核 | 本地 `sha256sum` 与 Artifact 内 `paw-live-amd64.iso.sha256` 逐字一致；`reports/evidence/final-iso-20261112/artifact-verify.txt` |
| 工作流结论 | **failure**：CJK/PAWDATA 等通过；仅 repair 虚拟夹具缺 `/bin/sh`、`/usr/bin/env` 而失败，ISO 未受影响 |

## 5. 未完成 / OPEN

| 项 | 状态 | 说明 |
|---|---|---|
| 50GiB 全链路 clone→repair→expand→target boot | **PARTIAL** | 12GiB 全链 PASS；50GiB 仅验证 source/PAWDATA。未在 2h 预算内重跑 |
| 真实 ASUS BIOS/USB/屏幕/键盘 | **NEEDS_TEST** | 无物理机 |
| 真实 SSD SMART/温度/全盘只读扫描 | **NEEDS_TEST** | 仅虚拟与 mock |
| 真实 Tailnet/VLESS/Exit Node/MCP | **NEEDS_TEST** | 未登录生产，不伪造 ONLINE |
| 物理 U 盘二次启动 | **NEEDS_TEST** | 虚拟同镜像二次启动 PASS，物理介质未测 |
| repair 虚拟夹具 | **BLOCKED** | `repair-virtual-test-report.txt`：fixture 缺 `/bin/sh`、`/usr/bin/env`，`chroot` 无法执行；运行时未改，未在预算内修夹具重跑 |

## 6. 裁决

**不 READY（虚拟预硬件范围）**。已交付：代码、两轮 PAWDATA、CJK 5/5、ISO 与 SHA256。
未关闭的 2 项：① 50GiB 全链路只到 source/PAWDATA（PARTIAL）；② repair 虚拟夹具缺 `/bin/sh`/`env`，
工作流因此红（BLOCKED，运行时代码未受影响）。补齐这两项并通过一次绿色 CI 后，才可升级为
`PREHARDWARE_RELEASE_READY`；物理与生产项仍 NEEDS_TEST，不得把虚拟 PASS 当作物理 PASS。
