# PAW v2.6.1 整改复审

状态：候选实现已整理；GitHub Actions 最终构建与虚拟测试尚未完成，本报告不代表验收通过。

## 本轮范围

- SSH 远端 zstd 压缩、原始流回退、字节计数和独立 SHA256 复核。
- Rescue Mode 源盘身份发现、只读挂载状态检查和登记门槛。
- ext4 PAWDATA 分区、启动挂载和虚拟介质持久性测试。
- 中文授权门槛、目标序列号核对、硬件健康门槛和写入前阻断。
- SMART 自检轮询、只读读扫超时、Memtest86+ 独立启动项、克隆后离线修复。
- Xray Reality 客户端配置字段校正、Rescue/恢复系统阶段隔离、依赖版本冻结及 Git 历史扫描。

## 证据状态

本地 PowerShell 语法解析、Bash `-n`、Python 编译、Windows 静态安全检查、工作区公开安全扫描和当前本地可达 Git 对象扫描通过。此 Windows 环境未安装 Linux 构建依赖，不能在本机生成 ISO。

第一次候选 Actions 在 ISO 构建阶段因冻结 Debian snapshot 的 `trixie-updates` Release 有效期过期而失败；未生成候选 ISO。已为 live-build 的 chroot APT 显式关闭快照有效期检查，并增加手动、末六位序列号确认的 PAWDATA 首次准备入口；修订后的候选需重新构建。真实 Rescue SSH、真实磁盘、真实 TF 卡写入和物理启动均未执行。

## 仍需关闭的验收项

- 独立、可信的 Memtest86+ 结果回传/签名证明尚未实现；报告只能保持 WARN/BLOCKED，不能信任普通日志文件。
- 离线 Ubuntu 网卡适配及回滚路径尚未在目标硬件验证。
- ISO 重复构建的逐字节可复现性没有当前候选的双构建证据。
- 物理写卡须由用户确认最终 ISO 后另行执行；本轮不写盘。
