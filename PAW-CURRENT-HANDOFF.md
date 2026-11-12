# PAW Current Handoff（只追加，不覆盖）

> 本文件是 PAW 项目的连续交接日志，也是新对话的首要交接入口。
>
> **不可变规则：只允许在文件末尾追加新的带日期记录。严禁修改、删除、重排、压缩或覆盖任何既有内容。**
>
> 如发现历史记录错误，不得回改原文；必须在新记录中追加“更正记录”，引用原记录日期/标题，说明错误内容、正确内容、证据来源和更正时间。
>
> 每次阶段开始、阶段完成、关键判断变化、对话结束或任务交接，都应追加记录。记录必须区分事实、推断、计划、PASS、WARN、BLOCKED、NEEDS_TEST。
>
> 每次追加前先读取文件末尾，确认最新记录和当前 HEAD；追加后重新读取并核对，确认原有内容未被改变。若无法证明只追加，停止修改并报告。
>
> 本文件的记录是历史交接证据，不代替实时 GitHub 核验。新对话必须重新核对分支、HEAD、运行时代码 SHA、Actions、Artifact 和相关原始日志。

---

## 记录 0001：项目交接基线

- 日期：2026-11-12
- 记录性质：新建交接基线
- 仓库：`riser-lang/paw-migration-kit`
- 工作分支：`vm/ds-final-prehardware-remediation-20261112`
- 记录时分支 HEAD：`f84b4d50f6ecb38ba93787439b4908c0c6018715`
- 最近已测试运行时代码：`fe6100e16f4c032310e3eb0b351d37f655d1d1a6`
- 最新已核实 CI：Run #100，ID `43206559080`
- Run #100 结果：FAILURE；失败在 Offline repair and rollback suite on loop ext4。
- Run #100 对应 ISO：953,155,584 bytes；SHA256 `bc37ebaebe469e40b61b0f7c841fee95690b68ccbaf4dfa73d5414fea3a9b0fe`；Artifact ID `13939752294`。该 ISO 仅供诊断，不是最终发布介质。
- PR #2：Open / Draft / 未合并；其 HEAD 不是当前工作分支，不得将 PR #2 当作本轮运行时代码基线。

### 已有成果（证据边界）

- 12GiB Ubuntu 24.04.5 虚拟源盘到 240GB 虚拟目标盘曾完成克隆、独立 SHA256、离线修复、GPT/ext4 扩容、重启及目标 Ubuntu 登录提示验证。
- PAWDATA 可写虚拟 USB 首次初始化和同一介质二次启动持久化已有通过记录。
- QEMU xHCI + USB Mass Storage 启动、CJK 五场景和 Memtest 菜单入口已有虚拟测试记录。
- 上述结果均为虚拟环境证据，不代表真实 ASUS B85M-G Plus、HD4600、Realtek 网卡、TF 读卡器、12GB DDR3 或真实 SSD 已通过。
- 12GiB 完整链路不等于 50GiB 完整链路通过。

### 当前阻断项

1. **BLOCK-REPAIR-CI（P0 / OPEN）**：Run #100 的离线修复/回滚测试失败。必须从第一次真实失败命令及 stderr 入手修复测试夹具；不得降低生产门禁或删除断言。
2. **BLOCK-SSD-IDENTITY-UX（P0 / OPEN）**：目标盘发现和用户选择已有基础，但无序列号磁盘被过滤；稳定组合身份、授权绑定和每个写盘阶段重新核验仍需补齐。用户不需要、也不可能提前提供 SSD 序列号。
3. **BLOCK-50G-FULLCHAIN（P0 / PARTIAL）**：精确 50GiB（53,687,091,200 bytes）到 240GB（240,000,000,000 bytes）的完整链路尚未获得通过证据。资源不足时必须如实 BLOCKED，不得以 12GiB 代替。
4. **BLOCK-RELEASE-ISO（P0 / OPEN）**：Run #100 虽构建出 ISO，但完整 workflow 失败；不得将该 Artifact 作为最终启动盘依据。
5. **真实硬件和生产网络项目**：ASUS Legacy BIOS、TF 卡/读卡器、HD4600、真实 Memtest、Realtek 网卡、真实 SSD SMART/温度/扫描、真实 Rescue SSH、家宽网络、Tailscale/Exit Node/MCP 均保持 NEEDS_TEST / OPEN。

### 下一步已确定任务

执行一次有明确结束条件的最后软件收尾：

1. 修复 Run #100 离线修复测试夹具，保留成功和故障回滚两条真实验证路径。
2. 完成 SSD 自动发现、用户选择、序列号可选、无序列号稳定身份识别和每个写盘阶段的身份复核。
3. 准备精确 50GiB 虚拟源盘，执行 50GiB → 240GB 完整链路；资源不足则保留 BLOCKED 证据。
4. 在同一个最终运行时代码 SHA 上完成完整 CI。
5. 构建与该运行时代码 SHA 对应的 ISO，下载 Artifact 并独立复核 ISO SHA256。
6. 更新 STATE、BLOCKERS、项目索引和用户说明。
7. 由 ChatGPT 独立复核代码、日志、CI、Artifact 和 ISO 后，再判断是否达到启动盘制作条件。

### 时间安排（估算，不是承诺）

- 阶段 1：离线修复夹具整改，约 1–1.5 小时。
- 阶段 2：SSD 身份识别和专项测试，约 1–2 小时。
- 阶段 3：50GiB 完整虚拟链路，约 3–5 小时，受云电脑资源影响。
- 阶段 4：完整 CI 与必要修复，约 0.5–1 小时。
- 阶段 5：最终 ISO 构建、下载和 SHA256 复核，约 30 分钟。
- 阶段 6：文档、证据和交接，约 30–45 分钟。

### 安全边界

本轮只处理代码、虚拟测试、GitHub 和文档。未经用户另行明确授权，不得修改生产 VPS、进入生产 Rescue、读取生产整盘、写入真实 SSD、写入/格式化真实 TF 卡、修改生产 Tailscale/Xray/MCP/Tunnel/Funnel/Nginx/COS、删除历史 Artifact、修改 main 或合并 PR。

### 本记录状态

- 本记录是基线快照，不表示上述任务已经执行。
- DS 的完整执行任务已准备，尚待在云电脑中执行并返回证据。
- 当前不允许宣布 PREHARDWARE_RELEASE_READY。
- 当前不允许将 Run #100 ISO 写入真实 TF 卡作为最终启动盘。
