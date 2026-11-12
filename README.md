# PAW Migration Kit

本仓库用于构建 PAW Debian Live 迁移启动介质，并在隔离虚拟环境中验证迁移流程。

## 项目长期目标与需求

新对话、模型或开发环境接手前，先阅读以下根目录文件：

1. [PAW-PROJECT-MASTER.md](PAW-PROJECT-MASTER.md)：最终目标、真实硬件、网络架构、MCP保留要求、SSD自动识别和安全边界。
2. [PAW-MIGRATION-STATE.md](PAW-MIGRATION-STATE.md)：当前进度快照。每次新对话必须重新核对GitHub实时状态。
3. [PAW-MIGRATION-BLOCKERS.md](PAW-MIGRATION-BLOCKERS.md)：当前阻断项和关闭条件。
4. [PAW-CHATGPT-PROJECT-GUIDE.md](PAW-CHATGPT-PROJECT-GUIDE.md)：AI协作与验收原则。
5. [PAW-PROJECT-SOURCE-INDEX.md](PAW-PROJECT-SOURCE-INDEX.md)：项目文件和ChatGPT资料的阅读顺序。
6. [PAW-CHATGPT-PROJECT-DESCRIPTION.md](PAW-CHATGPT-PROJECT-DESCRIPTION.md)：可复制到ChatGPT项目设置“说明”栏的短文本。

详细测试证据仍放在 reports/ 和 reports/evidence/。

## 当前状态

请以 PAW-MIGRATION-STATE.md、PAW-MIGRATION-BLOCKERS.md、最新GitHub Actions和对应commit为准。README不保存易过期的HEAD、CI或ISO状态。

## 安全边界

真实磁盘和TF卡写入必须经过用户明确授权。QEMU测试不能替代真实硬件验收。不得未经授权修改生产VPS、进入Rescue、读取生产整盘、修改生产PAW或网络配置。
