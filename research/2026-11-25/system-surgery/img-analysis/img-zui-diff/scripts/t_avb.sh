#!/bin/bash
A=/mnt/e/rom/work/tools/avbtool.py
Z16="/mnt/e/rom/TB331FC/刷机包/TB331FC_ZUI_16.0.544/image"
Z17=/mnt/e/rom/work/zui17_images
cd /mnt/e/rom/work/img-zui-diff
echo "dtbo SAME entries: $(python3 a10_dtbo.py 2>/dev/null | grep -c ' SAME$')"
for f in vbmeta vbmeta_system; do
  echo "===== $f  ZUI16 ====="
  python3 "$A" info_image --image "$Z16/$f.img" 2>&1 | head -40
  echo "===== $f  ZUI17 ====="
  python3 "$A" info_image --image "$Z17/$f.img" 2>&1 | head -40
done
