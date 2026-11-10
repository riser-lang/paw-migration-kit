# PAW Migration Kit v2.7 交付包

交付更新时间：2026-11-10 UTC（第二轮接管）
分支：`fix/v2.6.2-final-readiness`
代码 HEAD（本次 ISO 与全部测试证据对应）：`bf1a705`
文档 HEAD（仅文档，无代码/ISO 变化）：`bf1a705` 之后的文档提交
PR #2：<https://github.com/riser-lang/paw-migration-kit/pull/2>（Draft，未合并）
PR #1：<https://github.com/riser-lang/paw-migration-kit/pull/1>（Draft，未改动）

## 1. 最终构建

- Actions Run：<https://github.com/riser-lang/paw-migration-kit/actions/runs/42804949796>
- 结论：success（全部步骤通过，含 5 例 QEMU 中文用例）
- 最新全绿验证运行：`42873432670`（HEAD `ac0813e`，仅改 CI/工作流与交付自检脚本；ISO 载荷与交付件相同）
- Artifact ID：`13760370816`
- Artifact 名称：`paw-live-build-test-results`
- Artifact 大小：1,030,665,391 bytes
- 过期时间：2026-11-13 11:27:18 UTC（保留 3 天）
- 下载入口：打开 Actions Run 页面，在页面底部 Artifacts 区域下载；GitHub 需要
  登录且有仓库读权限。若 `gh run download` 长时间无进度，改用 API + 显式代理
  `curl` 直取 artifact zip。

## 2. ISO

- 文件：`paw-live-amd64.iso`
- 字节数：`953,155,584`
- SHA256：
  `d9fe28799f9c18d1ec69900b66ea0c71d70b232c5e62a0c4ab0e902fb95a4476`
- 校验文件副本：Artifact 内 `paw-live-amd64.iso.sha256`、构建日志中的
  `artifacts/iso-identity.txt`（字节数 + SHA256，不必先下载 1 GB）、以及
  `reports/evidence-v2.7/iso-identity-run-42804949796.txt`
- 分区结构：`MBR isohybrid cyl-align-on GPT APM`，Legacy BIOS 可启动，
  含 Memtest86+ 独立 ISOLINUX 菜单项

### 2.1 已完成的独立复核

本轮四次构建的 ISO 都在工作站上实际下载并重算哈希：

- Run `42804949796`（交付件）：Artifact `13760370816` 下载 1,030,665,391 bytes，
  解压后 `Get-FileHash -Algorithm SHA256` =
  `d9fe28799f9c18d1ec69900b66ea0c71d70b232c5e62a0c4ab0e902fb95a4476`，
  与 Artifact 内 `paw-live-amd64.iso.sha256` **完全一致**；ISO `953,155,584` bytes。
- Run `42795953493`：Artifact `13754343439` 下载并复核，
  `17789c0444d6f8bac0ef24aa7d6a68871e1dfedb2d7b3fe0c50355288a6e0363` 与侧车一致。
- Run `42747871471`：Artifact `13731684896` 同样下载并复核，
  `2295eb0a8d9d61b93be3e91cfeee735c42529ed3223cbf14593047104939336d` 与侧车一致。

下载方式说明：`gh run download` 在该网络下 20 分钟无字节写入（疑似代理），改用
GitHub API artifact zip 端点 + `curl --proxy` 后完成。

注意：ISO 构建**不是字节级可复现**。四次构建的 ISO 字节数同为 `953,155,584`，
但 SHA256 各不相同（`2295eb0a…` / `17789c04…` / `2edf88a0…` / `d9fe2879…`）。
核对哈希时必须使用**同一 Run** 的侧车文件，不能跨 Run 比较。

下载后在 Windows 重新计算并核对（务必对上表或同一 Run 的侧车）：

```powershell
Get-FileHash .\paw-live-amd64.iso -Algorithm SHA256
```

## 3. 交付内容

- Debian Live ISO（Hybrid MBR/GPT、Legacy BIOS、Memtest86+ 独立菜单）。
- 中文 PAW 控制台菜单：内存确认、PAWDATA、Rescue 源盘、目标 SSD、硬件、最终授权。
- 操作员面板统一绑定已验证的 tty1（带 300 秒超时与 ASCII 屏幕标记）。
- PAWDATA 自动引导与持久化。
- Rescue 组合身份识别。
- 远端 zstd + SSH + 本地解压 + 实际字节计数。
- 独立 SHA256、离线修复、GPT/ext4 扩容、首次启动检查。
- 用户说明：`docs/PAW-V2.7.1-USER-GUIDE-ZH.md`、`docs/PAW-V2.7-USER-GUIDE-ZH.md`
- 回滚说明：`docs/PAW-V2.7-ROLLBACK-ZH.md`
- 实机验证清单：`docs/PAW-V2.7-HARDWARE-CHECKLIST-ZH.md`（7 项，含每步预期屏幕文字与失败处置）
- 单页入口：`docs/PAW-START-HERE-ZH.md`（先看这个：第 0 步核对哈希、前 3 件事、三条硬规矩）
- 交付包自检：`scripts/verify-delivery.ps1` + `SHA256SUMS.txt`（Windows PowerShell 5.1 可跑，本机已通过 23 项检查，并做过篡改反向验证：改一个文件即 FAIL / exit 1）
- 写卡图示：`TF-CARD-RUFUS-GUIDE.md`
- 离线速查卡：`PAW-QUICK-CARD-ZH.html`（单文件、图片内嵌、无外部引用，可在手机或另一台电脑上离线打开；由 `scripts/build-offline-guide.py` 生成，本机校验 `OFFLINE_GUIDE=PASS`）
- 现场对照：`PAW-SCREEN-EXPECTATIONS-ZH.md` + `screens/`（5 张 CI 真实渲染的截屏，用来看屏幕上应该出现什么）
- 接管报告：`reports/PAW-V2.7-TAKEOVER.md`
- P0 实现记录：`reports/PAW-V2.7-P0-IMPLEMENTATION.md`
- 最终证据（上一轮）：`reports/PAW-V2.7-FINAL-EVIDENCE.md`
- 测试报告：`docs/PAW-V2.7.1-TEST-REPORT.md`（第 7 节为 Run `42804949796` 实际计数）
- 阻断清单：`PAW-MIGRATION-BLOCKERS.md`、`docs/PAW-V2.7.1-BLOCKERS.md`
- 软件清单：`software-packages.txt`、`software-packages.lock`、`software-manifest.txt`
- 构建来源：`build-provenance.txt`
- 公开安全审计：`reports/PAW-PUBLIC-SECURITY-AUDIT.md`

## 4. 验证状态矩阵

| 层级 | 状态 | 证据 |
|---|---|---|
| 云端构建 | PASS | Run `42804949796` |
| ISO SHA256 | PASS（构建生成） | `d9fe2879…fb95a4476` |
| ISO 独立复核 | PASS（四次 Run 均复核） | Run `42804949796` 的 ISO 已下载并重算：`d9fe2879…` 与侧车一致；`42795953493`（`2edf88a0…`）、`42778468039`（`17789c04…`）与 `42747871471`（`2295eb0a…`）同样复核通过 |
| ISO 字节级可复现 | NOT PROVEN | 同尺寸、三种不同 SHA256 |
| QEMU SeaBIOS/TCG 虚拟启动 | PASS（fail-closed） | `qemu-smoke-report.txt` |
| 中文 tty1 菜单（QEMU） | PASS | 5 例 / 96 断言 |
| 中文授权面板（真实脚本、真实字形） | PASS | `qemu-cjk-final.log`（25 断言） |
| PAWDATA 虚拟介质 | 12/12 PASS | `pawdata-virtual-test-report.txt` |
| 虚拟克隆/故障注入 | 39/39 PASS | `virtual-fault-injection-report.txt` |
| 离线修复/回滚 | 28/28 PASS（含两种形态的真实 grub-install 与修复盘启动链） | `repair-virtual-test-report.txt` |
| 网络阶段 | 17/17 PASS | `network-virtual-test-report.txt` |
| Finalize/重启门 | 36/36 PASS | `finalize-virtual-test-report.txt` |
| TTY 绑定（静态 + PTY） | 55 静态 + 15 PTY PASS | `tty-virtual-test-report.txt` |
| 真实 TF 卡写入 | NOT VERIFIED | 需用户实体操作 |
| 真实 ASUS 主板启动 | NOT VERIFIED | 需用户实体操作 |
| 真实 SSD/内存 | NOT VERIFIED | 需用户实体操作 |
| 真实腾讯云 Rescue/正式迁移 | NOT VERIFIED | 需另行授权 |

## 5. 使用顺序

1. 取 ISO：用本机已下载的 `paw-live-amd64.iso`，或从 Run `42804949796` 的
   Artifact 下载。
2. 重新计算 ISO SHA256，与 `d9fe2879…fb95a4476`（或同一 Run 的侧车）对照。
3. 按 `docs/PAW-V2.7.1-USER-GUIDE-ZH.md` 用 Rufus DD 模式写 TF 卡
   （`reports/TF-CARD-RUFUS-GUIDE.md` 有图形步骤）。
4. 新电脑 Legacy/CSM 启动，按 tty1 中文菜单逐项操作。
5. 任何 FAIL/WARN 都停止；不要用“再试一次”跳过身份或内存门槛。
6. 真实迁移前确认旧 VPS 仍在生产运行，且 Rescue 授权、网络和回滚窗口已准备好。

## 6. 重要限制

- `OPERATOR_CONFIRMED` 不是机器证明或密码学证明。
- QEMU/mock/loop 结果不等于真实硬件。
- 没有在云端写入任何真实磁盘或 TF 卡。
- 没有访问生产 VPS。
- 真实迁移必须由用户在场并单独授权。
- 回退到继承 stdin/stdout 的运行方式（无控制台或输入被重定向）不能当作实机
  tty1 证据。
