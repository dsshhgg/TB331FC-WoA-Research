#!/bin/bash
cd /mnt/e/rom/work
Z16="/mnt/e/rom/TB331FC/刷机包/TB331FC_ZUI_16.0.544/image"
Z17=/mnt/e/rom/work/zui17_images
echo "=== rescue-matrix 里机上读回的 vbmeta ==="
sha256sum rescue-matrix/reads/vbmeta_a_now.bin rescue-matrix/reads/vbmeta_system_a_now.bin
echo "--- 包内原厂（前 64KB 内的 8192/4096 字节）---"
head -c 8192 "$Z16/vbmeta.img" | sha256sum
head -c 8192 "$Z17/vbmeta.img" | sha256sum
head -c 4096 "$Z16/vbmeta_system.img" | sha256sum
head -c 4096 "$Z17/vbmeta_system.img" | sha256sum
echo
echo "=== boot-backup-20261024 ==="
for f in boot_a.img dtbo_a.img init_boot_a.img vendor_boot_a.img; do
  sz=$(stat -c %s "boot-backup-20261024/$f")
  h64=$(head -c 67108864 "boot-backup-20261024/$f" | sha256sum | cut -d' ' -f1)
  echo "$f size=$sz head64M=$h64"
done
echo
echo "=== 与两版包内同名镜像对比（整文件 sha256）==="
sha256sum boot-backup-20261024/*.img "$Z16/boot.img" "$Z17/boot.img" "$Z16/dtbo.img" "$Z17/dtbo.img" "$Z16/init_boot.img" "$Z17/init_boot.img" "$Z16/vendor_boot.img" "$Z17/vendor_boot.img"
