#!/bin/bash
D=/root/linux-tb331fc/arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dts
echo "=== bluetooth node full (lines 1975-2045) ==="
sed -n '1975,2045p' "$D"
echo
echo "=== ktz8866 driver upstream? ==="
ls /root/linux-tb331fc/drivers/video/backlight/ | grep -i ktz || echo "(no ktz in backlight)"
find /root/linux-tb331fc/drivers -iname '*ktz8866*' 2>/dev/null
echo
echo "=== aw88166 / aw883xx driver present? ==="
find /root/linux-tb331fc/sound -iname '*aw88*' 2>/dev/null
echo
echo "=== rt1711h tcpm present? ==="
find /root/linux-tb331fc/drivers -iname '*rt1711*' 2>/dev/null
