#!/bin/bash
cd /root/linux-tb331fc || exit 1
echo "=== disabled counts ==="
printf "sm6225.dtsi: %s\n" "$(grep -c 'status = "disabled"' arch/arm64/boot/dts/qcom/sm6225.dtsi)"
printf "sm6115.dtsi: %s\n" "$(grep -c 'status = "disabled"' arch/arm64/boot/dts/qcom/sm6115.dtsi)"
printf "tb331fc.dts : %s\n" "$(grep -c 'status = "disabled"' arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dts)"
echo
echo "=== pm6125.dtsi lines 50-60 with numbers ==="
sed -n '50,60p' arch/arm64/boot/dts/qcom/pm6125.dtsi | nl -ba -v50
echo
echo "=== preprocess pm6125.dtsi and look at output near the failure ==="
cd /root/kbtest 2>/dev/null || cd /root/linux-tb331fc
aarch64-linux-gnu-gcc -E -nostdinc -I include -I arch/arm64/boot/dts/qcom -I arch/arm64/include -undef -D__DTS__ -x assembler-with-cpp \
  /root/linux-tb331fc/arch/arm64/boot/dts/qcom/pm6125.dtsi 2>&1 | grep -n -i 'error' | head -5
echo "---(if empty above, pm6125.dtsi alone preprocesses fine)---"
