#!/bin/bash
K=/root/linux-tb331fc
echo "=== is include/dt-bindings/usb/pd.h present anywhere? ==="
find "$K/include/dt-bindings" -name 'pd*' -o -name '*usb*' | head -20
echo "--- usb dir listing ---"
ls -la "$K/include/dt-bindings/usb/" 2>/dev/null || echo "(no include/dt-bindings/usb dir)"
echo
echo "=== other dts files that include missing headers? (dry check) ==="
cd "$K/arch/arm64/boot/dts/qcom" || exit 1
for f in sm6225-lenovo-tb128.dts sm6225-lenovo-tb128-hx83102.dts; do
  echo "--- $f includes ---"; grep -n '#include' "$f" | head -12
done
echo
echo "=== which sm6225 dts are in the Makefile (why does dtbs try tb128?) ==="
grep -n 'sm6225' "$K/arch/arm64/boot/dts/qcom/Makefile"
