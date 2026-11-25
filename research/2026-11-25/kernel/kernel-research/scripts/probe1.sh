#!/bin/bash
K=/root/linux-tb331fc
echo "=== exists? ==="
ls -d "$K" 2>/dev/null || echo "MISSING"
cd "$K" || exit 1
echo "=== git repo? ==="
git rev-parse --is-inside-work-tree 2>&1 | head -2
echo "=== Makefile head ==="
head -6 Makefile
echo "=== tree size ==="
du -sh . 2>/dev/null
find . -type f 2>/dev/null | wc -l
echo "=== dts dir sm6225/sm6115 ==="
ls -la arch/arm64/boot/dts/qcom/ 2>/dev/null | grep -iE "sm6225|sm6115|bengal" || echo "(none matched)"
echo "=== sm6225.dtsi exists? wc ==="
wc -l arch/arm64/boot/dts/qcom/sm6225.dtsi 2>/dev/null || echo "no sm6225.dtsi"
echo "=== all sm6225* files ==="
find arch/arm64/boot/dts/qcom -maxdepth 1 -name '*sm6225*' -o -maxdepth 1 -name '*tb331fc*' -o -maxdepth 1 -name '*khaje*' 2>/dev/null
