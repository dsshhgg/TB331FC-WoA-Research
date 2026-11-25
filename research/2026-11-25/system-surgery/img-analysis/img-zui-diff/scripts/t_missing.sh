#!/bin/bash
cd "/mnt/e/rom/TB331FC/刷机包/TB331FC_ZUI_16.0.544/image" || exit 1
OUT=/mnt/e/rom/work/img-zui-diff/zui16.sha256
for f in *; do
  if ! grep -qF "  ./$f" "$OUT"; then
    sz=$(stat -c %s "$f")
    echo "MISSING $f  ($sz B)"
  fi
done
echo "--- done ---"
wc -l < "$OUT"
