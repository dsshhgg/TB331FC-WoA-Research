#!/bin/bash
# =============================================================================
# verify-installer.sh — 校验"改完的 product 镜像里是不是我们那个 APK"
#   bash verify-installer.sh <product_a.img> <期望的 apk>
# =============================================================================
set -u
IMG=${1:?usage: verify-installer.sh <product_a.img> <expected.apk>}
EXP=${2:?usage: verify-installer.sh <product_a.img> <expected.apk>}
P=/priv-app/MIUIPackageInstallerVariants/MIUIPackageInstallerVariants.apk
T=$(mktemp -d)
debugfs -R "dump $P $T/in.apk" "$IMG" 2>&1 | grep -v '^debugfs'
echo "in-image : $(sha256sum $T/in.apk | cut -d' ' -f1)"
echo "expected : $(sha256sum $EXP     | cut -d' ' -f1)"
cmp -s "$T/in.apk" "$EXP" && echo "cmp: IDENTICAL" || echo "cmp: DIFFERENT"
echo "--- stat/eattr ---"
debugfs -R "stat $P" "$IMG" 2>&1 | grep -E "Type|Mode|Size|uid|gid"
debugfs -R "ea_list $P" "$IMG" 2>&1 | grep -o 'security.selinux ([0-9]*) = .*' | head -1
echo "--- avb ---"
python /mnt/e/rom/work/tools/avbtool.py verify_image --image "$IMG" \
  && echo "avb: OK" || echo "avb: FAILED"
rm -rf "$T"
