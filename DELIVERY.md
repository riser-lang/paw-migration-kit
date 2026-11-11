# PAW Migration Kit v2.7.1 交付包

交付更新时间：2026-11-11 UTC（Stage 3 close / Stage 4 ISO verified / target boot re-verified）
分支：`vm/ds-clean-handover-20261110`
代码 HEAD（本 ISO 与全部测试证据对应）：`24c13f7`
文档 HEAD：本文件所在文档提交（只改文档，不改变脚本或 ISO）
PR #2：<https://github.com/riser-lang/paw-migration-kit/pull/2>（Draft，未合并）
PR #1：<https://github.com/riser-lang/paw-migration-kit/pull/1>（Draft，未改动）
`main`：未改动

## 1. 最终构建

- Actions Run：<https://github.com/riser-lang/paw-migration-kit/actions/runs/42941005270>
- 结论：**success**
- 触发：`workflow_dispatch`，代码 HEAD `24c13f7`
- Artifact ID：`13822300189`
- Artifact 名称：`paw-live-build-test-results`
- Artifact 大小：`1,030,665,613` bytes
- 过期时间：`2026-11-14 02:03:21 UTC`（GitHub 默认 3 天）
- 下载入口：Actions Run 页面底部 Artifacts 区域；或
  `gh run download 42941005270 -n paw-live-build-test-results`
- 如果 `gh run download` 长时间无进度，改用 GitHub API artifact zip 端点 +
  `curl` 直取，仍必须解压后对 ISO 文件本身计算哈希。

## 2. ISO

- 文件：`paw-live-amd64.iso`
- 字节数：`953,155,584`
- SHA256：`822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09`
- 同一 Run 侧车：`paw-live-amd64.iso.sha256: 822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09  boot/custom/paw-live-amd64.iso`
- 独立复核记录：`PAW-V2.7.1-ISO-SHA256.txt`、
  `reports/evidence-v2.7/iso-identity-run-42941005270.txt`
- 分区结构：`MBR isohybrid cyl-align-on GPT APM`（Legacy BIOS 可启动，含 Memtest86+ 独立菜单）

### 2.1 独立复核（本次实际执行）

- 从 Run `42941005270` 下载 `paw-live-build-test-results` artifact ZIP；
- 解压得到 `paw-live-amd64.iso`；
- 对 **ISO 文件本身**执行 `sha256sum`，得到 `822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09`；
- 与同一 Run 的 `paw-live-amd64.iso.sha256` 和 `iso-identity.txt` 完全一致。
- **没有**把 artifact ZIP 的哈希当作 ISO 哈希。

> ISO 构建不是字节级可复现：历史多次构建的 ISO 字节数相同但 SHA256 不同。
> 核对哈希时必须使用**同一 Run** 的侧车文件，不能跨 Run 比较，也不能用历史
> Run `42804949796` 的 `d9fe2879…fb95a4476` 代替本交付件。

## 3. 交付内容

- Debian Live ISO（Hybrid MBR/GPT、Legacy BIOS、Memtest86+ 独立菜单）。
- 中文 PAW 控制台菜单：内存确认、PAWDATA、Rescue 源盘、目标 SSD、硬件、
  最终授权。
- 操作员面板统一绑定已验证的 tty1（300 秒超时与 ASCII 屏幕标记）。
- PAWDATA 自动引导与持久化。
- Rescue 组合身份识别。
- 远端 zstd + SSH + 本地解压 + 实际字节计数。
- 独立 SHA256、完整离线修复、GPT/ext4 扩容、首次启动检查、自动重启。
- **Stage 3 26 步真实程序链路证据**：`reports/PAW-STAGE3-RESUME-20261110.md`。
- 用户说明：`docs/PAW-V2.7.1-USER-GUIDE-ZH.md`、`docs/PAW-V2.7-USER-GUIDE-ZH.md`
- 回滚说明：`docs/PAW-V2.7-ROLLBACK-ZH.md`
- 实机验证清单：`docs/PAW-V2.7-HARDWARE-CHECKLIST-ZH.md`
- 测试报告：`docs/PAW-V2.7.1-TEST-REPORT.md`
- 阻断清单：`PAW-MIGRATION-BLOCKERS.md`、`docs/PAW-V2.7.1-BLOCKERS.md`
- 验收清单：`PAW-MIGRATION-ACCEPTANCE.md`
- 软件清单：`software-packages.txt`、`software-packages.lock`、
  `software-manifest.txt`
- 构建来源：`build-provenance.txt`
- 公开安全审计：`reports/PAW-PUBLIC-SECURITY-AUDIT.md`
- 本 Run 的构建/测试报告副本：`reports/evidence-v2.7/run-42941005270/`
- Stage 3 目标盘独立启动证据：
  `reports/evidence/stage3-target-standalone-boot-20261111.{evidence.txt,json,command.txt,sha256}`

## 4. 验证状态矩阵

| 层级 | 状态 | 证据 |
|---|---|---|
| 当前分支 CI | **PASS** | Run `42941005270`，代码 `24c13f7` |
| 最终 ISO 构建 | **PASS** | Artifact `13822300189` |
| ISO 文件 SHA256 复核 | **PASS** | `822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09`，与同 Run 侧车一致 |
| ISO 字节级可复现 | NOT PROVEN | 历史多次同尺寸不同哈希 |
| Stage 3 26 步链路 | **PASS（QEMU 虚拟块设备；`target_boot` 独立复核）** | `reports/PAW-STAGE3-RESUME-20261110.md` |
| 目标盘独立启动（vda，无 direct kernel） | **PASS** | `reports/evidence/stage3-target-standalone-boot-20261111.evidence.txt`，`ubuntu login:`，`qemu_rc=0`；宿主原始串口日志 SHA256 `083ea333…3ec63a08` |
| 中文 tty1 菜单（QEMU） | **PASS** | `qemu-cjk-test-report.txt`（5 例） |
| PAWDATA 虚拟介质 | **PASS** | `pawdata-virtual-test-report.txt` |
| 虚拟克隆/故障注入 | **PASS** | `virtual-fault-injection-report.txt` |
| 离线修复/回滚 | **PASS** | `repair-virtual-test-report.txt` |
| 网络阶段 | **PASS** | `network-virtual-test-report.txt` |
| Finalize/重启门 | **PASS** | `finalize-virtual-test-report.txt` |
| TTY 绑定（静态 + PTY） | **PASS** | `tty-virtual-test-report.txt` |
| 真实 TF 卡写入 | **NOT VERIFIED** | 需用户实体操作 |
| 真实 ASUS 主板启动 | **NOT VERIFIED** | 需用户实体操作 |
| 真实 SSD/内存 | **NOT VERIFIED** | 需用户实体操作 |
| 真实腾讯云 Rescue/正式迁移 | **NOT VERIFIED** | 需另行授权 |

## 5. 使用顺序

1. 从 Run `42941005270` 的 Artifact 取 `paw-live-amd64.iso`，或使用已下载且
   哈希核对一致的文件。
2. 重新计算 ISO SHA256，与 `822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09`（或同一 Run 的侧车）对照。
3. 按 `docs/PAW-V2.7.1-USER-GUIDE-ZH.md` 用 Rufus DD 模式写 TF 卡
   （`reports/TF-CARD-RUFUS-GUIDE.md` 有图形步骤）。
4. 新电脑 Legacy/CSM 启动，按 tty1 中文菜单逐项操作。
5. 任何 FAIL/WARN 都停止；不要用“再试一次”跳过身份或内存门槛。
6. 真实迁移前确认旧 VPS 仍在生产运行，且 Rescue 授权、网络和回滚窗口已准备好。

## 6. 重要限制

- `OPERATOR_CONFIRMED` 不是机器证明或密码学证明。
- QEMU/mock/loop 结果不等于真实硬件；Stage 3 是虚拟块设备链路，不是物理 SSD
  验收。
- 没有在云端写入任何真实磁盘或 TF 卡。
- 没有访问生产 VPS。
- 真实迁移必须由用户在场并单独授权。
- 回退到继承 stdin/stdout（无控制台或输入被重定向）的运行方式不能当作实机
  tty1 证据。
- 没有合并 PR #2，没有改 `main`，没有删除任何历史 Artifact。
