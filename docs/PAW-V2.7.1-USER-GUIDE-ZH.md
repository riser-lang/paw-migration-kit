# PAW 迁移准备控制台 中文使用指南（v2.7.1）

适用镜像：PAW Migration Live（Debian 13 Trixie，Legacy BIOS/UEFI 均可尝试）
控制台：`/dev/tty1`（普通显示器 + 键盘）
串口：`ttyS0,115200n8` 仅用于诊断日志，不作为交互输入

> 本指南对应当前第一段收尾版本（基线 `d640712` + 字体失败安全门禁）。新分支
> CI、第二阶段生产块/SSH 克隆入口、第三/四阶段和真实 ASUS B85M-G Plus 现场
> 验收尚未完成；第二阶段已有虚拟 Ubuntu 启动证据，但不能当作生产克隆验收。
> 若屏幕显示异常，请按第 7 节采集证据，不要直接写入任何磁盘。

## 1. 启动前

- 用普通显示器连接目标机，键盘接 USB 或 PS/2。
- 不要插任何需要保留数据的磁盘；PAWDATA 只会追加/格式化**新分区**，但最终迁移
  会整盘覆盖目标 SSD。
- 确认目标机从 U 盘/光盘启动（Boot Menu 选择 PAW Live）。

## 2. 中文控制台

启动后会先加载中文字体，再显示 PAWDATA 面板或主菜单。屏幕应出现类似：

```
==============================================
 PAW 迁移准备控制台（v2.7）
==============================================
[PAW-MENU-KEYS] 1 Memtest 2 PAWDATA ...
当前：...
1) 登记 Memtest86+ 人工确认结果
2) 初始化/修复 PAWDATA 持久分区
...
请输入编号：
```

中文是 16x16 点阵字形，字与字之间可能有半个字符的间距，这是控制台对宽字符的
正常排版，不影响阅读。ASCII 行（如 `[PAW-MENU-KEYS]`）保留用于极端情况下
字体未加载时仍可按键操作。

如果屏幕只有英文/方块/空白，见第 7 节。

### 2.1 字体安全门禁（重要）

从当前 `vm/ds-clean-handover-20261110` 分支起，PAW 使用 **fail-closed** 字体
门禁：只有下面条件全部满足才允许分区、格式化、克隆、离线修复或扩容：

1. `/dev/fb0` 存在且内核 fbcon 已绑定；
2. 当前启动的是 `paw-cjk-16x16.psf`（不是 8x16 回退）；
3. 字体的实际 SHA256 与构建 manifest 的 `primary_font_sha256` 一致；
4. `setfont -C /dev/tty1` 返回 0；
5. `console-font.json` 的 `schema` 是 `paw.console-font.v2`、`status` 是
   `PASS`、`boot_id` 等于本次启动、`fbcon_bound` 是 `true`。

- 8x16 vgacon 回退只写 `status=WARN`，**不会**打开写门禁；屏幕仍可用于只读
  诊断，但不能继续迁移。
- 字体缺失、损坏、哈希错误、`setfont` 失败、报告缺失或 boot_id 过期都会写
  `status=FAIL` 并阻断所有破坏性操作；只读查看/诊断仍可用。
- 授权面板之前就会过门禁；如果没有 PASS，不会出现“输入序列号末六位”的破坏性
  授权提示。
- 当前 VM 的字体门禁已做 26 项故障注入；新分支 CI Run `42825407549` 已全绿
  （gate 26/26、CJK 25/25、TTY 56/56），现场仍以目标机的实际
  `console-font.json` 为准。

## 3. 首次 PAWDATA 初始化

首次启动会自动识别“当前启动本系统的可移动设备”，并显示：

```
PAW 首次启动 · PAWDATA 持久分区初始化
只针对当前启动本系统的可移动设备；不会碰其他磁盘。
物理设备：/dev/sdX
型号：...
容量：... bytes（约 ... GiB）
序列号：...
将只追加一个新的 PAWDATA 分区并格式化该新分区；ISO 启动分区不会被格式化。
请输入该设备序列号最后 6 位以继续：
```

- 输入**屏幕显示的序列号最后 6 位**（ASCII 字母/数字），按 Enter。
- 输入正确：显示“输入已确认；开始追加 PAWDATA 分区”，随后进入主菜单。
- 输入错误：显示“错误：序列号末六位不匹配，已安全停止，没有写入任何分区。”
  不会分区，也不会重启；可重新启动后再试。
- 300 秒不输入：显示“错误：等待输入超过 300 秒，已安全停止，没有写入任何分区。”
  （测试环境可用较短超时；生产默认 300 秒。）

注意：序列号只用于确认“你看到的就是当前启动盘”，不是密码；不要凭猜测输入。

## 4. 主菜单按键

| 键 | 功能 |
|---|---|
| `1` | 登记 Memtest86+ 人工确认结果 |
| `2` | 初始化/修复 PAWDATA 持久分区 |
| `3` | 配置 Rescue SSH 并识别旧 VPS 源盘 |
| `4` | 登记目标 SSD（只读盘点） |
| `5` | 目标 SSD 硬件检查（SMART/只读扫描/温度/内存） |
| `6` | 最终中文授权并开始迁移 |
| `7` | 查看状态和报告 |
| `8` | 选择 Rescue / Restored 网络阶段 |
| `0` | 重新显示状态 |

- 每个子流程结束后会提示“按 Enter 返回菜单”。
- 菜单和所有输入始终使用同一个 `/dev/tty1`；不会另外弹出一个 getty 或串口登录
  来抢输入。
- Tailscale 登录链接写入报告文件并在菜单中显示，不会占用交互终端。

## 5. 迁移完成提示

最终门禁全部通过后，屏幕会显示：

```
PAW 迁移成功：克隆、独立 SHA256 校验、离线修复、GPT/ext4 扩容和首次启动检查全部通过。
完成记录已原子写入并同步到磁盘。
系统将在 10 秒后自动重启进入正式 Ubuntu；按 C 取消自动重启。
倒计时 10 秒（按 C 取消）...
```

- 按 `C`：取消自动重启，显示“已取消自动重启，请手动重启：sudo systemctl reboot”，
  不会执行 reboot。
- 不按：倒计时结束后执行重启；若 reboot 命令失败，会显示
  “自动重启命令执行失败！迁移数据已完成，请立即手动重启”，状态为
  `NEEDS_MANUAL_ACTION`。
- 已成功下发重启后再次运行不会重复重启。

## 6. 串口诊断（可选）

串口只输出 systemd/脚本日志，不接收交互输入。采集：

```bash
# 在另一台机器上
picocom -b 115200 /dev/ttyUSB0
```

或启动参数保留 `console=ttyS0,115200n8`，日志会同时进入串口。串口出现登录提示
不代表 PAW 菜单被抢走；PAW 的交互仍只在 tty1。

## 7. 中文显示异常排查

先在目标机按 `Ctrl+Alt+F2` 切到另一个 VT（如果可用），或通过串口登录，执行：

```bash
cat /sys/class/graphics/fb0/name
cat /sys/class/graphics/fb0/virtual_size
cat /run/paw-migration/reports/console-font.json
systemctl status paw-console-font.service
journalctl -u paw-console-font.service -b --no-pager
```

期望：

- `/dev/fb0` 存在，名称类似 `i915drmfb` 或 `bochs-drmdrmfb`；
- `console-font.json` 中 `"schema": "paw.console-font.v2"`、
  `"mode": "fbcon"`、`"fbcon_bound": true`、`"font": "...16x16.psf"`、
  `"setfont_exit_code": 0`、`"status": "PASS"`，且 `"boot_id"` 等于当前
  `cat /proc/sys/kernel/random/boot_id`；
- 服务日志出现“控制台字体已加载：fbcon ...”。

如果 `/dev/fb0` 不存在：

- 说明内核没有拿到 framebuffer（常见于错误的 `nomodeset`、云内核、或显卡驱动
  未加载）。PAW 会回退到 8x16 字体并记 `WARN`；复杂汉字可能压缩/难读，屏幕可用
  于只读诊断，但**不会允许任何磁盘写入**。
- 记录 `dmesg | grep -Ei 'drm|fb0|bochs|i915|vesa'` 和
  `journalctl -b --no-pager`，交给维护者；不要自行写入磁盘。

如果 `console-font.json` 不存在或 `setfont_exit_code` 非 0：

- 记录 `ls -l /opt/paw-migration/fonts/`、`sha256sum /opt/paw-migration/fonts/*.psf`；
- 记录 `systemctl status paw-console-font.service`；
- 这属于字体/内核问题，不是序列号问题，不要继续最终授权；检查
  `boot_id`、`fbcon_bound`、`expected_font_sha256` 与实际 `font_sha256` 是否一致。

## 8. 安全边界

- 未确认序列号前，PAWDATA 不会分区；错误/超时会明确提示“没有写入任何分区”。
- 最终迁移授权会整盘覆盖目标 SSD；屏幕会再次显示数据损失说明。
- 不要在生产 PAW、旧 VPS、Tailscale/Funnel/Xray/Nginx/443/防火墙/COS 上执行
  本指南之外的命令。
- 本版本不会操作真实 TF 卡/真实硬盘，除非你在目标机上明确完成最终授权。

## 9. 现场验收清单（尚未完成）

- [ ] ASUS B85M-G Plus Legacy BIOS 启动，显示器出现完整中文菜单
- [ ] PAWDATA 中文面板、序列号提示、错误/超时原因可读
- [ ] 键盘输入正确/错误序列号均按预期
- [ ] `max_holders=1`，getty 未抢占 tty1
- [ ] 迁移完成中文提示与倒计时可读，按 C 可取消
- [ ] 记录 `console-font.json`、`fb0` 名称、内核版本、字体 SHA256
