#!/bin/bash
K=/root/linux-tb331fc
cd "$K" || exit 1
echo "=== defconfigs (arm64) mentioning qcom/tb331 ==="
ls arch/arm64/configs/ | head -20
echo "--- any tb331fc defconfig? ---"
ls arch/arm64/configs/ | grep -i -E 'tb331|sm6225|sm6115' || echo "(none)"
echo
echo "=== does arch/arm64/configs/defconfig enable qcom sm6115? ==="
grep -nE 'SM6115|ARCH_QCOM|QCOM_CLK_GCC|SM_GCC' arch/arm64/configs/defconfig | head -20
echo
echo "=== config used for the existing build (from out/config-*) ==="
C=/mnt/e/rom/work/linux-build/out/config-6.14.0-rc5-tb331fc
for k in CONFIG_ARCH_QCOM CONFIG_ARM64 CONFIG_DRM_MSM CONFIG_DRM_PANEL CONFIG_PHY_QCOM_QMP_UFS CONFIG_PHY_QCOM_QUSB2 CONFIG_SCSI_UFS_QCOM CONFIG_QCOM_CLK_GCC CONFIG_QCOM_CLK_DISPCC CONFIG_QCOM_CLK_GPUCC CONFIG_INTERCONNECT_QCOM_SM6115 CONFIG_PINCTRL_SM6115 CONFIG_BT CONFIG_BT_HCIUART CONFIG_BT_QCA CONFIG_ATH10K CONFIG_ATH10K_SNOC CONFIG_SND_SOC CONFIG_QCOM_APR CONFIG_QCOM_Q6V5_PAS CONFIG_QCOM_LLCC CONFIG_ARM_QCOM_CPUFREQ_NVMEM CONFIG_DRM_PANEL_HX83102 CONFIG_TOUCHSCREEN_HIMAX CONFIG_MM8013 CONFIG_REGULATOR CONFIG_SIMPLE_FRAMEBUFFER CONFIG_DRM_FBDEV_EMULATION CONFIG_EXT4_FS CONFIG_DEVTMPFS CONFIG_QCOM_SMD_RPM CONFIG_QCOM_RPMPD; do
  printf "%-38s %s\n" "$k" "$(grep -m1 "^$k=" "$C" 2>/dev/null || echo '(not set)')"
done
echo
echo "=== is it a defconfig-derived or full config? ==="
grep -c '^CONFIG_' "$C"
