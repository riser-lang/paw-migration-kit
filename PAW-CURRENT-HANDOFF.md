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


---

## 记录 0009：50GiB Run #17 完成及启动盘写入报告复核（2026-11-14）

- 记录时间：2026-11-14
- 复核分支：`vm/ds-final-prehardware-remediation-20261112`
- 复核时分支 HEAD：`6ffb2c486b20acbe007dbb8702a0c86adfb0b89a`
- 本次只读核验 GitHub Actions 和追加交接；未操作真实硬件。

### 1. 50GiB 完整虚拟链路：PASS

GitHub Run #17：
- Run ID：`43402874795`
- URL：https://github.com/riser-lang/paw-migration-kit/actions/runs/43402874795
- Workflow：`prehardware-50g.yml`
- conclusion：`success`
- 测试运行时代码：`7ec4dbf3d14fb7e23aa213f7f9021d24c569913a`
- ISO build Run：`43398893910`，同一代码 SHA。
- Artifact：`paw-50g-chain-evidence`，ID `14035420490`，35,058,030 bytes，digest `sha256:ebedfe020b04f4944a18c8d7b939509aa92e97fb56d6e42d1fab97c03c4b6de1`，保留至 `2026-11-27T12:14:04Z`。

从 GitHub 原始 Job log 复核到：
- 源盘：`53,687,091,200` bytes（精确50GiB）。
- 目标盘：`240,000,000,000` bytes。
- 启动介质：`32,000,000,000` bytes。
- steps_seen=31，required_steps=29。
- `chain_result_pass=PASS`。
- `auto_reboot_before_target_login=PASS`。
- `target_boot_login=PASS`。
- `no_fail_steps=PASS`。
- `all_required_steps_present=PASS`。
- `all_required_steps_pass=PASS`。
- `source_exact_50gib=PASS`。
- Host runner：`main result=TARGET_BOOT_SEEN chain_pass=True target_boot=True qemu_rc=0`。

关键 Guest 证据：
- `compressed_transfer PASS`：源盘53,687,091,200 bytes，payload 946,697,338 bytes，恢复53,687,091,200 bytes。
- `clone_complete PASS`：目标写入范围完成。
- `sha256_verify PASS`：SHA256 `110c9a0ac831bf5dc0f786fc34bd9eef7a5346d6512e30c8593aba00f97ee6ca`，验证字节数53,687,091,200，独立校验通过，CLONE-INCOMPLETE 清除。
- `offline_repair PASS)。
- `gpt_expand PASS)：目标根分区由52,612,283,904 bytes扩展到238,925,192,704 bytes。
- `preboot_handoff PASS)。
- `auto_reboot PASS)。
- Host runner 在自动重启后识别目标 Ubuntu ttyS0 登录提示，target_boot=true。

重要限制：
- 网络步骤为 `WARN`，日志说明这是本地链路（loopback）而非真实公网连接；主链按设计未将其作为失败条件。
- Rescue SSH 是 QEMU 内的 `127.0.0.1:2222`，不是腾讯云公网 Rescue。
- AHCI 是 QEMU 虚拟控制器，不是真实 B85 主板 SATA。
- CPU 是 QEMU Haswell 模型，不是真实 CPU 直通。
- 这是50GiB完整虚拟迁移链路 PASS，不是实际腾讯云源盘迁移或武汉实体机通过。

### 2. 实体启动盘制作报告复核

依据用户提供的 Gemini 本地执行报告（本会话不能直接读取用户 Windows 本地文件，故本地设备和Rufus操作事实来自用户提供的报告）：

- ISO：Run `43398893910`，Runtime SHA `7ec4dbf3d14fb7e23aa213f7f9021d24c569913a`。
- ISO：`953,155,584` bytes。
- ISO SHA256：`eec712f8f2b2677046d3aafabc8e76a7fce82219062f418bad19dbd46f696358`。
- Rufus：4.15.2396 portable，报告称官方签名验证通过。
- 写入模式：DD Image mode。
- 目标：Disk 1，Generic Mass-Storage，`31,362,908,160` bytes，序列号 `20240418000000`。
- USB 读卡器 PNP：`USB\VID_349C&PID_0418\20240418000000`。
- Rufus 报告写入完成，随后 Windows `CM_Request_Device_Eject` 安全弹出成功，系统只剩 Disk 0。

### 3. 108字节回读差异：不能记为全盘 SHA MATCH

用户提供的只读回读报告称：
- 从物理 TF 卡回读前953,155,584 bytes，SHA256 为 `d2a66b147577d54a561a6fc6a693bd239b285536ebb0386987490e0f56cdffd2`，与 ISO SHA256 不同。
- 逐字节比较称953,155,476 bytes一致，108 bytes不同；差异位于FAT分区区域（offset 287659 的60 bytes、offset 3681792 的48 bytes），其他字节一致。
- 报告推断差异来自 Windows 自动挂载 FAT 后写入卷/目录元数据。

独立判断：
- 这不是“整张卡与 ISO 位级完全一致”，不能写成全盘 SHA256 MATCH。
- 108 bytes 位于FAT区域且其余字节一致，可能是 Windows 自动挂载产生的 FAT 元数据变化；这不必然影响 Legacy BIOS 启动路径，但仅凭该差分报告不能证明 UEFI FAT 启动路径也完全无影响。
- 由于目标主板当前优先采用 Legacy BIOS/CSM，本次可以进入首次实机启动验证；应明确观察 BIOS 是否能从 USB 启动、PAW Live 是否完整加载。
- 不建议现在仅因108 bytes差异就反复重写TF卡；若 Legacy BIOS 启动失败，再优先排查写盘/读卡器/固件启动模式。若希望证明 bit-for-bit 一致，可在另一次写盘前禁用 Windows automount，再DD写入并只读回读；不得对当前卡执行任何修复性写入或格式化。
- Windows 自动弹出的格式化提示一律取消；不要格式化TF卡或手工改动PAWDATA分区。

### 4. 当前放行状态

- 常规 GitHub CI：PASS（Run #129 / `43398893910`）。
- 最终候选 ISO：构建与 SHA256 sidecar / Gemini本地独立计算一致。
- 50GiB完整虚拟迁移链路：PASS（Run #17 / `43402874795`）。
- 实体 TF/USB 启动盘：按用户报告，DD写入完成并安全弹出；回读非完全位级一致，108 bytes FAT区域差异。
- **允许进入 ASUS 实体主板首次启动和非破坏性硬件验收。**
- 首次启动检查 PAW Live、中文控制台、PAWDATA、SSD自动发现、SMART/只读扫描、Memtest、HD4600、Realtek网卡及网络。
- PAWDATA仍要求 Linux 下 live parent disk 的 `RM=1` 且 SERIAL 非空。若不满足或PAWDATA不PASS，停止，不绕过门禁、不手工分区。
- 真实生产整盘克隆仍需：真实硬件检查通过、真实腾讯云 Rescue SSH和源盘身份确认、目标SSD身份及健康检查通过、网络传输条件确认、备份/回退方案确认，并取得用户对具体源盘和目标盘的明确最终授权。
- 不得把 QEMU 50GiB PASS 等同于真实生产迁移已通过。

### 5. 下一步

1. 将TF卡/读卡器插入 ASUS B85M-G Plus，使用 Legacy/CSM 启动路径首次启动。
2. 只观察 PAW Live 是否启动、中文菜单是否正常、PAWDATA 是否PASS、硬件和网络检测结果。
3. 保存启动日志和报告；如PAWDATA或关键硬件门禁失败，停止并反馈。
4. 不输入最终迁移授权，不开始真实克隆。


---

## 记录 0010：目标主机改为 Dell OptiPlex 3020M 的镜像兼容性判断（2026-11-14）

- 记录时开发分支 HEAD：`6ee87f361a8214c600b9a8712955f88facea61f0`。
- 运行时代码仍为 `7ec4dbf3d14fb7e23aa213f7f9021d24c569913a`；本次未修改运行时代码、未触发新 CI、未重建 ISO、未写入 TF 卡或 SSD。
- 用户提供新硬件截图，目标主机由原计划 ASUS B85M-G Plus 改为 Dell OptiPlex 3020M Micro。

### 1. 截图可确认的当前硬件

- Dell OptiPlex 3020M。
- 主板标识 Dell 0WWRRC。
- Intel H81。
- Intel Core i5-4670T，Haswell，4核4线程，2.30GHz基础/3.30GHz最大，45W。
- 16GB（8GB+8GB），Micron + Samsung；DDR3/DDR3L混合组合待实机确认，截图显示1333MHz。
- Intel HD Graphics 4600，无独立显卡。
- 120GB SSD（截图文字只显示到“120GB S...”）；具体型号、SATA/NVMe接口、精确容量、序列号尚未读取。

### 2. 官方规格交叉核对

Dell OptiPlex 3020 Micro 官方规格资料确认：
- H81 芯片组；
- 第四代 Intel Core CPU；
- Intel HD Graphics 4600（适用CPU）；
- Micro版本两个SO-DIMM插槽，最高16GB；
- Micro版本支持一个2.5英寸硬盘位；
- Dell 3020 Micro 系列规格中列出集成 Realtek RTL8151GD 10/100/1000 Ethernet。

来源：
- Dell OptiPlex 3020 Micro Technical Specification：https://i.dell.com/sites/doccontent/business/smb/merchandizing/en/Documents/Dell_OptiPlex_3020_with_Micro_Technical_Spec_Sheet.pdf
- Debian trixie firmware-realtek 文件列表：https://packages.debian.org/trixie/all/firmware-realtek/filelist
- Debian trixie firmware-realtek 包说明：https://packages.debian.org/stable/firmware-realtek

### 3. 镜像适配判断

**无需改变的部分：**
- CPU 仍为 Haswell x86_64；现有 Debian amd64 内核无需因 i5-4670T 更换。
- H81 与之前 B85 同属该代 Intel 平台；不需要主板专用内核。
- HD Graphics 4600 与原计划完全相同；i915/fbcon/CJK路径无需因主机更换而重做。
- 16GB 内存处于 Dell 3020M 官方16GB上限；无需修改内存相关镜像配置，但实机必须跑 Memtest。
- Dell Micro 有2.5英寸硬盘位；截图所示120GB SSD是否为该接口仍需实机确认。

**建议的最小镜像改动：**
- 当前已验收运行时代码 `7ec4dbf3` 的 `configs/live-build/package-lists/paw.list.chroot` 未包含 `firmware-realtek`。
- Dell 3020M 官方规格列出 RTL8151GD 有线网卡；Debian trixie 的 `firmware-realtek` 包包含 `rtl_nic/rtl8168g-*.fw` 等 Realtek NIC 固件。
- 为降低 PAW Live 在真实有线网络初始化时因固件缺失而无法联网的风险，建议把 `firmware-realtek` 加入 live-build package list，重新运行 GitHub 完整 CI 并构建新 ISO。
- 这是兼容性保险建议，不是已经证明当前 ISO 一定无法驱动该网卡。必须以真实 PCI ID、`lspci -nnk`、`dmesg` 和 DHCP/DNS 实测确认；若当前 ISO 已能正常驱动 RTL8151GD，则不应仅为形式而重写 TF 卡。
- 当前 `configs/live-build/auto/config` 已启用 `non-free-firmware` archive area，包源配置允许安装该固件包。
- 不建议更换内核、重写网卡驱动或改变系统架构。

### 4. 120GB目标盘判断

- 旧腾讯云源盘已在50GiB虚拟链路中按精确 `53,687,091,200` bytes 验收。
- 标称120GB目标盘从容量上应大于50GiB源盘；但必须通过真实 `blockdev --getsize64` 读取精确字节数，确认实际目标容量大于源盘。
- 现有 `paw-stream-clone.sh`、`paw-stream-verify.sh`、`paw-final-confirm.sh` 使用实际源/目标容量比较，并未硬编码240GB作为必须容量。
- 现有50GiB QEMU完整链路的目标盘是240,000,000,000 bytes；它证明迁移流程在240GB目标盘上工作，但没有直接证明120GB目标盘的分区末端扩容行为。
- 建议在任何真实克隆前增加一次仅使用 disposable QEMU/loop image 的50GiB→120GB（目标精确字节数模拟真实SSD）的专项扩容测试；至少验证GPT备份头、root partition增长和ext4增长到目标末端。
- 不得对真实120GB SSD进行测试写入或格式化；现场首次检测只读。

### 5. 启动模式和现场检查

- 原云端源系统使用Legacy BIOS/GRUB PC路径，目标机首次启动应在Dell BIOS中选择Legacy/CSM路径，保持与克隆系统一致；不要为了“更新”而切换UEFI。
- Dell常规进入BIOS Setup为F2，一次性启动菜单为F12；以实机BIOS显示为准。
- 首次启动只做非破坏性检查：PAW Live、中文控制台、PAWDATA、SSD自动发现、SMART/只读扫描、Memtest、HD4600、RTL8151GD网卡、DHCP/DNS。
- PAWDATA仍有已知门禁：Linux live parent disk 必须报告 RM=1 且 SERIAL 非空；失败时停止，不绕过、不手工分区。
- 不输入最终迁移授权，不对真实120GB SSD执行克隆。

### 6. 本次结论

- 不需要因CPU/H81/HD4600/16GB内存更换而修改内核或系统架构。
- 建议最小补入 `firmware-realtek` 后重建候选 ISO，再决定是否重写TF卡；若先现场启动验证现有卡也可以，但网卡不通时不得开始迁移。
- 120GB容量理论上够用，但必须实测精确容量，并补做50GiB→120GB虚拟目标盘专项扩容验证。
- 当前TF卡可以用于首次非破坏性启动；不代表当前镜像的RTL8151GD网卡固件已经确认。
- 50GiB→240GB虚拟链路已PASS；真实Dell硬件、120GB目标盘、Rescue公网链路和PAW服务切换仍未实测。


---

## 记录 0011：Dell 3020M 的45W CPU与Micro官方35W规格差异（2026-11-14）

- 追加更正，不修改记录0010及任何历史内容。
- Dell 官方 OptiPlex 3020 Micro 规格将 Micro 机型第四代 Core i5 处理器标为35W级别；Intel 官方规格确认截图所示 i5-4670T 的 TDP 为45W。
- 因此，虽然截图显示该机器当前确实识别并运行 i5-4670T，但该CPU功耗等级高于Dell 3020 Micro公开规格所列35W Micro CPU等级。不能仅凭当前能开机就断言在持续迁移负载下散热/供电完全符合OEM设计。
- 这不是PAW ISO需要更换内核或CPU微码的理由；这是主机硬件稳定性/散热风险。首次实体验收应检查 BIOS 是否识别CPU、风扇和温度读数、持续负载温度及是否降频/关机；若温度异常、风扇策略不正常或出现热关机，不得开始长时间50GiB真实迁移。
- 相关来源：
  - Dell OptiPlex 3020 Micro Technical Specifications：https://i.dell.com/sites/csdocuments/shared-content_data-sheets_documents/en/optiplex-3020-micro-technical-spec-sheet.pdf
  - Intel Core i5-4670T 官方规格：https://www.intel.com/content/www/us/en/products/sku/75050/intel-core-i54670t-processor-6m-cache-up-to-3-30-ghz/specifications.html
- 结论：CPU/芯片组架构仍受现有amd64镜像支持；但45W CPU相对Micro官方35W规格的差异必须在实机持续负载和温度检查中关闭，不能忽略。


---

## 记录 0012：Dell 3020M 镜像补充及 50GiB→120GB 虚拟验收任务准备（2026-11-14）

- 记录时分支 HEAD：`d6f496dfb2ac13ca4710930078aba83148ec2814`。
- 用户要求：针对新目标 Dell OptiPlex 3020M，给 Gemini 4 Hydrogen 一份任务 Prompt，处理必要镜像补充，并对标称120GB SSD做50GiB→120GB虚拟扩容验收。
- 本轮未修改运行时代码、未构建ISO、未触碰真实SSD/TF卡。
- 当前已验收运行时代码仍为 `7ec4dbf3d14fb7e23aa213f7f9021d24c569913a`；Run #129 `43398893910` 与50GiB→240GB Run #17 `43402874795` 均在该代码SHA上成功。
- 分支 HEAD 当前含后续文档提交；不得把文档HEAD误认为新运行时代码。

### 已确认的关键事实

1. 当前 `configs/live-build/package-lists/paw.list.chroot` 不含 `firmware-realtek`，而 `configs/live-build/auto/config` 已启用 `non-free-firmware`。
2. 用户提供的 Dell OptiPlex 3020M 截图显示 i5-4670T、H81、16GB、HD4600、120GB SSD；网卡 PCI ID、SSD精确字节数和SSD接口尚未实测。
3. Dell 3020 Micro 的网卡配置不能只凭机型名称或不同机箱版本的规格表推定。应在实机通过 `lspci -nnk` 读取实际 PCI ID；加入 `firmware-realtek` 作为通用固件覆盖建议，不得宣称它已经证明网卡型号。
4. 当前50GiB链路存在明确240GB硬编码：
   - `tests/prehardware/prepare-images.sh` 中 `target_bytes=240000000000`，目标镜像名 `target240.img`；
   - `tests/prehardware/guest-chain.sh` 强制 `dst_bytes == 240000000000`；
   - `tests/prehardware/run-prehardware-lab.py` 使用 `target240.img`；
   - `.github/workflows/prehardware-50g.yml` 名称、注释和步骤描述均写死240GB。
5. 因此120GB验收不能只把QEMU镜像改小；必须把测试 harness 参数化，保证容量参数从 workflow 输入一路传到 image preparation、QEMU目标文件、Guest精确容量门禁和最终报告。
6. 当前真实源盘容量基线为53,687,091,200 bytes（50GiB）；120GB十进制测试目标建议用120,000,000,000 bytes作为可重复的模拟值，同时实机仍需用 `blockdev --getsize64` 读取实际字节数。
7. 当前迁移运行时代码按真实容量比较源/目标，扩容阶段按实际磁盘末端扩展；但现有50GiB虚拟全链路只对240GB目标盘完成端到端验证。

### 本轮任务范围

- 在 Live ISO package list 增加 `firmware-realtek`，并在构建后的 rootfs/ISO 中验证固件包实际安装和关键固件文件存在；不能只检查 package list 文本。
- 通过GitHub完整CI构建新ISO并独立核验 Artifact/ISO SHA256。
- 将50GiB虚拟链路目标容量参数化，默认保持240GB兼容性；增加精确120,000,000,000 bytes的完整虚拟目标盘测试。
- 120GB测试必须真实执行50GiB全盘流式克隆、恢复字节数核验、独立SHA256/O_DIRECT、离线修复、GPT备份头移动、root分区增长、ext4增长和重启后目标Ubuntu登录。
- 报告必须同时记录 source_bytes、target_bytes、partition_before/after、filesystem_before/after、target free space 和容量余量；不能只看到QEMU镜像逻辑容量就判定通过。
- 不允许将120GB虚拟测试说成真实120GB SSD通过，也不允许把50GiB→240GB旧Run与新120GB测试拼成一个Run。
- 如目标120GB在真实字节容量下小于53,687,091,200 bytes，必须BLOCKED；不能缩小源盘测试数据。

### 网卡识别原则更正

- 不再在MASTER或任务中把RTL8151GD当作已由用户截图证实的事实。
- 现场必须读取PCI ID、子系统ID、`lspci -nnk`、`dmesg` 和驱动/固件加载情况。
- `firmware-realtek` 是合理的固件覆盖补充，但若实际网卡不是Realtek或需要其他固件，应根据实测证据调整；不进行猜测式驱动替换。

### 安全边界

- 仅使用可丢弃的QEMU/loop普通文件镜像做120GB虚拟测试。
- 不对真实120GB SSD做测试写入、格式化、SMART写入测试或badblocks写入测试。
- 不写真实TF卡，不修改生产VPS，不进入生产Rescue，不修改main、不合并PR。
- 所有正式真实克隆仍需实机门禁及用户明确授权。


---

## 记录 0013：Dell OptiPlex 3020M `firmware-realtek` 适配、120GB 目标容量参数化及 50GiB→120GB 完整虚拟验收完成（2026-11-15）

- 运行时提交 SHA：`02d02c79fa3035ad3089f474566ca917e5d2482a`（分支：`vm/ds-final-prehardware-remediation-20261112`）。
- 本轮未修改 `main`、未合并 PR #2、未删除历史 Artifact，也未对真实 SSD、真实 TF 卡或生产 VPS 执行任何写操作。

### 1. 代码改动摘要（commit `02d02c79fa3035ad3089f474566ca917e5d2482a`）

1. **`firmware-realtek` 包入与双重构建验证**
   - `configs/live-build/package-lists/paw.list.chroot` 新增 `firmware-realtek`（使用 Debian Trixie 固定快照 `20261101T000000Z` 与 `main non-free-firmware`）。
   - `scripts/build-debian-live.sh` 在 `dpkg-query` 锁清单阶段强制校验 `firmware-realtek` 存在。
   - `.github/workflows/build-live-and-test.yml` 与 `scripts/ci/qemu-live-smoke.sh` 同时校验 chroot `dpkg-query -L firmware-realtek` 及成品 ISO 内 `/live/filesystem.squashfs` 中 `/usr/lib/firmware/rtl_nic/*.fw` 文件存在，并产出 `firmware-realtek-report.txt` 随产物上传。
2. **50GiB 预硬件链目标容量全链路参数化（默认兼容 `240000000000`）**
   - 参数传递与校验：`PAW_EXPECTED_TARGET_BYTES` / `--target-bytes`（必须为正整数、>= `53687091200` 且 512 字节对齐；默认 `240000000000`），贯通 `.github/workflows/prehardware-50g.yml`、`tests/prehardware/prepare-images.sh`、`tests/prehardware/build-live-lab-iso.sh`、`tests/prehardware/build-lab.sh`、`tests/prehardware/paw-prehardware-chain.service`、`tests/prehardware/guest-chain.sh` 与 `tests/prehardware/verify-chain-evidence.py`。
   - 镜像文件标准化：将硬编码 `target240.img` 统一替换为 `target.img`（`prepare-images.sh`、`run-prehardware-lab.py`、`prehardware-50g.yml`）。
   - 扩容与剩余空间指标增强：`scripts/paw-gpt-expand.sh` 与 `guest-chain.sh` 在 `gpt-expand.json` 与 `PAW3_STEP=gpt_expand` 记录 `disk_bytes`、`before_bytes`、`after_bytes`、`filesystem_before_blocks`、`filesystem_after_blocks`、`filesystem_block_size`、`filesystem_after_free_blocks`、`filesystem_after_free_bytes`、`gpt_verified`。
   - 单元测试补充：`scripts/ci/run-p0-remediation-tests.sh`（P0 套件由 46 扩充至 59 项）覆盖 240GB 默认、120GB 通过、容量失配拒绝、非法/不对齐/小于 50GiB `target_bytes` 拒绝及未扩容拒绝。

### 2. 新版 Live ISO 构建与独立校验结果

- Workflow：`build-live-and-test.yml` **Run #130（`43615851949`）**
  - `headSha`：`02d02c79fa3035ad3089f474566ca917e5d2482a`
  - 状态 / 结论：`completed / success`（全部 24 步通过：CJK 字体 1/1、CJK QEMU 25/25、PAWDATA 12/12、Fault-injection 43/43、Offline repair 27/27、Network 28/28、P0 59/59、P1 24/24、VLESS 25/25、Finalize 36/36、TTY 56/56）
- Artifact：`paw-live-build-test-results`（ID `14123560276`，ZIP 精确大小 `1030677538` bytes）
  - 本地下载目录：`C:\PAW-Release\run-43615851949\`
  - `7z t` ZIP 完整性：`Everything is Ok`（89 个文件）
  - `paw-live-amd64.iso` 精确字节数：`953155584` bytes
  - 本地独立 SHA256：`71012766e4a23b540182c6952c244768d4a9c1c9c88a9e0e289d5d5ca6e6364c`（与 `paw-live-amd64.iso.sha256`、`iso-identity.txt` 完全一致）
- `firmware-realtek` 验证（`firmware-realtek-report.txt`）：
  - 包版本：`firmware-realtek` `20250410-2`（`all`）
  - 状态：`INSTALLED_AND_VERIFIED_IN_ISO_SQUASHFS`
  - chroot 文件数：36；ISO `/live/filesystem.squashfs` 文件数：36（含 `rtl8168d/e/f/fp/g/h`、`rtl8105e/8106e/8107e`、`rtl8153/8156`、`rtl8125/8126`、`rtl8402/8411` 系列 `.fw`）

### 3. 50GiB → 120GB 完整虚拟迁移链验收结果

- Workflow：`.github/workflows/prehardware-50g.yml` **Run #18（`43618362793`）**
  - `headSha`：`02d02c79fa3035ad3089f474566ca917e5d2482a`（与 `iso-run.json` 校验一致，ISO 来源 Run `43615851949`，输入 `target_bytes=120000000000`）
  - 状态 / 结论：`completed / success`（`chain-50g` 耗时 `3h23m49s`，`runner_rc=0`）
  - Artifact：`paw-50g-chain-evidence`（ID `14129979760`，ZIP 大小 `35068330` bytes，已校验）
  - Host runner 结论：`main result=TARGET_BOOT_SEEN chain_pass=True target_boot=True qemu_rc=0`
  - `verify-chain-evidence.py` 结果：`status=PASS`（14 项 `checks` 全部 `true`）
  - 精确容量与扩容指标（`chain-acceptance.json` + `gpt-expand.json`）：
    - `source_bytes`：`53687091200`（50 GiB）
    - `target_bytes`：`120000000000`（`target_bytes_observed=120000000000`）
    - `root_partition_before_bytes`：`52612283904`
    - `root_partition_after_bytes`：`118925192704`（`partition_grew=true`）
    - `filesystem_before_blocks`：`12844795`（4096 B/block）
    - `filesystem_after_blocks`：`29034470`（`filesystem_grew=true`）
    - 目标盘剩余可用空间：`27559444` blocks（`112883482624` bytes ≈ 105.13 GiB）
    - `gpt_verified`：`true`（`filesystem_check_method=offline`）
    - 独立 O_DIRECT SHA256 回读：`491eb86f24ca8a8304505fdd504e58becd0c7409080dffde90e68062f06db0b1`（`bytes_verified=53687091200`，`CLONE-INCOMPLETE cleared`）
    - 目标系统启动：`auto_reboot PASS` 后观察到 `Ubuntu 24.04.5 LTS ubuntu ttyS0` 与 `ubuntu login:`
  - 注：此前 240GB 基线 Run #17（`43402874795`，`7ec4dbf3...`）亦已 `success`。

### 4. 诚实边界与现场待测事项

- QEMU/TCG 120GB 虚拟链路通过不等于真实 Dell OptiPlex 3020M 与真实 120GB SSD 通过。
- Dell OptiPlex 3020M 实机启动后必须确认：32GB TF 卡（需先以 Run `43615851949` 新版 ISO 重写）实际引导与 PAWDATA；实际网卡 `lspci -nnk` PCI ID/驱动与 `dmesg` 固件加载状态；120GB SSD 真实 `blockdev --getsize64` 容量（必须 >= `53687091200` bytes）与 SMART/只读扫描；16GB 内存 Memtest86+ 7.20 实测 0 errors；HD4600 中文控制台与交互；以及腾讯云 Rescue SSH / Tailscale / VLESS / MCP 现场切换。


---

## 记录 0014：ChatGPT 对 Dell 3020M / 120GB 新版 ISO 的独立审核结论（2026-11-15）

- 审核对象：用户提供的 `PAW-DELL-120G-AUDIT-BRIEF.md` 全文及 GitHub 对应代码、Actions、Artifact 和50GiB→120GB链路证据。
- 当前分支：`vm/ds-final-prehardware-remediation-20261112`
- 当前分支 HEAD：`0db974a9788b9f660bd816ca2ebaab5e3cd1e827`
- 已验收运行时代码：`02d02c79fa3035ad3089f474566ca917e5d2482a`
- 当前 HEAD 相对运行时代码仅有1个文档提交，文件为 `PAW-CURRENT-HANDOFF.md`、`PAW-MIGRATION-STATE.md)、`PAW-MIGRATION-BLOCKERS.md`；没有运行时代码在CI之后变化。
- `main` 仍为 `0d6aefd093984a65f40d19e1fae584dee623b8e9`，未修改。
- 本次审核未修改运行时代码、未写入实体TF卡/SSD、未操作生产VPS。

### 1. GitHub 常规CI与ISO：独立核对 PASS

- Run #130：`43615851949`
- URL：https://github.com/riser-lang/paw-migration-kit/actions/runs/43615851949
- head SHA：`02d02c79fa3035ad3089f474566ca917e5d2482a`
- Job `build-test`：`completed / success`，24个workflow步骤全部成功。
- Artifact：`paw-live-build-test-results`，ID `14123560276`，ZIP `1,030,677,538` bytes，GitHub ZIP digest `sha256:e51493caf47a07f396fdd7969438c2abc09a23199edce7ca260c695aa5711008`，当前未过期。
- runner构建日志明确记录：
  - ISO `953,155,584` bytes；
  - ISO SHA256 `71012766e4a23b540182c6952c244768d4a9c1c9c88a9e0e289d5d5ca6e6364c`；
  - Hybrid system area：`MBR isohybrid cyl-align-on GPT APM`；
  - SeaBIOS/TCG smoke通过。
- 关键专项测试：PAWDATA 12/12、fault injection 43/43、offline repair 27/27、network 28/28、P0 59/59、P1 24/24、SSD identity 41/41、VLESS/Tailscale 25/25、Finalize 36/36、TTY 56/56、CJK 25/25；均为0 failed。
- `firmware-realtek` 在Debian Trixie固定快照中的版本为 `20250410-2`；runner日志确认包安装，chroot中36个 `/usr/lib/firmware/rtl_nic/*.fw` 与成品ISO squashfs中36个文件一致，状态 `INSTALLED_AND_VERIFIED_IN_ISO_SQUASHFS`。
- Artifact ZIP digest 与 ISO SHA256 是不同对象，不可互相替代。ISO SHA256以上述runner构建日志为依据；Gemini本地报告的7z ZIP测试及本地ISO复算结果与sidecar一致，但ChatGPT未直接访问用户本地Windows文件。

### 2. 50GiB→120GB完整虚拟链路：独立核对 PASS

- Run #18：`43618362793`
- URL：https://github.com/riser-lang/paw-migration-kit/actions/runs/43618362793
- 状态：`completed / success`；Job `chain-50g` 所有步骤成功。
- head SHA：`02d02c79fa3035ad3089f474566ca917e5d2482a`，与Run #130 ISO来源SHA一致。
- 输入：`iso_run_id=43615851949`，`target_bytes=120000000000`。
- Artifact：`paw-50g-chain-evidence`，ID `14129979760`，35,068,330 bytes，未过期。
- ChatGPT已下载并解压该35MB GitHub Artifact，直接读取 `chain-acceptance.json`、`chain-acceptance.txt`、`gpt-expand.json`、`migration-transaction.json`、`offline-repair.json`、`reboot-status.json`、`preboot-handoff.json` 和相关Guest日志。
- 验收器：14项checks全部true；31个步骤被记录，29个必需步骤全部存在且PASS；没有missing、non-pass或failed步骤。
- 精确容量：
  - source：`53,687,091,200` bytes（50GiB）；
  - target：`120,000,000,000` bytes；
  - USB media：`32,000,000,000` bytes。
- 传输：
  - `source_bytes=53687091200`；
  - `restored_bytes=53687091200`；
  - 独立O_DIRECT SHA256：`491eb86f24ca8a8304505fdd504e58becd0c7409080dffde90e68062f06db0b1`；
  - `bytes_verified=53687091200`，`CLONE-INCOMPLETE`已清除。
- 扩容：
  - root partition：`52,612,283,904` → `118,925,192,704` bytes；
  - ext4：`12,844,795` → `29,034,470` blocks，block size 4096；
  - target free bytes：`112,883,482,624`；
  - GPT verified=true，fsck method=offline。
- Host runner：`main result=TARGET_BOOT_SEEN chain_pass=True target_boot=True qemu_rc=0`。
- Guest证据：`auto_reboot PASS`之后观察到 `Ubuntu 24.04.5 LTS ubuntu ttyS0` 和 `ubuntu login:`。
- 这证明50GiB→120GB在QEMU/TCG可丢弃镜像中完成全链路并启动目标Ubuntu，不证明真实Dell、真实120GB SSD、真实Rescue公网SSH或真实网卡已经通过。

### 3. 关键限制和审核观察

- `network STATUS=WARN`：链路网络为本地loopback模拟，不是真实家宽到腾讯云Rescue公网传输；不得报告真实网络PASS。
- `memtest STATUS=PASS`：Guest证据明确为operator attestation，且标注 `trust=operator_attestation_not_cryptographic`；不能替代真实Dell 16GB内存Memtest。
- `hardware STATUS=PASS`：使用virtual probe adapter；真实SMART、温度和物理硬件仍OPEN。
- `offline-repair.json` 中 `grub_debconf_pinned=cloud_style_no_debconf`、`grub_install_devices_stable=false`：这是Ubuntu cloud-style grub-pc分支，debconf install_devices pin不适用；同一报告确认显式 `grub-install` 使用 `/dev/disk/by-id/ata-QEMU_HARDDISK_PAW-DST-123456`。这不是当前链路失败，但真实目标盘修复时仍须核实by-id路径解析到已登记目标盘。
- 真实Dell有线网卡PCI ID尚未实测；`firmware-realtek`提供固件覆盖，不等于已证明真实网卡型号或驱动绑定。
- 120GB为十进制模拟目标容量；真实SSD必须通过 `blockdev --getsize64` 读取实际容量，且必须大于或等于源盘实际字节数（当前源盘基线53,687,091,200 bytes）。
- i5-4670T 45W相对3020M Micro公开35W级别配置的散热差异仍需现场检查BIOS识别、风扇、温度、持续负载降频/热关机；不是重写ISO内核的理由。
- `PAW-MIGRATION-BLOCKERS.md` 当前主表已将50GiB虚拟链路标记 `CLOSED_VIRTUAL_ONLY`，但后面的历史“发布放行标准”仍残留240GB旧基准描述；这是文档维护项，不影响本次Run证据，但后续应更新该段避免误导。

### 4. 最终审核决定

- **批准使用Run #130的新版ISO重写现有32GB TF卡。**
- 批准理由：Run #130完整CI 24/24通过；Realtek固件真实进入ISO squashfs；Run #18使用同一代码SHA和该Run ISO完成50GiB→120GB完整虚拟迁移、SHA256/O_DIRECT、离线修复、GPT/ext4扩容和目标Ubuntu重启登录。
- 本次批准只涵盖“将新版ISO写入TF卡”和随后“首次实体机非破坏性启动验收”，不涵盖真实SSD克隆。
- 新版ISO固定信息：
  - Run：`43615851949`
  - Runtime SHA：`02d02c79fa3035ad3089f474566ca917e5d2482a`
  - Artifact：`14123560276`
  - ISO size：`953155584` bytes
  - ISO SHA256：`71012766e4a23b540182c6952c244768d4a9c1c9c88a9e0e289d5d5ca6e6364c`
- 重刷前确认目标为32GB TF卡，使用Rufus DD Image mode；写入会覆盖TF卡全部数据。Windows弹出格式化提示必须取消，不得手工格式化或修改PAWDATA分区。
- 若要做位级回读校验，应注意Windows自动挂载FAT分区可能修改少量FAT元数据；以Rufus写入验证为主，不得将Windows后续写入的FAT元数据差异误判为ISO构建损坏，也不得把非完全匹配报告成全盘SHA MATCH。
- 首次实体启动只做：Dell Legacy/CSM启动、PAW Live、中文控制台、PAWDATA、SSD身份盘点、SMART/温度/只读扫描、Memtest、HD4600、真实网卡PCI ID/驱动/固件、DHCP/DNS和温度/风扇检查。
- PAWDATA若未PASS，停止，不绕过门禁、不手工分区。
- 真实腾讯云Rescue SSH、源盘只读身份、120GB SSD精确容量和健康、家宽传输、Tailnet/VLESS/MCP切换仍待现场验收。真实整盘克隆必须另获用户明确授权。

### 5. 本次未执行的操作

- 未写入或重刷实体TF卡；
- 未写入真实120GB SSD；
- 未进入腾讯云生产Rescue；
- 未修改生产VPS、Tailscale、Xray、MCP；
- 未修改main或合并PR。


---

## 记录 0015：Dell 3020M 适配版 Run #130 ISO 已重写实体 TF 卡（2026-11-15）

- 依据用户提供的本地 Gemini 执行报告 `PAW-USB-CREATION-REPORT-RUN43615851949.md`；ChatGPT 已独立核对对应 GitHub Run #130、Run #18 和 Artifact 元数据。
- 使用 ISO：Run `43615851949`，Runtime SHA `02d02c79fa3035ad3089f474566ca917e5d2482a`，ISO `953155584` bytes，SHA256 `71012766e4a23b540182c6952c244768d4a9c1c9c88a9e0e289d5d5ca6e6364c`。
- Rufus：4.15.2396，用户报告数字签名 Valid；DD Image mode，`DD_CHECK=1 ISO_CHECK=0`。
- 目标设备：Windows Disk 1，`Generic Mass-Storage USB Device`，USB，Removable Media，序列号 `20240418000000`，`31,362,908,160` bytes；系统盘 Disk 0（KIOXIA KXG80ZNV512G）报告全程隔离未触碰。
- 写入时间：12:52:26–12:53:04；Rufus恢复“准备就绪”。
- 只读物理回读：回读前 `953155584` bytes 的 SHA256 为 `c7484be2475a460b23c12d6fab13e490b37f07ea5fc7ea1a900eb2eb3acadfe1`，与ISO整段哈希不同。
- 逐字节比较：`953155476 / 953155584` bytes一致；108 bytes差异均在3.25MiB FAT分区目录元数据区域。报告称 MBR/引导区 `0..284671` 和 ISO主体 `3692544..953155583` 均为0字节差异。不能报告整卡/整段SHA256 MATCH。
- 安全弹出：`CM_Request_Device_Eject` 返回 `rc=0, vetoType=0`；弹出后Get-Disk仅余系统盘Disk 0。按用户报告，TF卡当前可安全拔出。
- 本地报告路径：`C:\PAW-Release\PAW-USB-CREATION-REPORT-RUN43615851949.md`（本会话未直接读取该本地文件，以上本地写入与回读细节依据用户粘贴的执行报告）。
- 结论：新版Run #130 ISO已写入实体TF卡，可进入Dell OptiPlex 3020M首次非破坏性启动验证；108字节差异不构成当前重复重刷的理由，但不能声称bit-for-bit完全一致。
- 下一步现场只检查Legacy/CSM启动、PAW Live、中文控制台、PAWDATA初始化/重启持久化、SSD只读识别和容量、SMART/温度、Memtest、HD4600、真实网卡PCI ID/驱动/固件、DHCP/DNS及CPU温度/风扇。
- PAWDATA若不PASS，停止，不绕过门禁、不手工修改分区。
- 不输入最终迁移授权，不对真实120GB SSD写入，不进入生产VPS Rescue。


---

## 记录 0016：Dell 3020M 实机启动、键盘输入与腾讯云 Rescue 操作计划（2026-11-18）

- 用户今晚将借用普通 USB 键盘，准备继续实体机验收。
- 当前目标设备：Dell OptiPlex 3020M Micro，i5-4670T、16GB、HD4600、标称120GB SSD、32GB TF+USB读卡器。
- 当前已写入 TF 卡：Run #130 ISO，Runtime SHA `02d02c79fa3035ad3089f474566ca917e5d2482a`，SHA256 `71012766e4a23b540182c6952c244768d4a9c1c9c88a9e0e289d5d5ca6e6364c`。
- 实体机已成功从 USB 启动并显示 Linux 驱动日志；真实 PAWDATA 输入尚待键盘完成。
- 本记录只定义操作顺序；不授权进入生产 Rescue 或真实克隆。

### 1. 首次启动键盘输入

- USB 键盘插 Dell 后置 USB 口，优先 USB 2.0 口；若当前屏幕仍停在输入提示，可直接热插入并等待识别，不必先重启。
- 首次 PAWDATA 初始化的输入是当前启动介质（TF卡/读卡器）序列号末六位，不是目标 SSD 序列号，也不是腾讯云源盘 UUID。
- 输入后程序只追加新 PAWDATA 分区并格式化该新分区；不应格式化整个 TF 卡或目标 SSD。
- 如果屏幕提示 RM 非 removable、序列号为空、身份不匹配或 PAWDATA BLOCKED，停止；不得绕过门禁或手工分区。

### 2. PAW 菜单与建议顺序

菜单键位：
1 = 登记 Memtest86+ 人工确认；
2 = 手动初始化/修复 PAWDATA（仅自动初始化未通过时才考虑；不能盲目重复）；
3 = Rescue SSH 并识别旧 VPS 源盘；
4 = 只读扫描并登记目标 SSD；
5 = SSD SMART/只读扫描/温度/内存预检；
6 = 最终授权并开始真实整盘迁移（破坏性操作）；
7 = 查看报告；
8 = 选择网络阶段 R/ U；
0 = 重绘状态。

推荐阶段：
- 第一次进入 PAW Live：先确认 PAWDATA PASS。
- 选择 4：只读发现目标 SSD，核对型号、精确容量、身份依据；输入序列号末六位，若无序列号则输入稳定硬件指纹末八位。登记本身不写 SSD。
- 从启动菜单选择 Memtest86+ 独立启动项，至少完成一整轮且 errors=0；然后重新启动 PAW Live，选择菜单 1，按真实看到的 pass 数和错误数登记，并输入“确认”。
- 选择 5：执行目标 SSD SMART、只读表面扫描、温度、内核 I/O 错误和内存状态检查。不得执行写入式磁盘测试。
- 菜单 7 查看报告，确认 PAWDATA、target identity、hardware health、memory 状态。若有 WARN/FAIL/UNKNOWN，先停下处理。
- 菜单 3 与 8(R) 属于腾讯云 Rescue 阶段，只有在用户决定进入正式迁移窗口、完成快照备份并准备好停机时才执行。
- 菜单 6 会进入最终破坏性授权并启动克隆。必须另行取得用户明确授权；本轮键盘/硬件验收期间禁止选择 6。

### 3. 腾讯云 VPS 操作边界

- 旧 VPS 不得永久关机、销毁、重装或清空。它仍是当前权威源和未来 paw-gateway / 美国 Exit Node。
- 进入腾讯云 Rescue Mode 前必须先做系统盘快照/可回退备份，并安排业务停机窗口。
- 腾讯云官方文档要求实例处于关机状态才能进入 Rescue Mode；建议先正常关机，不要默认强制关机。控制台路径为实例更多操作 > 运维与检测 > 进入救援模式；设置 Rescue root 密码后进入。进入 Rescue 后，旧 Ubuntu 上的 PAW、Xray、Tailscale 和其他 systemd 服务会停止。
- Rescue 环境中，使用 root 和本次设置的临时 Rescue 密码通过 VNC 登录；PAW 生成的一次性 ed25519 公钥需按界面提示加入 Rescue 临时 authorized_keys；在 VNC 中读取 SSH host key 指纹并与 PAW 候选 SHA256 指纹逐字核对。
- PAW 之后要求输入旧 VPS 根分区 UUID（应在旧 Ubuntu 正常运行时先只读获取并安全保存）。该 UUID 用于唯一识别源根分区，不是 TF/PAWDATA 或本地 SSD 的 UUID。
- 网络阶段菜单 8 选择 R（Rescue）；菜单 3 输入 Rescue 公网主机名/IP、SSH 端口（默认22）、固定主机指纹，再输入根分区 UUID。程序通过临时 SSH 只读盘点源盘并检查源盘容量、GPT、BIOS Boot、ext4、root 最后分区和只读挂载状态。
- Rescue SSH 失败、指纹不一致、源盘身份/布局不符或读写挂载检查失败时立即停止；不得修改源盘或放宽检查。
- 完成克隆后，只有在新系统启动和回退策略确认后，才退出 Rescue 并恢复旧 VPS 正常 Ubuntu；旧 VPS后续转为 paw-gateway。不要在新旧 PAW 写入业务同时运行时贸然启动重复任务。
- Rescue 阶段旧 VPS 的原 Ubuntu Xray/Tailscale 不运行，因此不可依赖旧 Ubuntu 的 VLESS/Exit Node 为这次 Rescue SSH 提供网络。新 Dell 到腾讯云 Rescue 的 SSH 是从本地向 VPS 发起的出站连接。

### 4. 正式迁移前需要从旧 VPS 预先收集的信息

在旧 Ubuntu 仍正常运行时，通过现有 SSH 只读获取：
- 根挂载源、文件系统类型和 UUID；
- 系统盘精确容量；
- `lsblk -b -o NAME,PATH,TYPE,SIZE,MODEL,SERIAL,RO,FSTYPE,UUID,PTTYPE,PARTN,START,MOUNTPOINTS` 输出；
- 确认根分区是否最后一个分区；
- 腾讯云实例 ID/地域/公网连接信息；
- 可恢复的系统盘快照 ID。
敏感信息（密码、私钥、VLESS UUID、Tailscale key）不得粘贴到聊天或写入仓库。

### 5. 当前安全状态

- 本记录不代表已进入 Rescue、不代表已创建快照、不代表已开始停机。
- 真实 SSD 仅允许只读发现和健康检查；正式克隆仍未授权。
- 旧 VPS 保持当前正常运行状态，除非用户在后续迁移窗口明确批准进入 Rescue。


---

## 记录 0017：PAWDATA 序列号末六位与主菜单操作顺序澄清（2026-11-18）

- 用户回忆 PAWDATA 初始化界面显示过带点号且后跟六位数字的设备标识，询问是否输入该六位数字及主菜单正确顺序。
- 已重新读取运行时代码 `02d02c79fa3035ad3089f474566ca917e5d2482a` 的 `paw-data-prepare.sh`、`paw-tty-lib.sh`、`paw-console-menu.sh`、`paw-target-discovery.sh`、`paw-memtest-confirm.sh`、`paw-hardware-preflight.sh`、`paw-rescue-key-prepare.sh`、`paw-source-discovery.sh`、`paw-network-phase-select.sh` 和 `paw-final-confirm.sh`。
- 若 PAWDATA 面板的字段标签确实是“序列号”，且显示完整值末尾为 `.123456`，输入提示为“请输入该设备序列号最后6位”时，应输入最后六个字符 `123456`，不输入点号及前缀。程序实际比较 Bash 字符串最后六个字符 `${serial: -6}`。
- 该次输入绑定当前 Live 启动介质（TF卡/读卡器）的父磁盘，不是本地120GB目标SSD，也不是腾讯云源盘 UUID。
- 当前脚本真实要求启动介质 `lsblk RM=1` 且 `lsblk SERIAL` 非空。无序列号或 RM 不为1时自动初始化会 BLOCKED；不得编造编号、输入硬件指纹替代、绕过或手工分区。
- PAWDATA 自动服务在主菜单之前运行。若 PAWDATA 已健康会直接跳过；若出现序列号末六位提示，按实际屏幕末六位输入。成功后只追加并格式化新 PAWDATA 分区，不格式化 ISO 启动分区。主菜单2仅为手动初始化/修复，不应在 PAWDATA 已 PASS 时重复执行。
- 推荐实体验收顺序：
  1. 启动时完成 PAWDATA 自动初始化/检查并确认 PASS。
  2. 主菜单输入 `4`，只读扫描并登记 Dell 内部120GB SSD；输入候选编号后，按提示确认该 SSD 的序列号末六位；若 SSD 无序列号则输入稳定硬件指纹末八位。该步骤不写SSD。
  3. 从启动菜单独立选择 `Memory test (Memtest86+ x64, then return to PAW Live)`，至少完成一轮且 Errors=0；退出/重启回 PAW Live。
  4. 主菜单输入 `1` 登记 Memtest 人工观察结果：选择 `1`（至少一轮且0错误），输入实际完成轮数，输入错误数 `0`，最后输入中文 `确认`。若测试未完成/不确定选3（WARN），不得登记通过；若有错误选2（FAIL）。
  5. 主菜单输入 `5` 执行 SSD SMART、只读表面扫描、温度、内核I/O和内存报告检查。
  6. 主菜单输入 `7` 查看状态和报告；若 PAWDATA、SSD身份、硬件或内存存在 WARN/FAIL/UNKNOWN，停止。
  7. 菜单 `0` 只重绘状态；菜单 `2` 不要重复执行；菜单 `3` 和 `8=R` 留到已安排的正式腾讯云 Rescue 维护窗口；菜单 `6` 是破坏性整盘迁移授权，本轮实体硬件验收期间禁止选择。
- 腾讯云 VPS 当前保持正常运行，不关机、不进入 Rescue、不停止业务。正式迁移窗口前先在旧 Ubuntu 运行时做系统盘快照并确认完成，收集旧根 UUID、精确磁盘容量和只读分区布局；安排停机窗口后才正常关机并从腾讯云控制台进入 Rescue。Rescue 会停止旧 Ubuntu 内的 PAW/Xray/Tailscale；迁移完成后再按切换计划恢复旧 VPS，保留为 paw-gateway。进入 Rescue、停机和真实克隆均需用户后续明确授权。
- 本记录仅澄清输入与顺序，不表示已完成 PAWDATA、SSD、Memtest、VPS快照或Rescue验收。


---

## 记录 0018：用户要求的极简实机操作顺序（2026-11-18）

- 当前分支 HEAD（记录时）：`015d3d11a66b6cd39d51f862982093a517f02c66`
- 按用户要求，仅记录实际菜单选择、输入内容、时间预估和进入腾讯云 Rescue 的时点。
- Dell OptiPlex 3020M，32GB TF/USB 启动介质，目标 SSD 标称120GB；本记录不授权真实克隆。

### 操作顺序

1. Dell 开机按 F12，选择 USB Storage Device。
2. PAWDATA 首次启动面板若显示序列号且提示输入末六位，输入显示序列号最后六个字符（例如末尾为 `.123456` 就输入 `123456`）。若无序列号、RM不是1或PAWDATA BLOCKED，停止。
3. PAWDATA PASS 后，PAW主菜单输入 `4`，选择120GB SSD候选编号；按屏幕提示输入SSD序列号末六位，或无序列号时输入稳定硬件指纹末八位。登记不写SSD。
4. 重启，再按F12选择USB；在启动菜单选择 `Memory test (Memtest86+ x64, then return to PAW Live)`。至少完成一整轮，Errors=0。测试时间视内存容量和硬件而定，不能提前结束。
5. 再次重启进入PAW Live；主菜单输入 `1`，选择 `1`，输入实际完成轮数、错误数 `0`，最后输入 `确认`。
6. 主菜单输入 `5`，等待SSD SMART、只读扫描、温度、内核I/O和内存检查完成。预计约10–60分钟，按实际进度等待。
7. 主菜单输入 `7`，检查PAWDATA、目标身份、Memtest和硬件报告均PASS。任一WARN/FAIL/BLOCKED/UNKNOWN均停止。
8. 今晚实体硬件验收期间不选择菜单 `3`、`6`、`8`；旧VPS保持正常运行。

### 何时进入腾讯云 Rescue

- 只有在Dell第1–7步完成且所有关键项PASS后，才安排正式迁移维护窗口。
- 旧VPS仍正常运行时，先创建系统盘快照并确认完成；同时只读记录旧根UUID、系统盘精确容量、分区布局、公网连接信息。
- 之后才正常关机，并在腾讯云控制台进入Rescue Mode。
- Dell启动PAW后，菜单 `8` 选择 `R`（Rescue），再选菜单 `3`。
- 菜单3按提示输入Rescue公网地址、端口（默认22）；将屏幕显示的一次性公钥加入腾讯云Rescue临时authorized_keys；与腾讯云VNC显示的SSH SHA256主机指纹核对并输入；随后输入旧Ubuntu根分区UUID。
- 源盘身份、容量、GPT、BIOS Boot、ext4、root最后分区和只读挂载检查通过后，再讨论正式迁移授权。
- 菜单 `6` 是实际整盘覆盖迁移。只有用户另行明确授权后才可选择；本记录不授权。

### 时间预估

- PAWDATA：约1–5分钟（异常时停止）。
- SSD登记：约2–5分钟。
- Memtest至少一轮：约20–60分钟或更久，必须等完整一轮结束。
- SSD只读健康扫描：约10–60分钟，取决于SSD速度和状态。
- 查看报告：约2–5分钟。
- 快照、Rescue和正式迁移另行安排维护窗口，不与首次硬件验收混在一起。


---

## 记录 0019：确认 Dell 内部 Windows SSD 是预定迁移目标，但被当前目标盘门禁排除（2026-11-18）

- 用户明确确认：截图中的 `/dev/sda`、型号 `HFS128G3BMND-3210A` 就是计划用于 PAW 迁移的 Dell 内部目标 SSD。
- 当前运行时代码：`02d02c79fa3035ad3089f474566ca917e5d2482a`。
- 已复核 `scripts/paw-identity.py` 的 `inventory()`：只要磁盘分区存在 NTFS/NTFS3/ExFAT 或 Windows GPT 分区类型，就添加 `windows_or_ntfs` 排除原因，`eligible=false)。
- 已复核 `scripts/paw-target-discovery.sh`：候选清单只接受 `eligible=true`；用户选择后又进行第二道检查，明确拒绝 `d["windows"]`、NTFS/NTFS3/ExFAT 或 Windows 分区类型。
- 因此当前镜像不会允许用户登记这块仍装有 Windows 的目标 SSD。该现象是现有软件门禁行为，不是用户选错，也不能据此认定 SSD 硬件损坏。
- 当前不得绕过或手工修改运行时状态；用户应按 Enter 返回主菜单并停止目标盘登记，不得选择菜单2/6，不得格式化、删除 Windows 分区或手动清盘。
- 后续需要对目标发现流程做经过评审的最小修改：允许用户在只读盘点中明确选择已确认的内部目标盘，即使它含 Windows/NTFS；必须显示型号、精确字节容量、序列号/WWN/by-id/sysfs、分区布局和 Windows 数据将被覆盖的明确警告；要求独立的强确认并绑定稳定身份；仍排除启动介质、已挂载/系统正在使用的磁盘、源盘、身份不稳定/歧义设备；登记阶段仍只读，不写任何扇区。正式覆盖只能在菜单6完整健康/源盘/网络/授权门禁通过且用户另行明确授权后进行。
- 必须增加 Windows 目标盘允许登记的正向测试，以及启动介质、源盘、已挂载盘、身份不稳定、身份歧义和身份变化的负向测试；保留克隆前重复身份校验。
- 修改后必须通过 GitHub 完整 CI 并构建新 ISO，重新制作启动介质；不能用当前 ISO 绕过此门禁。
- 当前实体硬件验收状态：PAW Live 已启动；TF 启动介质识别状态需以PAWDATA报告为准；目标 SSD 尚未登记；Memtest、SMART/只读扫描等尚未完成；旧 VPS 继续正常运行。
- 本记录不授权清盘、进入 Rescue 或执行真实迁移。


---

## 记录 0020：确认 Windows SSD 是预定目标，当前镜像不允许直接登记（2026-11-18）

- 用户再次明确希望今晚完成，不希望仅为此等待下一轮大修。
- 用户确认 Dell 内部 `/dev/sda`、型号 `HFS128G3BMND-3210A` 是预定目标 SSD，当前含 Windows/NTFS 分区。
- 复核项目 Master 第5节：需求明确要求程序向用户展示 Windows/EFI/NTFS 等已有系统特征，让用户选择并确认目标盘；正式克隆前必须重复核验身份。目标盘已有 Windows 并不是不允许迁移的条件，因为完整克隆本来就会覆盖目标盘。
- 复核运行时代码 `paw-identity.py inventory()` 与 `paw-target-discovery.sh`：任何包含 NTFS/NTFS3/ExFAT 或 Microsoft Basic Data GPT 类型的磁盘被标记 `windows_or_ntfs` 并从 eligible candidates 中排除；目标发现脚本又进行第二道 `d["windows"]` / NTFS 拒绝。因此当前已写入 TF 卡的镜像不能通过正常菜单4登记这块目标盘。
- 判断：这是实现与项目需求不一致的过度排除，不是用户选错盘，也不是 SSD 故障。此前项目设计本来就应考虑目标盘存在 Windows；当前代码把“识别并警告 Windows 数据将被覆盖”错误实现为“永远不允许选择”。
- 用户的确认“这块就是迁移目标 SSD”只确认设备身份和目标用途，不等于允许现在立即清除 Windows。正式整盘覆盖仍须在菜单6之前通过所有门禁并再次明确授权。
- 不建议用 DiskPart clean、格式化、删除 Windows 分区、手工编辑 target-ssd.json 或其他命令绕过当前发现门禁。这些操作会提前破坏现有数据，且不能替代经测试的身份登记路径。
- 当前安全结论：当前 ISO 下没有受支持的正常菜单操作可以登记该 Windows SSD；应停止菜单4，不选择2/6，不关闭旧 VPS。
- 最小正确修复：目标发现阶段仍完整展示 Windows/NTFS 标记和将被覆盖警告，但允许用户在只读清单中明确选择这块非启动介质、非源盘、未挂载且身份唯一稳定的内部 SSD；要求额外强确认；登记过程不写扇区；保留正式克隆前重复身份校验、容量、挂载、源盘和启动介质排除门禁。新增正负向测试并经 GitHub 完整 CI 构建新 ISO。
- 如果用户必须今晚继续，优先评估一次极小的定向补丁和 GitHub 快速完整验收；不要在现场用未经测试的命令手工绕过。若时间不够，暂停真实迁移，不以破坏性清盘换取流程继续。


---

## 记录 0021：用户明确调整迁移方式为“清空目标盘、全新安装系统、再迁移 PAW 数据”（2026-11-18）

- 用户明确要求：现在格式化 Dell 内部目标 SSD、安装新的操作系统，然后把旧 VPS 上的 PAW 数据迁移进来。
- 这意味着用户当前意图不是将旧 VPS 的50GiB系统盘做块级整盘克隆到目标 SSD，而是改为“目标盘全新安装基础操作系统 + PAW业务/数据/配置迁移与恢复”。
- 用户要求的最终目标不变：Dell 成为 PAW 主服务器；旧腾讯云 VPS 保留为 paw-gateway / 美国网络出口；尽可能保持 GPT、Claude、Gemini MCP 路径和原有业务连续性。
- 之前项目 Master 和现有 PAW Live 菜单6按块级克隆设计；当前 `paw-target-discovery.sh` 排除 Windows/NTFS 的问题与“允许清空并重装”的新方案不再是核心阻断，但不得直接绕过安全门禁。
- 当前 PAW ISO 是 Debian Live 迁移工具，不应未经核实就当作 Ubuntu 安装器。新方案需要明确基础 OS 版本、安装方式、分区方案、PAW 业务/数据库/配置/凭据迁移清单、服务依赖、网络身份迁移和回退步骤。
- 旧 VPS 在快照完成、迁移窗口明确、用户授权前保持运行；不得现在进入 Rescue 或停止服务。
- 目标 SSD 格式化/安装系统将清除现有 Windows 数据。用户已表达清空目标盘的意图，但实际写盘前仍须在设备屏幕确认准确设备为 `HFS128G3BMND-3210A`，并确认没有需要保留的本地数据。
- 下一步应先重新设计并审核“干净 Ubuntu 安装 + PAW 应用/数据恢复”方案，明确它与旧整盘克隆方案的差异；不能继续沿用菜单6的块级克隆流程，也不能把 PAWDATA 初始化当成 SSD 安装步骤。
- 在新方案完成前，不选择当前菜单4尝试登记 Windows SSD，不选择菜单6，不格式化、不删除分区、不进入腾讯云 Rescue。


---

## 记录 0022：全新 Ubuntu Server 24.04 安装 + PAW 全量业务迁移实施方案（2026-11-18）

### 用户已确认的目标

- Dell OptiPlex 3020M Micro：i5-4670T、16GB RAM、Intel HD Graphics 4600、内部 HFS128G3BMND-3210A 标称约120GB SSD。
- 新系统：Ubuntu Server 24.04 LTS。
- 迁移范围：完整迁移 PAW 全部业务、数据库、配置、MCP 和自动化任务。
- 用户明确希望清空目标 SSD、全新安装操作系统，再迁移旧 VPS 上的 PAW 内容；不再把旧 VPS 50GiB 系统盘块级克隆作为目标方法。
- 最终角色不变：新 Dell 成为 PAW 主服务器；旧腾讯云 VPS 保留为 paw-gateway / 美国网络出口，保留 VLESS/Xray 和适当的 Tailscale Exit Node；Windows 通过 Tailscale SSH 管理新服务器；尽可能保持 GPT、Claude、Gemini Spark MCP 的原有URL和路径。

### 与现有 Master 的冲突

- 当前 `PAW-PROJECT-MASTER.md` 第2节仍写明“完整复制旧 Ubuntu 系统盘”，与用户本次明确确认的新方式冲突。
- 当前 PAW Live ISO 是 Debian Live 迁移工具，不是 Ubuntu Server 安装器。
- 下一轮应将“全新 Ubuntu 安装 + 应用/数据/配置迁移”更新为新的权威迁移方式，并将整盘克隆记录为已放弃的旧方案/历史验证。不要继续沿用 PAW Live 菜单6。
- 本次只记录用户决策与实施计划，不格式化 SSD、不安装系统、不访问或修改生产 VPS。

### 建议实施阶段

1. **生产 VPS 只读盘点（VPS保持运行）**
   - 清点 PAW 应用代码版本、目录、服务、systemd units/timers、cron、容器、数据库类型/版本/数据库列表/大小、持久化目录、MCP服务与URL路径、Nginx/反向代理、Tunnel/Funnel、COS、证书、用户/权限、环境变量、外部API和任务依赖。
   - 生成不含秘密的服务与数据清单。
   - 明确所有敏感凭据位置和恢复方式；不得把密钥、token、VLESS UUID、Tailscale state 或密码提交 GitHub 或粘贴到聊天。

2. **备份与可恢复性验证**
   - 在旧 VPS 正常运行时创建腾讯云系统盘快照并等待完成。
   - 对数据库执行适配数据库类型的一致性导出（例如 PostgreSQL pg_dump/pg_dumpall、MySQL/MariaDB mysqldump、SQLite一致性备份）；不要只依赖文件系统快照。
   - 对 PAW 持久化业务目录、MCP配置、服务配置、Nginx配置、脚本和自动化任务做清单化归档。
   - 凭据和私密配置加密备份，保存在与源VPS不同的安全位置；单独保存解密密钥。
   - 对所有备份生成SHA256，抽样/完整执行恢复演练，确认数据库可恢复、文件权限/属主可重建。
   - 备份未验证前不得清理旧 VPS 或开始切换。

3. **Dell 目标盘与硬件确认**
   - 用 Ubuntu 安装介质启动安装器前，再次确认内部目标盘为 `HFS128G3BMND-3210A`，读取精确容量、SMART和接口。
   - 明确目标 SSD 全部现有 Windows 数据将被清除；只在安装器显示正确型号/容量且用户再次确认后操作。
   - 当前旧PAW Live菜单4会排除Windows盘；新方案不再使用该菜单登记或菜单6克隆。
   - 先完成真实 Memtest、SSD健康、BIOS/UEFI、SATA和有线网卡检查；若硬件失败先处理。

4. **全新安装 Ubuntu Server 24.04 LTS**
   - 从 Ubuntu 官方渠道获取最新24.04 LTS point release ISO并核对SHA256。
   - 以Dell支持的UEFI启动方式优先安装；若实际固件/启动介质只能可靠Legacy启动，再按实机验证选择Legacy。安装模式、GPT和GRUB模式必须一致。
   - 安装器选择整块已确认的120GB内部SSD作为目标并使用整盘安装；不得选择32GB TF卡。
   - 使用ext4；不采用ZFS；不复制旧VPS的系统盘布局、machine-id、SSH host keys或tailscaled.state。
   - 设置独立管理员账号、主机名、时区、DHCP/有线网络、OpenSSH Server；安装完成后移除安装介质并确认本地SSD独立启动。
   - 完成系统更新、时间同步、磁盘/内存/温度/网卡基础检查。

5. **新服务器基础接入**
   - 安装独立Tailscale节点身份，加入现有Tailnet；不复制旧VPS的tailscaled.state。
   - 配置仅LAN/Tailscale可访问的SSH管理，不依赖公网IPv4或路由器端口映射。
   - Windows Codex通过Tailscale SSH管理新Dell。
   - 保持新机和旧VPS的machine-id、SSH host keys、Tailscale身份独立。

6. **恢复 PAW 应用与数据**
   - 根据盘点清单安装精确版本的运行环境和依赖，不从旧VPS整盘复制操作系统文件。
   - 从代码仓库/固定release部署PAW程序；从已验证备份恢复数据库和业务数据。
   - 恢复配置、systemd units、脚本、MCP服务、证书和自动化任务。
   - 恢复密钥时从加密备份/安全凭据源注入，不写入GitHub、普通日志或聊天。
   - 先保持业务写入、外部MCP入口、COS同步和定时任务关闭；逐项验证数据库连接、API、文件权限、服务健康和日志。

7. **MCP与网络路径切换**
   - 先只读审计生产实际URL、域名、端口、路径、认证、Tunnel/Funnel/Serve和后端依赖。
   - GPT独立Tunnel尽量保持原样，切换其origin到新Dell或通过稳定代理转发。
   - Claude和Gemini Spark原有Tailscale相关路径优先保留；如需改变，先做兼容转发，不让用户提前重新绑定。
   - 旧VPS继续保留Xray/VLESS和美国出口；新Dell以独立Tailscale身份加入Tailnet，可按需要使用旧VPS Exit Node。
   - 在切换前完成GPT、Claude、Gemini Spark实际客户端端到端测试；不把虚拟测试当成真实MCP验收。

8. **最终数据同步与业务切换**
   - 初始备份恢复后，安排短暂业务维护窗口。
   - 暂停旧VPS上会写入数据库/业务数据的任务，执行最终增量数据库导出和文件同步。
   - 将最终数据恢复到新Dell，校验记录数、关键文件哈希、应用状态。
   - 更新Tunnel/反向代理入口，逐个启用新机MCP和业务服务。
   - 新机业务验证通过后，旧VPS停止重复PAW业务写入和定时任务，仅保留gateway-only能力。
   - 避免新旧两台机器同时运行相同的轮询、自动化或数据库写入任务。

9. **旧 VPS 转为 paw-gateway 与观察**
   - 保留原VPS系统盘快照、数据库备份和回退资料。
   - 保留SSH管理、Xray/VLESS、所需Tailscale Exit Node。
   - 禁用重复PAW业务/MCP/COS轮询任务，但先导出原服务清单并记录回退命令。
   - 观察新机至少一个完整业务周期；确认自动化、MCP、数据库备份和重启恢复。
   - 若新机失败，暂停新机写入并按回退清单恢复旧VPS服务及原入口。

### 腾讯云 Rescue 决策

- 在“全新Ubuntu安装 + PAW应用/数据迁移”方案下，**正常情况下不需要把旧VPS关机并进入Rescue Mode**。
- 数据通过旧Ubuntu正常运行时的SSH、数据库一致性导出和文件同步迁移；旧VPS可继续提供Xray/VLESS/Exit Node，直到最终切换。
- 只有发现某些必须离线读取、且无法通过正常系统导出的数据时，才重新评估Rescue；不得默认进入Rescue。
- 旧VPS停机仅限最终一致性切换所需的短窗口，且必须在快照和备份验证完成后进行。

### 当前停止条件

- 不格式化Dell SSD，直到Ubuntu安装ISO、目标磁盘身份、备份和安装方案全部准备好，并在安装器中再次确认正确磁盘。
- 不选择旧PAW Live菜单6；它属于块级克隆旧流程，与新方案不兼容。
- 不进入腾讯云Rescue，不关闭或修改生产VPS。
- 不切换MCP/Tunnel/Funnel/DNS，不启动新机重复写入业务。
- 先完成生产VPS只读盘点和可恢复备份，再开始Dell安装。


---

## 记录 0023：用户再次确认优先使用现有 PAW 启动盘直接迁移（2026-11-18）

- 用户明确表示不希望继续开发/重做 ISO，希望直接使用已经制作的 PAW 启动盘完成迁移。
- 当前可用实体介质对应最新 Run #130（GitHub Run `43615851949`），Runtime SHA `02d02c79fa3035ad3089f474566ca917e5d2482a`，ISO SHA256 `71012766e4a23b540182c6952c244768d4a9c1c9c88a9e0e289d5d5ca6e6364c`。
- 同一 Runtime SHA 的 GitHub Run #18（`43618362793`）已完成 50GiB → 120GB（`target_bytes=120000000000`）QEMU完整虚拟链路，结论 success，SHA256/O_DIRECT、GPT/ext4扩容、自动重启和目标 Ubuntu 登录通过。
- 该 ISO 是 Debian Live PAW 迁移工具，支持原方案：从腾讯云 Rescue SSH 读取旧 Ubuntu 系统盘，完整克隆到 Dell 内部 SSD，离线适配 AHCI/GRUB/initramfs/网络并扩容。它不是 Ubuntu Server 安装器，也不执行“空白Ubuntu安装后仅恢复PAW应用”的新方案。
- 用户最新意图为直接使用现有启动盘完成整盘迁移；本记录将实施优先方向恢复为“现有 PAW Live + 腾讯云 Rescue + 50GiB整盘克隆”，此前记录0021/0022中的全新Ubuntu安装方案作为短暂讨论过的备选，不作为当前执行路径。若用户之后再次改变方案，需明确记录。
- 当前目标 SSD `/dev/sda` 型号 `HFS128G3BMND-3210A`，含 Windows/NTFS。当前 ISO 的 target discovery 明确排除 Windows/NTFS，故正常菜单4不能登记。若要继续当前ISO路径，必须先清除目标SSD现有分区表/Windows分区，再重启PAW重新扫描；不能在未确认设备型号、容量和路径前执行擦除命令。目标盘清空是不可逆的，必须在操作现场再次核对 `/dev/sda`、型号、精确字节容量和非启动介质身份。
- 不需要重新制作 ISO；但当前实体机实测目标 SSD、内存、PAWDATA、网卡和Rescue SSH仍需完成。GitHub 120GB虚拟链路 PASS不等于真实硬件 PASS。
- 正式步骤：PAWDATA PASS → 清空并重新扫描目标SSD → 菜单4登记目标SSD → Memtest至少一轮0错误并菜单1登记 → 菜单5硬件健康检查 → 菜单7确认状态 → 旧VPS运行时创建快照并只读记录源盘UUID/容量/分区 → 维护窗口正常关机并进入腾讯云Rescue → 菜单8选R → 菜单3配置Rescue SSH/host fingerprint/root UUID并只读识别源盘 → 复核源盘/目标盘/网络/备份 → 菜单6最终授权并开始真实整盘克隆。
- 用户尚未在本轮明确确认已清空SSD、已创建VPS快照、已授权进入Rescue或已授权菜单6真实克隆。禁止推定这些动作已获授权。


---

## 记录 0024：实体 PAW Live 当前状态与命令行登录失败（2026-11-18）

- 用户已完成 PAWDATA 首次初始化；PAW报告截图显示 `data: PASS`。
- 当前启动盘代码版本为 `02d02c79fa3035ad3089f474566ca917e5d2482a`（Run #130 ISO）。
- 目标盘 `/dev/sda`，型号 `HFS128G3BMND-3210A`，仍含 Windows/NTFS，因此被当前 `paw-identity.py inventory()` / `paw-target-discovery.sh` 排除；菜单4无法登记。
- 用户按 Ctrl+Alt+F2 进入 Debian tty 登录提示，尝试之前助手猜测的 `paw/live` 后显示 Authentication failure。该用户名/密码未经当前镜像证实，禁止继续猜测密码。
- 用户按 Ctrl+Alt+F1 已返回 PAW 中文主菜单；当前可继续安全查看菜单，但没有已证实的受支持菜单项能清除 Windows SSD。
- 当前菜单选项：1 Memtest登记、2 PAWDATA手动初始化/修复、3 Rescue SSH/源盘识别、4目标SSD登记、5硬件检查、6最终迁移、7报告、8网络阶段、0刷新。没有清盘/分区管理菜单。
- 不得将菜单2当作SSD清理；不得选择菜单6；不得在没有已验证root shell和设备身份复核的情况下提供 `wipefs`、`sgdisk`、`dd`、`parted` 等清盘命令。
- 下一步需先找到该ISO实际配置的合法管理Shell入口/凭据，或承认当前ISO不提供可用路径；在此之前让用户停留在PAW主菜单，不做磁盘写入。旧VPS保持运行，不进入Rescue。
- 此记录不代表SSD已清空、已登记或迁移已开始。


---

## 记录 0025：通过 systemd 临时 debug shell 进入 root 命令行（2026-11-18）

- 用户已回到 PAW Live 启动菜单；此前 Ctrl+Alt+F2 进入 tty2 登录提示，尝试未证实的 paw/live 凭据后 Authentication failure。不要继续猜密码。
- 当前 ISO 运行时代码：`02d02c79fa3035ad3089f474566ca917e5d2482a`，Debian 13 Trixie Live，systemd。
- 操作方案：启动菜单高亮 `Live system (amd64)`，按 Tab 编辑该项启动命令行，在现有内核参数末尾追加空格和 `systemd.debug_shell=1`，按 Enter 启动；PAW Live 启动后按 Ctrl+Alt+F9 进入 systemd debug shell。该临时 shell 预期为 root，无需 paw/live 登录。仅临时本地控制台使用，完成后正常重启且不再添加该参数，避免保留无密码 root shell。
- 首先只运行 `whoami` 与 `lsblk -b -o NAME,SIZE,MODEL,SERIAL,TRAN,RM,FSTYPE,MOUNTPOINTS`，确认当前用户为 root、内部目标盘仍为 HFS128G3BMND-3210A、启动介质为32GB Mass-Storage，且目标盘没有挂载。不要仅依赖旧的 /dev/sda 设备名。
- 用户已明确授权清空内部 HFS128G3BMND-3210A SSD 上全部现有 Windows 数据；但执行 wipe 前仍必须在当前启动会话重新核对型号、精确容量、序列号/WWN、启动介质父设备和挂载状态，确保不会清除 TF 启动盘。
- 清除后重新启动 PAW Live，菜单4登记 SSD；当前 target discovery 对 Windows/NTFS 的排除条件仍存在，清空分区表后才可能通过正常登记。
- 旧 VPS 继续正常运行，不关机、不进入 Rescue；本记录不授权菜单6或开始真实克隆。


---

## 记录 0026：Dell 实机出现 TF 启动介质 /dev/sdb 写入 I/O 错误（2026-11-18）

- 用户最新屏幕显示 PAW tty1 主菜单等待输入，同时内核日志报告：
  - `sd 4:0:0:0: [sdb] tag#0 FAILED Result: hostbyte=DID_OK`
  - `Sense Key: Not Ready`
  - `Additional Sense: Medium not present`
  - `I/O error, dev sdb, sector 52200160 op 0x1:(WRITE)`
- 之前现场盘点显示 `/dev/sdb` 为 32GB Mass-Storage TF 卡/USB读卡器；`/dev/sda` 为内部 SSD `HFS128G3BMND-3210A`。因此本次日志报错指向启动介质，不是内部 SSD。
- PAWDATA此前报告曾显示 PASS，但当前出现针对启动介质的写入 I/O 错误，持久化状态和日志写入可靠性不能继续假定正常。
- 立即停止任何菜单操作；不选择2、4、5、6，不清理内部SSD，不进入Rescue，不关闭旧VPS。
- 建议通过 Ctrl+Alt+Del 请求正常重启/关机；确认机器完全停止后，再重新插紧TF卡和读卡器，改插Dell后置主板USB口（不经过Hub），重新启动并观察是否再次出现相同 I/O 错误及 PAWDATA 状态。
- 若相同错误再次出现，停止实机迁移；不要继续依赖该TF卡保存事务状态。应更换/重新制作启动介质或排查读卡器/TF卡，但未经用户后续决定不自动重做ISO。
- 当前不提供任何SSD擦除命令。启动介质稳定、PAWDATA二次启动/持久化确认通过后，才继续处理内部SSD。


---

## 记录 0027：TF卡错误后重启恢复，PAWDATA再次显示PASS（2026-11-18）

- 用户重新启动后提供的最新照片显示 PAW 中文主菜单正常，状态行显示 `data=PASS`。
- 最新照片中未见此前 `/dev/sdb` 的 `Medium not present` / WRITE I/O error 行；这只能说明当前画面未显示该错误，不能证明介质已完成持久化写入稳定性测试。
- 当前菜单仍显示 `source=BLOCKED`、`target_identity=BLOCKED)、`hardware=BLOCKED`，属于尚未登记源/目标盘及未完成硬件检查。
- 下一步尝试 `Ctrl+Alt+F9) 进入临时 systemd debug shell；如果出现 root 提示符，先执行 `whoami` 和只读 `lsblk -b -o NAME,SIZE,MODEL,SERIAL,TRAN,RM,FSTYPE,MOUNTPOINTS`。
- 若 F9 无反应，返回 tty1，不猜测 paw/live 密码；需要确认本次启动是否实际添加 `systemd.debug_shell=1` 启动参数。
- 用户已明确授权清空内部 SSD HFS128G3BMND-3210A 上全部现有 Windows 数据，但清盘命令仍须在当前会话再次核对目标型号、精确容量、稳定身份、挂载状态以及 TF 启动盘设备，禁止仅凭旧设备编号操作。
- 旧 VPS 保持运行；不进入 Rescue；不执行菜单6。


---

## 记录 0028：Ctrl+Alt+F9 未打开 debug shell（2026-11-18）

- 用户在当前 PAW Live 主菜单按 Ctrl+Alt+F9 无反应。
- 只有在本次启动的内核命令行实际包含 `systemd.debug_shell=1` 时，systemd 才会启用 tty9 的 root debug shell；单纯在已经启动的系统里按 F9 不会开启它。
- 当前尚无现场证据确认该参数是否成功加入本次启动命令行，因此不能断言键盘或系统故障。
- 下一步应重新启动，从 USB 进入 Debian 启动菜单；高亮 `Live system (amd64)` 后按 Tab 编辑该启动项，在命令行末尾追加空格和 `systemd.debug_shell=1`，然后按 Enter 启动。不要在 PAW 主菜单里输入该字符串。
- 启动完成后再按 Ctrl+Alt+F9；若键盘 F 区需要 Fn，则按 Fn+Ctrl+Alt+F9。成功应出现 root shell 提示符。
- 若无法确认 Tab 编辑后的完整启动行，用户先拍照发来，不要盲目启动或输入清盘命令。
- 进入 shell 后只执行 `whoami` 和 `lsblk -b -o NAME,SIZE,MODEL,SERIAL,TRAN,RM,FSTYPE,MOUNTPOINTS` 进行只读核对；未核对当前设备身份和挂载状态前，不提供擦除命令。


---

## 记录 0029：Memtest人工登记末尾中文确认无法在US文本控制台输入（2026-11-18）

- 用户在 PAW 主菜单的 Memtest 人工结果登记流程遇到最后确认提示，要求输入中文 `确认`；用户只有普通 USB 键盘，当前 Live 使用 US 键盘布局且无中文输入法。
- 已从当前运行时代码 `02d02c79fa3035ad3089f474566ca917e5d2482a` 重新读取 `scripts/paw-memtest-confirm.sh)：脚本严格判断 `[[ "$confirmed" != '确认' ]]`，因此 `confirm`、`queren` 等 ASCII 替代值都会被拒绝。
- 不要指导用户输入英文替代，不要伪造/手工写入 `memtest-attestation.json`，不要绕过 Memtest人工观察确认。
- 当前提示处先不要输入；可等待300秒安全超时，或按 Ctrl+C 中止子流程并返回菜单（若返回失败则拍照）；该次不会登记 Memtest 结果。
- 这是现场可用性缺陷。后续最小修复应接受明确 ASCII token（例如 `CONFIRM`）并保留原有状态/轮次/错误数检查，新增实际 tty 正向/负向测试；但用户当前不希望重新制作 ISO，因此本轮不要求其重做镜像。若要继续当前镜像，只能找到已验证的本地输入法/键盘 Unicode 输入方式，否则暂缓该人工登记步骤，不能假报 PASS。
- 当前用户可继续做的非破坏性工作须遵守现有菜单依赖；Memtest人工登记未完成时硬件/迁移状态保持 BLOCKED，不选择菜单6，不关闭旧VPS、不进入Rescue。


---

## 记录 0030：用户询问跳过 Memtest 登记直接迁移（2026-11-18）

- 用户当前希望跳过 Memtest 人工登记，不再输入中文“确认”，并直接进行真实迁移。
- 已核对运行时代码 `02d02c79fa3035ad3089f474566ca917e5d2482a`：
  - `paw-memtest-confirm.sh` 的选项3会记录 `WARN`，不是通过；选项1只有用户确实观察到至少一整轮且错误数为0时才能记录 `OPERATOR_CONFIRMED)。
  - `paw-memory-test-report.sh` 未发现有效人工登记时生成 `WARN`；`FAIL` 或 `WARN` 不会变成通过。
  - `paw-hardware-preflight.sh` 对 Memtest 状态不是 `OPERATOR_CONFIRMED/PASS` 时将硬件状态置为 `WARN`。
  - `paw-live-controller.sh` 只有目标身份与硬件报告均为 `PASS` 才能形成可继续状态。
  - `paw-final-confirm.sh` 明确要求当前启动的硬件报告与 Memtest 状态为 `OPERATOR_CONFIRMED` 或 `PASS`，否则拒绝最终授权。
- 结论：当前ISO没有支持“跳过Memtest登记但继续菜单6”的选项。取消/跳过登记可以退出当前子流程，但迁移会保持 BLOCKED；选择选项3也会记录 WARN 并阻断。不得手工伪造报告或修改状态文件绕过门禁。
- 若用户不愿做 Memtest 或无法输入中文确认，当前可以停止本轮真实迁移；也可以完成其他只读检查，但菜单6仍不可用。恢复迁移需完成真实 Memtest 至少一轮、0错误，并解决中文确认输入；不允许把未测结果标为通过。
- 当前旧VPS保持运行，不进入Rescue；目标SSD不得开始克隆。


---

## 记录 0031：Memtest已完成1轮0错误；通过临时TTY键位映射输入中文确认（2026-11-18）

- 用户实际观察并报告：Memtest86+ 完成 1 个完整 Pass，Errors=0。
- 允许将真实观察结果登记为 `OPERATOR_CONFIRMED`；这不是伪造测试结果，也不代表机器自动证明。
- 当前 `paw-memtest-confirm.sh` 最后一步严格要求中文字符串 `确认`，US Linux VT 文本控制台无法直接输入中文。
- 可临时使用 Linux `loadkeys` 键盘映射把 F11/F12 的无修饰键映射成对应 UTF-8 字符，再在 PAW 的 tty1 确认提示处依次按 F11、F12。
- 字符编码：`确` U+786E UTF-8 octal `\347\241\256`；`认` U+8BA4 UTF-8 octal `\350\256\244`。
- 临时 keymap 仅修改当前 Live 启动会话的内核键盘映射；使用 `plain keycode` 仅改无修饰键，保留 Ctrl+Alt+Fn 的虚拟终端切换组合。Linux kbd keymap 文档支持 `U+` Unicode keysym、F100 string action 和 plain modifier-specific definitions。
- root debug shell 如未启用，需再次通过启动项 Tab 在内核参数末尾追加 `systemd.debug_shell=1`，启动后 Ctrl+Alt+F9 进入 root shell。
- 先以 `loadkeys -p -u -` 对以下 map 做语法解析，再执行 `loadkeys -u -) 实际加载：
  ```
  keymaps 0-15
  plain keycode 87 = F100
  plain keycode 88 = F101
  string F100 = "\347\241\256"
  string F101 = "\350\256\244"
  ```
- 返回 tty1 后执行菜单1登记：选1、输入passes=1、errors=0；最后提示中文确认时，依次按 F11、F12、Enter。确认后可回到 debug shell 执行 `loadkeys -d` 恢复默认键盘映射，或直接重启恢复。
- 不得把该输入方法用于虚构 Memtest 结果；本次仅因用户已实际报告1轮、0错误而登记。
- 登记后执行菜单5硬件检查，菜单7查看状态；旧VPS仍保持运行，不进入Rescue，直到目标硬件与其它准备门禁完成。


---

## 记录 0032：Dell 实机完成 Memtest 登记、目标 SSD 登记及硬盘检查（2026-11-18）

- 记录性质：用户现场报告 + 当前 PAW 主菜单照片核对；本记录不声称助手远程读取了 PAW 设备上的报告文件。
- 用户报告：真实 Memtest86+ 已完成至少 1 个完整 Pass、Errors=0，且菜单 1 人工登记已完成；目标 SSD 已完成菜单 4 登记；菜单 5 硬盘检查已完成，用户现场观察未见 SSD 介质异常；用户确认当前 TF/读卡介质可正常使用。
- 照片中 PAW readiness 的可见状态：总体 `BLOCKED`；`data=PASS`、`source=BLOCKED`、`target_identity=PASS`、`hardware=WARN`、`network=BLOCKED`。
- 照片可见目标盘：`/dev/sda`，型号 `HFS128G3BMND-3210A`，精确容量 `128035676160` bytes。稳定身份依据显示为 `serial+wwn+model+exact_capacity+by-id+sysfs+partition`。目标身份登记和本次总控身份复核为 PASS；设备路径仅作为定位符，不作为唯一身份。
- PAWDATA 当前报告为 PASS。之前记录 0026 的 TF/读卡器写入 I/O 错误保留为历史事件；本次照片没有显示该错误，用户报告当前介质正常，但不能据此改写历史或声称已找到旧错误根因。
- `hardware=WARN` 尚未关闭。菜单 5 的整体健康状态除 SSD SMART/只读扫描外，还包含存储内核错误、温度传感器读数和 Memtest 当前启动/目标身份绑定。仅凭用户报告硬盘检查完成，不能把整个 hardware 状态提升为 PASS。需读取当前会话的 `paw-hardware-health-report.json`、`memory-test.json`、`smart-sda.json`、`storage-kernel-errors.txt`、`hardware-sensors.txt`，定位 WARN 的真实来源；不得手改报告或绕过门禁。
- `source=BLOCKED` 的代码条件是当前启动会话尚无通过固定 SSH 主机指纹的 Rescue 源盘发现记录；需要完成 Rescue endpoint/host-key pinning、一次性 SSH 公钥配置、输入旧 VPS 根分区 UUID，并对远端磁盘容量、GPT、BIOS Boot、ext4 根分区布局和无读写挂载进行只读核验。
- 当前代码将 `network` 状态直接映射为 `source` 状态（`network_status="$source_status"`）。因此本次 `network=BLOCKED` 不能单独解释为家庭宽带不通；源盘 Rescue SSH 尚未通过是当前 readiness 网络门禁显示 BLOCKED 的直接原因。实际外网/DNS/NTP报告仍需单独检查。
- 照片中报告时间显示为 `2026-04-13`，与本记录日期 `2026-11-18` 不一致。需核实 Live 系统时间/NTP；在时间未确认前，不把基于时间的网络/TLS检查视为已通过。
- 下一步顺序：先只读查看当前硬件 WARN 报告并定位原因；保持本次 Live 启动会话，不要贸然重启，以免使绑定当前 `boot_id` 的 Memtest 人工登记失效；硬件状态达到 PASS 后，再在旧 VPS 正常运行时完成快照和可恢复备份，随后由用户安排维护窗口进入 Tencent Rescue，菜单 8 选择 R、菜单 3 完成 Rescue SSH 和源盘只读身份识别。
- 当前禁止：菜单 6、真实克隆、目标 SSD 写入、旧 VPS 关机/重启/进入 Rescue、生产 PAW/MCP/Tailscale/Xray/Tunnel/Funnel 配置变更。以上仍需相应明确授权。
- 本记录不代表源盘已识别、Rescue SSH 已通过、迁移已开始或业务已切换。



---

## 记录 0033：用户要求在单机、单启动介质和键盘限时条件下优先完成今晚迁移（2026-11-18 22:30 Asia/Shanghai）

- 用户明确说明：不再构建或重做 ISO；当前只有正在迁移的 Dell 服务器、手机和这一张 PAW 启动介质；USB 键盘仅能使用到今晚结束；希望今晚完成迁移。
- 执行决策：继续使用实体 TF 卡上现有 Run #130 ISO（运行时代码 `02d02c79fa3035ad3089f474566ca917e5d2482a`），不改运行时代码、不要求第二台电脑、不要求重新写卡、不新增测试性工作。
- 本次 GitHub 实时核对：工作分支 `vm/ds-final-prehardware-remediation-20261112`；分支 HEAD（本记录追加前）`8d2055448ebeaad518883405817898ba6e3cfcf9`；最新完整 CI Run #130（`43615851949`）成功；同一运行时代码的 50GiB→120GB QEMU 完整链路 Run #18（`43618362793`）成功。两项均为 2026-11-14 的历史 CI 证据，不代表当前实机和生产网络已通过。
- 当前实机状态以记录 0032 和用户照片为准：PAWDATA PASS、目标 SSD 身份 PASS、Memtest 人工登记已完成、用户报告硬盘检查完成；source BLOCKED、hardware WARN、network BLOCKED。尚无证据证明 Rescue SSH、旧 VPS 源盘身份、真实克隆、目标系统首次启动或 MCP/Codex 接管已完成。
- 由于 Memtest 人工登记绑定当前 `boot_id`，优先保留当前 Live 启动会话；在没有必要前不重启。若本次启动参数仍含 `systemd.debug_shell=1`，优先通过 Ctrl+Alt+F9 进入现有 root debug shell，只读查看硬件报告与系统时间；不清空日志、不手改报告、不绕过 WARN。
- 计划并行使用手机处理腾讯云控制台：先创建旧 VPS 系统盘快照并确认完成；快照属于回退点，不等同于数据库一致性导出。不得在快照完成前关机或进入 Rescue。
- Hardware WARN 必须先从 `paw-hardware-health-report.json`、`memory-test.json`、`smart-sda.json`、`storage-kernel-errors.txt`、`hardware-sensors.txt` 定位原因。若仅为传感器模块未加载，可在当前 Live 会话评估加载 `coretemp` 后再按需复检；若存在当前 I/O 错误或 SSD SMART/扫描异常，必须停止克隆。
- 若硬件警告可安全解除，再安排旧 VPS 进入 Rescue；菜单 8 选 R，菜单 3 生成一次性 SSH key、由用户通过手机/Rescue VNC 配置公钥并核对 SSH host fingerprint，再输入旧 VPS 根分区 UUID，执行远端容量/GPT/BIOS Boot/ext4/只读挂载核验。任何 UUID、主机指纹或磁盘布局不匹配都必须停止。
- 只有 readiness 全部达到 PASS、快照/回退点已确认、用户在现场再次核对源盘与目标盘后，才允许用户明确授权菜单 6。菜单 6 会覆盖整个目标 SSD，并执行流式克隆、独立 SHA256、离线修复、GPT/ext4 扩容和自动重启；不能跳过其中任一校验。
- QEMU Run #18 耗时 3h23m49s，但这不是实网速度或实际迁移耗时预测。真实源盘压缩率、家宽上行/下行、Rescue SSH 吞吐和 SSD 写入速度未知；截至本记录时间 22:30，无法承诺在键盘归还前安全完成整个真实迁移。
- 即使今晚完成块级克隆和首次启动，也不能仅凭此宣称 Windows Codex SSH、GPT/Claude/Gemini Spark MCP、Tailscale Exit Node 和旧 VPS gateway-only 全部完成。用户当前没有第二台 Windows 电脑，Codex Windows 端到端验收需后续在该电脑可用时完成；手机可作为临时 SSH/Tailscale 管理端，但不能代替 Windows Codex 验收。
- 安全底线：不为赶今晚而跳过快照、源盘只读身份核验、目标盘身份复核、独立 SHA256、离线修复或扩容检查；不修改/删除旧 VPS 数据，不停用旧 VPS gateway，不在未验收新系统前进行 MCP/Tunnel/Funnel/DNS 切换。若时间不足，保留旧 VPS 可启动和可回退状态，明确记录未完成项，不误报迁移完成。



---

## 记录 0034：现场操作改为单行命令、逐步确认（2026-11-18）

- 用户说明只能在 PAW 现场手动逐字输入命令，不熟悉代码，也不知道如何在控制台中输入换行；此前提供的多行 Shell 检查块不适合现场使用。
- 后续指导约束：每轮最多给一条简短、单行命令；不要求用户粘贴多行脚本、不要求用户自行编辑文件或理解代码；明确说明输入位置、按 Enter 执行、拍照反馈。根据真实输出再决定下一条命令。
- 优先使用 PAW 已有菜单和报告，不重复要求用户运行已完成的 Memtest/SSD 检查；只做必要的只读诊断，任何真实磁盘写入、Rescue/生产变更仍需明确授权。
- 当前尚未确认用户现场是否处于 root debug shell 或 PAW 菜单；发出命令前先确认当前屏幕状态，避免让用户在菜单提示符误输入 Shell 命令。


---

## 记录 0035：实机硬件健康报告现已 PASS（2026-11-18）

- 用户通过当前 root debug shell 手动执行只读命令 `cat /var/lib/paw-migration/reports/paw-hardware-health-report.json` 并上传屏幕照片。
- 照片明确显示报告 `status=PASS`，`reason=All currently supported checks passed`；目标设备为 `/dev/sda`，精确容量 `128035676160` bytes，稳定身份依据为 `serial+wwn+model+exact_capacity+by-id+sysfs+partition`。
- 同一报告明确显示 `memory_status=OPERATOR_CONFIRMED`、`memory_trust=operator_attestation_not_cryptographic`。Memtest 已按人工观察登记；未将人工确认夸大为机器证明。
- 报告中的 `boot_id` 与此前登记绑定的启动会话相同（截图可见）；本轮不要求重启，以保留现有会话状态。
- 报告 `generated_at=2026-04-13T19:59:45Z`，与当前日期不一致。当前系统时间/NTP 仍待核实。不要因为报告时间旧就修改报告；应先只读运行 `date -u` 检查实时系统时钟。
- 因此，记录 0032 中的 `hardware=WARN` 已被本次更新的硬件报告 `PASS` 取代；但完整 readiness 仍可能因 `source=BLOCKED` 而为 BLOCKED，须在时间核实后刷新总控状态。不得把硬件 PASS 等同于源盘/网络/迁移已通过。
- 用户现场为 `root@localhost:/#` 命令行。后续每轮只提供一条简短单行命令，明确只读/写入属性，并等待照片确认。


---

## 记录 0036：确认 Live 系统时钟未同步且 RTC 严重落后（2026-11-18）

- 用户在 root debug shell 执行 `date -u`，结果：`Mon Apr 13 20:57:16 UTC 2026`。
- 随后执行 `timedatectl status`，照片显示：
  - Local time / Universal time：`Mon 2026-04-13 21:00:59 UTC`（命令执行间隔导致数分钟差异）
  - RTC time：`Tue 2019-05-21 06:16:40`
  - Time zone：`Etc/UTC`
  - `System clock synchronized: no`
  - `NTP service: active`
  - `RTC in local TZ: no`
- 结论：NTP 服务已启动，但系统时钟并未完成同步；主板 RTC 约停留在 2019 年。当前不能把 NTP active 误判为时间已校准，也不能据此认定外网已连通或断开。
- 不要手动修改系统时间或 RTC，不要关闭/重启 systemd-timesyncd，不要重启 Live 系统；先只读执行 `timedatectl timesync-status`，查看实际选中的 NTP 服务器、轮询和同步状态，再根据输出逐步诊断网络/DNS。
- 系统时钟修复前，TLS/HTTPS、证书有效期、Rescue SSH host-key/时间戳检查可能受影响；旧 VPS 仍保持运行，尚未进入 Rescue，未开始克隆。
- 当前用户只能手动输入单行命令；每轮只给一条短命令并等待照片。保持当前 boot_id，保护已登记的 Memtest 人工确认。



---

## 记录 0037：NTP 状态显示尚未收到任何时间同步数据包（2026-11-18）

- 用户在当前 root debug shell 执行 `timedatectl timesync-status` 并上传照片。
- 输出为：`Server: n/a (1.debian.pool.ntp.org)`、`Poll interval: 0 (min: 32s; max: 34min 8s)`、`Packet count: 0`。
- 结论：systemd-timesyncd 已配置 Debian NTP pool，但当前没有成功收到 NTP 数据包；不能仅凭 `NTP service: active` 认为已连通或同步。根因尚未确定，可能涉及有线链路未获得地址、默认路由、DNS 或 UDP/123 出站访问。
- 下一步只读检查网络接口及地址：`ip -br address`。根据结果再检查默认路由和 DNS；不要手动改系统时间/RTC，不要重启服务或 Live 系统。
- 用户仅能手动输入单行命令，后续每轮最多给一条短命令并等待照片。旧 VPS 仍未进入 Rescue，真实克隆尚未开始。



---

## 记录 0038：有线网卡已 UP 并获得家庭路由器 IPv4 地址（2026-11-18）

- 用户在当前 root debug shell 执行 `ip -br address` 并上传照片。
- 可见输出：`enp2s0 UP 192.168.3.50/24`，并有 IPv6 link-local 地址；`wlp3s0 DOWN`；`tailscale0 UNKNOWN`，仅显示 link-local IPv6。
- 结论：有线网卡链路已 UP，DHCP 已成功分配 IPv4 地址 `192.168.3.50/24`。这证明本机到局域网的基础连接建立，但不证明默认路由、DNS、互联网访问或 NTP UDP/123 可用。
- 下一步只读检查默认路由：`ip route show default`。如果有 default via 路由，再分别检查 DNS 和公网 HTTPS；如果没有默认路由，再检查 DHCP/路由器配置。不要修改网络配置或重启 Live。
- 系统时钟仍未同步（`2026-04-13`），NTP `Packet count=0`；主板 RTC 显示 2019 年。保持当前 boot_id，不手动设置时间或 RTC。
- 用户只能手动输入一行命令；后续每轮只给一条短命令并等待照片。



---

## 记录 0039：默认路由表为空，Live DHCP 网络配置已核对（2026-11-18）

- 用户在 root debug shell 正确执行 `ip route show default`；命令无输出，确认当前内核路由表没有 IPv4 默认路由。此前一次 `riute` 拼写错误已由后续正确执行排除。
- 当前有线接口 `enp2s0` 为 UP，获得 DHCP IPv4 地址 `192.168.3.50/24`；无线接口 `wlp3s0` 为 DOWN；`tailscale0` 尚未建立。
- 已核对当前运行时代码 `02d02c79fa3035ad3089f474566ca917e5d2482a` 的 `boot/20-wired.network`：`[Match] Name=en* eth*`，`[Network] DHCP=yes`、`IPv6AcceptRA=yes`。构建脚本会将其安装到 `/etc/systemd/network/20-wired.network`，并启用 systemd-networkd、systemd-resolved、networkd-wait-online。网络配置本身请求 DHCP，不是静态配置。
- 结论：DHCP 已为网卡分配地址，但当前未出现默认路由。需要进一步读取 systemd-networkd 对 `enp2s0` 的 DHCP 状态、DHCP server 和 Gateway 信息；不猜测家庭路由器网关地址，不直接添加默认路由。
- NTP 状态仍为 Server n/a、Packet count 0；系统时间 2026-04-13，未同步；RTC 为 2019-05-21。默认路由缺失是目前外网不可达的直接可疑原因，但仍需确认 DHCP 网关字段。
- 下一步只读命令：`networkctl status --no-pager enp2s0`。不要更改网络配置、添加静态路由、手动改时钟或重启 Live。
- 用户只能手动逐字输入单行命令；每轮只给一条简短命令并等待照片。



---

## 记录 0040：networkctl 确认 Realtek 网卡驱动及 IPv6 网关（2026-11-18）

- 用户在 root debug shell 执行 `networkctl status --no-pager enp2s0` 并上传照片。
- 实机网卡信息：`enp2s0`，驱动 `r8169`，Realtek RTL8111/8168/8211/8411 PCI Express Gigabit Ethernet Controller，硬件地址 `64:00:6a:3c:57:d6`，Speed 1Gbps、Duplex full、Link UP。
- DHCPv4 地址：`192.168.3.50/24`，networkctl 显示 DHCPv4 via `192.168.3.1`（该字段表示 DHCPv4 服务器/租约来源，不能仅凭此当作已安装 IPv4 默认路由）。
- networkctl 显示 IPv6 地址，Gateway 为 `fe80::e277:26ff:fea7:18d`，DNS 也指向该 IPv6 link-local 地址；State 为 `routable (configuring)`，Online state 为 `online`。
- 日志重复出现 `Could not acquire DHCPv6 lease on NDisc request: Address already in use`，随后接口重新配置；当前配置文件为 `/etc/systemd/network/20-wired.network`。该 DHCPv6 提示可能与 IPv6 DHCP/NDisc 重试有关，但目前不能断定它是 NTP 失败的根因。
- 与先前 `ip route show default` 无输出并不矛盾：该命令查看 IPv4 路由；networkctl 所列 Gateway 是 IPv6 link-local 网关。尚未查看 IPv6 路由表，也尚未证明 IPv4 默认路由存在。
- 已确认真实 Dell 有线网卡型号和驱动绑定，说明本次 ISO 的 Realtek 驱动覆盖在该设备上至少已绑定成功；仍需确认固件加载/外网连通，不把 Link UP 当成互联网可用。
- 下一步只读命令：`ip -6 route show default`，确认 IPv6 默认路由是否实际安装。不要手动添加路由、修改 DHCP/IPv6 配置或重启网络服务。
- NTP 仍为 Packet count 0，系统时钟未同步；保持当前 Live boot_id 和 Memtest 登记。用户只能手动输入一行命令，每轮只给一条短命令。



---

## 记录 0041：IPv6 默认路由表同样为空（2026-11-18）

- 用户在 root debug shell 执行 `ip -6 route show default` 并上传照片；命令返回 shell 提示符，没有任何路由输出。
- 因此当前没有安装 IPv6 默认路由。此前 `networkctl status` 显示的 `Gateway: fe80::e277:26ff:fea7:18d` 不能替代内核实际路由表证据。
- 当前确认：Realtek `enp2s0` Link UP、驱动 `r8169`、1Gbps/full duplex；IPv4 `192.168.3.50/24` 已分配；IPv4 和 IPv6 默认路由查询均无输出；NTP Packet count=0、系统时钟未同步。
- networkctl 记录 DHCPv4 地址来源为 `192.168.3.1`，但尚未确认 DHCP 租约是否包含 Router option。下一步只读查看 networkd 当前租约：`cat /run/systemd/netif/leases/2`（networkctl 将 enp2s0 标为 ifindex 2）。重点查看 `ROUTER=`、`SERVER_ADDRESS=`、`DNS=` 等字段。
- 不要猜测并手动添加默认路由；先确认 DHCP 租约是否包含路由器选项。不要修改配置或重启网络服务。
- 用户只能手动输入单行命令；每轮只给一条短命令并等待照片。



---

## 记录 0042：退出并重新进入 Tencent Rescue 后的一次性 SSH 公钥处理（2026-11-19）

- 代码核对范围：当前远程分支 `vm/ds-final-prehardware-remediation-20261112`，HEAD `2d66603ffca87234460feb237ee1a9245457dff9`；运行时代码仍为 `02d02c79fa3035ad3089f474566ca917e5d2482a`。
- `scripts/paw-rescue-key-prepare.sh` 将 Rescue endpoint、Ed25519 私钥 `/run/paw-network/rescue_ed25519`、公钥 `/run/paw-network/rescue_ed25519.pub` 和 pinned `known_hosts` 存在 `/run/paw-network`；脚本明确要求 `/run` 为 tmpfs。因此这些客户端凭据只在本次 PAW Live 启动会话的 RAM 中存在，PAW Live 重启/断电后会丢失。
- Tencent Rescue 侧使用临时 `authorized_keys`。退出 Rescue 并恢复普通 Ubuntu 后，再次进入 Rescue 属于新的 Rescue 会话；不能假设前一次写入的临时授权仍存在。重新进入后需要把当前 PAW Live 会话对应的公钥再次加入新 Rescue 会话的临时 `authorized_keys`。
- 若 Dell 上的 PAW Live 自上次菜单6退出后一直未重启，`/run/paw-network/rescue_ed25519.pub` 理论上仍是原公钥，可重新添加同一公钥；若 PAW Live 已重启，旧私钥/公钥已随 tmpfs 清空，必须由新 Live 会话生成新密钥并添加新公钥。
- 重新进入 Rescue 时还必须核对当前 Rescue VNC 显示的 SSH 主机指纹。不能因为公钥相同就信任旧 host key；脚本启用了 `StrictHostKeyChecking=yes`。
- 发现当前菜单3有一个重要的重复进入限制：它先调用 `paw-rescue-key-prepare.sh` 再调用 `paw-source-discovery.sh`；若本次 PAW Live 的旧密钥文件仍存在，key-prepare 会拒绝生成并不会重新显示公钥（但菜单会继续尝试 source-discovery）。因此在确认 PAW Live 是否重启、现有 key 是否仍在、Rescue endpoint/host key 是否变化前，不要盲目重复菜单3，也不要手工删除私钥/known_hosts 或绕过主机指纹门禁。
- `paw-final-confirm.sh` 在最终授权前会再次调用 `paw-source-discovery.sh`，重新通过固定 host key 的 SSH 读取源盘并比对 source UUID、容量、组合身份和 host fingerprint；所以即使五项 readiness 曾全部 PASS，退出 Rescue 后仍需重新建立临时 SSH 授权并完成源盘复核，才能继续菜单6。
- 下一步先确认 Dell PAW Live 自菜单6停止后是否重启/断电。若未重启，先只读检查当前公钥文件是否仍在；若已重启，则按新 Live 会话生成新 key。随后重新进入 Tencent Rescue、重新写入对应公钥，并核对新 Rescue host fingerprint。真实 SSD 写入前仍须检查迁移事务和 `CLONE-INCOMPLETE`，不得直接重复菜单6。

