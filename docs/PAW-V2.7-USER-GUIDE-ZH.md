# PAW v2.7 使用说明（中文）

> 当前状态：云端代码与虚拟测试仍在验证。真实 TF 卡写入、真实主板启动、真实 SSD 和真实 Rescue 均未验证。不要在未完成验证前对生产环境操作。

## 1. 你需要准备

- 一张质量可靠的 32 GB TF 卡和 USB 读卡器。
- 新电脑、网线、显示器/键盘。
- 目标 SSD（容量不小于旧 VPS 系统盘）。
- 旧 VPS 的 Tencent Cloud Rescue Mode 授权和 VNC 访问（另行确认，不在本工具中保存）。
- 已核对 SHA256 的 `paw-live-amd64.iso`。

## 2. 写卡前

1. 在 Windows 上核对 ISO：

   ```powershell
   Get-FileHash .\paw-live-amd64.iso -Algorithm SHA256
   ```

   必须与交付的 `.sha256` 文件完全一致。
2. 插入 TF 卡，打开 Rufus。只选择容量、型号、序列号都与实物一致的读卡器；**盘符不是设备身份**。
3. 选择 ISO，写入模式选择 **DD Image mode**。写入会清除整张卡。
4. 写完后不要用 Windows 格式化或复制文件；直接拔出。

## 3. 第一次启动

1. 新电脑插网线，开机按主板启动菜单键，选择 TF 卡。
2. 选择 Legacy/CSM 启动；如果主板只允许 UEFI，当前 Hybrid ISO 的真实兼容性尚未验证。
3. 进入 PAW Live 后，屏幕会显示当前启动介质的型号、容量、序列号。
4. 输入序列号**最后 6 位**。程序只会在该卡尾部追加 PAWDATA 分区，不会格式化 ISO 启动分区。
5. 看到 PAWDATA 挂载成功后，继续。

如果没有任何提示，或提示“不可移动/序列号不可读”，不要继续；记录屏幕内容并停止。

## 4. 内存检测（建议必做）

1. 重启，在 ISOLINUX 菜单选择 `Memory test (Memtest86+ x64...)`。
2. 至少完成 1 轮，记录完成轮次和错误数。
3. 重启回到 PAW Live。
4. 在控制台运行：

   ```bash
   /opt/paw-migration/scripts/paw-memtest-confirm.sh
   ```

5. 按中文界面选择：
   - 完成且错误数为 0 → `OPERATOR_CONFIRMED`
   - 有错误 → `FAIL`
   - 未完成/不确定 → `WARN`
6. 输入目标 SSD 序列号末六位并输入“确认”。

`OPERATOR_CONFIRMED` 只是操作员目视确认，不是机器自动证明，也不是密码学证明。`FAIL` 或 `WARN` 时不会允许克隆。

## 5. 识别旧 VPS 源盘

此步骤需要你已在 Tencent Cloud 控制台把旧 VPS 进入 Rescue Mode，并取得 VNC 中显示的 SSH 主机名/地址和端口。

1. 运行：

   ```bash
   /opt/paw-migration/scripts/paw-rescue-key-prepare.sh
   ```

2. 按提示输入 Rescue SSH 地址和端口；程序生成一次性密钥并打印公钥。
3. 在 Rescue Mode 的临时 `authorized_keys` 中加入该公钥。
4. 在 VNC 中核对 SSH 主机 SHA256 指纹，并把完整指纹粘贴回程序。**不要只相信 ssh-keyscan。**
5. 运行源盘识别，输入你保存的 Rescue 根分区 UUID。
6. 程序核对：根 UUID 唯一、50 GiB、GPT、BIOS Boot、ext4、无读写挂载、固定主机指纹。云盘没有序列号时会使用组合身份，不会放宽容量/GPT/BIOS Boot 要求。

## 6. 登记目标 SSD

1. 运行 `/opt/paw-migration/scripts/paw-target-discovery.sh`。
2. 按编号选择目标 SSD；只读盘点，不写盘。
3. 核对型号、容量、序列号，输入序列号末六位登记。
4. 运行硬件预检（SMART、只读扫描、温度、内存状态）。任何 FAIL/WARN 都会阻断。

## 7. 最终授权与自动迁移

1. 运行 `/opt/paw-migration/scripts/paw-final-confirm.sh`。
2. 屏幕会显示源盘、目标盘、容量、序列号、组合身份、主机指纹、硬件、网络和数据损失。
3. 确认目标 SSD 整盘会被覆盖后，输入目标 SSD 序列号最后 6 位。
4. 程序会再次识别源盘和目标盘；任何变化立即停止。
5. 通过后自动执行：远端 zstd → SSH → 本地解压 → 写入 → 独立 SHA256 → 离线修复 → GPT/ext4 扩容 → 首次启动检查。
6. 完成后自动重启到新 Ubuntu。不要拔卡或断电。

## 8. 正式 Ubuntu 启动后

由 Windows Codex 或其他远程 Codex 接管，完成 Tailscale、美国出口、机器名称、Funnel、MCP 和 PAW 验收。PAW 正式业务验收前，旧 VPS 仍是生产权威。

## 9. 出现问题时

- 不要反复重试整盘克隆；先保存屏幕和 `/var/lib/paw-migration/reports/`。
- 不要手工格式化 TF 卡或目标 SSD。
- 不要修改旧 VPS 的 Tailscale/Funnel/Xray/Nginx/防火墙/COS。
- 把屏幕照片、报告文件和发生步骤集中反馈，不要发送私钥、Token 或完整服务器地址。
