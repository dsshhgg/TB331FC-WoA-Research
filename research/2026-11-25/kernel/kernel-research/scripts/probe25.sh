#!/bin/bash
cd /root/linux-tb331fc || exit 1
echo "=== mm8013 registration ==="
grep -rn 'mm8013' drivers/power/supply/Kconfig drivers/power/supply/Makefile 2>/dev/null | head
echo "--- file exists? ---"; ls -la drivers/power/supply/mm8013.c | awk '{print $5,$9}'
echo
echo "=== what sound/machine node does sm6225.dtsi declare? ==="
grep -n -A 20 'sound:' arch/arm64/boot/dts/qcom/sm6225.dtsi | head -30
echo
echo "=== and in the board dts (tb331fc) ==="
grep -n -A 25 'sound' arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dts | grep -iE 'compatible|model|audio|dai-link|sound' | head -20
