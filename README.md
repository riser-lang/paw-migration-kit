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

## 当前工作边界

- 虚拟测试不能替代真实 ASUS B85M-G Plus、TF卡、SSD、内存、网卡和腾讯云 Rescue 验收。
- 真实磁盘和TF卡写入必须经过用户明确授权。
- 用户不知道SSD序列号，程序必须自动发现并展示设备，由用户选择确认；不得要求用户提前提供序列号。
- 不修改生产VPS，不进入生产Rescue，不读取生产整盘，不修改生产PAW/Tailscale/Funnel/Xray/Nginx/COS。
- 不删除历史Artifact，不修改main，不合并PR，除非用户明确授权。

## 当前状态

请以 [PAW-MIGRATION-STATE.md](PAW-MIGRATION-STATE.md)、[PAW-MIGRATION-BLOCKERS.md](PAW-MIGRATION-BLOCKERS.md)、最新GitHub Actions和对应commit为准。README不保存易过期的HEAD、CI或ISO状态。
