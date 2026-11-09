# PAW 持久化分区设计（v2.7）

启动介质保留 live ISO 的 Hybrid MBR/GPT 启动结构，并在经身份核对的启动介质尾部追加 PAWDATA 分区，格式为 ext4、卷标 `PAWDATA`。启动时以 `nosuid,nodev,noexec` 挂载到 `/var/lib/paw-migration`；目录权限为 root-only。该分区承载状态、配置和报告，不覆盖 ISO 内容。

## 自动流程

`paw-data-init.service` 在 `paw-preflight.service` 之前运行 `paw-data-prepare.sh auto`：

- 若 PAWDATA 已挂载且健康，直接跳过。
- 否则用 `findmnt --target /run/live/medium` 找当前 Live 介质，兼容“整盘”与“分区”两种 source。
- 只接受 removable 介质；显示型号、容量和序列号。
- 要求操作员输入完整序列号末六位；不匹配不写入。
- 调用 `paw-prepare-data-partition.sh`，只追加分区，不重新格式化 ISO 启动分区。

## 分区表处理

- 现有 PAWDATA：只接受 ext4，挂载；不格式化。
- DOS/MBR Hybrid：要求 512 字节扇区、少于 4 个主分区、尾部至少 128 MiB；用 `sfdisk --append` 追加类型 83 分区，保留原有启动代码。
- GPT Hybrid：先备份并恢复 MBR 启动区，备份 GPT，移动备份 GPT 头，追加类型 8300 / 名称 `PAWDATA` 的最大空闲分区；原有 GPT 分区保持不动。
- 只对刚追加、数量恰好 +1、名称/位置匹配且容量 ≥128 MiB 的新分区执行 `mkfs.ext4`。

## 持久化验证

- 挂载后迁移 `/run/paw-migration` 临时状态，写入 `.paw-state-migrated`。
- `PAW_VERIFY_REMOUNT=1` 时写入标记、卸载、重挂载并读取标记。
- `media-partition.json` 记录分区表类型、追加前后数量、是否只格式化新分区、是否验证重挂载。

## 测试状态

代码已实现，等待 GitHub Actions 的 MBR/GPT 虚拟介质测试结果。`PAW_VERIFY_REMOUNT` 只证明卸载/重挂载，不等于真实重启；真实 TF 卡和 ASUS 主板启动仍未验证。
