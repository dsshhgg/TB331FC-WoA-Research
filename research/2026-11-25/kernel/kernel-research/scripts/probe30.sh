#!/bin/bash
K=/root/linux-tb331fc
echo "=== tb331fc_defconfig vs the config that was actually built (out/config-*) ==="
for f in "$K/arch/arm64/configs/tb331fc_defconfig" /mnt/e/rom/work/linux-build/out/config-6.14.0-rc5-tb331fc; do
  echo "--- $f ---"
  for k in SOUND SND SND_SOC SND_SOC_QCOM BT_LE DEBUG_INFO_BTF SM_GCC_6225 SPI_QCOM_GENI; do
    printf "   %-18s %s\n" "$k" "$(grep -m1 -- "CONFIG_$k\b" "$f" 2>/dev/null || echo '<absent>')"
  done
done
echo
echo "=== how many CONFIG_ lines each ==="
grep -c '^CONFIG_' "$K/arch/arm64/configs/tb331fc_defconfig"
grep -c '^CONFIG_' /mnt/e/rom/work/linux-build/out/config-6.14.0-rc5-tb331fc
echo
echo "=== diff between defconfig and the built config (lines) ==="
diff <(sort "$K/arch/arm64/configs/tb331fc_defconfig") <(sort /mnt/e/rom/work/linux-build/out/config-6.14.0-rc5-tb331fc) | grep -c '^[<>]'
echo "--- what differs (first 20) ---"
diff <(sort "$K/arch/arm64/configs/tb331fc_defconfig") <(sort /mnt/e/rom/work/linux-build/out/config-6.14.0-rc5-tb331fc) | grep '^[<>]' | head -20
