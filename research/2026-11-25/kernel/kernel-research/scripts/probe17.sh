#!/bin/bash
cd /root/linux-tb331fc || exit 1
echo "=== sdhci-msm compatibles of interest ==="
grep -nE 'sm6115|sm4250|sm6225|sdm660' drivers/mmc/host/sdhci-msm.c | head -8
echo
echo "=== total bytes of non-upstream component set ==="
du -cb \
  drivers/clk/qcom/gcc-sm6225.c \
  drivers/clk/qcom/dispcc-sm6225.c \
  drivers/clk/qcom/gpucc-sm6225.c \
  drivers/pinctrl/qcom/pinctrl-sm6225.c \
  drivers/interconnect/qcom/sm6225.c \
  drivers/gpu/drm/panel/panel-himax-hx83102.c \
  drivers/gpu/drm/panel/p255_inx_init.h \
  sound/soc/codecs/aw88166.c \
  sound/soc/codecs/aw88166.h \
  drivers/input/touchscreen/nt36523_ts.c \
  drivers/input/touchscreen/nt36523_fw_update.c \
  drivers/input/touchscreen/nt36523.h \
  drivers/input/touchscreen/nt36523_mem_map.h \
  arch/arm64/boot/dts/qcom/sm6225.dtsi \
  arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dts \
  2>/dev/null | awk 'END{printf "%.2f MB total\n", $1/1024/1024}'
echo
echo "=== does the DTS rely on qcom,sm6225-sdhci? ==="
grep -n 'sdhci' arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dts | head -5
grep -n 'sdhci' arch/arm64/boot/dts/qcom/sm6225.dtsi | head -5
