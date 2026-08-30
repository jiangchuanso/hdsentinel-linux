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
packaging/email/                   Bash 邮件告警脚本(依赖 curl, SMTP) + 配置示例
packaging/wrapper/                 /usr/bin/hdsentinel 包装器
packaging/cron/                    cron.d 定时任务(每 15 分钟, 以 root 运行)
.github/workflows/build-packages.yml   CI 多架构构建 + 发 Release
```

## 邮件告警功能

`hdsentinel` 命令行本身**没有**发信参数，邮件靠本包集成实现：

- `/opt/hdsentinel/hdsentinel-email-alert`：Bash 脚本（依赖 `curl`），按磁盘解析 `hdsentinel`
  完整报告中的 **健康度 / 性能 / 温度 / 历史最高温度**，任一指标超阈值时经 SMTP 发信。
  支持同一告警冷却（默认 60 分钟），避免持续异常时邮件轰炸。
- `/etc/hdsentinel/email.conf`：SMTP 邮件配置（安装时默认生成，编辑后 `chmod 600`）。
- 由 **cron** 每 15 分钟以 root 触发：`/etc/cron.d/hdsentinel-email` 已随包安装，可编辑改间隔或停用。
- 只在**任一指标超阈值**时发信，全部正常则静默不发送。

### 快速上手

```bash
# 1. 安装 deb/rpm 包后，默认配置已生成在 /etc/hdsentinel/email.conf
sudo chmod 600 /etc/hdsentinel/email.conf

# 2. 编辑 SMTP 与阈值（参考下方说明）
sudoeditor /etc/hdsentinel/email.conf

# 3. 调用服务发测试邮件，验证 SMTP 配置可用（详见下方"发送测试邮件"）
sudo /opt/hdsentinel/hdsentinel-email-alert --test-mail

# 4. 手动试运行——会打印执行情况；若有指标超阈值则真的发信
sudo /opt/hdsentinel/hdsentinel-email-alert

# 5. 定时任务随包安装, 确认 cron 条目存在即可
ls -l /etc/cron.d/hdsentinel-email
```

> 冷却状态目录 `/var/lib/hdsentinel` 由脚本通过 `mkdir -p` 自动创建，无需手工建目录。

默认安装后，SMTP 配置缺失/不完整时脚本会明确报错提示编辑 `/etc/hdsentinel/email.conf`；
配置好有效 SMTP 之前**不会**发任何邮件。
手动运行会打印其中之一：`无告警 / 告警已发送 / 同一告警冷却中`。

### 发送测试邮件

`email.conf` 里的 SMTP 配置是脚本发信的唯一来源。改完配置后，直接**调用告警服务自身**发一封
测试邮件——它复用脚本的 SMTP 发送逻辑（与定时运行完全一致），无需手写任何 curl 命令：

```bash
sudo /opt/hdsentinel/hdsentinel-email-alert --test-mail
```

脚本读取 `/etc/hdsentinel/email.conf`（可用环境变量 `HDSENTINEL_EMAIL_CONF` 换路径），把一封
测试邮件发到 `smtp.to` 配置的收件人。成功打印 `测试邮件已发送 至: ...`；失败打印原因，常见如下：

- `SMTP 配置不完整 (smtp.host / smtp.port / smtp.from 必填)` —— 配置缺失，按上文补全；
- `curl: (67) Access denied` —— 账号/密码错误，或需要认证却漏了 `smtp.user`；
- `curl: (60) SSL certificate problem` —— 自签名证书。测试可临时加 `-k`，生产环境应配置可信 CA；
- 超时或 `Connection refused` —— 检查 `host`/`port` 及防火墙是否放行。

### 配置说明

配置为纯 INI 格式，分三个段。仅支持整行 `#`/`;` 注释（值内的 `#` 不会被当作注释）。
段名与键名不区分大小写。

```ini
[smtp]
# SMTP 服务器。常见端口组合:
#   25  = 明文 / STARTTLS(use_tls)
#   465 = SMTPS(use_ssl)
#   587 = STARTTLS(use_tls)
host = localhost
port = 25
# 登录凭据; 留空表示匿名 / 本机中继
user =
password =
# 加密方式: 二者互斥, 需与端口匹配。
#   use_ssl=true  -> SMTPS(465, 全程加密)
#   use_tls=true  -> 先用明文连 25/587 再 STARTTLS 升级
#   二者都 false   -> 25 端口纯明文(本机中继/内网)
use_ssl = false
use_tls = false
# 收发件人。`to` 支持逗号分隔多个地址
from = hdsentinel@yourhost.local
to = admin@example.com, oncall@example.com
subject_prefix = [HD Sentinel Alert]

[alert]
# 只在任一指标超阈值时发告警信; 全部正常则不发信。
# (早期版本的 mode = daily「每次运行都发完整报告」已移除, 残留的 mode 键会被忽略)
# 各磁盘阈值:
health_min = 60          # 任一磁盘健康度低于此值(%)告警
performance_min = 60     # 任一磁盘性能低于此值(%)告警
temp_max = 55            # 任一磁盘温度高于此值(℃)告警
highest_temp_max = 65    # 任一磁盘历史最高温度高于此值(℃)告警
# 同一告警冷却时间(分钟), 0 表示不冷却; 避免指标持续异常时邮件轰炸
cooldown_minutes = 60
# 记录上次告警签名与时间的状态文件(用于冷却)
state_file = /var/lib/hdsentinel/email-alert-state.json
# 邮件正文格式:
#   text = 纯文本报告(默认)
#   html = 执行 "hdsentinel -html -r <临时文件>", 把 HTML 报告作为邮件正文(同官方脚本);
#          阈值解析仍基于 stdout 的文本报告, HTML 只影响邮件正文
report_format = text

[hdsentinel]
# hdsentinel 二进制路径, 及额外参数。
# extra_args 留空输出完整报告(推荐, 可解析各指标); 填 "-solid" 则输出单行摘要。
path = /opt/hdsentinel/hdsentinel
extra_args =
```

### SMTP 配置示例

25 端口明文本机中继（如内网 Postfix，无认证）：

```ini
[smtp]
host = localhost
port = 25
user =
password =
use_ssl = false
use_tls = false
```

587 端口 STARTTLS（多数邮箱服务商）：

```ini
[smtp]
host = smtp.example.com
port = 587
user = admin@example.com
password = your-app-password
use_ssl = false
use_tls = true
```

465 端口隐式 SMTPS：

```ini
[smtp]
host = smtp.example.com
port = 465
user = admin@example.com
password = your-app-password
use_ssl = true
use_tls = false
```

### 定时触发

包内自带 `/etc/cron.d/hdsentinel-email`，每 **15 分钟以 root** 运行告警脚本：

```cron
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=""
*/15 * * * * root /opt/hdsentinel/hdsentinel-email-alert >> /var/log/hdsentinel-email.log 2>&1
```

cron 输出已重定向到 `/var/log/hdsentinel-email.log`（会持续增长，建议按需配置 logrotate）。
`PATH` 显式声明是因为 cron 的默认 PATH 很窄，需确保能找到 `curl`。要改间隔就改 `*/15`（或注释该行停用）。

### 告警判定与冷却

- 脚本逐盘比对健康度/性能/温度/历史最高温度与阈值，若有超阈值则发**一封**邮件列出所有异常；
  全部正常则不发信。
- **冷却**：脚本对异常集合（按 `device|model|metric|value` 排序后
  sha256 取前 16 位十六进制）生成签名。同一签名在 `cooldown_minutes`（默认 60）分钟内被抑制；
  不同的异常则立即发送。签名与时间戳保存在 `state_file`
  （`/var/lib/hdsentinel/email-alert-state.json`）。

### 常见问题排查

- **`错误: 未安装 curl`** —— 安装 `curl`，脚本发信用它。
- **没发信也没报错** —— 检查 `smtp.to` 是否配置，以及 `email.conf` 是否存在
  （SMTP 配置缺失时脚本会明确报错，并提示编辑 `/etc/hdsentinel/email.conf`）。
- **邮件收不到** —— 用 `sudo` 手动运行脚本看 `curl` 退出码，并检查 `/var/log/hdsentinel-email.log`。
- 主题中的非 ASCII 字符会自动按 RFC 2047 编码为 `=?UTF-8?B?…?=`；正文为 `UTF-8 / 8bit`。

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
- **本仓库的打包脚本、cron 单元、邮件告警配置与文档**（不包含上述二进制）：
  采用 MIT 许可，见 [LICENSE](LICENSE)。
