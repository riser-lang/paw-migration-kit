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


---

## 记录 0005：纠正 Gemini 4 Hydrogen 两小时任务 Prompt（2026-11-13）

- 记录时分支 HEAD：`aba61424c581a3399a9221fdcc1c17ca5bd0c00e`
- 用户指出上一份 Gemini Prompt 错误地固定复用 Run #124 的旧 ISO，没有把本轮必要纠错和修复后 GitHub 构建作为真正交付目标。
- 本记录只追加，不修改任何此前记录。

### 用户最终澄清的执行目标

两小时用于：
1. 由用户本地 Gemini 4 Hydrogen 在本地工作区执行必要代码纠错；
2. 将修复提交并推送至 GitHub 当前开发分支；
3. 修复后的正式测试必须通过 GitHub Actions 执行；
4. 最终 ISO 必须由修复后最新代码 HEAD 的 GitHub 成功工作流构建；
5. 获取新 Artifact 并独立校验 ISO SHA256。

不得将 Run #124 的旧 ISO 固定为本轮最终产物，也不得仅下载旧 Artifact 就宣布完成。

### 本次复核发现的真实问题范围

1. **SSH 中断测试授权字段缺失（测试夹具）**
   - 文件：`tests/prehardware/guest-chain.sh`，约721–734行。
   - 目标登记从 `target-identity.json` 写入 `hardware_identity_sha256` 和 `composite_identity_sha256`。
   - 中断测试随后创建的 `operator-authorization.json` 没有写入 `target_hardware_identity_sha256` 和 `target_composite_identity_sha256`。
   - `scripts/paw-transaction.py cmd_init` 明确要求两项授权字段与目标登记匹配。
   - 修复测试夹具，不能修改正式身份门禁。

2. **50GiB目标启动证据误判（测试验证器）**
   - 文件：`tests/prehardware/verify-chain-evidence.py`。
   - 当前 `target_boot_login` 只检查日志任意位置包含 `login:`。
   - 应要求 `auto_reboot PASS` 之后出现目标 Ubuntu 登录证据，并且与 `run-prehardware-lab.py` 的 Host runner 结果 `TARGET_BOOT_SEEN`、`chain_pass=True`、`target_boot=True` 相互印证。
   - 增加启动前残留 login 的负向测试。
   - 需按真实日志格式实现，不要臆造字符串。

3. **源盘 root 分区不是最后一个分区，当前只在扩容阶段才发现（真实迁移失败风险）**
   - 文件：`scripts/paw-source-discovery.sh`。
   - 当前源盘发现校验 root partition number 合法，但没有提前确认 root partition 是否为磁盘上最后一个分区。
   - `scripts/paw-gpt-expand.sh` 到扩容阶段才通过 START offset 检查 root partition 必须是最后一个分区。
   - 这可能导致源盘识别、克隆和校验已经完成后，才在 GPT/ext4 扩容阶段失败。
   - 必须把相同的“root partition start 必须等于所有分区最大 start”检查前移到源盘发现阶段；无法读取/比较时 fail closed。
   - 增加 root 最后分区的正向测试和 root 后面还有分区的负向测试。不得自动移动/删除源盘分区。

4. **无序列号 SSD 的稳定身份能力与总控门禁不一致（真实启动阻断风险）**
   - 文件：`scripts/paw-live-controller.sh`。
   - `paw-target-discovery.sh`、`paw-identity.py`、`paw-hardware-preflight.sh` 已支持无序列号但有 WWN/by-id 等稳定身份的 SSD。
   - 但 live controller 当前仍要求 `target_serial` 非空，并直接比较序列号和容量；这会使无序列号设备无法达到 READY_FOR_OPERATOR，与 MASTER 的稳定身份回退要求冲突。
   - 应复用 `paw-identity.py verify --phase prewrite --check-unique` 和硬件身份哈希、精确容量、健康报告绑定；不得降低身份唯一性或硬件检查门禁。
   - 增加 live-controller 无序列号 WWN/by-id 正向测试，以及身份不唯一/替换设备负向测试。
   - 若两小时内无法安全完成此项，必须在交接中明确标为 OPEN，不得假装无序列号路径已端到端通过。

### 本轮构建原则

- 起始分支：`vm/ds-final-prehardware-remediation-20261112`
- 记录时分支 HEAD：`aba61424c581a3399a9221fdcc1c17ca5bd0c00e`（这是交接文档提交，不是固定的最终运行时代码）。
- 当前历史常规 CI Run #124 / SHA `0ced6e8...` 只作基线参考，**不是本轮最终 ISO**。
- 修复后必须产生新的运行时代码 commit SHA。
- GitHub Actions `build-live-and-test.yml` 必须在该新 SHA 上运行并成功。
- 最终 ISO 必须由该新 SHA 的成功 Run 构建、上传、下载并独立 SHA256 校验。
- 不得使用 Run #124、Run #123 或任何旧 Artifact/ISO 作为本轮最终交付。
- 成功构建后，如时间允许，使用同一新代码 SHA 对应的 build Run ID 触发 `prehardware-50g.yml`；其 workflow 会校验 ISO Run headSha 与自身 checkout SHA 相同。该50GiB任务可以在两小时工作预算结束后继续运行。
- 50GiB未通过时，完整迁移仍未验收，真实破坏性克隆不能放行。

### 两小时和模型额度控制

- 使用用户本地 Gemini 4 Hydrogen，不要转交回云电脑 DeepSeek。
- 只读项目 Master、State、Blockers、Current Handoff 和本记录涉及的文件；不要全仓库重审。
- 先确认本地工作区状态、当前分支、未提交改动和远端 HEAD；不得 reset --hard、clean -fd 或 force push。
- 只做上述有明确依据的最小修改；不重构、不改生产VPS、不操作真实SSD/TF卡。
- 本地只跑快速定向测试和语法检查；权威完整测试必须在 GitHub Actions。
- 最多一次完整 GitHub build/test dispatch；若出现明确且局部的代码错误，可在预算内修复一次并再跑一次。禁止无限重试。
- Artifact 下载通过本地 GitHub CLI；connector 对大于512MiB的 ZIP 有大小限制。
- 成功后记录新 Runtime SHA、CI Run ID、Artifact ID、ISO bytes、ISO SHA256、独立下载复算结果。
- 追加更新本文件，不得修改任何历史记录。

### 当前状态

- 旧 Run #124 ISO 不得作为本轮最终 ISO。
- 本轮纠错和新 GitHub 构建尚未执行。
- 50GiB链路仍为 BLOCKED / 未验收。
- 最终迁移目标保持不变。


---

## 记录 0006（2026-11-13，本地 Windows / Gemini 4 Hydrogen — P0-1..P0-4 最终纠错、GitHub 全绿构建、新 ISO 独立校验与 50GiB 链路触发）

### 本轮已完成的 4 项 P0 修复与测试

1. **P0-1：SSH 中断测试授权字段缺失（`tests/prehardware/guest-chain.sh`）**
   - 从 `$interrupt/target-identity.json` 动态读取 `hardware_identity_sha256` 与 `composite_identity_sha256`，写入 `$interrupt/operator-authorization.json` 的 `target_hardware_identity_sha256` 与 `target_composite_identity_sha256`（不硬编码哈希，未削弱 `scripts/paw-transaction.py` 门禁）。
   - 保存 `paw-transaction.py init` 的 `tx-init.stdout`、`tx-init.stderr`、`tx-init.rc`，失败时输出实际退出码与 stderr 原因。
   - 在 `scripts/ci/run-p0-remediation-tests.sh` 增加正负向测试：匹配哈希允许初始化、错误 hardware/composite 哈希拒绝、任一字段缺失拒绝、SSH 中断后 `CLONE_INCOMPLETE` 与 `CLONE-INCOMPLETE` 标记保留。

2. **P0-2：目标 Ubuntu 启动证据验证与双端相互印证（`tests/prehardware/verify-chain-evidence.py`、`tests/prehardware/run-prehardware-lab.py`、`.github/workflows/prehardware-50g.yml`）**
   - 移除只要日志任意位置出现 `login:` 即通过的误判。
   - 严格要求先出现 `PAW3_STEP=auto_reboot STATUS=PASS`，其后才允许匹配 `Ubuntu 24.04... ubuntu ttyS0` 与紧随其后的 `ubuntu login:`。
   - 增加 `--runner-log` 校验 Host runner 输出中的 `main result=TARGET_BOOT_SEEN ... chain_pass=True ... target_boot=True`，实现 Host runner 与 Guest verifier 相互印证。
   - 在 `scripts/ci/run-p0-remediation-tests.sh` 增加正负向测试（仅启动前 login FAIL、无 auto_reboot FAIL、仅有重启无目标 Ubuntu login FAIL、仅有通用 login FAIL、runner 标记不一致 FAIL、完整证据 PASS）。

3. **P0-3：源盘 Root 最后一个分区前移检查（`scripts/paw-source-discovery.sh`、`scripts/ci/run-virtual-tests.sh`、`scripts/ci/run-p0-remediation-tests.sh`）**
   - 在 `paw-source-discovery.sh` 解析 Rescue SSH `lsblk --json` 返回的 `partn`（禁止缺失/重复）、`START`（禁止缺失/非正整数/重复）与 `SIZE`，严格核对 `root_start == max_start`。
   - 若 Root 后存在其他分区或 `START` 缺失/不完整，直接 fail closed 写出 `"status": "BLOCKED"` 诊断报告并拒绝创建 `source.json`；正常情况将 `root_is_last_partition`、`root_partition_start`、`max_partition_start` 与 `partition_layout_check` 写入 `source-discovery.json`。
   - 保留 `scripts/paw-gpt-expand.sh` 原第二道扩容门禁，不自动移动/删除源盘任何分区。
   - 在 `run-virtual-tests.sh` 与 `run-p0-remediation-tests.sh` 增加正向（常规与 cloud 分区号排布）及负向（Root 非最后分区、START 缺失、partn 重复）测试。

4. **P0-4：无序列号 SSD 端到端进入总控流程（`scripts/paw-live-controller.sh`、`scripts/paw-hardware-preflight.sh`、`scripts/paw-memtest-confirm.sh`、`scripts/paw-memory-test-report.sh`、`scripts/paw-final-confirm.sh`）**
   - 移除 `paw-live-controller.sh`、`paw-memtest-confirm.sh`、`paw-memory-test-report.sh` 与 `paw-final-confirm.sh` 对 `target_serial` 非空的硬性要求；复用 `paw-identity.py resolve` 与 `verify --phase prewrite --check-unique`、精确容量校验与硬件身份哈希绑定。
   - `paw-hardware-preflight.sh` 将 `target_hardware_identity_sha256`、`target_composite_identity_sha256` 与 `target_identity_basis` 持久化到 `paw-hardware-health-report.json`。
   - 修复 `paw-final-confirm.sh` `target_serial_suffix` 在短/空序列号时安全回退至 `target_hardware_identity_sha256[-8:]`，并确保中文 tty 提示控制在内核 fbcon 512 字形槽位上限内（保持 416 个唯一非 ASCII 字符）。
   - 在 `scripts/ci/run-ssd-health-tests.sh` 增加 7 组完整正负向场景：有序列号 SSD PASS、无序列号 WWN SSD 全链路 `READY_FOR_OPERATOR`、无序列号 by-id SSD `READY_FOR_OPERATOR`、身份不足 BLOCKED、同身份双盘歧义 BLOCKED、授权/登记后替换盘 BLOCKED、健康报告 WARN/FAIL 阻断。

### 权威 GitHub Actions 验证与全新 ISO 独立校验结果

- **代码分支**：`vm/ds-final-prehardware-remediation-20261112`
- **已验收 Runtime Commit SHA**：`7ec4dbf3d14fb7e23aa213f7f9021d24c569913a`（公开安全与历史扫描 `check-public-safety.py` / `check-public-history.py` 全通过）
- **常规 CI（`build-live-and-test.yml`）**：Run ID **`43398893910`**，`conclusion=success`（全流程 24 步绿色通过，含 CJK font `1/1` (`416` 唯一字形)、PAWDATA `12/12`、Virtual fault-injection `43/43`、Repair `27/27`、Network `28/28`、P0 `46/46`、P1 `24/24`、SSD identity/controller `41/41`、VLESS `25/25`、Finalize `36/36`、TTY `56/56`）
- **新 Artifact**：`paw-live-build-test-results`，Artifact ID **`14025033882`**，ZIP 精确字节数 **`1030672881`**
- **本地 ZIP 完整性与 ISO 独立校验**（下载目录 `C:\PAW-Release\run-43398893910`）：
  - `7z t C:\PAW-Release\run-43398893910\paw-live-build-test-results.zip`：`Everything is Ok`（88 files，`Physical Size = 1030672881`）
  - ISO 路径：`C:\PAW-Release\run-43398893910\paw-live-amd64.iso`
  - ISO 精确字节数：**`953155584`** bytes（与 `iso-identity.txt` 完全一致）
  - ISO 实算 SHA256：**`eec712f8f2b2677046d3aafabc8e76a7fce82219062f418bad19dbd46f696358`**
  - 与 `paw-live-amd64.iso.sha256`、`iso-identity.txt` 比对：**100% MATCH**
- **历史 Run #124（`43374947901` / `0ced6e8...`）**：仅作历史对比基线，**已作废，不作为本轮最终 ISO**。

### 50GiB 完整链路触发状态

- 使用新 build Run ID `43398893910` 触发 `.github/workflows/prehardware-50g.yml`：
  - Run ID：**`43402874795`**（`https://github.com/riser-lang/paw-migration-kit/actions/runs/43402874795`）
  - 对应 `headSha`：`7ec4dbf3d14fb7e23aa213f7f9021d24c569913a`（已通过 `Check out the exact tested commit`、`Fetch the ISO artifact from the selected build run` 与源/目标镜像准备步骤）
  - 记录时状态：**`in_progress`**（正在构建 test-only toram Live ISO 并即将执行 50GiB→240GB QEMU 链路，结果待该 Run 结束后核对）。

### 当前状态与未完成项

- 本轮 P0-1..P0-4 代码整改、新增测试、GitHub 完整构建测试及新 ISO 独立下载校验全部完成。
- `prehardware-50g.yml` Run `43402874795` 正在执行中；在其完整 PASS 前，50GiB 完整链路仍为 **OPEN / IN_PROGRESS**。
- 本次未执行真实 TF 卡写盘、未修改生产 VPS / Tailnet / Xray / MCP / `main` 分支。


---

## 记录 0007：ChatGPT 独立验收与启动盘制作判断（2026-11-13 17:47 Asia/Shanghai）

### 1. 本次核验的 GitHub 实际状态

- 仓库：`riser-lang/paw-migration-kit`
- 分支：`vm/ds-final-prehardware-remediation-20261112`
- 当前分支 HEAD：`dd2b297ed985df9d80319ef50ddb59d292da14d6`
- 已验收运行时代码：`7ec4dbf3d14fb7e23aa213f7f9021d24c569913a`
- 比较运行时代码与当前分支 HEAD：仅 ahead 1 个文档提交，涉及 `PAW-CURRENT-HANDOFF.md`、`PAW-MIGRATION-STATE.md)、`PAW-MIGRATION-BLOCKERS.md`；没有发现运行时代码在 CI 后继续变化。
- PR #2 仍未作为本轮发布基线；本轮验收针对上述开发分支和运行时代码 SHA。

### 2. 常规 GitHub CI 和 ISO：PASS

- Run #129：`43398893910`
- Workflow：`build-live-and-test.yml`
- Runtime SHA：`7ec4dbf3d14fb7e23aa213f7f9021d24c569913a`
- Job `build-test`：SUCCESS；GitHub job steps 全部完成且成功。
- 关键测试摘要与原始日志核对：
  - console font fail-closed：26 assertions / 0 failed；
  - CJK font coverage：1 passed / 0 failed，416 个唯一非 ASCII 字符；
  - CJK framebuffer tty1 + keyboard：25 passed / 0 failed，5 cases；
  - PAWDATA 虚拟介质：12 passed / 0 failed；
  - virtual disk/fault injection：43 passed / 0 failed；
  - offline repair/rollback：27 passed / 0 failed；
  - network/staged connectivity：28 passed / 0 failed；
  - P0 remediation：46 passed / 0 failed；
  - P1 remediation：24 passed / 0 failed；
  - SSD stable identity/controller：41 passed / 0 failed；
  - VLESS/Tailscale：25 passed / 0 failed；
  - Finalize/reboot：36 passed / 0 failed；
  - TTY/PTY：56 passed / 0 failed，0 blocked。
- P0-1 日志确认：目标硬件和组合身份哈希正确时允许事务初始化；错误或缺失哈希拒绝；SSH 中断后保留 CLONE-INCOMPLETE。
- P0-2 日志确认：启动前 login、缺失 auto_reboot、重启后无 Ubuntu login、通用 login、Host runner 不匹配均被拒绝；有效 post-reboot Ubuntu login + Host runner corroboration 通过。
- P0-3 日志确认：root 最后分区通过；root 后还有分区、START 缺失、PARTN 重复均 BLOCKED；扩容阶段第二道门禁保留。
- P0-4 日志确认：无序列号 WWN SSD 和 by-id SSD 可以进入 READY_FOR_OPERATOR；身份不足、重复身份、替换盘及健康 WARN/FAIL 仍被阻断。
- GitHub runner ISO 构建日志记录：
  - `iso_bytes=953155584`
  - SHA256：`eec712f8f2b2677046d3aafabc8e76a7fce82219062f418bad19dbd46f696358`
  - xorriso 识别 `El Torito` 与 `MBR isohybrid cyl-align-on GPT APM`。
  - SeaBIOS/TCG smoke step 成功。
- Artifact：`paw-live-build-test-results`，ID `14025033882`，ZIP size `1030672881` bytes，GitHub digest `sha256:a7a5851535a001d5800fbf749c5e6ffd4ea6d87545cfbe50f713c39f4850ad84`，expires `2026-11-27T09:36:41Z`。
- Gemini 本地报告：ZIP `7z t` 通过（88 files，Everything is Ok）；提取 ISO 为 `953155584` bytes；本地独立 SHA256 `eec712f8f2b2677046d3aafabc8e76a7fce82219062f418bad19dbd46f696358`，与 sidecar 和 `iso-identity.txt` 一致。ChatGPT 已从 GitHub runner 日志复核 ISO 字节数和 SHA256；本会话无法直接读取用户本地 Windows 文件，故本地 ZIP 测试和独立哈希属于 Gemini 提供的本地执行证据。
- 本轮最终 ISO 不使用旧 Run #124；Run #124 仅为历史基线。

### 3. 50GiB 完整链路：仍 IN_PROGRESS，不得放行真实克隆

- Run #17：`43402874795`
- URL：https://github.com/riser-lang/paw-migration-kit/actions/runs/43402874795
- Workflow：`prehardware-50g.yml`
- 运行时代码 SHA：`7ec4dbf3d14fb7e23aa213f7f9021d24c569913a`
- 使用 ISO build Run ID：`43398893910`；workflow 已验证 ISO Run 的 headSha 与自身 checkout SHA 相同。
- 核验时状态：`in_progress`。
- 已完成成功的步骤：checkout exact commit、runner capacity、工具安装、获取对应 ISO Artifact、Ubuntu cloud image 校验、准备精确50GiB源盘/240GB目标盘、构建 test-only toram Live ISO、构建32GB USB虚拟介质、QEMU权限准备。
- 当前正在执行：`Run 50 GiB source to 240 GB target chain (QEMU/TCG)`。
- 后续 `Verify chain evidence`、`Collect evidence`、`Publish artifact` 尚未执行。
- 因此目前不能声明50GiB完整克隆、传输字节数、独立SHA256、离线修复、扩容、自动重启和目标Ubuntu启动通过。
- 50GiB Run 完成前，真实生产整盘克隆继续 BLOCKED。

### 4. 额外发现的真实硬件兼容性风险：PAWDATA 对 TF/USB 读卡器的识别

ChatGPT 复核了运行时代码 `scripts/paw-data-prepare.sh`：

- 真实（非 simulation）路径会从 `findmnt /run/live/medium` 识别当前启动介质的父磁盘；
- 随后硬性要求 `lsblk RM` 等于 `1`；
- 随后硬性要求该设备返回非空 SERIAL；
- 任一条件不满足，PAWDATA 自动初始化就会返回阻断状态。
- 当前 PAWDATA 12/12 测试使用 loop/simulation 介质，并 mock 序列号；没有证明 ASUS 主板上的真实 USB TF 读卡器一定返回 `RM=1` 且提供非空 SERIAL。
- 若真实读卡器报告 `RM=0` 或无序列号，PAWDATA 初始化将不会自动完成；`paw-live-controller.sh` 会因 PAWDATA 不健康而保持 BLOCKED，正式克隆不会启动。这是安全阻断，不会因此误写目标 SSD。
- 该风险不阻止现在制作启动盘，但意味着不能承诺首次真实启动时 PAWDATA 必然自动初始化。首次实机启动必须观察 PAWDATA 是否 PASS；若未 PASS，停止，不得绕过门禁或手工改写磁盘分区。
- 后续如需兼容特定读卡器，应以当前启动介质父设备、USB transport、稳定身份、唯一性、容量、ISO/分区布局和用户确认建立替代识别方案；不得简单删除 RM/身份门禁。

### 5. 文档一致性问题

- `PAW-MIGRATION-BLOCKERS.md` 已把 `BLOCK-SSD-IDENTITY-UX` 标记 CLOSED。
- 但当前 `PAW-MIGRATION-STATE.md` 仍保留一段旧的“必须解决：用户不知道SSD序列号”文字，与同一文件前面“P0-4已通过”的状态矛盾。
- 这是文档快照不一致，不是本次 ISO 构建失败；建议下一轮仅修正文档当前状态，历史交接记录仍不可修改。

### 6. 最终验收判断

- **PREHARDWARE_MEDIA_READY_NONDESTRUCTIVE_ONLY：允许制作实体启动盘。**
- 允许理由：最新修复代码 Run #129 全部24个 workflow steps 成功；ISO 构建、Hybrid MBR/GPT/El Torito 信息、SeaBIOS smoke、CJK、PAWDATA虚拟测试、磁盘安全测试通过；Artifact 已上传；Gemini 本地报告 ZIP 完整性和 ISO 独立 SHA256 MATCH，且 runner 日志 SHA256 一致。
- 该结论仅授权进入实体启动介质制作和非破坏性硬件验收阶段，不代表真实硬件兼容性已通过，也不代表50GiB完整迁移已通过。
- 制作 TF 卡时应使用 ISO/DD 镜像写入模式，保留 Hybrid ISO 原始分区布局；Windows 弹出格式化提示必须取消；不得手工调整/格式化 PAWDATA 分区。
- 首次启动只做 PAW Live、中文控制台、PAWDATA、SSD身份盘点、SMART/只读扫描、Memtest、HD4600、网卡、网络检查；不要输入最终迁移授权。
- **真实 SSD 整盘克隆：NOT RELEASED / NOT AUTHORIZED**，至少等待 Run #17 50GiB完整链路 PASS，并在实体机确认启动介质、PAWDATA、目标SSD身份、硬件健康和真实Rescue SSH后，再单独向用户请求最终迁移授权。
- 本次 ChatGPT 仅进行 GitHub 只读核验和本文件末尾追加；未修改运行时代码、未写入真实 TF 卡/SSD、未操作生产 VPS。

### 7. 下一步

1. 用户可使用本次 ISO（953155584 bytes，SHA256 `eec712f8f2b2677046d3aafabc8e76a7fce82219062f418bad19dbd46f696358`）制作32GB TF/USB启动盘。
2. 采用 Rufus DD 模式或等效 raw image 写入；写入前确认目标设备确为TF卡，避免选中其他磁盘。
3. 写入完成后不要接受 Windows 格式化提示。
4. 首次实机启动保持非破坏性，只观察 PAWDATA 与硬件检测结果；如 PAWDATA 未 PASS 或任一关键硬件状态 BLOCKED/WARN，停止，不进入最终授权。
5. ChatGPT 后续重新核对 Run #17 的最终状态和证据，再决定完整迁移是否放行。


---

## 记录 0008：在家庭 Windows 电脑制作实体 TF/USB 启动盘的交接（2026-11-13）

- 目的：用户更换到家中 Windows 电脑制作启动盘；该电脑尚未安装 Rufus。
- 当前仓库分支 HEAD：`1f5639e47d191e9b677967595c9fb4c39df7f89e`（记录时仅包含运行时代码之后的文档追加）。
- 已验收运行时代码：`7ec4dbf3d14fb7e23aa213f7f9021d24c569913a`。
- GitHub build Run：`43398893910`，SUCCESS；head SHA 与已验收运行时代码一致。
- Artifact：`paw-live-build-test-results`，ID `14025033882`，ZIP `1,030,672,881` bytes；当前未过期。
- ISO：`paw-live-amd64.iso`，`953,155,584` bytes。
- ISO SHA256：`eec712f8f2b2677046d3aafabc8e76a7fce82219062f418bad19dbd46f696358`。
- Artifact ZIP digest：`sha256:a7a5851535a001d5800fbf749c5e6ffd4ea6d87545cfbe50f713c39f4850ad84`（注意这不是 ISO SHA256）。
- GitHub 50GiB workflow Run `43402874795` 在本记录时仍为 `in_progress`，不能将50GiB完整链路记为PASS；不改变实体启动介质制作许可与真实破坏性克隆仍阻断的边界。

### 家庭 Windows 电脑执行规则

1. 从 GitHub Run `43398893910` 下载 Artifact `14025033882`，只取本轮 ISO 及其 sidecar、iso-identity、provenance 和测试摘要；不要下载历史 Run #124 ISO。
2. 优先用 GitHub CLI。若未安装，先从 Microsoft winget 安装官方 GitHub CLI，或通过已登录的 GitHub 官方网页下载该 Run 的 Artifact。不得要求用户粘贴 PAT、密码或其他凭据。
3. 本地核对 Run conclusion=success、headSha=`7ec4dbf3d14fb7e23aa213f7f9021d24c569913a`、Artifact ID、ZIP 完整性、ISO 精确字节数及 SHA256。
4. 家庭电脑未安装 Rufus：从官方站点 `https://rufus.ie/` 下载当前稳定版 Windows x64 portable 可执行文件；不使用第三方下载站、广告下载器或来历不明的镜像。记录下载来源、版本、文件签名（如有）和 SHA256。无需安装，使用 portable 即可。
5. 插入 TF 卡读卡器前后分别枚举 Windows 磁盘，依据新增设备、USB 总线、型号、容量、序列号/PNP 信息交叉识别；不能仅凭磁盘编号、可移动标志或容量猜测目标。若出现多块可能目标磁盘，先要求用户断开其他外置存储设备。
6. 写入前向用户明确展示 Windows Disk Number、型号、精确容量、BusType、SerialNumber（若有）和将被完全覆盖的风险；必须由用户对该具体设备再次明确确认后才能点击 Rufus Start。
7. Rufus 选择本轮 ISO，遇到 ISOHybrid 写入模式选择时使用 DD Image mode，保留 ISO 原始 Hybrid MBR/GPT/El Torito 布局；不要用文件复制或手工格式化代替镜像写入。
8. 写入后执行 Rufus 可用的写入验证；如能安全只读回读，则对目标物理盘开头 `953155584` bytes 计算 SHA256，与 ISO SHA256 比对。不得对物理盘执行 PowerShell 写入、DiskPart clean、format、initialize 或其他额外破坏性命令。
9. Windows 弹出“需要格式化磁盘才能使用”提示时必须取消；不要格式化、不要调整分区、不要手工创建 PAWDATA 分区。PAWDATA 由 PAW 首次启动流程按设计处理。
10. 写盘成功后安全弹出 TF 卡；报告 ISO SHA、TF 卡型号/容量、Disk Number、Rufus 版本、写入验证结果和时间。

### 首次真实启动安全边界

- 仅进行 PAW Live 启动、中文控制台、PAWDATA 初始化、SSD 自动识别、SMART/只读扫描、Memtest、HD4600、Realtek 网卡和网络检查。
- PAWDATA 真实读卡器识别仍有待验证风险：当前 `paw-data-prepare.sh` 要求 live parent device 报告 `RM=1` 且 SERIAL 非空。若读卡器返回 `RM=0` 或无 SERIAL，PAWDATA 会 BLOCKED；停止，不得绕过。
- 不输入最终迁移授权，不运行整盘克隆，不对真实 SSD 写入。
- 50GiB Run `43402874795` 只有在完成完整证据链并 PASS 后才可关闭对应阻断；实体硬件和真实 Rescue SSH 仍需现场验收及用户另行授权。

### 本次任务状态

- 已完成 GitHub 候选 ISO 的版本和 Artifact 信息核对。
- 家庭电脑 Rufus 尚未下载。
- 实体 TF 卡尚未写入。
- 本记录只作为执行交接，不表示写盘已经完成。
