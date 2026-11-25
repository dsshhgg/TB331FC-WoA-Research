#!/bin/bash
# Fetch a static aarch64 busybox from the Tsinghua Ubuntu mirror and stage it
# in $OUT (default /mnt/e/rom/work/linux-boot/build).
set -u
OUT=${OUT:-/mnt/e/rom/work/linux-boot/build}
mkdir -p "$OUT"
cd "$OUT" || exit 1

# 1) try the local TWRP/OrangeFox style busybox first (usually static aarch64)
LOCAL="/mnt/e/rom/work/of-slim/work/root/sbin/busybox"
if [ -f "$LOCAL" ]; then
  cp -f "$LOCAL" ./busybox.test
  if file ./busybox.test | grep -q 'ARM aarch64'; then
    if ! readelf -l ./busybox.test 2>/dev/null | grep -q INTERP; then
      mv -f ./busybox.test ./busybox
      echo "OK: using local static aarch64 busybox ($(stat -c%s ./busybox) bytes)"
      exit 0
    fi
  fi
  rm -f ./busybox.test
fi

# 2) download from the mirror, discovering the exact pool filename
base=https://mirrors.tuna.tsinghua.edu.cn/ubuntu/pool/main/b/busybox
name=$(curl -sSL "$base/" | grep -o 'busybox-static_[^"]*_arm64\.deb' | sort -u | tail -1)
if [ -z "$name" ]; then echo "FAIL: cannot list mirror pool"; exit 1; fi
echo "downloading $name"
curl -sSLO "$base/$name" || { echo "FAIL: download"; exit 1; }
rm -rf x && mkdir -p x
dpkg-deb -x "$name" x || { echo "FAIL: dpkg-deb"; exit 1; }
cp -f x/bin/busybox ./busybox
chmod +x ./busybox
file ./busybox
echo "OK: $(stat -c%s ./busybox) bytes"
