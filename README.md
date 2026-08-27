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
packaging/email/                   Bash e-mail alert script (requires curl) + config example
packaging/wrapper/                 /usr/bin/hdsentinel wrapper
packaging/systemd/                 e-mail alert service + timer
packaging/cron/                    cron.d fallback config
.github/workflows/build-packages.yml   CI multi-arch build + Release
```

## E-mail alert

The `hdsentinel` CLI itself has **no** mail option, so sending e-mail is implemented by this package:

- `/opt/hdsentinel/hdsentinel-email-alert`: a Bash script (requires `curl`) that parses
  **Health / Performance / Temperature / Highest temperature** per disk from the full `hdsentinel`
  report and sends an SMTP e-mail (via curl) whenever any metric exceeds its threshold.
  Includes per-alert cooldown (60 min by default) to avoid mail flooding during persistent failures.
- `/etc/hdsentinel/email.conf.example`: config template — copy it to `email.conf`, edit the SMTP
  settings, then `chmod 600`.
- Two ways to trigger it:
  - **systemd** (recommended): `systemctl enable --now hdsentinel-email.timer` (checks every 15 min)
  - **cron**: `/etc/cron.d/hdsentinel-email` is installed with the package (runs as root every 15 min)

> Keep **only one** of the two schedulers: after enabling the systemd timer, remove/comment out
> `/etc/cron.d/hdsentinel-email`, otherwise it fires twice (alert mode is saved by cooldown, but
> daily mode will send duplicate mails).
- Modes: `alert` (send only when a threshold is exceeded) or `daily` (send the full report on every
  run), see `alert.mode` in the config.

Config example:
```ini
[alert]
health_min = 60
performance_min = 60
temp_max = 55
highest_temp_max = 65
cooldown_minutes = 60
```

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
- **This repository's build scripts, systemd/cron units, e-mail alert config and documentation**
  (not the binaries above): MIT-licensed, see [LICENSE](LICENSE).
