#!/bin/bash
# test_busybox_qemu.sh - run the staged aarch64 busybox under qemu-user and
# check every applet our init script relies on.
Q=${Q:-qemu-aarch64-static}
BB=${1:-/mnt/e/rom/work/linux-boot/build/busybox}
[ -x "$Q" ] || Q=$(command -v qemu-aarch64-static) || { echo "no qemu-aarch64-static"; exit 1; }
echo "== $($Q "$BB" 2>&1 | head -1)"
echo "== applets: $($Q "$BB" --list 2>/dev/null | wc -l)"
$Q "$BB" --list 2>/dev/null | sort > /tmp/bb.applets
NEED="sh ash mount umount cat echo ls mkdir mknod sleep dmesg cut grep sed awk poweroff reboot switch_root setsid mdev gzip gunzip sync dd free ps kill blkid find ln rm cp mv chmod uname df head tail tr date id mountpoint"
miss=0
for a in $NEED; do
    grep -Fxq "$a" /tmp/bb.applets || { echo "  MISSING: $a"; miss=$((miss+1)); }
done
echo "  missing=$miss"
echo "== sample of applets:"; head -12 /tmp/bb.applets | paste -sd' '
exit $miss
