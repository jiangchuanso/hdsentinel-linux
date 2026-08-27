# Hard Disk Sentinel Linux — deb/rpm 打包（含邮件告警）

**[English](README.md) | 简体中文**

把 [HD Sentinel Linux 控制台版](https://www.hdsentinel.com/hard_disk_sentinel_linux.php)
的各 CPU 架构二进制封装为 `.deb` / `.rpm`，并集成邮件发送警告功能。
打包在 **GitHub Actions** 中完成。

## 架构矩阵

| 架构 (包名) | deb Architecture | rpm Architecture | 源二进制 | 说明 |
|-------------|------------------|-----------------|----------|------|
| i386        | i386             | i386            | hdsentinel-019b.gz     | 32-bit x86 |
| amd64       | amd64            | x86_64          | hdsentinel-020c-x64.zip| 64-bit x86 |
| armhf       | armhf            | armv7hl         | hdsentinel-armv7.gz    | ARMv7 (RPi4/NAS) |
| arm64       | arm64            | aarch64         | hdsentinel-armv8.zip   | ARMv8 / ARM64 |
| armel       | armel            | armv5tel        | hdsentinelarm          | ARMv5 (NAS, 未压缩) |

> 源文件名/下载 URL 映射见 `binaries.manifest`。`hdsentinel-020-arm.gz`(ARMv6 老版 Pi)
> 与 `hdsentinel-armv7.gz`(ARMv7) 同为 32-bit ARM、都归 `armhf` 架构，二者用不同
> 迭代号打成**两个独立的 armhf 包**（deb: `hdsentinel_0.20-1_armhf.deb` 来自 armv7，
> `hdsentinel_0.20-2_armhf.deb` 来自 020-arm；rpm: `hdsentinel-0.20-1.armv7hl.rpm`
> 与 `hdsentinel-0.20-2.armv6hl.rpm`，rpm 架构已分别标注 armv7hl / armv6hl）。同架构只能装其一，按需选用。
> 所有二进制均在构建时从官方 `/hdslin/` 源地址下载，不提交进仓库。

## 目录结构

```
binaries.manifest                  架构 → 源文件映射
binaries/                          构建时从官方源地址下载的二进制(.gitignore 忽略)
scripts/download-binaries.sh       从官网抓取二进制(若不存在)
scripts/build-packages.sh          用 fpm 生成 deb/rpm
packaging/email/                   Bash 邮件告警脚本(依赖 curl) + 配置示例
packaging/wrapper/                 /usr/bin/hdsentinel 包装器
packaging/systemd/                 email 告警 service + timer
packaging/cron/                    cron.d 兜底配置
.github/workflows/build-packages.yml   CI 多架构构建 + 发 Release
```

## 邮件告警功能

`hdsentinel` 命令行本身**没有**发信参数，邮件靠本包集成实现：

- `/opt/hdsentinel/hdsentinel-email-alert`：Bash 脚本（依赖 curl），按磁盘解析 `hdsentinel` 完整报告中的
  **健康度 / 性能 / 温度 / 历史最高温度**，任一指标超阈值时经 SMTP（curl）发信。
  支持同一告警冷却（默认 60 分钟），避免持续异常时邮件轰炸。
- `/etc/hdsentinel/email.conf.example`：配置模板，复制为 `email.conf` 并改 SMTP 后 `chmod 600`。
- 两种触发方式：
  - **systemd**（推荐）：`systemctl enable --now hdsentinel-email.timer`（每 15 分钟检查一次）
  - **cron**：`/etc/cron.d/hdsentinel-email` 已随包安装（每 15 分钟 root 运行）

> 两种定时方式**只保留一种**：启用 systemd timer 后请删除/注释
> `/etc/cron.d/hdsentinel-email`，否则会重复触发（alert 模式靠 cooldown 兜底，
> daily 模式会重复发信）。
- 模式：`alert`（仅超阈值发信）或 `daily`（每次运行都发完整报告），见配置 `alert.mode`。

配置示例：
```ini
[alert]
health_min = 60
performance_min = 60
temp_max = 55
highest_temp_max = 65
cooldown_minutes = 60
```

## 本地构建（Linux）

```bash
sudo apt-get install -y ruby ruby-dev build-essential rpm unzip gzip
sudo gem install fpm
./scripts/download-binaries.sh        # 从官方 /hdslin/ 源地址下载各发行版
./scripts/build-packages.sh           # 全部架构; 或 amd64 / arm64 ...
ls dist/
```

> 在 x64 主机上用 `fpm -a <arch>` 即可产出任意架构的包（仅设置元数据，
> 不实际运行/编译二进制），无需 qemu。要真机验证运行仍需在对应 CPU 上测试。

## GitHub Actions 构建

1. 本目录初始化为 git 仓库并推送到 GitHub。
2. 二进制不在仓库中：CI 运行 `download-binaries.sh` 从官方 `/hdslin/` 源地址现抓，
   每个文件解包后的 `hdsentinel*` 统一命名为 `hdsentinel`。
3. **Actions → Run workflow** 手动触发；或对 `v*` tag 推送自动构建并发 Release。
4. 产物：每个架构一个 `.deb` + 一个 `.rpm`，上传为 artifact；打 tag 时附到 Release。

## 许可 / License

- **HD Sentinel 二进制**：**闭源 Freeware**，
  **版权归 H.D.S. Hungary（HD Sentinel）所有**。本仓库**不包含、也不重新分发**这些文件——
  构建时仅从官方源地址 `https://www.hdsentinel.com/hdslin/` 临时下载并打进包中。
  将构建产物（`.deb`/`.rpm`）发布到公开渠道前，请确认 HD Sentinel 的许可条款允许再分发其二进制。
- **本仓库的打包脚本、systemd/cron 单元、邮件告警配置与文档**（不包含上述二进制）：
  采用 MIT 许可，见 [LICENSE](LICENSE)。
