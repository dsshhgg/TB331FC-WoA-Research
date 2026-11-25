#!/bin/bash
cd /root/linux-tb331fc/arch/arm64/boot/dts/qcom || exit 1
echo "=== sizes / line counts ==="
wc -l sm6115.dtsi sm6225.dtsi sm6225-lenovo-tb331fc.dts sm6225-lenovo-tb128.dts 2>/dev/null
echo
echo "=== md5 sm6115.dtsi (compare to mainline v6.14 sha 94c081bf7a blob) ==="
md5sum sm6115.dtsi sm6225.dtsi
echo
echo "=== sm6225.dtsi head 40 ==="
head -40 sm6225.dtsi
echo
echo "=== diff stat sm6115.dtsi vs sm6225.dtsi ==="
diff -u sm6115.dtsi sm6225.dtsi > /tmp/sm.diff; echo "diff lines: $(wc -l < /tmp/sm.diff)"
echo "--- added lines only (count) ---"
grep -c '^+' /tmp/sm.diff
echo "--- removed lines only (count) ---"
grep -c '^-' /tmp/sm.diff
echo
echo "=== which include does sm6225.dtsi use ==="
grep -n '#include' sm6225.dtsi | head -20
