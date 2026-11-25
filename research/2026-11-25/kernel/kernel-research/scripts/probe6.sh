#!/bin/bash
R=/mnt/e/rom/work/kernel-research/ref
L=/root/linux-tb331fc/arch/arm64/boot/dts/qcom
cd "$R" || exit 1
echo "=== line ending check ==="
for f in CANONICAL.dts repo-tb331fc.dts "$L/sm6225-lenovo-tb331fc.dts"; do
  cr=$(grep -c $'\r' "$f"); tot=$(wc -l < "$f")
  echo "$f : lines=$tot crlf_lines=$cr"
done

echo
echo "############ DIFF 1b: repo dts vs local dts, ignoring CR ############"
diff --strip-trailing-cr -u repo-tb331fc.dts "$L/sm6225-lenovo-tb331fc.dts" > /tmp/d1b.diff
echo "real diff lines: $(wc -l < /tmp/d1b.diff)  hunks: $(grep -c '^@@' /tmp/d1b.diff)"
cat /tmp/d1b.diff | head -80

echo
echo "############ DIFF 2b: CANONICAL vs repo dts, ignoring CR ############"
diff --strip-trailing-cr -u CANONICAL.dts repo-tb331fc.dts > /tmp/d2b.diff
echo "real diff lines: $(wc -l < /tmp/d2b.diff)  hunks: $(grep -c '^@@' /tmp/d2b.diff)"
grep -E '^[+-]' /tmp/d2b.diff | grep -viE '^[+-]{3}' | head -100
