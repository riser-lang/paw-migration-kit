# PAW 公开仓库安全审计（v2.7）

审计时间：2026-11-09 UTC
仓库：`riser-lang/paw-migration-kit`，保持 Public；未修改权限，未删除 Actions 运行或历史 Artifact。

## 当前文件与历史

- `scripts/ci/check-public-safety.py` 扫描当前工作区：PASS。
- `scripts/ci/check-public-history.py` 扫描全部可达 Git 对象：PASS（本轮约 428 个对象）。
- 扫描覆盖：私钥块、GitHub/Tailscale/COS 凭据、云 AK/SK、IPv4、邮箱、个人 Windows 路径、账号名、二进制提交。
- 标准 GPT 分区类型 GUID 和白名单回环地址按预期放行；`getty@tty1.service` 作为 systemd 单元名放行，不属于邮箱。
- 当前仓库未发现真实私钥、Token、OAuth、Tailscale auth key、VLESS UUID、COS 凭据、生产主机地址或用户个人路径。

## 本轮新增证据的处理

- 最终 Run `42615204317` 的测试报告、软件清单、构建来源和 ISO SHA256 已放入 `reports/evidence-v2.7/`。
- 原始 `live-build.log` 和完整 `software-packages.lock` **没有放入仓库**：前者包含 Debian 镜像解析出的公网 IPv4，后者包含会被正则误判为 IPv4 的版本号。它们仍保留在 Actions Artifact 中。
- `reports/evidence-v2.7/` 中的文件已通过当前文件安全扫描。
- 没有把任何生产服务器地址、真实根 UUID、密钥或授权信息写入报告。

## Actions 日志抽查

- 已抽查最近成功/失败运行的构建、QEMU、PAWDATA、虚拟克隆、修复和网络测试日志。
- 未在测试报告中原样打印真实凭据；运行日志中的 Debian 镜像 IPv4 属于公共发行基础设施，不作为用户生产地址。
- 未重新下载全部历史 Artifact 二进制进行逐字节复扫；历史 Artifact 元数据未删除。

## 仍需注意

- 真实生产凭据、Rescue 临时私钥和 Tailscale 授权 URL 只能出现在运行时 RAM/控制台，不得提交。
- `OPERATOR_CONFIRMED` 是操作员记录，不是密码学证明。
- 公开仓库的 Actions Artifact 也可能被有权限者下载；不要把真实生产数据或镜像上传为 Artifact。
