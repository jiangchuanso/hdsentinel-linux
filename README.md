# Hard Disk Sentinel Linux — deb/rpm Packaging (with E-mail Alert)

**English | [简体中文](README-zh.md)**

Wraps the [HD Sentinel Linux console edition](https://www.hdsentinel.com/hard_disk_sentinel_linux.php)
binaries for every supported CPU architecture into `.deb` / `.rpm` packages, and bundles an
e-mail alert integration. Packaging is done in **GitHub Actions**.

## Architecture matrix

| Arch (package) | deb Architecture | rpm Architecture | Source binary        | Notes            |
|----------------|------------------|-----------------|----------------------|------------------|
| i386           | i386             | i386            | hdsentinel-019b.gz     | 32-bit x86       |
| amd64          | amd64            | x86_64          | hdsentinel-020c-x64.zip| 64-bit x86       |
| armhf          | armhf            | armv7hl         | hdsentinel-armv7.gz    | ARMv7 (RPi4/NAS) |
| arm64          | arm64            | aarch64         | hdsentinel-armv8.zip   | ARMv8 / ARM64    |
| armel          | armel            | armv5tel        | hdsentinelarm          | ARMv5 (NAS, raw) |

> The source filename → download URL mapping lives in `binaries.manifest`. `hdsentinel-020-arm.gz`
> (ARMv6, older Pi) and `hdsentinel-armv7.gz` (ARMv7) are both 32-bit ARM and both map to the
> `armhf` architecture, but are packaged as **two separate armhf packages with different
> iteration numbers** (deb: `hdsentinel_0.20-1_armhf.deb` from armv7, `hdsentinel_0.20-2_armhf.deb`
> from 020-arm; rpm: `hdsentinel-0.20-1.armv7hl.rpm` and `hdsentinel-0.20-2.armv6hl.rpm`, with the
> rpm architecture labelled armv7hl / armv6hl respectively). Only one can be installed per
> architecture — pick what fits your device.
> All binaries are downloaded from the official `/hdslin/` source during the build; they are not
> committed to this repository.

## Directory layout

```
binaries.manifest                  arch → source file mapping
binaries/                          binaries downloaded from the official source at build time (.gitignore'd)
scripts/download-binaries.sh       fetch binaries from the official site (if missing)
scripts/build-packages.sh          generate deb/rpm with fpm
packaging/email/                   Bash e-mail alert script (requires curl, SMTP) + config example
packaging/wrapper/                 /usr/bin/hdsentinel wrapper
packaging/cron/                    cron.d schedule (every 15 min, runs as root)
.github/workflows/build-packages.yml   CI multi-arch build + Release
```

## E-mail alert

The `hdsentinel` CLI itself has **no** mail option, so sending e-mail is implemented by this package:

- `/opt/hdsentinel/hdsentinel-email-alert`: a Bash script (requires `curl`) that parses
  **Health / Performance / Temperature / Highest temperature** per disk from the full `hdsentinel`
  report and sends an SMTP e-mail (via curl) whenever any metric exceeds its threshold.
  Includes per-alert cooldown (60 min by default) to avoid mail flooding during persistent failures.
- `/etc/hdsentinel/email.conf`: SMTP config installed by default — edit it, then `chmod 600`.
- Triggered by **cron** every 15 minutes as root: `/etc/cron.d/hdsentinel-email` is installed with
  the package. Edit it to change the interval or disable it.
- Mail is sent **only when a metric breaches its threshold**; a fully healthy run sends nothing.

### Quick start

```bash
# 1. Install the package (deb/rpm); the default config is already at /etc/hdsentinel/email.conf
sudo chmod 600 /etc/hdsentinel/email.conf

# 2. Edit SMTP + thresholds (see reference below)
sudoeditor /etc/hdsentinel/email.conf

# 3. Send a test mail through the alert service itself (see "Sending a test mail")
sudo /opt/hdsentinel/hdsentinel-email-alert --test-mail

# 4. Test a run manually — prints what it would do, and actually sends mail if a
#    threshold is breached
sudo /opt/hdsentinel/hdsentinel-email-alert

# 5. The scheduler ships with the package: verify the cron entry is present
ls -l /etc/cron.d/hdsentinel-email
```

> The cooldown state directory `/var/lib/hdsentinel` is created automatically by the script via
> `mkdir -p`, so no manual step is needed.

If SMTP settings are missing or incomplete, the script prints a clear error telling you to edit
`/etc/hdsentinel/email.conf`; it does **not** send anything until valid SMTP is configured.
A manual run prints one of: `无告警 / 告警已发送 / 同一告警冷却中`.

### Sending a test mail

The SMTP settings in `email.conf` are the **only** source the script uses for sending. After
editing the config, send a test mail by **calling the alert service itself** — it reuses the
script's own SMTP logic (identical to scheduled runs), no curl commands needed:

```bash
sudo /opt/hdsentinel/hdsentinel-email-alert --test-mail
```

The script reads `/etc/hdsentinel/email.conf` (override with `HDSENTINEL_EMAIL_CONF`) and delivers
a test mail to the recipients in `smtp.to`. On success it prints `测试邮件已发送 至: ...`; on
failure it prints the reason. Common failures:

- `SMTP 配置不完整 (smtp.host / smtp.port / smtp.from 必填)` — settings are missing, fill them in;
- `curl: (67) Access denied` — wrong username/password, or auth is required but `smtp.user` is empty;
- `curl: (60) SSL certificate problem` — self-signed certificate. Add `-k` temporarily for testing;
  configure a trusted CA for production;
- Timeout or `Connection refused` — check `host`/`port` and firewall rules.

### Configuration reference

The config is plain INI, grouped into three sections. Only full-line `#`/`;` comments are
supported (inline `#` in a value is kept literally). Section/key names are case-insensitive.

```ini
[smtp]
# SMTP server. Common port combos:
#   25  = plaintext / STARTTLS (use_tls)
#   465 = SMTPS (use_ssl)
#   587 = STARTTLS (use_tls)
host = localhost
port = 25
# Credentials; leave blank for anonymous / local relay
user =
password =
# Encryption: these two are mutually exclusive and must match the port.
#   use_ssl=true  -> SMTPS (465, encrypted end-to-end)
#   use_tls=true  -> STARTTLS upgrade on 25/587
#   both false    -> plaintext on 25 (local relay / LAN)
use_ssl = false
use_tls = false
# Sender / recipients. `to` accepts a comma-separated list.
from = hdsentinel@yourhost.local
to = admin@example.com, oncall@example.com
subject_prefix = [HD Sentinel Alert]

[alert]
# Mail is sent only when a metric breaches its threshold; a healthy run sends nothing.
# (The old mode = daily "mail the full report on every run" has been removed; a leftover
#  mode key is ignored.)
# Per-disk thresholds:
health_min = 60          # alert when any disk Health  < this (%)
performance_min = 60     # alert when any disk Performance < this (%)
temp_max = 55            # alert when any disk Temperature > this (℃)
highest_temp_max = 65    # alert when any disk Highest Temp > this (℃)
# Same-alert cooldown in minutes (0 = never cooldown); avoids mail storms
cooldown_minutes = 60
# State file storing the last alert signature + time (for cooldown)
state_file = /var/lib/hdsentinel/email-alert-state.json
# Mail body format:
#   text = plain-text report (default)
#   html = run "hdsentinel -html -r <tmpfile>" and use that HTML report as the mail body
#          (same as the official script). Thresholds are still parsed from the stdout text report;
#          this only changes the mail body.
report_format = text

[hdsentinel]
# Path to the hdsentinel binary, and any extra args.
# Leave extra_args empty for the full report (recommended, so all metrics parse).
# Use "-solid" for a single-line summary instead.
path = /opt/hdsentinel/hdsentinel
extra_args =
```

### SMTP examples

Plaintext local relay (e.g. a LAN Postfix, no auth):

```ini
[smtp]
host = localhost
port = 25
user =
password =
use_ssl = false
use_tls = false
```

STARTTLS on port 587 (e.g. a typical mailbox provider):

```ini
[smtp]
host = smtp.example.com
port = 587
user = admin@example.com
password = your-app-password
use_ssl = false
use_tls = true
```

Implicit SMTPS on port 465:

```ini
[smtp]
host = smtp.example.com
port = 465
user = admin@example.com
password = your-app-password
use_ssl = true
use_tls = false
```

### Scheduling

The package installs `/etc/cron.d/hdsentinel-email`, which runs the alert script as **root** every
15 minutes:

```cron
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=""
*/15 * * * * root /opt/hdsentinel/hdsentinel-email-alert >> /var/log/hdsentinel-email.log 2>&1
```

Output goes to `/var/log/hdsentinel-email.log` (it grows over time — add a logrotate rule if you
care). `PATH` is declared explicitly because cron's default PATH is very narrow and must find `curl`.
To change the interval, edit the `*/15` field (or comment the line to disable).

### Alerting & cooldown

- The script compares each disk's Health / Performance / Temperature / Highest-Temp against the
  thresholds and sends **one** mail listing every breach. If nothing is breached, no mail is sent.
- **Cooldown**: the script signs the set of breaches (sorted `device|model|metric|value`, sha256,
  first 16 hex). The same signature is suppressed for `cooldown_minutes` (default 60); a *different*
  breach always sends immediately. The signature + timestamp live in `state_file`
  (`/var/lib/hdsentinel/email-alert-state.json`).

### Troubleshooting

- **`错误: 未安装 curl`** — install `curl`; the script needs it for SMTP.
- **No mail, no error** — check `smtp.to` is set, and that `email.conf` exists (if SMTP settings are
  missing, the script prints a clear error telling you to edit `/etc/hdsentinel/email.conf`).
- **Mail not arriving** — run the script manually with `sudo` to see the `curl` exit code, and check
  `/var/log/hdsentinel-email.log`.
- Non-ASCII subjects are RFC 2047 encoded (`=?UTF-8?B?…?=`) automatically; bodies are `UTF-8 / 8bit`.

## Building locally (Linux)

```bash
sudo apt-get install -y ruby ruby-dev build-essential rpm unzip gzip
sudo gem install fpm
./scripts/download-binaries.sh        # download each release from the official /hdslin/ source
./scripts/build-packages.sh           # all architectures; or amd64 / arm64 ...
ls dist/
```

> On an x64 host, `fpm -a <arch>` can produce packages for any architecture (it only sets metadata,
> it does not run/compile the binary), so no qemu is needed. Real-world verification still has to
> happen on the target CPU.

## Building with GitHub Actions

1. Initialize this directory as a git repository and push it to GitHub.
2. Binaries are not stored in the repo: CI runs `download-binaries.sh` to fetch them from the
   official `/hdslin/` source at build time; every unpacked `hdsentinel*` is renamed to `hdsentinel`.
3. Trigger **Actions → Run workflow** manually, or push a `v*` tag to build automatically and
   publish a Release.
4. Artifacts: one `.deb` + one `.rpm` per architecture, uploaded as artifacts; attached to the
   Release when built from a tag.

## License

- **HD Sentinel binaries**: closed-source **freeware**, **© H.D.S. Hungary (HD Sentinel)**.
  This repository does **not** include or redistribute these files — they are downloaded
  temporarily from the official source `https://www.hdsentinel.com/hdslin/` at build time and
  bundled into the packages. Before publishing the resulting `.deb`/`.rpm` publicly, verify that
  the HD Sentinel license permits redistribution of its binaries.
- **This repository's build scripts, cron unit, e-mail alert config and documentation**
  (not the binaries above): MIT-licensed, see [LICENSE](LICENSE).
