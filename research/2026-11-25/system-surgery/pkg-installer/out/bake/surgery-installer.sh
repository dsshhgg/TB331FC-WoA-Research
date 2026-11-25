#!/bin/bash
# =============================================================================
# surgery-installer.sh — 用 debugfs 把新 APK 塞回 product 镜像
#
#   bash surgery-installer.sh <product.img(ext4数据区)> <MIUIPackageInstallerVariants.apk>
#
# 照抄 E:\rom\work\kit-baked\surgery.sh 的已验证做法：
#   - 路径：product image 的根就是 /，所以是 /priv-app/... 而不是 /product/priv-app/...
#   - SELinux：security.selinux 必须 NUL 结尾（26 字节 "u:object_r:system_file:s0\0"），
#     所以先用 printf 落一个 .bin 再 ea_set -f，不要直接 ea_set 字符串
#   - 时间戳钉 1230768000（2009-01-01 00:00 UTC，ROM 惯例）→ 产物可复算
# =============================================================================
set -u
IMG=${1:?usage: surgery-installer.sh <product.img> <apk>}
APK=${2:?usage: surgery-installer.sh <product.img> <apk>}
P=/priv-app/MIUIPackageInstallerVariants/MIUIPackageInstallerVariants.apk
PIN_EPOCH=1230768000
FAIL=0
say() { echo "[surgery-installer] $*"; }

L=$(mktemp -d)
printf 'u:object_r:system_file:s0\0' > "$L/system_file.bin"
dbg() { debugfs -w -R "$*" "$IMG" 2>&1 | grep -v '^debugfs ' ; }

[ -f "$APK" ] || { say "!! 没有 $APK"; exit 2; }
ls -l "$APK"

say "replace $P <- $APK"
dbg "rm $P"
dbg "write $APK $P" >/dev/null
dbg "sif $P mode 0100644"
dbg "sif $P uid 0"
dbg "sif $P gid 0"
dbg "ea_set -f $L/system_file.bin $P security.selinux"
dbg "sif $P mtime $PIN_EPOCH" >/dev/null
dbg "sif $P ctime $PIN_EPOCH" >/dev/null
dbg "sif $P atime $PIN_EPOCH" >/dev/null

ST=$(debugfs -R "stat $P" "$IMG" 2>&1)
SIZE=$(stat -c %s "$APK")
echo "$ST" | grep -q "Type: regular"            || { say "!! 文件没建出来"; FAIL=1; }
echo "$ST" | grep -q "Mode:  0644"              || { say "!! mode 不对"; FAIL=1; }
echo "$ST" | grep -q "Size: $SIZE"              || { say "!! size 不对（want $SIZE）"; FAIL=1; }
debugfs -R "ea_list $P" "$IMG" 2>&1 | grep -q "security.selinux" || { say "!! 没有 selinux xattr"; FAIL=1; }
say "stat: $(echo "$ST" | grep -E 'Type|Mode|Size' | tr '\n' ' ')"
say "xattr: $(debugfs -R "ea_list $P" "$IMG" 2>&1 | grep 'security.selinux' | head -1)"
rm -rf "$L"
exit $FAIL
