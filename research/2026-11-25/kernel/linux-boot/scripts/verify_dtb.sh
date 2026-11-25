#!/bin/bash
# verify_dtb.sh <dtb> - report __symbols__ entry count, abl-stub count, key nodes
set -u
DTB=${1:-/mnt/e/rom/work/linux-boot/out/sm6225-lenovo-tb331fc-linux.dtb}
TMP=$(mktemp)
dtc -I dtb -O dts "$DTB" > "$TMP" 2>/dev/null || { echo "dtc failed"; exit 1; }
echo "dtb        : $DTB ($(stat -c%s "$DTB") bytes)"
echo -n "__symbols__: "
if grep -q '__symbols__ {' "$TMP"; then
    awk '/__symbols__ \{/ {f=1; next} f && /^\t\};/ {f=0} f && /= "/ {n++} END {print n+0 " entries"}' "$TMP"
else
    echo "MISSING  (ABL/libufdt overlay application will fail)"
fi
echo -n "abl-stubs  : "; grep -c 'abl-stub' "$TMP"
echo -n "model      : "; grep -m1 'model =' "$TMP" | sed 's/^[[:space:]]*//'
echo -n "bt node    : "; grep -m1 'qcom,wcn3[0-9]*.*-bt"' "$TMP" | sed 's/^[[:space:]]*//'
echo -n "bt fw      : "; grep -m2 'crbtfw\|apbtfw\|firmware-name' "$TMP" | sed 's/^[[:space:]]*//' | tr '\n' ' '; echo
echo -n "chosen bootargs: "
awk '/chosen \{/{f=1} f&&/bootargs/{print; exit}' "$TMP" | sed 's/^[[:space:]]*//'
rm -f "$TMP"
