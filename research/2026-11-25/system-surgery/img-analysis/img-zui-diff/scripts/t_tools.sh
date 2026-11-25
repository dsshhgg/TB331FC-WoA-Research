#!/bin/bash
for t in lz4 unlz4 lz4c zstd xz cpio dtc python3 gzip; do
  printf '%-10s ' "$t"
  command -v "$t" || echo MISSING
done
echo "--- python lz4 ---"
python3 -c 'import lz4.block, sys; print("lz4.block OK")' 2>&1 | tail -1
echo "--- pip list lz4 ---"
python3 -m pip list 2>/dev/null | grep -i -E 'lz4|zstd' || echo none
