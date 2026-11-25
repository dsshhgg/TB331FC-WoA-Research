#!/bin/bash
# mk_initramfs.sh - build the minimal TB331FC initramfs (target: <= 5 MB).
#
# Inputs
#   $BB        static aarch64 busybox          (default /mnt/e/rom/work/linux-boot/build/busybox)
#   $SRC       init + gadget.sh                (default /mnt/e/rom/work/linux-boot/scripts/initramfs)
# Output
#   $OUT/initramfs-tb331fc.cpio.gz  + a size report
set -eu
OUT=${OUT:-/mnt/e/rom/work/linux-boot/out}
BB=${BB:-/mnt/e/rom/work/linux-boot/build/busybox}
SRC=${SRC:-/mnt/e/rom/work/linux-boot/scripts/initramfs}
BUILD=${BUILD:-/mnt/e/rom/work/linux-boot/build}
LIMIT=$((5*1024*1024))

mkdir -p "$OUT" "$BUILD"
[ -f "$BB" ] || { echo "missing static aarch64 busybox: $BB (run get_busybox.sh)"; exit 1; }
file "$BB" | grep -q 'ARM aarch64' || { echo "$BB is not aarch64"; exit 1; }

STAGE="$BUILD/initramfs-root"
rm -rf "$STAGE"
mkdir -p "$STAGE"/{bin,sbin,proc,sys,dev,tmp,run,newroot,lib/firmware}

install -m 0755 "$BB"              "$STAGE/bin/busybox"
install -m 0755 "$SRC/init"        "$STAGE/init"
install -m 0755 "$SRC/gadget.sh"   "$STAGE/bin/gadget.sh"

# Pre-create the applet symlinks so /init does not depend on
# `busybox --install` succeeding at boot.  Verified present in the staged
# binary (BusyBox v1.36.1-osm0sis, 353 applets) by scripts/test_busybox_qemu.sh.
APPLETS="sh ash mount umount cat echo ls mkdir mknod sleep dmesg cut grep sed awk
 poweroff reboot switch_root setsid sync dd free ps kill blkid find ln rm cp mv chmod
 uname df head tail tr date id mountpoint printf test env modprobe insmod lsmod
 lsblk blkid vi less tar gzip gunzip zcat"
for a in $APPLETS; do
    ln -sf busybox "$STAGE/bin/$a"
done
for a in poweroff reboot switch_root modprobe insmod; do
    ln -sf ../bin/busybox "$STAGE/sbin/$a"
done

# shell syntax check of the two scripts (needs qemu-aarch64-static; skipped if absent)
Q=$(command -v qemu-aarch64-static || true)
if [ -n "$Q" ]; then
    "$Q" "$STAGE/bin/busybox" sh -n "$STAGE/init"      && echo "  init: syntax OK"
    "$Q" "$STAGE/bin/busybox" sh -n "$STAGE/bin/gadget.sh" && echo "  gadget.sh: syntax OK"
else
    echo "  (qemu-aarch64-static not found - skipping script syntax check)"
fi

# A couple of static device nodes so the very first busybox call cannot fail
# even if devtmpfs mounting is deferred.
mknod -m 622 "$STAGE/dev/console" c 5 1 2>/dev/null || true
mknod -m 666 "$STAGE/dev/null"    c 1 3 2>/dev/null || true

( cd "$STAGE" && find . -mindepth 1 -printf '%P\n' | LC_ALL=C sort | cpio -o -H newc --owner 0:0 --quiet ) \
  | gzip -9 > "$OUT/initramfs-tb331fc.cpio.gz"

RAW=$(mktemp)
( cd "$STAGE" && find . -mindepth 1 -printf '%P\n' | LC_ALL=C sort | cpio -o -H newc --owner 0:0 --quiet ) > "$RAW"
GZ=$(stat -c%s "$OUT/initramfs-tb331fc.cpio.gz")
RAW_SZ=$(stat -c%s "$RAW")
rm -f "$RAW"

echo "--- initramfs ---"
echo "  raw cpio : $RAW_SZ bytes"
echo "  gz cpio  : $GZ bytes  ($(( GZ / 1024 )) KiB)"
echo "  limit    : $LIMIT bytes (5 MiB)"
if [ "$GZ" -gt "$LIMIT" ]; then echo "  !! OVER LIMIT"; exit 1; fi
echo "  contents :"
(cd "$STAGE" && find . -mindepth 1 | sed 's/^/    /')
