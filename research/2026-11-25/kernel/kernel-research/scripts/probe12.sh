#!/bin/bash
K=/root/linux-tb331fc
cd "$K" || exit 1
echo "=== files carrying TB331FC/TB128/p255/nt36523 vendor markers (excluding dts dir & .bak) ==="
grep -rl -iE 'tb331fc|tb128fu|p255|nt36523|lenovo' drivers sound include arch/arm64/boot/dts/qcom 2>/dev/null \
 | grep -vE '\.(bak|orig|rej|hookbak)' | grep -v 'dts/qcom/sm6225' | sort
echo
echo "=== byte sizes of the non-upstream component set ==="
tot=0
for f in arch/arm64/boot/dts/qcom/sm6225.dtsi \
         drivers/clk/qcom/gcc-sm6225.c drivers/clk/qcom/dispcc-sm6225.c drivers/clk/qcom/gpucc-sm6225.c \
         drivers/pinctrl/qcom/pinctrl-sm6225.c drivers/interconnect/qcom/sm6225.c \
         drivers/gpu/drm/panel/panel-himax-hx83102.c \
         sound/soc/codecs/aw88166.c ; do
  if [ -f "$f" ]; then s=$(stat -c%s "$f"); tot=$((tot+s)); printf "%8d  %s\n" "$s" "$f"; fi
done
echo "--- touch drivers (out-of-tree) ---"
du -sb drivers/input/touchscreen/himax_v3_mmi 2>/dev/null
ls -la drivers/input/touchscreen/nt36523* 2>/dev/null | awk '{print $5, $9}'
echo "--- dt-bindings ---"
stat -c'%s  %n' include/dt-bindings/clock/qcom,gcc-sm6225.h include/dt-bindings/clock/qcom,dispcc-sm6225.h include/dt-bindings/clock/qcom,sm6225-gpucc.h include/dt-bindings/interconnect/qcom,sm6225.h 2>/dev/null
echo
echo "=== is nt36523 registered in Makefile/Kconfig? ==="
grep -n 'nt36523' drivers/input/touchscreen/Makefile drivers/input/touchscreen/Kconfig 2>/dev/null | head
echo
echo "=== aw88166 in Makefile/Kconfig? ==="
grep -n 'aw88166' sound/soc/codecs/Makefile sound/soc/codecs/Kconfig 2>/dev/null | head
echo
echo "=== hci_qca.c: tb331fc patches? (suspend fix) ==="
grep -n -iE 'suspend|tb331|lenovo' drivers/bluetooth/hci_qca.c | head -8
