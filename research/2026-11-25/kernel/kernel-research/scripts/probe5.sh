#!/bin/bash
R=/mnt/e/rom/work/kernel-research/ref
L=/root/linux-tb331fc/arch/arm64/boot/dts/qcom
cd "$R" || exit 1
echo "=== sizes ==="
wc -c CANONICAL.dts repo-tb331fc.dts "$L/sm6225-lenovo-tb331fc.dts"
echo "--- line counts ---"
wc -l CANONICAL.dts repo-tb331fc.dts "$L/sm6225-lenovo-tb331fc.dts"

echo
echo "############ DIFF 1: repo HEAD dts  vs  our local dts ############"
diff -u repo-tb331fc.dts "$L/sm6225-lenovo-tb331fc.dts" > /tmp/d1.diff
echo "hunks: $(grep -c '^@@' /tmp/d1.diff)  added: $(grep -c '^+[^+]' /tmp/d1.diff)  removed: $(grep -c '^-[^-]' /tmp/d1.diff)"
head -120 /tmp/d1.diff

echo
echo "############ DIFF 2: CANONICAL.dts  vs  repo HEAD dts ############"
diff -u CANONICAL.dts repo-tb331fc.dts > /tmp/d2.diff
echo "hunks: $(grep -c '^@@' /tmp/d2.diff)  added: $(grep -c '^+[^+]' /tmp/d2.diff)  removed: $(grep -c '^-[^-]' /tmp/d2.diff)"
echo "--- first 60 lines ---"
head -60 /tmp/d2.diff
echo "--- node-level: which top nodes differ (grep node names in diff) ---"
grep -E '^[+-]\s+[a-z0-9_]+(@[0-9a-f]+)?\s*\{' /tmp/d2.diff | head -40
