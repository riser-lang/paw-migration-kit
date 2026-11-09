# PAW 持久化分区设计

启动介质保留 live ISO 的 Hybrid MBR/Legacy BIOS 启动结构，并在经身份核对的启动介质尾部追加 MBR 主分区，格式为 ext4、卷标 `PAWDATA`。启动时以 `nosuid,nodev,noexec` 挂载到 `/var/lib/paw-migration`；目录权限为 root-only。该分区承载状态、配置和报告，不覆盖 ISO 内容。

首次启动如缺少该分区，控制台会显示手动准备命令。`paw-data-prepare.sh` 从 `/run/live/medium` 解析启动介质父盘，只接受 removable 标记，并打印型号、序列号和容量；随后要求输入设备序列号末六位。未调用该命令时，启动服务不改写介质。创建分区仅针对当前启动 live 系统的可移动启动介质。已有同名分区必须为 ext4，否则拒绝格式化。虚拟测试只接受 `tests/virtual` 下 loop 镜像。

Hybrid ISO 使用混合 MBR，`sgdisk` 会拒绝读取其分区数据，因此首次准备通过 `sfdisk --append` 添加 MBR 分区，要求 DOS/MBR 分区表、未用主分区槽和足够的尾部空间；不重建 ISO 的分区表。CI 将检查追加分区、ext4 标签、挂载、卸载重挂载持久性、缺失、损坏和空间不足。写卡以后 PAWDATA 才会存在；ISO 单独构建不等于持久分区已建立。候选 ISO 上的实际结果以 Actions 报告为准。
