#!/bin/bash
cd /mnt/e/rom/work/img-boot-group/dtbo_extract || exit 1
for f in *.dtb; do
  dtc -q -I dtb -O dts -o "${f%.dtb}.dts" "$f" 2>/dev/null
done
# vendor_boot base dtb
dd if=/mnt/e/rom/work/of/v3/stock/vendor_boot_a.bin of=/tmp/base.dtb bs=1 skip=11636736 count=1290690 2>/dev/null
dtc -q -I dtb -O dts -o /mnt/e/rom/work/img-boot-group/dtbo_extract/vendor_boot_base.dts /tmp/base.dtb 2>/dev/null
ls -la | tail -5
echo "--- dts count ---"
ls *0.dts 2>/dev/null | wc -l
ls *.dts | wc -l
