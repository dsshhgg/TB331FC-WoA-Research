#!/bin/bash
K=/root/linux-tb331fc
cd "$K" || exit 1
echo "=== sdhci-msm: sm6225? ==="
grep -n 'sm6225' drivers/mmc/host/sdhci-msm.c | head -5
echo "=== all driver files mentioning sm6225 (fast, exact dirs) ==="
grep -rln 'sm6225' drivers/clk/qcom drivers/interconnect/qcom drivers/pinctrl/qcom drivers/mmc/host drivers/phy/qualcomm drivers/gpu/drm/msm drivers/iommu drivers/soc/qcom 2>/dev/null | grep -v '\.o$' | sort
echo
echo "=== count of non-upstream bytes total (the 4 clock/icc/pinctrl + panel + aw88166 + nt36523 set) ==="
du -cb drivers/clk/qcom/gcc-sm6225.c drivers/clk/qcom/dispcc-sm6225.c drivers/clk/qcom/gpucc-sm6225.c drivers/pinctrl/qcom/pinctrl-sm6225.c drivers/interconnect/qcom/sm6225.c drivers/gpu/drm/panel/panel-himax-hx83102.c drivers/gpu/drm/panel/p255_inx_init.h sound/soc/codecs/aw88166.c sound/soc/codecs/aw88166.h drivers/input/touchscreen/nt36523_ts.c drivers/input/touchscreen/nt36523_fw_update.c drivers/input/touchscreen/nt36523.h drivers/input/touchscreen/nt36523_mem_map.h arch/arm64/boot/dts/qcom/sm6225.dtsi arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dts include/dt-bindings/clock/qcom,gcc-sm6225.h include/dt-bindings/clock/qcom,dispcc-sm6225.h include/dt-bindings/clock/qcom,sm6225-gpucc.h include/dt-bindings/interconnect/qcom,sm6225.h 2>/dev/null | tail -1
