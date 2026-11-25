#!/bin/bash
K=/root/linux-tb331fc
cd "$K" || exit 1
echo "=== panel@0 node + panel compatible in tb331fc.dts ==="
sed -n '2430,2470p' arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dts
echo "..."
grep -n 'panel@0' -A 20 arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dts | grep -iE 'compatible|panel' | head
echo
echo "=== backlight / smartpa / typec / hall nodes ==="
grep -nE 'ktz8866|aw88166|aw883xx|fsa4480|rt1711|hall|mm8013|bq27|sy6974|nv|novatek' arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dts | head -25
echo
echo "=== suspicious non-upstream artifacts (.bak/.orig/.hookbak/.rej/.tmp by author) ==="
find . -type f \( -name '*.bak*' -o -name '*.orig' -o -name '*.rej' -o -name '*.hookbak' -o -name '*.bak70' \) 2>/dev/null | grep -v '^./arch/arm64/boot/dts/qcom/\.' | head -30
echo
echo "=== out-of-tree looking driver dirs ==="
ls -d drivers/input/touchscreen/*/ 2>/dev/null
echo
echo "=== panel-himax-hx83102.c: upstream has it? check git-blame-ish header ==="
head -25 drivers/gpu/drm/panel/panel-himax-hx83102.c
echo
echo "=== does it differ from upstream? size compare target ==="
wc -c drivers/gpu/drm/panel/panel-himax-hx83102.c drivers/gpu/drm/panel/panel-himax-hx83102.c.bak70 2>/dev/null
