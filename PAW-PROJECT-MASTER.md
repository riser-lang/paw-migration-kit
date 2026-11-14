# PAW 项目总说明与最终需求基线

文档性质：长期项目目标、用户需求、架构决策与安全边界。  
更新日期：2026-11-14（目标硬件基准更新）  
仓库：https://github.com/riser-lang/paw-migration-kit

## 1. 本文件的作用与优先级

本文件记录项目长期目标和稳定需求，不记录容易过期的实时 CI 状态。

每次新对话、新模型或新开发环境接手时，必须先阅读：

1. PAW-PROJECT-MASTER.md：理解最终要交付什么，以及用户不能接受什么。
2. PAW-MIGRATION-STATE.md：了解当前分支、提交、CI、ISO 和已完成工作。
3. PAW-MIGRATION-BLOCKERS.md：了解尚未解决的问题和禁止继续的事项。
4. 最新验收报告及对应原始日志：核对证据，不只相信报告结论。

发生冲突时：
- 长期目标和用户约束以本文件为准。
- 当前进度以 PAW-MIGRATION-STATE.md 为准。
- 未解决风险以 PAW-MIGRATION-BLOCKERS.md 为准。
- 测试事实以对应提交的代码、原始日志和 GitHub Actions 记录为准。
- 不能用旧对话中的分支、HEAD、CI 或 ISO 信息代替实时核对。

## 2. 用户希望最终得到什么

把当前运行在腾讯云 Ubuntu 服务器上的 PAW 系统完整迁移到武汉本地电脑，使本地电脑成为 PAW 主服务器。

这不是在新电脑上重新安装一个空白 Ubuntu，再手工重装业务；目标是把旧服务器的 Ubuntu 系统盘完整复制到新 SSD，完成必要的启动修复和扩容后，让原来的系统和 PAW 业务在新电脑上继续运行。

迁移完成后：
- 武汉本地新电脑承担 PAW 的主要业务、MCP、数据库、自动化任务。
- 腾讯云旧 VPS 不关闭，改为长期网络网关和美国网络出口。
- 旧 VPS 保留必要的系统备份和回退能力。
- Windows 本地电脑通过 Tailscale 连接新服务器。
- Windows 桌面版 Codex 通过 SSH 远程管理新 Ubuntu。
- GPT、Claude、Gemini Spark 的 MCP 接入尽量保持原地址、路径和使用方式。
- 用户尽量不需要重新绑定 MCP 或手工恢复大量配置。

## 3. 用户的使用特点与助手职责

用户不是 Linux 专业人员。用户提供业务目标、现实条件和初步思路；助手负责判断、设计和落地。

助手必须：
- 独立判断用户的想法是否可行，不要一味顺从。
- 发现更简单、更安全、维护成本更低的方案时主动提出。
- 解释技术问题时优先用自然中文和简单类比。
- 不堆砌专业术语，不写成咨询公司式方案。
- 不要求用户自己排查复杂 Linux 问题。
- 能由 DS、Codex 或自动化程序完成的工作，尽量整理成完整、可执行的任务。
- 重要风险必须明确说出，不能为了让用户放心而淡化。
- 不把推测说成事实，不把计划说成结果。
- 缺少关键事实时先检查仓库、日志或官方资料；确实无法确认时标记 NEEDS_EVIDENCE。
- 不为了显示专业而增加无价值的功能或防御性修改。

用户希望最终操作尽量简单：插入启动卡、开机选择 USB、按提示完成少量必须由人完成的确认，其余工作自动执行。

允许用户进行少量人工操作：
- 进入 BIOS 或一次性启动菜单；
- 选择并确认目标 SSD；
- 必要时完成浏览器登录授权；
- 必要时输入自己的 VLESS 配置；
- 按提示拔掉 TF 卡；
- 对不可自动判断的安全事项作出明确确认。

## 4. 目标电脑的当前硬件基准（2026-11-14更新）

用户已将原计划的 ASUS B85M-G Plus 台式机更换为 Dell OptiPlex 3020M Micro。此前 ASUS B85M-G Plus / i5-4590 / 12GB / 240GB SSD 仅作为历史方案保留，不再是当前目标硬件。

| 项目 | 当前配置 |
|---|---|
| 品牌/型号 | Dell OptiPlex 3020M Micro |
| 主板 | Dell 0WWRRC（以用户提供的硬件信息为准） |
| 芯片组 | Intel H81 |
| CPU | Intel Core i5-4670T |
| CPU | 4核4线程，Haswell，x86_64，2.30GHz基础频率，最高3.30GHz，45W |
| 内存 | 16GB（8GB+8GB），Micron + Samsung |
| 内存类型/频率 | DDR3/DDR3L组合待实机确认；当前报告1333MHz |
| 显示 | Intel HD Graphics 4600 核显 |
| 独立显卡 | 无 |
| 目标硬盘 | 用户提供的配置截图显示120GB SSD；具体型号、接口和精确字节数待实机读取 |
| 目标容量 | 标称120GB；必须用 blockdev --getsize64 获取精确容量，确认大于源盘53,687,091,200 bytes |
| 启动介质 | 32GB TF 卡 + USB 读卡器 |
| 启动模式 | 优先 Legacy BIOS/CSM；Dell 3020M 支持 Legacy/UEFI，首次按原源系统的 Legacy 启动路径验证 |

重要判断：
- CPU 从 i5-4590 改为 i5-4670T，但仍是 Haswell x86_64，HD Graphics 4600 与原方案相同；不需要因 CPU 或核显型号变化重做通用内核适配。
- H81 与原 B85 都是 Haswell 时代 Intel 芯片组；Linux 通用 AHCI 驱动路径不需要主板专用镜像。
- 16GB 是 OptiPlex 3020M 的规格上限；1333MHz 在 i5-4670T 支持范围内。两条不同品牌内存仍必须完成真实 Memtest，不能仅凭容量和频率判断稳定。
- Dell 3020M 的有线网卡型号不能仅凭产品型号推定：Dell 3020 Micro 规格表与技术手册对 Micro 网络控制器描述存在差异，用户截图也没有显示 PCI ID。必须以实机 `lspci -nnk` 读取到的 vendor/device/subsystem ID 为准。为增加 Realtek 设备的固件覆盖，可在新 ISO 中加入 Debian `firmware-realtek` 包；这只是兼容性补充，不代表已确认本机一定使用 Realtek，也不替代实机驱动绑定、固件加载和网络测试。
- Dell 3020M 使用2.5英寸 SATA 硬盘位；截图中的120GB SSD接口和准确型号仍需实机确认。
- 120GB 标称容量大于50GiB源盘。当前迁移代码按精确字节检查目标盘不得小于源盘，并按目标盘实际末端扩展分区；运行时代码没有固定要求目标盘必须是240GB。但本轮50GiB QEMU完整链路使用240GB虚拟目标盘，120GB目标容量尚需补充针对性容量/扩容验证。
- Dell BIOS 的 F2 用于 BIOS Setup，F12 用于一次性启动菜单；Legacy/UEFI 模式可选。首次实机启动优先选 Legacy/CSM，与旧系统启动方式保持一致。
- 真实网卡 PCI ID、固件加载结果、SATA 模式、SSD精确容量、内存条组合和 BIOS 设置仍需现场读取，不得臆测。
- QEMU Haswell、AHCI、USB 和标准 VGA 只能验证虚拟逻辑，不能证明 Dell 实际主板、Realtek 网卡、HD4600 或 SSD 已通过。

## 5. 重要要求：用户不知道 SSD 序列号

用户无法预先提供新 SSD 的序列号，也不应该被要求在购买或安装前先知道序列号。

**禁止把“用户提前提供 SSD 序列号”作为启动或迁移的前置条件。**

程序必须在新电脑上自动发现磁盘，并向用户展示清楚的信息：
- 磁盘编号；
- 型号；
- 容量（同时显示 GB 和精确字节数）；
- SATA / NVMe / USB 等连接类型；
- 序列号或 WWN（设备能够提供时）；
- 分区数量；
- 文件系统；
- 是否存在 Windows、EFI、NTFS 或其他已有系统特征；
- 是否已挂载；
- 是否为 PAW 启动介质；
- 是否为源盘。

用户通过屏幕上的列表选择目标盘，并根据型号、容量和实际接线确认。用户不需要提前记住或输入序列号。

用户确认后，程序才把当次实际检测到的设备身份写入迁移事务。之后每次写盘前都必须重新读取并核对设备身份。

身份识别优先组合使用：
- 序列号；
- WWN；
- 型号；
- 精确容量；
- 稳定的 /dev/disk/by-id 路径；
- sysfs 物理设备路径；
- 连接总线和分区特征。

如果设备没有可读取的序列号：
- 不得直接失败并要求用户提供一个他不可能知道的值；
- 应使用其他稳定身份信息进行组合识别；
- 如果仍有多块磁盘无法区分，必须提示用户断开无关硬盘或进一步确认；
- 不能猜测，不能仅凭 /dev/sda、/dev/sdb 或容量自动选盘。

**最终原则：程序负责读取和识别序列号，用户负责确认屏幕上展示的目标设备。**

TF 卡自身的身份确认与目标 SSD 身份确认是两件不同的事，不得混淆。

## 6. 启动介质要求

使用定制 Debian Live amd64 ISO，写入现有32GB TF卡和 USB 读卡器。

要求：
- Legacy BIOS / CSM 启动；
- Hybrid ISO；
- 真正的 USB Mass Storage 启动路径；
- PAW 中文控制台；
- tty1 键盘交互；
- 中文字体和可验证的字形显示；
- Memtest86+；
- PAWDATA 持久化分区；
- 网络引导；
- 硬件检查；
- 磁盘身份确认；
- 系统迁移程序；
- 故障保护和日志。

不能只用 QEMU CD-ROM 启动证明 USB 启动成功。

必须将 ISO 写入32GB虚拟 USB 存储设备，再从 USB 设备通过 SeaBIOS 启动；真实 Dell OptiPlex 3020M 和真实读卡器仍需现场验收。

用户之前已经手动格式化过 TF 卡。Codex/DS 没有真实 TF 卡格式化权限，也没有本机管理员权限。不得要求它们绕过权限或擅自格式化、写入真实 TF 卡。

任何真实写卡操作必须由用户明确授权，并由有权限的工具执行。

### PAWDATA

PAWDATA 是追加在启动卡尾部的数据分区，用于保存迁移状态、日志、必要的非敏感配置、恢复信息和持久化标记。

要求首次初始化、写入、重启、再次挂载和持久化校验全部通过。

已有 PAWDATA 时不得无条件重新格式化。

Windows 插入 TF 卡若提示格式化，用户必须取消。

## 7. 启动后的硬件检查

正式克隆前必须检查：

### 内存
- Memtest86+ 能从启动菜单真正启动；
- 真实设备至少完成一个完整测试轮次；
- 错误数为0；
- 操作员确认必须标记为人工确认，不得伪装成密码学证明。

### SSD
- 自动识别型号、容量和设备身份；
- SMART 总体健康；
- 温度；
- 支持的自检；
- 只读表面扫描；
- ATA / I/O 错误；
- 设备掉线和链路异常。

只允许只读扫描和安全自检。禁止写入式 badblocks、随机写入、格式化测试和擦盘测试。

区分 PASS、WARN、FAIL、UNSUPPORTED、UNKNOWN。明确硬件故障必须阻断迁移。

### 显示与网卡
- Intel HD 4600：i915、framebuffer、fbcon、中文字体、tty1；
- Dell 3020M 的实际有线网卡型号以实机 PCI ID 为准，不得从 MT/SFF 规格套用到 Micro；
- 建议加入 Debian `firmware-realtek` 包作为通用固件覆盖，并检查包内文件是否随 live rootfs 进入 ISO；只有在实机识别为相应 Realtek 芯片后，才能判断所需固件和 `r8169` 驱动是否匹配；
- DHCP、DNS、默认路由、断网恢复。

QEMU 标准 VGA 和 e1000 不能冒充真实 HD4600 或 Realtek 网卡通过。

## 8. 源服务器和目标硬盘迁移要求

历史源服务器基线：
- 腾讯云 Ubuntu 24.04.x；
- x86_64；
- 2 vCPU；
- 2GB RAM；
- 50GiB Virtio 系统盘；
- GPT；
- Legacy BIOS；
- ext4。

这些是历史盘点数据，正式迁移前必须重新只读核对。

当前目标盘标称120GB（精确字节数待实机读取）。源盘约50GiB，即53,687,091,200 bytes；目标盘必须通过 blockdev --getsize64 确认实际容量大于源盘。代码按实际目标容量扩展，不得硬编码240GB。50GiB→240GB QEMU通过不等于120GB目标容量专项验证通过。

### 源盘安全
- 必须确认源盘身份、UUID、容量、GPT、文件系统和挂载状态。
- 源盘读取必须只读。
- findmnt 缺失、失败或结果不完整时不能默认放行。
- 无法证明源盘安全状态时必须停止。

### 数据传输
采用 zstd + SSH 流式传输。记录实际读取字节、传输字节、压缩率、速度、中断和错误。不能假设50GiB一定在固定时间内完成。

### 授权事务
授权绑定 migration_id、authorization_id、源盘身份、目标盘身份、容量、数据字节数和迁移状态。克隆、校验、离线修复和扩容属于同一事务。克隆已完成且校验通过后，后续修复失败应允许安全恢复，不得因六小时授权时间戳过期而无条件重传覆盖。任何目标盘身份变化必须停止。

### 独立校验
写入后执行 flush、O_DIRECT 回读和独立 SHA256。字节数必须一致。SHA256 未通过不得进入离线修复。

### 离线修复和扩容
适配云端 Virtio 系统迁移到本地 SATA/AHCI：
- GRUB / grub-pc；
- BIOS Boot；
- initramfs；
- AHCI；
- 网卡驱动；
- fstab；
- UUID / PARTUUID；
- machine-id；
- SSH Host Keys；
- Tailscale 身份。

不得保留依赖旧 /dev/vda、/dev/xvda 的配置。

完成 GPT 备份头移动、根分区扩容和 ext4 扩容，并核对实际容量。

### 自动重启
只有克隆、SHA256、离线修复、GPT/ext4 扩容、预重启交接检查和原子完成记录全部通过后才允许倒计时重启。提供10秒倒计时和取消选项。重启失败必须标记 NEEDS_MANUAL_ACTION。不得把预重启检查写成已经完成首次启动。必须防止重启后再次进入 PAW Live；必要时提示用户移除 TF 卡。

## 9. 最终网络架构

### 设备分工

| 设备 | 长期角色 |
|---|---|
| Windows 本地电脑 | Codex、Tailscale、XrayN |
| 武汉新服务器 | PAW 主服务器、MCP、数据库、自动化业务 |
| 腾讯云旧 VPS | paw-gateway、美国出口、VLESS、Tailscale Exit Node、回退备份 |

### Windows
用户接受 Windows 安装 Tailscale，加入现有 Tailnet。Codex 通过 SSH over Tailscale 直接管理新 Ubuntu。不要求公网 SSH 端口映射。

### 新服务器
使用独立、持久的 Tailscale 设备身份。尽可能接管原 PAW 业务主机名和 MagicDNS 名称。不能复制旧 VPS 的 tailscaled.state、节点私钥或设备身份。

### 旧 VPS
不永久关闭。保留原 Tailscale 身份和美国出口。改造成 paw-gateway，运行必要的 SSH、Xray/VLESS 和 Exit Node。停止重复的 PAW 业务、MCP、轮询和定时任务。保留可恢复的系统快照和必要数据备份。

### VLESS
PAW Live 优先直连 Tailscale；失败时允许用户手动输入自己的 VLESS 配置，通过 Xray 本地代理完成首次登录。真实凭据不得进入 GitHub、日志、Artifact 或对话。tailscaled 后台服务必须真正使用代理，不能只在普通 Shell 设置环境变量。旧 VPS 进入 Rescue 后原 Ubuntu 的 Xray/Tailscale 会停止，克隆传输必须直接走武汉家宽到腾讯云 Rescue SSH。最终 Ubuntu 必须独立、持久加入 Tailnet。

### Exit Node
长期目标是新 PAW 通过 Tailscale 使用旧 VPS 作为美国 Exit Node。Exit Node 和 VLESS 是不同功能，必须分别验证。旧 VPS 作为 Exit Node 必须保持在线；如果 VPS 关机，出口功能不可用。

### 家庭宽带
用户使用中国移动家庭宽带和华为路由器。WAN IPv4、IPv6、CGNAT 状态尚未知。默认架构不得依赖公网 IPv4 或路由器端口映射。SSH 通过 Tailscale；内部 API 只在 localhost/内部网络；外部 MCP 入口使用适合调用方的 Tunnel/Funnel。

## 10. MCP 路径保持要求

用户希望尽可能不重新绑定 MCP。

已知接入方式：
- GPT MCP：独立 Tunnel；
- Claude MCP：Tailscale 相关路径；
- Gemini Spark MCP：Tailscale 相关路径。

历史记录中出现过 MagicDNS 主机名和 /mcp、/paw-r13、/paw-spark、/paw-claude-mcp 等路径，但必须在正式切换前只读审计当前生产配置。

必须区分：
- Linux hostname；
- Tailscale 设备名；
- MagicDNS 名称；
- Tailscale 100.x IP；
- Serve；
- Funnel；
- 独立 Tunnel；
- 服务端口和 URL 路径。

设备改名不会转移旧 Tailscale IP。新服务器接管原名称前，旧节点必须释放名称。Funnel/Tunnel 配置需要按实际情况重新绑定或转发。

GPT 独立 Tunnel 尽量保持原样；Claude 和 Gemini Spark 尽量保持原有接入路径。不得未经核对把私有 Serve 当成公网 Funnel。

## 11. 旧 VPS 备份与切换

旧 VPS 清理前：
1. 制作腾讯云云盘快照或独立备份。
2. 备份 PAW 数据库和关键配置。
3. 备份 MCP 配置。
4. 保留 Tailscale 身份。
5. 保留 Xray/VLESS 配置。
6. 保留 SSH 管理配置。
7. 保留必要 COS 配置。
8. 记录原有 systemd unit、定时任务和服务依赖。

备份不能只放在同一块系统盘。

新服务器业务全部验收后，旧 VPS 才能禁用重复 PAW 业务。旧 VPS 不能与新服务器同时运行相同的业务写入、轮询或定时任务。

回退时必须有清晰的服务切换顺序，防止双写和身份冲突。

## 12. 开发、测试与验收原则

- 所有重要修改必须在独立开发分支。
- 不随意修改 main。
- 不合并 Draft PR，除非用户明确授权。
- 不删除历史 Artifact。
- 每个重要逻辑单元先测试再提交。
- 长任务边执行边落盘，避免长时间只推理。
- 不降低断言来追求全绿。
- 不把静态检查说成运行测试。
- 不把 mock、loop、QEMU、模拟网络说成真实硬件或生产网络。
- 不把不同提交的 PASS 拼成同一版本完整 PASS。
- 最新 ISO 必须对应明确的 Git commit、Actions Run、Artifact 和 SHA256。
- Artifact ZIP 哈希不能替代 ISO 文件哈希。
- 任何真实磁盘写入、真实 TF 卡写入、生产 VPS 修改都需要明确授权。
- 用户没有给出 SSD 序列号时，程序必须自动识别并展示，不得把它变成用户的预置条件。

## 13. 最终验收阶段

### 阶段一：软件和启动介质
最新代码、完整 CI、USB 虚拟启动、中文界面、PAWDATA、Memtest、磁盘身份保护、ISO SHA256。

### 阶段二：实体电脑非破坏性验收
真实 BIOS、USB、核显、内存、网卡、SATA、SSD SMART、只读扫描、家宽网络。

### 阶段三：正式迁移前检查
Rescue SSH、源盘身份、目标盘自动发现与用户确认、源盘只读、持续传输能力、授权、快照和回退。

### 阶段四：正式克隆
经用户授权后执行 zstd/SSH、独立校验、离线修复、扩容、重启和目标盘启动。

### 阶段五：业务与网络接管
新 Tailscale 身份、旧 VPS 网关、Exit Node、GPT Tunnel、Claude MCP、Gemini Spark MCP、Codex SSH、数据库、COS、定时任务、服务隔离和回退。

## 14. 不可改变的最终判断标准

项目不是为了让测试数字好看，也不是为了持续增加功能。

最终只有一个目标：

**用户拿到新电脑后，能够安全、顺利、尽可能少地手动操作，把原来的 PAW 完整迁移过来；迁移后原有 MCP、Codex、网络出口和自动化业务继续正常运行。**

任何架构调整都必须解释：原方案是什么、为什么改变、新方案解决什么实际问题、是否增加用户操作、是否影响 MCP 原有路径、如何回退。未经明确判断，不得擅自改变项目最终目标。
