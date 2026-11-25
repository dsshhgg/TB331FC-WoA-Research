#!/bin/bash
cd /root/kbtest || exit 1
echo "=== pd.h head ==="
head -3 include/dt-bindings/usb/pd.h
echo "=== file type ==="
file include/dt-bindings/usb/pd.h
echo "=== direct cpp test ==="
aarch64-linux-gnu-gcc -E -nostdinc -I include -I arch/arm64/boot/dts -undef -D__DTS__ -x assembler-with-cpp arch/arm64/boot/dts/qcom/sm6225-lenovo-tb128.dts -o /tmp/t.i
echo "cpp exit=$?"
echo "=== Makefile.dtbs include flags ==="
grep -nE 'nostdinc|DTC_CPP|dtc_cpp' scripts/Makefile.dtbs | head -10
echo "=== compare to source tree ==="
ls -la /root/linux-tb331fc/include/dt-bindings/usb/pd.h
md5sum /root/linux-tb331fc/include/dt-bindings/usb/pd.h /root/kbtest/include/dt-bindings/usb/pd.h
