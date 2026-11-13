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


---

## 记录 0002：2026-11-13 最新进展复核（ChatGPT 独立核查）

- 记录时间：2026-11-13 14:30（Asia/Shanghai）
- 仓库：`riser-lang/paw-migration-kit`
- 工作分支：`vm/ds-final-prehardware-remediation-20261112`
- 本次复核时分支 HEAD：`0ced6e8210cca67d678ccf5d24e2f12f591e91a7`
- 最新运行时代码：`0ced6e8210cca67d678ccf5d24e2f12f591e91a7`
- 本记录为只读评审和交接追加；没有修改运行时代码，没有触发工作流，没有操作真实硬件或生产 VPS。

### 1. 常规构建与测试工作流

- Run #124：https://github.com/riser-lang/paw-migration-kit/actions/runs/43374947901
- Run ID：`43374947901`
- 运行时代码：`0ced6e8210cca67d678ccf5d24e2f12f591e91a7`
- 结果：SUCCESS；`build-test` job 的23个工作流步骤全部成功。
- 通过的主要专项输出：PAWDATA 12/0、虚拟故障注入39/0、离线修复27/0、网络28/0、P0 26/0、P1 24/0、SSD身份30/0、VLESS 25/0、Finalize 36/0、TTY 56/0、CJK五场景25/0。
- Artifact：`paw-live-build-test-results`，ID `14014299163`，ZIP大小 `1,030,674,014` bytes；Artifact ZIP digest `sha256:8d075674f288e2d4e936d65fa80dbea6b0894ca7d3c428ea76b68e05e4cff09d`；到期时间 `2026-11-27T06:19:52Z`。
- Run #124 构建的 ISO：`953,155,584` bytes；构建日志中的 ISO SHA256：`eed910bb6d06314e33547a5b65fa0e9ee896d910b494b7d9eb54dbb4fdecaf5e`。
- 说明：ISO SHA256 是该次 runner 构建记录；Artifact 下载后的独立提取与复算尚未完成，不能把 ZIP digest 当作 ISO digest，也不能声称已完成独立下载复核。
- 该工作流不包含独立的50GiB完整迁移链路；常规 CI 全绿不等于50GiB链路通过。

### 2. 50GiB独立工作流实际状态

- 最新50GiB工作流 Run #16：https://github.com/riser-lang/paw-migration-kit/actions/runs/43372389032
- Run ID：`43372389032`
- 结果：FAILURE。
- 该次50GiB工作流的 head SHA：`6662723145603914eba6f5b28bd42b7ee23543d4`，早于本记录时最新运行时代码 `0ced6e8210cca67d678ccf5d24e2f12f591e91a7`。
- 该次运行使用的 ISO 构建 Run ID：`43368913055`（Run #123），不是最新 Run #124 的 ISO。
- 前一轮 Run #15（ID `43364557104`）也在相同的 `ssh_interrupt` 阶段失败。
- GitHub 当前没有排队或正在运行的工作流。

### 3. 50GiB链路已证明和未证明的内容

该次 Run #16 日志证明虚拟环境已准备并识别：
- 源盘：`53,687,091,200` bytes（精确50GiB）；
- 目标盘：`240,000,000,000` bytes；
- 启动介质：`32,000,000,000` bytes；
- QEMU/TCG、Haswell、ICH9 AHCI、USB Mass Storage启动路径；
- Ubuntu 24.04.5源系统识别；
- PAWDATA初始化；
- 目标盘虚拟身份登记；
- 256MiB混合数据流和独立SHA256；
- 网络步骤为WARN（仅本地链路）。

但在 `ssh_interrupt` 阶段，Guest 输出：
`STEP ssh_interrupt STATUS=FAIL could not initialize the interruption transaction`

Host runner 同时报告：
`main result=CHAIN_FAIL chain_pass=False target_boot=False qemu_rc=0`

因此主50GiB克隆、完整传输字节数、独立SHA256、离线修复、GPT/ext4扩容、自动重启和目标系统启动均未完成。该次运行不能称为50GiB完整链路通过。

### 4. 已定位的测试夹具契约不匹配

当前 `tests/prehardware/guest-chain.sh` 的 SSH 中断测试：
- 从 `target-identity.json` 创建 `target-ssd.json`，其中包含 `hardware_identity_sha256` 和 `composite_identity_sha256`；
- 但随后创建的 `operator-authorization.json` 只有 `target_device`、`target_serial` 等字段，缺少 `target_hardware_identity_sha256` 和 `target_composite_identity_sha256`；
- 当前 `scripts/paw-transaction.py cmd_init` 在目标登记包含硬件身份哈希时，明确要求授权文件提供并匹配上述两个哈希。

这构成一个可直接从当前代码确认的测试夹具数据契约不匹配。正确修复方向是让测试授权记录携带从同一份 `target-identity.json` 读取的两个身份哈希，并保留正式事务校验；不得放宽 `paw-transaction.py` 的身份门禁。

当前最新提交 `0ced6e8` 将中断测试适配器从可能被 noexec 挂载的 `/run/paw3-intbin` 移到 rootfs 的 `/usr/local/lib/paw3-intbin`，这是合理的环境修复，但没有补齐授权文件缺失的两个哈希，因此不能认为它已经解决 Run #16 的事务初始化失败。

此外，当前 `tests/prehardware/verify-chain-evidence.py` 的 `target_boot_login` 判定仅为日志中出现任意 `login:` 字符串；这不足以证明目标系统在自动重启之后到达登录界面。Run #16 的 Host runner 明确报告 `target_boot=False`，所以该 verifier 的 `target_boot_login=PASS` 不能作为目标系统启动通过证据。应要求自动重启标记之后出现目标 Ubuntu 的准确串口登录标识，并与 Host runner 的 `target_boot=True / TARGET_BOOT_SEEN` 结果相互印证。

### 5. 模型选择判断与下一步

- 当前判断：暂不更换开发模型。Run #124 的23/23常规工作流通过，说明常规修复和专项测试取得了实质进展；50GiB失败目前集中在一个可定位的测试夹具身份字段不匹配，不足以证明当前模型整体无法胜任。
- 下一步只给DS一次范围明确的修复任务：
  1. 在SSH中断测试的授权JSON中加入与目标登记完全一致的 `target_hardware_identity_sha256` 和 `target_composite_identity_sha256`；
  2. 保留 `paw-transaction.py` 正式身份检查，不降低门禁；
  3. 将事务初始化 stdout/stderr 和退出码写入独立日志，失败时保留诊断；
  4. 修正50GiB证据验证器，禁止仅凭任意 `login:` 判定目标启动成功；要求自动重启之后的目标Ubuntu登录证据，并核对Host runner目标启动结果；
  5. 先运行针对性中断事务测试，再在新代码HEAD上运行完整常规CI并构建对应ISO；
  6. 再运行50GiB工作流，`iso_run_id` 必须指向同一代码HEAD的成功构建Run；
  7. 必须看到29/29必需步骤全部PASS、Host runner报告目标启动成功，才可认定50GiB链路通过。
- 如果上述明确修复后仍在同一处失败，或DS无法提供事务初始化的实际错误码和诊断日志，再考虑更换模型/执行代理。

### 6. 安全边界与当前放行状态

- 本轮没有修改生产VPS、没有进入生产Rescue、没有读取生产整盘、没有写入真实SSD或TF卡。
- 没有修改main、没有合并PR、没有删除Artifact。
- 当前软件常规CI：PASS（Run #124）。
- 50GiB完整迁移链路：BLOCKED（Run #16失败，且运行代码早于最新HEAD）。
- ISO独立下载复核：NEEDS_TEST。
- 真实硬件、真实Rescue SSH和生产网络：继续保持OPEN / NEEDS_TEST。
- 当前不能宣布 `PREHARDWARE_RELEASE_READY`，不能据此放行真实整盘克隆。


---

## 记录 0003：两小时截止与本地 Gemini 执行方案

- 记录时间：2026-11-13（用户提出最多再投入两小时，要求完成启动盘准备）
- 本次分支 HEAD：`81e33ca7c12f88c517967ad321f0211a8fbc93a0`
- 最新已测试运行时代码：`0ced6e8210cca67d678ccf5d24e2f12f591e91a7`
- 本次记录只追加项目决策和执行计划，不修改任何历史记录、运行时代码或真实介质。

### 1. 用户决定

用户希望改由本地电脑上的 Gemini 4 Hydrogen 承担本轮本地执行，认为它可能比云电脑 DeepSeek 更强、更快。用户可用时间最多约两小时，目标是尽快完成启动介质准备。

### 2. 执行能力边界

- 当前 ChatGPT 会话没有可直接启动用户本地 Gemini 4 Hydrogen 或远程控制其本地终端的工具。
- 现有 Agy 工具是服务器侧执行器，默认 Gemini 3.8 Flash High，并非用户指定的 Gemini 4 Hydrogen，也不是用户本地电脑；不得冒充为用户要求的执行环境。
- GitHub Artifact connector 对 Run #124 的约1.03GB Artifact 返回超过512MiB上限的错误，不能通过当前 connector 直接取回完整 ZIP。
- 因此建议用户在本地 Gemini 4 Hydrogen 中执行 GitHub CLI 下载和本地 SHA256 复核。

### 3. 两小时内的最短可靠路线

不建议从源码重新构建一份新 ISO。Run #124 已经在运行时代码 `0ced6e8210cca67d678ccf5d24e2f12f591e91a7` 上完成常规 CI 并成功构建 ISO。重新本地编译会产生不同构建环境和新哈希，浪费时间并降低与已测试产物的一致性。

优先下载并验证现有 Run #124 Artifact：

- Run：`43374947901`
- Artifact ID：`14014299163`
- Artifact 名称：`paw-live-build-test-results`
- Artifact ZIP 大小：`1,030,674,014` bytes
- ISO：`paw-live-amd64.iso`
- ISO 大小：`953,155,584` bytes
- 预期 ISO SHA256：`eed910bb6d06314e33547a5b65fa0e9ee896d910b494b7d9eb54dbb4fdecaf5e`
- 运行时代码 SHA：`0ced6e8210cca67d678ccf5d24e2f12f591e91a7`

本地执行要求：
1. 检查 GitHub CLI 登录状态。
2. 查询 Run #124 的 conclusion 和 headSha，确认 SUCCESS 且 headSha 精确匹配上述运行时代码。
3. 使用 `gh run download 43374947901 --repo riser-lang/paw-migration-kit --name paw-live-build-test-results --dir <专用输出目录>` 下载并解压 Artifact。
4. 检查 ISO 文件大小。
5. 使用 Windows PowerShell `Get-FileHash -Algorithm SHA256` 对提取出的 ISO 独立复算。
6. 与预期 SHA256 及 Artifact 内 sidecar / iso-identity 文件交叉核对。
7. 保存本地校验报告和 ISO 路径。

### 4. 安全和放行边界

- Run #124 的常规 CI 通过，不代表独立50GiB完整链路通过。
- 50GiB Run #16 仍为 FAILURE，失败于 SSH 中断负向测试的事务初始化；该链路的主克隆、50GiB独立校验、离线修复、扩容和最终启动没有完成。
- Run #124 ISO 可作为通过常规软件测试的候选启动介质，用于启动、中文界面、PAWDATA和非破坏性硬件检查；不能据此宣布正式整盘克隆已获完整验收。
- 用户必须在实体机上先完成 BIOS/USB、TF卡识别、SSD身份、SMART/只读扫描、内存、显卡、网卡和 Rescue 网络检查。
- 未获得用户对具体 TF 卡的明确写入授权前，不得运行 DiskPart clean、格式化、dd、Rufus 写入或任何覆盖真实介质的命令。
- 未获得正式迁移授权且现场安全门禁未通过前，不得对真实 SSD 执行整盘克隆。

### 5. 当前建议状态

- 常规软件 CI：PASS（Run #124）。
- 候选 ISO 已构建：PASS（runner 构建记录）。
- Artifact 本地下载和 ISO 独立 SHA256：待 Gemini 本地执行。
- 真实 TF 卡写入：待用户明确授权及核对设备。
- 50GiB完整链路：BLOCKED / 未验收。
- 正式生产克隆：NOT AUTHORIZED / NOT RELEASED。

### 6. 下一步

让本地 Gemini 4 Hydrogen 执行 Run #124 Artifact 下载、独立 ISO 哈希复核和本地校验报告。优先复用已构建的 ISO，不重新编译。校验完成后由 ChatGPT 再核对结果，并在用户明确授权后安排 TF 卡写入。


---

## 记录 0004：用户澄清两小时任务范围与最终目标（2026-11-13）

- 记录时分支 HEAD：`183099fae59d6ec8ed22dcfea4b05965d0f29a36`
- 用户明确澄清：两小时用于“必要纠错 + 修复后的 GitHub 测试 + 最终 ISO 构建”，不是仅下载现有 ISO，也不是把工作降级为非破坏性启动盘。
- 如有代码修改，必须提交到当前 GitHub 开发分支，并由 GitHub Actions 执行正式测试和构建；不得用本地测试替代 GitHub 验收。
- 用户希望由本地 Gemini 4 Hydrogen 执行本轮开发，减少 DeepSeek 的长任务消耗和 Gemini token 浪费。
- 最终项目目标没有变化：制作可用于完整 PAW 迁移的启动介质，安全完成旧腾讯云 Ubuntu 50GiB 系统盘向武汉本地 SSD 的迁移，恢复 PAW 服务、Tailscale/VLESS/Exit Node 和原有 GPT/Claude/Gemini MCP 路径；旧 VPS 保留为 paw-gateway。
- 不得将“候选 ISO 构建成功”改称“完整迁移已验收”，不得删除50GiB完整链路和真实硬件门禁。

### 当前事实基线

- 开发分支：`vm/ds-final-prehardware-remediation-20261112`
- 分支 HEAD（本记录开始时）：`183099fae59d6ec8ed22dcfea4b05965d0f29a36`，这是交接文档提交。
- 最新常规 CI 运行时代码：`0ced6e8210cca67d678ccf5d24e2f12f591e91a7`
- 常规 CI Run #124：`43374947901`，SUCCESS，23/23 workflow steps。
- Run #124 Artifact：`14014299163`，名称 `paw-live-build-test-results`，约1.03GB。
- Run #124 ISO：`953155584` bytes；runner 记录 SHA256 `eed910bb6d06314e33547a5b65fa0e9ee896d910b494b7d9eb54dbb4fdecaf5e`。本地独立下载复核尚未完成。
- 50GiB Run #16：`43372389032`，FAILURE；失败于 `ssh_interrupt` 事务初始化，尚未完成主50GiB克隆及后续修复/扩容/重启/目标启动。
- 50GiB workflow `prehardware-50g.yml` 有350分钟超时；常规 `build-live-and-test.yml` 为 workflow_dispatch，job 超时120分钟。Run #124 实际约27分钟。
- 当前没有已知排队或正在运行的相关 Actions。
- GitHub Artifact connector 对大于512MiB的 ZIP 无法直接下载；本地 Gemini 应使用 GitHub CLI 下载。

### 两小时内允许的最小工作范围

1. 只修改两个已确认的测试问题，不做生产运行时代码重构：
   - `tests/prehardware/guest-chain.sh`：SSH中断测试创建的 `operator-authorization.json` 缺少与 `target-ssd.json` 对应的 `target_hardware_identity_sha256` 和 `target_composite_identity_sha256`。应从同一份 `target-identity.json` 读取并写入；保留正式 `paw-transaction.py` 身份校验。
   - `tests/prehardware/verify-chain-evidence.py`：不得仅凭日志任意位置出现 `login:` 判定目标启动成功。必须验证自动重启标记之后的目标 Ubuntu 登录证据；Host runner 也必须独立确认 `TARGET_BOOT_SEEN`、`chain_pass=True` 和 `target_boot=True`。
2. 增加上述两个问题的快速正向/负向测试。
3. 提交到当前开发分支。
4. 通过 GitHub Actions 手动触发一次完整 `build-live-and-test.yml`；不能用本地测试代替。
5. 若常规 CI 成功，下载该次构建 Artifact，独立核对 ISO 大小、SHA256、sidecar 和代码 HEAD。
6. 使用该次成功构建的 Run ID 触发 `prehardware-50g.yml`。它可在两小时窗口结束后继续运行；必须等其结果和证据才能决定完整迁移是否放行。
7. 如50GiB workflow未能在两小时内完成，记录为进行中/未验收，不能降低标准；启动盘可以作为候选介质准备，但正式破坏性克隆仍须等待50GiB和实体硬件门禁通过。

### 两小时资源控制

- 本地 Gemini 只读取 Master、当前 Handoff、相关两个脚本及对应 workflow；不要重新阅读整个仓库或重做全面审计。
- 只允许一次针对性补丁、一次常规完整 GitHub CI/ISO构建、一次50GiB workflow dispatch。
- 如果常规 CI 失败，只允许在剩余时间内修复明确且直接相关的失败；禁止无关重构和反复重跑。
- 不要重新编译与 GitHub 测试无关的本地 ISO。
- 不得修改 main、合并 PR、操作生产 VPS、写真实 TF 卡/SSD。
- 两小时是纠错与最终构建的工作预算，不改变完整迁移验收标准。

### 当前结论

- 现有 Run #124 ISO 只是已通过常规CI的候选产物，不是本轮纠错后的最终构建。
- 本轮目标是用最小修改得到新的 GitHub 完整CI成功Run和对应最终ISO，并启动同一代码版本的50GiB完整链路验收。
- 最终迁移目标保持不变；如果50GiB或真实硬件门禁未通过，不得执行真实整盘克隆。
