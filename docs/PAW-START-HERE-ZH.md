# PAW v2.7 · 从这里开始（单页）

一句话状态：**云端构建与虚拟测试全部通过；实机 7 项还没做，所以现在还不要拿它去覆盖你的生产盘。**

---

## 第 0 步：先核对 ISO（1 分钟）

在 Windows PowerShell 里，进入 `delivery` 文件夹后执行：

```powershell
Get-FileHash -Algorithm SHA256 .\paw-live-amd64.iso
```

期望值（本次交付件）：

```
d9fe28799f9c18d1ec69900b66ea0c71d70b232c5e62a0c4ab0e902fb95a4476
```

文件大小应为 **953,155,584 字节**。对不上就重新下载，不要写卡。

想一次核对整个交付包（推荐）：

```powershell
powershell -ExecutionPolicy Bypass -File .\verify-delivery.ps1
```

它会核对 `SHA256SUMS.txt` 里每个文件、ISO 大小与哈希，最后打印 PASS / FAIL。

---

## 前 3 件事（今天就能做，不碰生产）

> 每屏应该长什么样都有对照图：`PAW-SCREEN-EXPECTATIONS-ZH.md`（交付包内，含 5 张截屏）。
> 现场对不上就停，别硬按。

### 1) 写 TF 卡

用 Rufus，选这个 ISO，**DD 模式**写入。图形步骤见 `TF-CARD-RUFUS-GUIDE.md`。
写完**回读**一次：把卡重新插好，确认能列出分区、PAW 启动项存在。

### 2) 目标电脑从 TF 卡启动（Legacy / CSM）

应看到：

```
 PAW 迁移准备控制台（v2.7）
1) 登记 Memtest86+ 人工确认结果
...
```

### 3) 登记内存检测 + 初始化 PAWDATA

- 启动菜单里选 **Memtest86+** 跑至少 1 轮，回来按 `1` 登记（选 1 = 0 错误）。
- 按 `2` 初始化 PAWDATA：核对面板上的型号/容量/序列号，输入序列号**最后 6 位**。

这两步都不写你的 SSD，只动 TF 卡上的 PAWDATA 分区。

---

## 之后再往下（需要你先做决定）

- 按 `4` 登记目标 SSD、按 `5` 跑硬件检查（SMART / 只读扫描 / 温度）。
- 按 `3` 配置 Rescue SSH 并识别旧 VPS 源盘 —— **这一步需要把旧 VPS 进 Rescue Mode，会停机**，时机由你定。
- 按 `6` 最终中文授权 → 整盘覆盖迁移。**目标 SSD 原有数据会全部丢失**，面板上会逐行写明。
- 迁移完成后关机、换盘、开机，做离线修复与首次启动检查。

每一步的预期屏幕文字和失败处置，都在 `PAW-V2.7-HARDWARE-CHECKLIST-ZH.md` 里，照抄即可。

---

## 三条硬规矩

1. 任何一步出现 **FAIL / WARN**，停下，不要"再试一次"绕过去。
2. 迁移成功并在新机验证通过之前，**旧 VPS 保持生产运行**，不要停、不要改。
3. `OPERATOR_CONFIRMED` 是"你亲眼看过了"，不是机器证明；别凭猜测填 1。

---

## 出问题时给我这些

1. 出问题那一步的**屏幕照片**（尤其内存检测、Rescue、最终授权）。
2. 菜单 `7) 查看状态和报告` 里生成的报告文件。
3. 任何 FAIL/WARN 的原文。

---

## 文件索引

| 文件 | 用途 |
|---|---|
| `paw-live-amd64.iso` | 交付 ISO（953,155,584 字节） |
| `paw-live-amd64.iso.sha256` | ISO 哈希侧车 |
| `SHA256SUMS.txt` | 整个交付包每个文件的哈希 |
| `verify-delivery.ps1` | 一键核对脚本（Windows PowerShell） |
| `TF-CARD-RUFUS-GUIDE.md` | 写卡图示步骤 |
| `PAW-SCREEN-EXPECTATIONS-ZH.md` + `screens/` | 5 张 CI 真实渲染截屏 + 逐字应出现的文字 |
| `PAW-QUICK-CARD-ZH.html` | 离线单页速查（图片内嵌，双击即可看，不需要网络） |
| `PAW-V2.7-HARDWARE-CHECKLIST-ZH.md` | 实机 7 项逐步清单（含预期屏幕文字） |
| `PAW-V2.7.1-USER-GUIDE-ZH.md` | 使用说明 |
| `PAW-V2.7-ROLLBACK-ZH.md` | 回滚说明 |
| `PAW-MIGRATION-STATE.md` | 当前状态与证据映射 |
| `PAW-MIGRATION-BLOCKERS.md` | 阻断项一览（哪些已关、哪些还开着） |
| `PAW-MIGRATION-ACCEPTANCE.md` | 验收清单 |
| `PAW-V2.7.1-TEST-REPORT.md` | 测试报告（含失败记录） |
| `PAW-V2.7.1-REPAIR-REPORT.md` | 离线修复与启动链证据 |
| `DELIVERY.md` | 交付说明（构建来源、运行、哈希） |
| `software-manifest.txt` / `software-packages.txt` | 软件清单 |
| `build-provenance.txt` | 构建来源 |

---

## 还没证的事（别当成已证）

- 真实 TF 卡写入回读、真实主板启动、真实 SSD SMART/扫描/温度、真实内存检测。
- 真实腾讯云 Rescue SSH、真实整盘克隆、真实 Ubuntu 根启动到登录。
- ISO 构建**不是字节级可复现**（八次构建同尺寸、八个不同哈希），所以哈希只与同一 Run 的侧车对照。
