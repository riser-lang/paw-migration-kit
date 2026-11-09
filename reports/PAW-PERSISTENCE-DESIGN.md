# PAW 持久化分区设计

启动介质保留 live ISO 启动结构，并在经身份核对的启动介质尾部增加 GPT ext4 分区，卷标 `PAWDATA`。启动时以 `nosuid,nodev,noexec` 挂载到 `/var/lib/paw-migration`；目录权限为 root-only。该分区承载状态、配置和报告，不覆盖 ISO 内容。

创建分区仅允许对当前启动 live 系统的可移动父设备进行，并要求确认设备序列号末六位。已有同名分区必须为 ext4，否则拒绝格式化。虚拟测试只接受 `tests/virtual` 下 loop 镜像。

CI 将检查 GPT 扩展、ext4 标签、挂载、卸载重挂载持久性、缺失、损坏和空间不足。写卡以后 PAWDATA 才会存在；ISO 单独构建不等于持久分区已建立。候选 ISO 上的实际结果以 Actions 报告为准。
