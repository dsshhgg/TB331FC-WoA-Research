#!/bin/bash
A=/mnt/e/rom/work/tools/avbtool.py
Z16="/mnt/e/rom/TB331FC/刷机包/TB331FC_ZUI_16.0.544/image"
Z17=/mnt/e/rom/work/zui17_images
O=/mnt/e/rom/work/img-zui-diff/work/x
cd "$O"
python3 "$A" info_image --image "$Z16/vbmeta.img" > vb16.info 2>&1
python3 "$A" info_image --image "$Z17/vbmeta.img" > vb17.info 2>&1
python3 "$A" info_image --image "$Z16/vbmeta_system.img" > vbs16.info 2>&1
python3 "$A" info_image --image "$Z17/vbmeta_system.img" > vbs17.info 2>&1
echo "=== vbmeta 描述符里的分区名 / Image Size（ZUI16 vs ZUI17）==="
for f in vb16 vb17; do
  echo "--- $f ---"
  grep -E 'Partition Name:|Image Size:' "$O/$f.info" | paste - - 2>/dev/null | sed 's/[[:space:]]\+/ /g'
done
echo
echo "=== vbmeta_system 全量（ZUI16）==="
cat "$O/vbs16.info"
echo "=== vbmeta_system 全量（ZUI17）==="
cat "$O/vbs17.info"
