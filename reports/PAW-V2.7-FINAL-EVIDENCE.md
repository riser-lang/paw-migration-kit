# PAW v2.7 最终云端证据

记录时间：2026-11-09 UTC
分支：`fix/v2.6.2-final-readiness`
最终代码提交：`f18202b714cd2431733ff54e132c3083a4197aca`
Draft PR：<https://github.com/riser-lang/paw-migration-kit/pull/2>

## GitHub Actions

- Run ID：`42618901559`
- Run URL：<https://github.com/riser-lang/paw-migration-kit/actions/runs/42618901559>
- 结论：success
- 开始：2026-11-09 12:39:55 UTC
- 完成：2026-11-09 12:48:12 UTC
- Runner：`ubuntu-24.04`
- Artifact ID：`13675072020`
- Artifact：`paw-live-build-test-results`
- Artifact 大小：938,778,039 bytes
- Artifact 过期：2026-11-12 12:48:02 UTC
- Artifact 下载：<https://github.com/riser-lang/paw-migration-kit/actions/runs/42618901559>

## ISO

- 文件名：`paw-live-amd64.iso`
- ISO 字节数（ZIP 中央目录）：938,475,520 bytes
- SHA256（构建步骤生成并随产物上传）：
  `8c8ffedd3a6eb84c56f1da84b3ee3a79df10b8e1e987099ad88d398e6854c4a7`
- 校验文件：`reports/evidence-v2.7/paw-live-amd64.iso.sha256`
- 说明：本机受 GitHub→Azure 产物下载带宽限制，未在云端工作站重新整盘下载并二次计算 ISO 哈希；SHA256 来自同一构建步骤对 ISO 的计算，下载后仍应再核对一次。

## 双构建可复现性

同一代码树的两次构建：

- Run `42615204317`：ISO SHA256 `5daf4c0b7af05258c7e90d8c84ba5e474b2ba8215a2cc75781c5374e4c15a4b8`
- Run `42618901559`：ISO SHA256 `8c8ffedd3a6eb84c56f1da84b3ee3a79df10b8e1e987099ad88d398e6854c4a7`

两次 ISO 字节数相同（938,475,520），但 SHA256 不同。**逐字节可复现性仍未证明**，不得声称双构建一致。交付使用最新的 Run `42618901559`。

## 虚拟测试结果

| 套件 | 结果 | 证据 |
|---|---:|---|
| PAWDATA MBR/GPT 自动初始化、持久化、损坏/空间耗尽 | 12 / 12 PASS | `pawdata-virtual-test-report.txt` |
| 源盘/内存/压缩/SSH/SHA/SMART/扩容故障注入 | 35 / 35 PASS | `virtual-fault-injection-report.txt` |
| 离线修复与回滚 | 15 / 15 PASS | `repair-virtual-test-report.txt` |
| Xray/Rescue/Restored/Tailscale 网络阶段 | 17 / 17 PASS | `network-virtual-test-report.txt` |
| SeaBIOS + QEMU TCG 虚拟启动 | PASS，BLOCKED，clone_started=false | `qemu-smoke-report.txt` |

关键证据：

- 远端 zstd 混合数据：8,388,608 bytes 源 → 4,194,723 bytes SSH payload → 8,388,608 bytes 恢复；SHA256 PASS。
- 无 Virtio 序列号：使用固定 Host Key 指纹 + 根 UUID + 父盘唯一匹配 + 50 GiB + GPT 布局 + BIOS Boot 的组合身份。
- Memtest 人工确认：`OPERATOR_CONFIRMED`、FAIL、WARN、目标不匹配四种状态均按预期阻断或接受。
- PAWDATA：MBR 和 GPT 都只追加一个新分区；原 ISO/BIOS Boot 几何保持；错误序列号不改变分区表。
- 离线修复：netplan、initramfs、machine-id、SSH Host Key、authorized_keys、PAW 数据、udev 和备份；注入 update-grub 失败后回滚通过。

## 软件来源

- Debian Live base：`debian-live-13.7.0-amd64-standard.iso`
- Debian CD key fingerprint：`DF9B9C49EAA9298432589D76DA87E80D6294BE9B`
- Debian base 签名：PASS
- Debian base SHA256：`040a44f35186321eb6cdaab52a8a2d06224fe6b77f6fbb9f1861ad89c14e17ec`
- Tailscale：`1.104.5`，来自 Tailscale 签名 Debian stable 仓库
- Xray：`v26.3.27`，官方 release digest 校验通过
- 包清单：`software-packages.txt`、`software-manifest.txt`
- 构建来源：`build-provenance.txt`（snapshot `20261101T000000Z`，SOURCE_DATE_EPOCH `1793491200`）

## 仍未验证（真实世界）

以下四项保持未验证，不能因为本轮 Actions 成功而升级：

1. 真实 TF 卡整盘写入与读回。
2. 真实 ASUS 主板 Legacy/CSM 启动。
3. 真实 SSD SMART、只读扫描、温度、内存。
4. 真实腾讯云 Rescue SSH、真实整盘克隆和真实 PAW 迁移。

本报告不包含生产服务器地址、凭据、真实根 UUID 或私钥。
