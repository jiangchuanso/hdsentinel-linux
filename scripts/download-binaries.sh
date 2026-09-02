#!/usr/bin/env bash
# 构建时从官方源地址下载各发行版二进制到 binaries/。
# 每个文件解包后的 hdsentinel* 统一命名为 hdsentinel(见 build-packages.sh)。
# 已存在的文件会重新下载覆盖, 确保始终来自源地址。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$ROOT/binaries"
MANIFEST="$ROOT/binaries.manifest"
mkdir -p "$BIN_DIR"

# 校验 .zip 文件: 前 4 字节为 PK\x03\x04 (50 4B 03 04) 且体积达到下限。
# 返回 0 表示有效, 1 表示下载损坏(错误页/截断等)。
verify_zip() {
  local f="$1" size magic
  [[ -s "$f" ]] || return 1
  size="$(stat -c%s "$f" 2>/dev/null || wc -c < "$f")"
  # 最小体积下限: 真实 hdsentinel zip 约 1.7MB; 此处仅防御空文件/极小垃圾页
  (( size >= 10240 )) || return 1
  magic="$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')"
  [[ "$magic" == "504b0304" ]] || return 1
  return 0
}

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

  # 下载 + 校验(仅 .zip), 失败重试; 全部失败则明确报"下载损坏, 请重跑"
  local attempt max_attempts=3
  for (( attempt=1; attempt<=max_attempts; attempt++ )); do
    echo "fetch  $url (尝试 $attempt/$max_attempts)"
    if command -v curl >/dev/null 2>&1; then
      curl -fSL "$url" -o "$dest" || true
    else
      wget -q "$url" -O "$dest" || true
    fi
    [[ "$fname" != *.zip ]] && return 0
    if verify_zip "$dest"; then
      echo "  OK: $fname 通过 zip 校验"
      return 0
    fi
    echo "  !! $fname 校验失败(可能下载损坏), 准备重试..."
    rm -f "$dest"
  done
  echo "!! 下载损坏: $fname 始终不是有效 zip, 请重新运行本步骤/工作流以重试下载。" >&2
  return 1
}

# 读取 manifest 第 3 列(URL)逐个下载
while IFS=$'\t' read -r arch src url ext deb rpm iter desc; do
  [[ "$arch" == "ARCH" || -z "$arch" || "$arch" == \#* || -z "$url" ]] && continue
  fetch "$url"
done < "$MANIFEST"

echo "==> 完成, 文件位于 $BIN_DIR"
