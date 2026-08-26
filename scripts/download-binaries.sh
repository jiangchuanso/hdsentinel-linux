#!/usr/bin/env bash
# 构建时从官方源地址下载各发行版二进制到 binaries/。
# 每个文件解包后的 hdsentinel* 统一命名为 hdsentinel(见 build-packages.sh)。
# 已存在的文件会重新下载覆盖, 确保始终来自源地址。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$ROOT/binaries"
MANIFEST="$ROOT/binaries.manifest"
EMAILUTIL_URL="https://www.hdsentinel.com/hdslin/hdsentinel_emailutil.zip"
mkdir -p "$BIN_DIR"

fetch() {
  local url="$1" dest="$BIN_DIR/$(basename "$url")"
  echo "fetch  $url"
  if command -v curl >/dev/null 2>&1; then
    curl -fSL "$url" -o "$dest"
  else
    wget -q "$url" -O "$dest"
  fi
}

# 读取 manifest 第 3 列(URL)逐个下载
while IFS=$'\t' read -r arch src url ext deb rpm desc; do
  [[ "$arch" == "ARCH" || -z "$arch" || -z "$url" ]] && continue
  fetch "$url"
done < "$MANIFEST"

# 官方第三方邮件脚本(随包附带, 作参考)
fetch "$EMAILUTIL_URL"

echo "==> 完成, 文件位于 $BIN_DIR"
