#!/bin/bash
set -e
SRC=/mnt/e/rom/work/of/v3/stock/vendor_boot_a.bin
dd if="$SRC" of=/tmp/vb_ramdisk.lz4 bs=4096 skip=1 count=2839 status=none
ls -l /tmp/vb_ramdisk.lz4
lz4 -d -f /tmp/vb_ramdisk.lz4 /tmp/vb_ramdisk.cpio 2>&1 | tail -2
ls -l /tmp/vb_ramdisk.cpio
echo "=== ko entries in ramdisk cpio:"
grep -a -o '[A-Za-z0-9_./-]*\.ko' /tmp/vb_ramdisk.cpio | sort -u | head -60
echo "=== count:"; grep -a -o '[A-Za-z0-9_./-]*\.ko' /tmp/vb_ramdisk.cpio | sort -u | wc -l
echo "=== cpufreq entries:"
grep -a -o '[A-Za-z0-9_./-]*cpufreq[A-Za-z0-9_.-]*' /tmp/vb_ramdisk.cpio | sort -u | head -20
