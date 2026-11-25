#!/bin/bash
# 增量输出 sha256，避免 sort 缓冲导致长时间无进度
set -u
DIR="$1"
OUT="$2"
cd "$DIR" || exit 1
: > "$OUT"
# 先小文件（<100MB），再大文件串行
find . -maxdepth 1 -type f -size -100M -print0 | xargs -0 -P4 -I{} sh -c 'sha256sum "$1" >> "$2"' _ {} "$OUT"
find . -maxdepth 1 -type f -size +100M -print0 | xargs -0 -I{} sh -c 'echo "  big: $1" >&2; sha256sum "$1" >> "$2"' _ {} "$OUT"
sort -k2 -o "$OUT" "$OUT"
echo "DONE $(wc -l < "$OUT") lines"
