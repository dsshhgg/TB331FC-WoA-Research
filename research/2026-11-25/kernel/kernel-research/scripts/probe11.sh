#!/bin/bash
echo "=== build env ==="
nproc; free -g | head -2; df -h /root /tmp | sed -n '1,4p'
echo "=== gcc/ld version ==="
aarch64-linux-gnu-gcc --version | head -1
echo "=== tree sizes ==="
du -sh /root/linux-tb331fc 2>/dev/null
echo "--- how much of it is build artifacts? ---"
K=/root/linux-tb331fc
echo "source-only estimate (excluding *.o/*.a/vmlinux/Image/.tmp):"
find "$K" -type f ! -name '*.o' ! -name '*.a' ! -name '*.cmd' ! -name '*.dtb' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {printf "%.2f GB\n", s/1024/1024/1024}'
echo "object files:"
find "$K" -name '*.o' -printf '%s\n' 2>/dev/null | awk '{s+=$1; n++} END {printf "%d files, %.2f GB\n", n, s/1024/1024/1024}'
echo "=== a clean v6.14 tarball size for reference ==="
cd /tmp && timeout 60 curl -sIL https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.10.tar.xz 2>&1 | grep -iE 'content-length|HTTP/' | head -4
