#!/bin/bash
R=/mnt/e/rom/work/kernel-research/ref
L=/root/linux-tb331fc/arch/arm64/boot/dts/qcom
cd "$R" || exit 1
# normalize CRLF just in case
for f in sm6115-v6.6.dtsi sm6115-v6.12.dtsi sm6115-v6.14.dtsi; do sed -i 's/\r$//' "$f"; done

echo "=== does the local sm6115.dtsi == upstream v6.14 ? ==="
diff -q sm6115-v6.14.dtsi "$L/sm6115.dtsi" && echo "IDENTICAL to v6.14" || { echo "DIFFERS -> $(diff sm6115-v6.14.dtsi "$L/sm6115.dtsi" | wc -l) diff lines"; }

echo
echo "=== subsystem node presence across upstream versions ==="
printf "%-34s %-10s %-10s %-10s %-10s\n" "pattern" "6.6" "6.12" "6.14" "sm6225(tree)"
for pat in 'ufs_mem_hc' 'ufs_mem_phy' 'qmp-ufs-phy' 'mdss:' 'mdss_dsi0:' 'dsi-phy' 'dpu' 'gpu@' 'adreno' 'usb@4e00000' 'dwc3' 'wifi@' 'wcn3990-wifi' 'remoteproc_mpss' 'remoteproc_adsp' 'remoteproc_cdsp' 'q6asm' 'sound:' 'camss' 'tsens' 'llcc' 'i2c@' 'qcom,sm6115-dispcc' 'qcom,sm6115-gcc'; do
  a=$(grep -c -- "$pat" sm6115-v6.6.dtsi); b=$(grep -c -- "$pat" sm6115-v6.12.dtsi); c=$(grep -c -- "$pat" sm6115-v6.14.dtsi); d=$(grep -c -- "$pat" "$L/sm6225.dtsi")
  printf "%-34s %-10s %-10s %-10s %-10s\n" "$pat" "$a" "$b" "$c" "$d"
done

echo
echo "=== so what did 6.6 NOT have that 6.14 has? (node names only in 6.14) ==="
comm -13 <(grep -oE '^\s+[a-z0-9_]+: [a-z0-9_@-]+ \{' sm6115-v6.6.dtsi | tr -d ' \t' | sort -u) <(grep -oE '^\s+[a-z0-9_]+: [a-z0-9_@-]+ \{' sm6115-v6.14.dtsi | tr -d ' \t' | sort -u)
echo
echo "=== compatibles present in sm6225.dtsi but NOT in upstream sm6115.dtsi (the gaps) ==="
comm -13 <(grep -oE '"[a-z0-9,._-]+"' "$L/sm6115.dtsi" | sort -u) <(grep -oE '"[a-z0-9,._-]+"' "$L/sm6225.dtsi" | sort -u) | grep -E 'qcom,|sm6225' | head -40
