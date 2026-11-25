#!/bin/bash
K=/root/linux-tb331fc
cd "$K" || exit 1
echo "=== ALL files with sm6225 in the NAME (whole tree) ==="
find . -iname '*sm6225*' -not -path './arch/arm64/boot/dts/qcom/.*' 2>/dev/null | sort
echo
echo "=== files whose CONTENT mentions sm6225 (excluding dts dir), top 40 ==="
grep -rl 'sm6225' --include='*' drivers include sound 2>/dev/null | sort | head -40
echo
echo "=== Kconfig/Makefile sm6225 refs ==="
grep -rn 'sm6225\|SM6225' --include='Kconfig*' --include='Makefile' drivers include 2>/dev/null | head -40
