#!/bin/bash
T=/root/kbtest
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
cd "$T" || exit 1
echo "=== fix linux-event-codes.h symlink ==="
cd include/dt-bindings/input || exit 1
ls -la linux-event-codes.h | awk '{print $5,$9}'
rm -f linux-event-codes.h
ln -s ../../uapi/linux/input-event-codes.h linux-event-codes.h
ls -la linux-event-codes.h
cd "$T" || exit 1
echo
echo "=== make dtbs (full) ==="
S=$(date +%s); make -j8 dtbs > /root/kbtest-dtbs3.log 2>&1; RC=$?; E=$(date +%s)
echo "exit=$RC elapsed=$((E-S))s"
echo "fatal errors: $(grep -c 'fatal' /root/kbtest-dtbs3.log)"
echo "FATAL parse:  $(grep -c 'FATAL ERROR' /root/kbtest-dtbs3.log)"
echo "--- produced dtbs ---"
ls -l arch/arm64/boot/dts/qcom/sm6225-*.dtb 2>/dev/null | awk '{print $5, $9}'
echo "--- tail of log ---"
tail -6 /root/kbtest-dtbs3.log
