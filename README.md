# PAW Migration Kit

本仓库包含一个最小化 Debian Live 迁移准备系统及其隔离虚拟测试。仓库不包含 PAW 数据库、生产服务器镜像、生产配置、凭据、SSH 私钥、Tailscale 授权密钥或 VLESS UUID。

## 当前版本

- 开发分支：`fix/v2.6.2-final-readiness`（HEAD `91a79ea`）
- Draft PR：#2
- 基线：v2.6.1 `0128110`
- 构建运行：GitHub Actions → `PAW live build and isolated tests` → Run workflow
- 最终云端成功运行：`42795953493`（2026-11-10 UTC，全部步骤通过，含 5 例 QEMU 中文用例）
- 当前 ISO：953,155,584 bytes，SHA256
  `2edf88a09684ebbb88680c79a73a29ea77fbc794aa168243649b2b67b2fc20ed`
- 最终证据：`reports/evidence-v2.7/iso-identity-run-42795953493.txt`（本轮），
  历史记录见 `reports/PAW-V2.7-FINAL-EVIDENCE.md`
- 交付说明：`DELIVERY.md`
- 产物保留：3 天（本次 Artifact `13754343439` 到期 2026-11-13 10:22:46 UTC）
- 自动克隆：**不会自动开始**；必须完成 PAWDATA、源盘、目标盘、硬件/内存和中文最终授权。

## 云端构建会做什么

Actions 在 Ubuntu 24.04 runner 上：

1. 做 Bash/Python/PowerShell/JSON/YAML 静态检查与公开仓库安全扫描。
2. 校验 Debian 官方 CD 签名与 SHA256。
3. 从 Tailscale 签名 APT 仓库和 Xray 官方 release 获取固定版本，并校验摘要。
4. 构建 `paw-live-amd64.iso`（Debian Live、Hybrid ISO、Legacy BIOS）。
5. 用 SeaBIOS + QEMU TCG 虚拟启动，要求缺少前置条件时 fail-closed。
6. 在虚拟介质上测试 PAWDATA MBR/GPT 自动初始化、持久化、损坏和空间耗尽。
7. 用 mock SSH 测试远端 zstd 压缩流、raw fallback、短读/中断、SHA256、混合数据。
8. 在 loop ext4 上测试离线修复和回滚。
9. 用 mock 网络测试 Xray 配置错误、Rescue/Restored 阶段、Tailscale 登录等待。

## 真实用户流程（尚未在实体机验证）

1. 将最终 ISO 以 DD/整盘模式写入 TF 卡；写前核对设备型号、容量、序列号和 SHA256。
2. 新电脑插网线，开机选择一次 TF 卡 Legacy BIOS 启动。
3. 启动后按中文提示确认 TF 卡序列号末六位，让 PAWDATA 自动创建在卡尾；ISO 启动分区不会被格式化。
4. 物理显示器/键盘的 tty1 会显示 PAW 中文控制台菜单；可逐项完成内存确认、源盘识别、目标盘登记、硬件检查、最终授权。
4. 如需内存检测：从 ISOLINUX 菜单进入 Memtest86+，完成后回到 PAW Live，用中文界面登记轮次和错误数；该记录是 `OPERATOR_CONFIRMED`，不是机器证明。
5. 通过固定 SSH 主机指纹和 Rescue 临时密钥识别旧 VPS 源盘，核对根 UUID、50 GiB、GPT、BIOS Boot。
6. 登记目标 SSD，完成 SMART/只读扫描；内存未完成或错误时不会允许克隆。
7. 在最终中文界面核对源盘、目标盘、容量、序列号、硬件、网络和数据损失，输入目标 SSD 序列号末六位。
8. 程序重新识别源/目标后，才执行远端 zstd → SSH → 本地解压 → 写入 → 独立 SHA256 → 离线修复 → GPT/ext4 扩容 → 首次启动检查。
9. 正式 Ubuntu 启动后，再由远程 Codex 完成 Tailscale、美国出口、机器名、Funnel、MCP 和 PAW 验收。

## 重要边界

- 成功的 Actions 构建不等于 TF 卡已写入。
- QEMU/SeaBIOS 成功不等于真实 ASUS 主板启动成功。
- mock SSH/loop 测试不等于真实腾讯云 Rescue、真实 SSD 或真实 PAW 迁移。
- `OPERATOR_CONFIRMED` 不等于密码学证明；没有可信硬件签名时不得写成 `PASS`。
- 旧 VPS 是生产环境；迁移准备阶段不得停止、重启、救援或修改生产服务。
