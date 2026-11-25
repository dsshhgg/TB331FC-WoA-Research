#!/bin/bash
D=/root/linux-tb331fc/arch/arm64/boot/dts/qcom
cd "$D" || exit 1
echo "=== sm6225.dtsi: gpu node ==="
sed -n '/gpu@/,/^\t\t};/p' sm6225.dtsi | head -30
echo
echo "=== sm6225.dtsi: ufs node essentials ==="
grep -n -A 6 'ufs_mem_hc: ufs@\|ufs_mem_phy: phy@' sm6225.dtsi | head -30
echo
echo "=== sm6225.dtsi: wifi node ==="
grep -n -B2 -A 18 'wifi@\|wifi: wifi' sm6225.dtsi | head -40
echo
echo "=== sm6225.dtsi: mdss/dsi compatible + status ==="
grep -nE 'display-subsystem|mdss:|mdss_dsi0:|qcom,sm[0-9]+-dpu|qcom,dsi-ctrl|qcom,sm6225-dispcc|qcom,sm6115-dispcc' sm6225.dtsi | head -20
echo
echo "=== does sm6225.dtsi reference camss at all? ==="
grep -c camss sm6225.dtsi
echo
echo "=== adsp/cdsp/mpss firmware-name in dtsi vs dts ==="
grep -n 'firmware-name' sm6225.dtsi | head
echo
echo "=== tb331fc.dts: which nodes are 'okay' (top-level count) ==="
grep -c 'status = "okay"' sm6225-lenovo-tb331fc.dts
echo "=== tb331fc.dts: disabled nodes ==="
grep -c 'status = "disabled"' sm6225-lenovo-tb331fc.dts
