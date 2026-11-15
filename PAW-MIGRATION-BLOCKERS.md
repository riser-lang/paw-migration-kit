# PAW Migration Blockers

更新：2026-11-15。关闭条件必须有代码、日志或实际测试证据。

| ID | 优先级 | 状态 | 问题 | 关闭条件 |
|---|---|---|---|---|
| BLOCK-REPAIR-CI | P0 | CLOSED | Run #100 repair-virtual测试失败 | Run `43398893910` & `43615851949` `Offline repair and rollback suite` 27/27 PASS |
| BLOCK-50G-FULLCHAIN | P0 | CLOSED_VIRTUAL_ONLY | 50GiB 源盘完整虚拟链路（240GB 基线 & 120GB Dell 参数化） | 240GB Run #17 (`43402874795`) `success`；120GB Run #18 (`43618362793`, `02d02c79...`, `target_bytes=120000000000`) 全步骤 PASS、GPT/ext4 扩容（`12844795 -> 29034470` blocks）与 `TARGET_BOOT_SEEN` PASS；物理 120GB SSD 实盘待现场 `BLOCK-SSD-PHYSICAL` |
| BLOCK-SSD-IDENTITY-UX | P0 | CLOSED | 预检/总控与无序列号SSD稳定身份不一致 | `paw-live-controller.sh`/`paw-hardware-preflight.sh`/`paw-memtest-confirm.sh`/`paw-final-confirm.sh` 已全线对齐 `paw-identity.py`，Run `43398893910` `41/41` PASS（在 `02d02c79...` 未回退） |
| BLOCK-RELEASE-ISO | P0 | CLOSED | 需要基于 Dell 120GB + `firmware-realtek` 最新提交的全绿 ISO | Run #130 (`43615851949`, SHA `02d02c79fa3035ad3089f474566ca917e5d2482a`) 全绿，`firmware-realtek` `20250410-2` chroot+squashfs 双重验证（36 个 `.fw`），Artifact `14123560276` 独立复算 SHA256 `71012766e4a23b540182c6952c244768d4a9c1c9c88a9e0e289d5d5ca6e6364c` MATCH |
| BLOCK-USB-PHYSICAL | P1 | NEEDS_TEST | 只有QEMU USB证据（且实体 TF 卡待重刷 Run `43615851949` ISO） | 使用最新 Run `43615851949` ISO 刷写 TF 卡后，在真实 Dell OptiPlex 3020M BIOS 从 TF/读卡器启动并验证 PAWDATA |
| BLOCK-SSD-PHYSICAL | P1 | NEEDS_TEST | 真实 120GB SSD 精确容量/SMART/温度/只读扫描未执行 | 实机扫描确认 `blockdev --getsize64 >= 53687091200` 及 SSD 身份与只读健康检查 |
| BLOCK-MEMTEST-PHYSICAL | P1 | NEEDS_TEST | QEMU不能证明真实16GB DDR3/DDR3L健康 | Dell 3020M 真实 16GB 内存完成至少一轮 Memtest86+ 且 0 errors |
| BLOCK-GPU-PHYSICAL | P1 | NEEDS_TEST | QEMU标准显卡不能证明HD4600 | 真实 HD4600 显示中文控制台并正常交互 |
| BLOCK-NIC-PHYSICAL | P1 | NEEDS_TEST | 虚拟网卡与 `firmware-realtek` 包入不能证明真实板载网卡 | 实机启动后执行 `lspci -nnk`、`dmesg` 实证真实 PCI ID、驱动绑定、固件加载与 DHCP/DNS |
| BLOCK-RESCUE-REAL | P1 | NEEDS_TEST | 腾讯云Rescue SSH未验证 | 真实Rescue下主机指纹、SSH、只读源盘身份确认 |
| BLOCK-TAILSCALE-REAL | P1 | NEEDS_TEST | 真实Tailnet/VLESS/Exit Node未验证 | Windows 与新 Dell Ubuntu 互通，旧 VPS Exit Node 可用且重启恢复 |
| BLOCK-MCP-CUTOVER | P1 | NEEDS_TEST | GPT/Claude/Spark端到端切换未验证 | 原URL、端口、路径、认证和后端逐项验证 |
| BLOCK-HOME-WAN | P2 | UNKNOWN | 中国移动华为路由器WAN/IPv6/CGNAT未知 | 实地检查；架构不得依赖公网IPv4或端口映射 |

## Run #100
https://github.com/riser-lang/paw-migration-kit/actions/runs/43206559080

静态检查、公开安全检查、Debian签名、Xray/Tailscale准备、ISO构建、CJK五场景、PAWDATA虚拟介质、故障注入39/39通过。失败在Offline repair and rollback suite on loop ext4。日志出现netplan期望文件缺失，后续offline-repair.json缺失；报告另提fixture缺/bin/sh和/usr/bin/env。必须查第一个真实失败点。后续步骤被跳过，Run #100不是完整PASS。

## SSD序列号的正确实现
用户不知道SSD序列号，不能要求提前提供。程序扫描块设备，排除PAW启动介质和源盘，展示编号、型号、容量、接口、序列号/WWN（如有）、分区、文件系统、Windows/EFI/NTFS特征和挂载状态。用户选择并确认后，程序绑定当次实际设备身份。每次写盘前重新识别。无序列号时用WWN、型号、精确容量、by-id、sysfs路径和连接信息组合识别；仍无法区分时要求断开无关盘。禁止仅凭/dev/sda或240GB选盘。

## 不得误报
12GiB完整虚拟链路不等于50GiB通过；QEMU AHCI不等于物理SATA；QEMU USB不等于真实读卡器；QEMU Memtest不等于真实内存；QEMU VGA不等于HD4600；mock网络不等于真实Tailnet；ISO构建成功不等于CI全绿；Artifact上传不等于实体TF卡更新；OPERATOR_CONFIRMED是人工确认，不是密码学证明；预重启检查不等于首次启动完成。

## 发布放行标准
repair fixture根因修复；最新完整CI绿色；PAWDATA首次/二次启动通过；CJK五场景通过；Memtest从启动菜单启动；USB Mass Storage启动；Haswell/AHCI证据与报告一致；50GiB完整链路通过或明确BLOCKED；240GB精确字节数；SHA256/O_DIRECT；目标Ubuntu独立启动；SSD自动发现和用户选择通过；Tailscale/VLESS重启恢复；最新ISO对应最新代码；Artifact下载后SHA256 MATCH。

物理硬件和生产网络仍需现场验收。PREHARDWARE_RELEASE_READY不代表真实迁移已完成。

## 保护边界
不修改旧VPS、不进入生产Rescue、不读生产整盘、不写真实TF卡/SSD、不改生产PAW/Tailscale/Funnel/Xray/Nginx/COS、不删历史Artifact、不改main、不合并PR。所有真实破坏性操作必须用户明确授权。
