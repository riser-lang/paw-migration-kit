# PAW Migration Kit v2.7 交付包

交付时间：2026-11-09 UTC
分支：`fix/v2.6.2-final-readiness`
最终云端测试提交：`f18202b714cd2431733ff54e132c3083a4197aca`
PR #2：<https://github.com/riser-lang/paw-migration-kit/pull/2>（Draft）

## 1. 最终构建

- Actions Run：<https://github.com/riser-lang/paw-migration-kit/actions/runs/42618901559>
- 结论：success
- Artifact ID：`13675072020`
- Artifact 名称：`paw-live-build-test-results`
- Artifact 大小：938,778,039 bytes
- 过期时间：2026-11-12 12:48:02 UTC
- 下载入口：打开 Actions Run 页面，在页面底部 Artifacts 区域下载；GitHub 需要登录且有仓库读权限。

## 2. ISO

- 文件：`paw-live-amd64.iso`
- 字节数：938,475,520
- SHA256：
  `8c8ffedd3a6eb84c56f1da84b3ee3a79df10b8e1e987099ad88d398e6854c4a7`
- 校验文件副本：`reports/evidence-v2.7/paw-live-amd64.iso.sha256`

下载后请在 Windows 重新计算并核对：

```powershell
Get-FileHash .\paw-live-amd64.iso -Algorithm SHA256
```

## 3. 交付内容

- Debian Live ISO（Hybrid MBR/GPT、Legacy BIOS、Memtest86+ 独立菜单）。
- 中文 PAW 控制台菜单：内存确认、PAWDATA、Rescue 源盘、目标 SSD、硬件、最终授权。
- PAWDATA 自动引导与持久化。
- Rescue 组合身份识别。
- 远端 zstd + SSH + 本地解压 + 实际字节计数。
- 独立 SHA256、离线修复、GPT/ext4 扩容、首次启动检查。
- 用户说明：`docs/PAW-V2.7-USER-GUIDE-ZH.md`
- 回滚说明：`docs/PAW-V2.7-ROLLBACK-ZH.md`
- 接管报告：`reports/PAW-V2.7-TAKEOVER.md`
- P0 实现记录：`reports/PAW-V2.7-P0-IMPLEMENTATION.md`
- 最终证据：`reports/PAW-V2.7-FINAL-EVIDENCE.md`
- 证据副本：`reports/evidence-v2.7/`
- 软件清单：`software-packages.txt`、`software-manifest.txt`
- 构建来源：`build-provenance.txt`
- 公开安全审计：`reports/PAW-PUBLIC-SECURITY-AUDIT.md`

## 4. 验证状态矩阵

| 层级 | 状态 | 证据 |
|---|---|---|
| 云端构建 | PASS | Run `42618901559` |
| ISO SHA256 | PASS（构建生成） | sidecar `5daf...` |
| QEMU SeaBIOS/TCG 虚拟启动 | PASS（fail-closed） | `qemu-smoke-report.txt` |
| PAWDATA 虚拟介质 | 12/12 PASS | `pawdata-virtual-test-report.txt` |
| 虚拟克隆/故障注入 | 35/35 PASS | `virtual-fault-injection-report.txt` |
| 离线修复/回滚 | 15/15 PASS | `repair-virtual-test-report.txt` |
| 网络阶段 | 17/17 PASS | `network-virtual-test-report.txt` |
| 真实 TF 卡写入 | NOT VERIFIED | 需用户实体操作 |
| 真实 ASUS 主板启动 | NOT VERIFIED | 需用户实体操作 |
| 真实 SSD/内存 | NOT VERIFIED | 需用户实体操作 |
| 真实腾讯云 Rescue/正式迁移 | NOT VERIFIED | 需另行授权 |

## 5. 使用顺序

1. 下载 Artifact 并解压出 ISO。
2. 重新计算 ISO SHA256，与 sidecar 对照。
3. 按 `docs/PAW-V2.7-USER-GUIDE-ZH.md` 用 Rufus DD 模式写 TF 卡。
4. 新电脑 Legacy/CSM 启动，按 tty1 中文菜单逐项操作。
5. 任何 FAIL/WARN 都停止；不要用“再试一次”跳过身份或内存门槛。
6. 真实迁移前确认旧 VPS 仍在生产运行，且 Rescue 授权、网络和回滚窗口已准备好。

## 6. 重要限制

- `OPERATOR_CONFIRMED` 不是机器证明或密码学证明。
- QEMU/mock/loop 结果不等于真实硬件。
- 没有在云端写入任何真实磁盘或 TF 卡。
- 没有访问生产 VPS。
- 真实迁移必须由用户在场并单独授权。
