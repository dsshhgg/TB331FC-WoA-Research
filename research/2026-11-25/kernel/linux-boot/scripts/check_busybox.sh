#!/bin/bash
# check_busybox.sh - offline sanity check of the static aarch64 busybox:
#   * static?  * aarch64?  * does it export the applets our init needs?
BB=${1:-/mnt/e/rom/work/linux-boot/build/busybox}
echo "file: $(file -b "$BB")"
readelf -l "$BB" 2>/dev/null | grep -q INTERP && echo "!! dynamic (has PT_INTERP)" || echo "static: yes (no PT_INTERP)"
strings -a "$BB" | grep -m1 -E '^BusyBox v[0-9]' || echo "(version string not found)"

NEED="sh ash mount umount cat echo ls mkdir mknod sleep dmesg cut grep sed awk poweroff reboot switch_root setsid mdev gzip gunzip sync dd free ps kill blkid find ln rm cp mv chmod uname df head tail tr date id mountpoint"

strings -a "$BB" | sort -u > /tmp/bb.strings
miss=0
for a in $NEED; do
    if grep -Fxq "$a" /tmp/bb.strings; then :; else echo "  MISSING applet: $a"; miss=$((miss+1)); fi
done
echo "missing applets: $miss"
# also report the applet count the binary advertises
echo "applet-name-like strings: $(strings -a "$BB" | grep -cE '^[a-z][a-z0-9_.-]{1,14}$')"
