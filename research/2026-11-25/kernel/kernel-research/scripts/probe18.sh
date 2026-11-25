#!/bin/bash
R=/mnt/e/rom/work/kernel-research/ref
cd "$R" || exit 1
echo "=== upstream sm6115.dtsi v6.6 : key compatibles (what upstream already supports) ==="
for pat in 'adreno-610' 'qcom,sm6115-mdss\|qcom,sm8250-mdss\|mdss' 'qcom,sm6115-dpu\|dpu' 'qcom,sm6115-dispcc' 'qcom,sm6115-qmp-ufs-phy' 'qcom,sm6115-ufshc\|ufshc' 'qcom,wcn3990-wifi' 'qcom,sm6115-sdhci' 'qcom,sm6115-gcc' 'qcom,sm6115-smmu-v2\|smmu-v2' 'qcom,sm6115-dsi-phy\|dsi-phy' ; do
  printf "%-42s v6.6=%s  v6.14=%s\n" "$pat" "$(grep -cE -- "$pat" sm6115-v6.6.dtsi)" "$(grep -cE -- "$pat" sm6115-v6.14.dtsi)"
done
echo
echo "--- exact compatible lines in v6.6 dtsi for gpu/mdss/ufs/wifi ---"
grep -nE 'compatible = "(qcom,adreno|adreno)|compatible = "qcom,.*(mdss|dpu|ufs|wifi|gcc|dispcc|smmu)' sm6115-v6.6.dtsi | head -14
echo
echo "=== v6.6 vs v6.14: q6asm/q6adm (ADSP audio services) context ==="
grep -c 'q6asm\|q6adm' sm6115-v6.6.dtsi; grep -c 'q6asm\|q6adm' sm6115-v6.14.dtsi
echo
echo "=== which upstream release first had interconnect nodes for sm6115? ==="
grep -c 'interconnect@' sm6115-v6.6.dtsi; grep -c 'interconnect@' sm6115-v6.12.dtsi; grep -c 'interconnect@' sm6115-v6.14.dtsi
