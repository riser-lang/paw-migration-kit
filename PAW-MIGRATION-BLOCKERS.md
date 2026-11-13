# PAW Migration Blockers

更新：2026-11-13。关闭条件必须有代码、日志或实际测试证据。

| ID | 优先级 | 状态 | 问题 | 关闭条件 |
|---|---|---|---|---|
| BLOCK-REPAIR-CI | P0 | CLOSED | Run #100 repair-virtual测试失败 | Run `43398893910` `Offline repair and rollback suite` 27/27 PASS |
| BLOCK-50G-FULLCHAIN | P0 | IN_PROGRESS | 50GiB源盘未完成完整克隆链路 | Run `43402874795`（基于 `7ec4dbf3d14fb7e23aa213f7f9021d24c569913a` / Run `43398893910` ISO）正在执行；完整 PASS 前仍阻断真实克隆 |
| BLOCK-SSD-IDENTITY-UX | P0 | CLOSED | 预检/总控与无序列号SSD稳定身份不一致 | `paw-live-controller.sh`/`paw-hardware-preflight.sh`/`paw-memtest-confirm.sh`/`paw-final-confirm.sh` 已全线对齐 `paw-identity.py`，Run `43398893910` `41/41` PASS |
| BLOCK-RELEASE-ISO | P0 | CLOSED | 需要基于最终修复SHA的全绿最新ISO | Run `43398893910`（SHA `7ec4dbf3d14fb7e23aa213f7f9021d24c569913a`）全绿，Artifact `14025033882` 独立复算 SHA256 `eec712f8f2b2677046d3aafabc8e76a7fce82219062f418bad19dbd46f696358` MATCH |
| BLOCK-USB-PHYSICAL | P1 | NEEDS_TEST | 只有QEMU USB证据 | 真实ASUS BIOS从真实TF/读卡器启动并验证PAWDATA |
| BLOCK-SSD-PHYSICAL | P1 | NEEDS_TEST | 真实SMART/温度/只读扫描未执行 | 真实SSD身份确认后完成只读检查 |
| BLOCK-MEMTEST-PHYSICAL | P1 | NEEDS_TEST | QEMU不能证明真实DDR3健康 | 真实12GB内存完成至少一轮Memtest且0 errors |
| BLOCK-GPU-PHYSICAL | P1 | NEEDS_TEST | QEMU标准显卡不能证明HD4600 | 真实HD4600显示中文控制台并正常交互 |
| BLOCK-NIC-PHYSICAL | P1 | NEEDS_TEST | 虚拟网卡不能证明真实板载网卡 | 真实PCI ID、驱动、DHCP、DNS和网络恢复通过 |
| BLOCK-RESCUE-REAL | P1 | NEEDS_TEST | 腾讯云Rescue SSH未验证 | 真实Rescue下主机指纹、SSH、只读源盘身份确认 |
| BLOCK-TAILSCALE-REAL | P1 | NEEDS_TEST | 真实Tailnet/VLESS/Exit Node未验证 | Windows与新Ubuntu互通，旧VPS Exit Node可用且重启恢复 |
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
