#!/bin/bash
K=/root/linux-tb331fc
cd "$K" || exit 1
C=/mnt/e/rom/work/linux-build/out/config-6.14.0-rc5-tb331fc
echo "=== tb331fc_defconfig: size & how it was made ==="
wc -l arch/arm64/configs/tb331fc_defconfig
head -20 arch/arm64/configs/tb331fc_defconfig
echo
echo "=== real sm6225 symbols in the BUILT config ==="
grep -E '6225' "$C" | sort
echo
echo "=== sm6115-ish symbols built-in ==="
grep -E 'SM_GCC_6115|SM_DISPCC|SM_GPUCC|SM_VIDEOCC|PINCTRL_SM6115|INTERCONNECT_QCOM' "$C" | sort | head -20
echo
echo "=== DRM panel drivers present in tree (candidates for TB331FC) ==="
ls drivers/gpu/drm/panel/ | grep -iE 'boe|csot|kingdisplay|starry|ivo|t109|kd110|hx83102|nt36|novatek' || echo "(none)"
echo "--- hx83102 anywhere? ---"
grep -rl 'hx83102' drivers/ include/ 2>/dev/null | head
echo
echo "=== touchscreen drivers: himax / novatek ==="
ls drivers/input/touchscreen/ | grep -iE 'himax|novatek|nvt|hx' || echo "(none)"
echo
echo "=== fuel gauge: mm8013 upstream? ==="
ls drivers/power/supply/ | grep -iE 'mm8013|bq27' || echo "(none)"
echo
echo "=== panel timing files in dts? what panel does the tb331fc.dts use ==="
grep -nE 'compatible = ".*panel|panel@|dsi0_out|panel-init-sequence|hx83102|nt36|hx8' arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dts | head -20
