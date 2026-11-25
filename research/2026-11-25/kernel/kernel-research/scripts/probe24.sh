#!/bin/bash
cd /root/linux-tb331fc || exit 1
echo "=== Kconfig symbols (authoritative) ==="
echo "--- mm8013 ---"; grep -rn -B2 -A4 'mm8013' drivers/power/supply/Kconfig | head -14
echo "--- ktz8866 ---"; grep -rn -A3 'config BACKLIGHT_KTZ8866' drivers/video/backlight/Kconfig
echo "--- rt1711h ---"; grep -rn -A4 'RT1711H' drivers/usb/typec/tcpm/Kconfig | head -12
echo "--- nt36523 ---"; grep -rn -A5 'config TOUCHSCREEN_NT36523_SPI' drivers/input/touchscreen/Kconfig
echo "--- aw88166 ---"; grep -rn -A6 'config SND_SOC_AW88166' sound/soc/codecs/Kconfig
echo "--- sm6225 clocks ---"; grep -rn -A4 'config SM_GCC_6225' drivers/clk/qcom/Kconfig
echo
echo "=== audio machine drivers for sm6115? ==="
grep -rln 'sm6115' sound/soc/qcom/*.c 2>/dev/null
echo "--- what compatibles does sm8250 machine driver claim? ---"
grep -n 'compatible' sound/soc/qcom/sm8250.c 2>/dev/null | head
echo
echo "=== lpass / qdsp6 present? ==="
ls sound/soc/qcom/ | head -30
echo "count: $(ls sound/soc/qcom/ | wc -l)"
