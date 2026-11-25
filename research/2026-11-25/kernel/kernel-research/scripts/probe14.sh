#!/bin/bash
K=/root/linux-tb331fc
cd "$K" || exit 1
echo "=== modified upstream drivers: where the client-specific bits are ==="
for f in drivers/phy/qualcomm/phy-qcom-qmp-ufs.c drivers/gpu/drm/msm/msm_mdss.c \
         drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c drivers/gpu/drm/msm/dsi/dsi_host.c \
         drivers/power/supply/mm8013.c drivers/bluetooth/hci_qca.c \
         drivers/tty/serial/qcom_geni_serial.c drivers/gpu/drm/msm/adreno/a6xx_gpu.c; do
  n=$(grep -ciE 'sm6225|sm6115|tb331|lenovo|p255' "$f" 2>/dev/null)
  printf "%-56s hits=%s\n" "$f" "$n"
  grep -niE 'sm6225|tb331|p255' "$f" 2>/dev/null | head -4 | sed 's/^/    /'
done
echo
echo "=== panel Makefile/Kconfig entries added ==="
grep -nE 'p255|hx83102|himax' drivers/gpu/drm/panel/Makefile drivers/gpu/drm/panel/Kconfig | head -10
echo
echo "=== panel-compatible strings supported by panel-himax-hx83102.c ==="
grep -n 'compatible = "' drivers/gpu/drm/panel/panel-himax-hx83102.c | head -20
echo
echo "=== p255_inx_init.h size ==="
ls -la drivers/gpu/drm/panel/p255_inx_init.h 2>/dev/null | awk '{print $5, $9}'
grep -c . drivers/gpu/drm/panel/p255_inx_init.h 2>/dev/null
echo
echo "=== novatek panel driver (TDDI) in tree? ==="
ls -la drivers/gpu/drm/panel/panel-novatek-nt36523.c 2>/dev/null | awk '{print $5, $9}'
grep -n 'compatible = "' drivers/gpu/drm/panel/panel-novatek-nt36523.c 2>/dev/null | head
