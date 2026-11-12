# PAW 项目资料索引与阅读顺序

本文件说明 GitHub 仓库和 ChatGPT 项目资料应该放什么、先读什么，以及各文件的权威范围。

## 一、GitHub 仓库根目录的长期文件

仓库：https://github.com/riser-lang/paw-migration-kit

| 文件 | 作用 | 更新频率 |
|---|---|---|
| PAW-PROJECT-MASTER.md | 长期目标、用户需求、硬件、网络架构和安全原则 | 需求或架构决策变化时 |
| PAW-MIGRATION-STATE.md | 当前分支、HEAD、CI、ISO、已完成工作 | 每轮开发/验收后 |
| PAW-MIGRATION-BLOCKERS.md | 未解决问题、风险、阻断条件 | 问题发现/关闭时 |
| PAW-CHATGPT-PROJECT-GUIDE.md | ChatGPT和其他AI的协作方式 | 协作要求变化时 |
| PAW-PROJECT-SOURCE-INDEX.md | 本文件，资料导航和权威顺序 | 文件结构变化时 |
| PAW-CHATGPT-PROJECT-DESCRIPTION.md | ChatGPT项目“说明”栏的短文本 | 项目目标变化时 |

详细测试证据仍放在 reports/ 和 reports/evidence/，不要把所有原始日志都堆到根目录。

## 二、ChatGPT 项目建议放入的资料

建议把以下文件作为 ChatGPT 项目的资料来源上传：

1. PAW-PROJECT-MASTER.md：必须，保存最终目标和稳定需求。
2. PAW-CHATGPT-PROJECT-GUIDE.md：必须，约束助手如何协助。
3. PAW-MIGRATION-STATE.md：建议，提供当前进度；每次重要更新后应替换为最新版本。
4. PAW-MIGRATION-BLOCKERS.md：建议，避免新对话遗漏阻断项；关闭问题后更新。
5. PAW-PROJECT-SOURCE-INDEX.md：建议，帮助新对话理解资料关系。
6. 最新的主验收报告：按当前版本选择，不要上传过期报告当作最新状态。
7. PAW-FINAL-USER-GUIDE-ZH.md：建议，保存用户实际操作方式。

不要把全部构建日志、二进制Artifact、密钥或生产配置上传到 ChatGPT 项目资料。

## 三、ChatGPT 项目设置中的“说明”栏

“说明”栏适合放短指令，不适合粘贴整份技术文档。

请复制 PAW-CHATGPT-PROJECT-DESCRIPTION.md 中的内容到项目设置的“说明”栏。

完整需求放在项目资料文件中。

## 四、资料权威顺序

1. PAW-PROJECT-MASTER.md：最终目标与长期要求。
2. PAW-MIGRATION-STATE.md：当前进度快照。
3. PAW-MIGRATION-BLOCKERS.md：当前未解决风险。
4. 最新验收报告：该版本测试结论。
5. 原始日志、GitHub Actions、代码和commit：事实证据。

如果报告写PASS，但对应原始日志失败，应以原始日志为准。

如果当前代码已经变化，旧报告只能作为历史记录。

## 五、更新规则

每次重要开发完成后：
- 更新 STATE；
- 更新 BLOCKERS；
- 报告必须注明对应分支、HEAD、Run、Artifact和SHA256；
- ChatGPT项目资料中的旧STATE/BLOCKERS应替换为新版本。

每次出现新需求：
- 先判断是否改变长期目标；
- 如果改变，更新 MASTER；
- 如果只是当前实现任务，更新 STATE 或 BLOCKERS；
- 不要把短期任务写成永久目标。

## 六、当前重要提醒

SSD序列号是新发现的用户体验要求：用户不知道序列号，程序必须自动识别、展示并让用户选择确认。不得要求用户预先提供SSD序列号。

家庭宽带当前为中国移动、华为路由器，但公网IPv4、IPv6、CGNAT尚未确认。最终方案不能依赖公网IPv4或端口映射。

旧VPS迁移后继续保留为paw-gateway和美国出口，不是永久关闭。
