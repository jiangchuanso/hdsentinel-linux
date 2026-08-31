#!/usr/bin/env bash
# 构建时从官方源地址下载各发行版二进制到 binaries/。
# 每个文件解包后的 hdsentinel* 统一命名为 hdsentinel(见 build-packages.sh)。
# 已存在的文件会重新下载覆盖, 确保始终来自源地址。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$ROOT/binaries"
MANIFEST="$ROOT/binaries.manifest"
mkdir -p "$BIN_DIR"

fetch() {
  local url="$1"
  # 去掉 Windows 提交可能带入的 CRLF / 空白 / 查询串, 避免文件名带控制字符
  url="${url%$'\r'}"
  url="${url%$'\n'}"
  local fname="${url##*/}"
  fname="${fname%%[[:space:]]*}"
  fname="${fname%%\?*}"
  # 用 bash 原生展开取文件名, 不依赖 basename; 与 local url 分开声明, 避免取值顺序 bug
  local dest="$BIN_DIR/$fname"
  mkdir -p "$BIN_DIR"
  echo "fetch  $url"
  if command -v curl >/dev/null 2>&1; then
    curl -fSL "$url" -o "$dest"
  else
    wget -q "$url" -O "$dest"
  fi
}

# 读取 manifest 第 3 列(URL)逐个下载
while IFS=$'\t' read -r arch src url ext deb rpm iter desc; do
  [[ "$arch" == "ARCH" || -z "$arch" || "$arch" == \#* || -z "$url" ]] && continue
  fetch "$url"
done < "$MANIFEST"

echo "==> 完成, 文件位于 $BIN_DIR"
