# DS 干净环境接管报告（2026-11-10）

- 主机：`VM-63-23-ubuntu`
- 用户：`agentuser`（uid 1002，gid 1003）
- 系统：Ubuntu 24.04，kernel `6.8.0-101-generic`，KVM guest
- 仓库：<https://github.com/riser-lang/paw-migration-kit>
- 新工作区：`/home/agentuser/paw-migration-kit`
- 新分支：`vm/ds-clean-handover-20261110`
- 分支基线：`d64071251bb3075d9cb26a967dfcba6cf139250a`
- 首个新提交：`8e6e300997ffbc32652cfe20e5abf9f96e10bf1f`
  （`Enforce a fail-closed fbcon 16x16 font gate before disk writes`）
- 字体槽位修复提交：`d5f1a859d4349faffc770bc0736c915fecea7110`
  （`Keep the console font within the 512-slot kernel budget`）
- fbcon 检测修复提交：`4572280721cfa71f62f8ddd3d246043ad3849422`
  （`Wait for fbcon and match real vtconsole names before loading the font`）
- CI 并发隔离提交：`4af304e26e21357c68bac7fa882c661712969dc9`
  （`Scope CI concurrency to the branch under test`）
- 当前分支 CI：Run `42825407549`（`4af304e`）**SUCCESS**，artifact
  `13769479260`；测试 ISO 953,155,584 bytes，SHA256
  `c34cb13712acbe49247fadf3f088a1a4d9765d481303df6e2856c26da2e068fb`
- 报告生成时间：2026-11-10 UTC

本报告只记录实际执行过的清理、验证和当前状态。没有触碰生产腾讯云 VPS、
Rescue Mode、生产磁盘、PAW 数据库、MCP、Tailscale、Funnel、Xray、Nginx、
443、防火墙、COS、真实 TF 卡或任何真实硬盘；没有修改仓库可见性，没有删除
GitHub 历史 Artifact，没有合并 PR #1/#2。

## 1. 旧 PAW 现场清理清单

### 1.1 清理前检查

- `id`：`agentuser`，groups 只有 `agentuser`；没有可用 root 权限。
- `systemd-detect-virt`：`kvm`；`/proc/1/cgroup`：`0::/init.scope`。
- 旧工作区归属核对：`MANIFEST-before.txt` 记录所有候选目录均为
  `agentuser:agentuser`，旧工作区 remote 为
  `https://github.com/riser-lang/paw-migration-kit.git`，旧分支
  `fix/v2.6.2-final-readiness`。
- 旧 PAW 任务/定时任务：`systemctl list-units`、`systemctl list-timers`、`ps`
  未发现 PAW 专属服务/定时器/进程；唯一匹配是当前 DS 会话本身。没有停止或杀死
  任何旧 PAW PID，没有停止 DS 服务。
- `crontab -l` 因 `/var/spool/cron/crontabs/agentuser` 权限被拒绝；没有发现
  PAW 专属用户 cron 或 system timer。
- 清理前磁盘：`50G total, 40G used, 8.0G available`（`/dev/vda2`）。

### 1.2 隔离目录

清理采用“先改名为隔离目录、从 GitHub 重新克隆、验证后再删除”的顺序：

`/home/agentuser/paw-cleanup-isolation-20261110`

隔离目录在删除前 `du -sh` 为约 **13G**。其中：

| 条目 | `du -sh` 约值 | 说明 |
|---|---:|---|
| `paw-migration-kit/` | 3.4M | 旧 Git 工作区 |
| `paw-qemu/` | 5.0G | 旧 QEMU 测试镜像/实验残料 |
| `paw-fb/` | 6.2G | 旧 framebuffer/CJK 截图与 QEMU 证据 |
| `paw-artifact/` | 896M | 旧 Actions artifact 解包，含 ISO 副本 |
| `paw-artifact-reports/` | 40K | 旧 artifact 报告 |
| `paw-delivery-v2.7/` | 132K | 旧交付整理 |
| `paw-final2/` | 48K | 旧最终材料 |
| `paw-final-evidence/` | 336K | 旧最终证据 |
| `paw-iso-artifact/` | 23M | 旧 ISO artifact |
| `paw-segment1-evidence/` | 6.8M | 第一段证据 |
| `paw-test-network/` | 8.0K | 旧网络测试状态 |
| `paw-test-state/` | 48K | 旧测试状态 |
| `paw-artifact-42606712998.zip` | 1.0M | 旧 artifact ZIP |
| `paw-v2.7-cloud-delivery.zip` | 36K | 旧交付 ZIP |
| `paw-sudo-evidence.txt` | 1.8K | 旧 sudo 证据 |
| `MANIFEST-before.txt` | 1.6K | 隔离前清单 |

### 1.3 实际删除

删除前再次校验：

```bash
iso=/home/agentuser/paw-cleanup-isolation-20261110
[ "$(realpath "$iso")" = "/home/agentuser/paw-cleanup-isolation-20261110" ]
rm -rf --one-file-system -- "$iso"
```

- **没有**使用 `rm -rf ~/*`、`rm -rf /home/agentuser/*` 或任何宽泛通配符。
- **没有**删除整个 `$HOME`，**没有**删除非 PAW 项目。
- 删除后确认路径不存在。

实际释放：

- 删除前 `df -B1`：used `41,952,952,320`，avail `8,496,828,416`。
- 删除后 `df -B1`：used `29,046,034,432`，avail `21,403,746,304`。
- 释放字节：**12,906,917,888 bytes（约 12.0 GiB）**。
- 当前 `df -h`：`50G total, 28G used, 20G available, 58%`。

说明：隔离只是同文件系统改名，所以隔离后、删除前 `df` 仍显示约 8G 可用；
只有显式删除隔离目录后才真正回收空间。

### 1.4 没有删除/没有触碰

- Ubuntu 系统、账户、sudo 配置文件、系统服务。
- Git、GitHub CLI、Python、Bash、Node、DS runtime。
- GitHub 登录、DS 模型登录、代理配置、SSH 配置和密钥。
- 非 PAW 目录：`paw_s4a_po`（120K）、`midtest`（28K）、`sshroot`（36K）、
  `tools`（107M）等。
- `~/.dsh/jobs/` 调度记录（只查看，不删除）。
- `hermes`、`xray-client`、`vela` 等服务。
- GitHub 仓库可见性、历史 Artifact、PR #1/#2。

## 2. 新 GitHub 工作区与分支

- 路径：`/home/agentuser/paw-migration-kit`
- 来源：重新 `git clone`，不是复制旧工作树。
- `origin`：`https://github.com/riser-lang/paw-migration-kit.git`
- 当前分支：`vm/ds-clean-handover-20261110`
- 基线：`d64071251bb3075d9cb26a967dfcba6cf139250a`
  （`fix/v2.6.2-final-readiness` 最新远端 HEAD；没有回退、没有覆盖原分支）
- `main`：`0d6aefd093984a65f40d19e1fae584dee623b8e9`（未修改）
- PR #1：`0128110788ee3c649bf51ad9c3ff22eca769b8ab`，OPEN/DRAFT，未改动
- PR #2：head `d640712...`，OPEN/DRAFT，未合并
- 新分支已推送：`origin/vm/ds-clean-handover-20261110`
- 首个提交：`8e6e300997ffbc32652cfe20e5abf9f96e10bf1f`
- 文档提交在本报告生成后单独提交；最终 HEAD 以 `git log` 为准。

## 3. 工具与登录验证

| 项目 | 实际结果 |
|---|---|
| GitHub CLI | `gh 2.103.3`；`gh auth status` 显示登录 `riser-lang`，token scopes `gist, read:org, repo, workflow` |
| Git | `2.43.0`；remote fetch/push 正常 |
| Python | `3.11.17`（`/home/agentuser/.hermes/hermes-agent/venv/bin/python3`） |
| Bash | `5.2.21(1)-release` |
| Node | `v22.22.2` |
| ShellCheck | `0.11.0`（`/home/agentuser/tools/shellcheck-v0.11.0/shellcheck`） |
| DS runtime | `DSH_HOME=/home/agentuser/.dsh`，profile `agent`，当前会话标识已省略；`.dsh/.credentials.yaml` 存在；本任务由 DS V4.1 Flash 执行 |
| QEMU | 无系统级 `qemu-system-x86_64`；保留 portable QEMU `8.2.2`：`/home/agentuser/tools/qemu-portable-20261110/sysroot/usr/bin/qemu-system-x86_64`，`qemu-img` 同目录；必须设置 `LD_LIBRARY_PATH=/home/agentuser/tools/qemu-portable-20261110/sysroot/usr/lib/x86_64-linux-gnu` |
| KVM | `/dev/kvm` 不存在；QEMU 只能用 TCG |
| 代理 | `HTTPS_PROXY=socks5h://127.0.0.1:10808`、`HTTP_PROXY=socks5h://127.0.0.1:10808` 可用 |
| SSH | `~/.ssh` 权限 700；`config`、`id_ed25519`、`id_ed25519.pub`、`known_hosts` 权限 600，未改动 |
| sudo | **当前 bash 通道不可用**：`sudo -n id` 报 `The "no new privileges" flag is set`；`/proc/self/status` 为 `NoNewPrivs: 1`、`CapEff: 0000000000000000`。这是执行通道限制，不是 sudoers 配置损坏；本报告不声称本机 sudo 可用 |

## 4. 当前项目阶段

- P0-1 字体失败安全门禁：**已实现，本机 26/26 故障注入通过**。只有同启动、
  fbcon 已绑定、主 16x16 PSF2、manifest/实际 SHA256 一致、`setfont` 返回 0、
  报告 `paw.console-font.v2` 且 `status=PASS` 才允许写盘；8x16 回退为 `WARN`
  并拒绝；缺失/损坏/哈希错/加载失败/报告缺失/过期一律阻断。只读诊断可用。
- 新分支 CI（实际失败历史，不能隐藏）：
  - Run `42812469612`（HEAD `8e6e300`）在构建字体时失败：
    “needs 418 non-ASCII glyphs but only 417 free”。已定位为字体门禁新增的
    中文“槽”字使唯一字形数超限，改成“个字形”后，用 Unifont 15.1.01 实际
    构建通过（417 个 CJK/UI + ASCII，512 slots），提交 `d5f1a85`。
  - Run `42817841755`（HEAD `d5f1a85`）构建和字体校验通过，但在 CJK/PAWDATA
    套件失败：内核实际把 vtconsole 名称写成 `(M) frame buffer device`，而新
    字体服务按完整字符串 `frame buffer device` 比较，误判为未绑定 fbcon，
    跳过 `setfont` 并报告 FAIL；屏幕因此仍是 VGA 字形，PAWDATA 门禁也拒绝
    写入。这是本轮新门禁引入的真实回归，不是测试噪声。
  - 修复提交 `4572280721cfa71f62f8ddd3d246043ad3849422`：等待 `/dev/fb0`/
    fbcon 绑定，按名称后缀匹配真实 vtconsole，并在尚未绑定时仍加载已校验的
    字体（报告保持 FAIL，绝不打开写盘门禁）；服务移除过早的
    `ConditionPathExists=/dev/tty1`。
  - Run `42824906347`（`4572280`）因工作流共享 concurrency 组，被原开发分支
    的 Run `42821382664` 阻塞而排队；该排队运行已取消，未作为失败或成功证据。
    已提交 `4af304e` 把 concurrency 组按分支隔离，触发 Run `42825407549`。
  - Run `42825407549`（`4af304e`）：**SUCCESS**。font-gate 26/26、CJK QEMU
    25/25、PAWDATA 12/12、虚拟故障 39/39、repair 19/19、network 17/17、
    finalize 36/36、TTY 56/56（0 blocked）。测试 ISO 953,155,584 bytes，
    SHA256 `c34cb13712acbe49247fadf3f088a1a4d9765d481303df6e2856c26da2e068fb`；
    artifact `13769479260`。不能把历史 `42804949796` 当作新证据。
- P0-2 文档：七份文件已按当前分支更新；本报告是新增交接报告。
- 第二阶段 Ubuntu 24.04 克隆盘：**VIRTUAL_BOOT_PASS / BLOCK_CLONE_PATH_OPEN**。
  已完成真实 raw → 240GB 稀疏虚拟盘、项目 clone/verify（显式
  `PAW_SIMULATION=1`）、GPT/ext4 扩容、真实 GRUB/initramfs、SeaBIOS 启动和
  无 seed 第三次启动登录；生产块/SSH clone 和完整项目离线修复仍 OPEN。证据：
  `reports/PAW-STAGE2-REAL-UBUNTU-BOOT-20261110.md`。
- 第三阶段完整迁移链路：**OPEN**。
- 第四阶段最终 ISO + 下载后 ISO SHA256：**OPEN**。

本机已实际执行的非 root 验证：

- `font-gate-tests.py`：**26 assertions, 0 failed**。
- Finalize：**36 passed, 0 failed**。
- TTY 本机：**55 passed, 0 failed, 1 blocked**（`/dev/ptmx` 不可用）；
  CI Run `42825407549`：**56 passed, 0 failed, 0 blocked**。
- ShellCheck `--severity=error`：无命中。
- Bash `-n`、Python compile：PASS。
- `PUBLIC-SAFETY=PASS`；`PUBLIC-HISTORY=PASS`（849 objects）。

## 5. 下一步

1. 在新分支提交 P0-2 文档和本报告，并确保工作区干净。
2. Stage 2 剩余缺口：在块设备/受限 CI loop 上执行生产 clone 入口和完整
   `paw-offline-repair.sh`，再启动目标盘。虚拟 Ubuntu 启动、GPT/ext4 扩容、
   真实 GRUB/initramfs/SeaBIOS 启动和第三次启动登录已有证据，禁止用 stub 重做。
3. Stage 3/4 仍需真实迁移链和最终 ISO 下载后 SHA256；本报告不声称完成。
4. Stage 3：完整迁移链路真实入口整合。
5. Stage 4：最终 ISO；下载 ISO 后重算 ISO SHA256，绝不把 ZIP 哈希当 ISO 哈希；
   更新中文使用说明和回滚说明。
6. 真实 ASUS/TF/SSD/腾讯云 Rescue/正式迁移仍需现场和单独授权，当前不声称完成。
