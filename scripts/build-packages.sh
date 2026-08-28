#!/usr/bin/env bash
# 用 fpm 把各架构二进制 + email 告警集成打包成 deb/rpm。
# 用法:
#   ./scripts/build-packages.sh            # 构建全部架构
#   ./scripts/build-packages.sh amd64      # 仅构建指定架构
#   PKG_VERSION=0.20 ./scripts/build-packages.sh arm64
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$ROOT/binaries"
OUT_DIR="$ROOT/dist"
PKG_VER="${PKG_VERSION:-0.20}"
PKG_ITER="${PKG_ITER:-1}"
MANIFEST="$ROOT/binaries.manifest"
mkdir -p "$OUT_DIR"

command -v fpm >/dev/null 2>&1 || { echo "错误: 未安装 fpm (gem install fpm)"; exit 1; }

build_one() {
  local arch="$1" src="$2" ext="$3" debarch="$4" rpmarch="$5" iter="$6" desc="$7"
  echo "==> 构建架构: $arch ($desc)  源=$src"

  local stage; stage="$(mktemp -d)"
  mkdir -p "$stage/opt/hdsentinel" "$stage/usr/bin" "$stage/etc/hdsentinel" \
           "$stage/etc/cron.d"

  # 1) 提取对应架构的 hdsentinel 可执行文件
  local bin="$stage/opt/hdsentinel/hdsentinel"
  case "$ext" in
    gz)
      gunzip -c "$BIN_DIR/$src" > "$bin"
      ;;
    zip)
      local tmp found
      tmp="$(mktemp -d)"
      unzip -o "$BIN_DIR/$src" -d "$tmp" >/dev/null
      # zip 内可执行文件命名不固定(大小写/版本后缀差异), 先按 *entinel*(不区分大小写)匹配;
      # 再兜底取体积最大的常规文件(二进制通常最大)
      found="$(find "$tmp" -type f -iname '*entinel*' -print -quit)"
      if [[ -z "$found" ]]; then
        found="$(find "$tmp" -type f -printf '%s\t%p\n' | sort -n | tail -n1 | cut -f2-)"
      fi
      if [[ -z "$found" ]]; then
        echo "错误: $src 解压后未找到任何文件"
        rm -rf "$tmp"
        exit 1
      fi
      cp "$found" "$bin"
      rm -rf "$tmp"
      ;;
    raw)
      cp "$BIN_DIR/$src" "$bin"
      ;;
    *)
      echo "未知压缩格式: $ext"; rm -rf "$stage"; exit 1 ;;
  esac
  chmod 0755 "$bin"

  # 2) 打包 email 告警集成
  cp "$ROOT/packaging/email/hdsentinel-email-alert" "$stage/opt/hdsentinel/"
  chmod 0755 "$stage/opt/hdsentinel/hdsentinel-email-alert"
  # 默认配置文件不带 .example 后缀(模板源为 packaging/email/email.conf.example);
  # 含 SMTP 密码, 安装时收紧为 0600。
  cp "$ROOT/packaging/email/email.conf.example" "$stage/etc/hdsentinel/email.conf"
  chmod 0600 "$stage/etc/hdsentinel/email.conf"

  # 3) 命令行包装器 (/usr/bin/hdsentinel)
  cp "$ROOT/packaging/wrapper/hdsentinel" "$stage/usr/bin/hdsentinel"
  chmod 0755 "$stage/usr/bin/hdsentinel"

  # 4) cron.d(每 15 分钟以 root 运行告警脚本)
  cp "$ROOT/packaging/cron/hdsentinel-email" "$stage/etc/cron.d/hdsentinel-email"

  local common=(
    -s dir -C "$stage"
    -n hdsentinel -v "$PKG_VER" --iteration "${iter:-$PKG_ITER}"
    --description "Hard Disk Sentinel Linux console edition ($desc). Bundled with e-mail alert integration (SMTP)."
    --maintainer "HD Sentinel Packaging <packaging@local>"
    --vendor "H.D.S. Hungary" --license "Freeware (HD Sentinel © H.D.S. Hungary)"
    --url "https://www.hdsentinel.com"
    --category "utils" --provides hdsentinel --provides hdsentinel-email-alert
    --depends curl --rpm-os linux
  )

  echo "    -> deb ($debarch, iter ${iter:-$PKG_ITER})"
  # --deb-recommends 是 deb 专属选项(旧版 fpm 无通用 --recommends); cron 是唯一调度方式, 一并装上
  fpm "${common[@]}" --deb-recommends cron -t deb -a "$debarch" \
      -p "$OUT_DIR/hdsentinel_${PKG_VER}-${iter:-$PKG_ITER}_${debarch}.deb" .

  echo "    -> rpm ($rpmarch, iter ${iter:-$PKG_ITER})"
  # 不为 rpm 加 Recommends: 旧版 fpm 未必支持 --rpm-recommends, 且 RHEL 系默认已带 cronie
  fpm "${common[@]}" -t rpm -a "$rpmarch" \
      -p "$OUT_DIR/hdsentinel-${PKG_VER}-${iter:-$PKG_ITER}.${rpmarch}.rpm" .

  rm -rf "$stage"
  echo "==> 产物已写入 $OUT_DIR"
}

if [[ $# -gt 0 ]]; then
  for want in "$@"; do
    found=0
    while IFS=$'\t' read -r arch src url ext deb rpm iter desc; do
      arch="${arch%$'\r'}"; src="${src%$'\r'}"; url="${url%$'\r'}"; ext="${ext%$'\r'}"
      deb="${deb%$'\r'}"; rpm="${rpm%$'\r'}"; iter="${iter%$'\r'}"; desc="${desc%$'\r'}"
      [[ "$arch" == "ARCH" || -z "$arch" ]] && continue
      if [[ "$arch" == "$want" ]]; then
        build_one "$arch" "$src" "$ext" "$deb" "$rpm" "$iter" "$desc"; found=1
      fi
    done < "$MANIFEST"
    [[ "$found" -eq 1 ]] || { echo "未知架构: $want"; exit 1; }
  done
else
  while IFS=$'\t' read -r arch src url ext deb rpm iter desc; do
    arch="${arch%$'\r'}"; src="${src%$'\r'}"; url="${url%$'\r'}"; ext="${ext%$'\r'}"
    deb="${deb%$'\r'}"; rpm="${rpm%$'\r'}"; iter="${iter%$'\r'}"; desc="${desc%$'\r'}"
    [[ "$arch" == "ARCH" || -z "$arch" ]] && continue
    build_one "$arch" "$src" "$ext" "$deb" "$rpm" "$iter" "$desc"
  done < "$MANIFEST"
fi
