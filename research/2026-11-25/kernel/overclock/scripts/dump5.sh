#!/system/bin/sh
D=/sys/firmware/devicetree/base/soc
hexp() {
  # print property as big-endian hex cells
  f="$1"
  printf '%s = ' "$(basename "$f")"
  od -An -tx1 "$f" 2>/dev/null | tr -d '\n' | tr -s ' '
  echo
}
echo "##### BINS"
for b in "$D/qcom,kgsl-3d0@5900000/qcom,gpu-pwrlevel-bins"/qcom,gpu-pwrlevels-*; do
  echo "===== $b"
  for f in "$b"/*; do [ -f "$f" ] && hexp "$f"; done
  for p in "$b"/qcom,gpu-pwrlevel*; do
    [ -d "$p" ] || continue
    echo "  --- $(basename "$p")"
    for f in "$p"/*; do [ -f "$f" ] && { printf '    '; hexp "$f"; }; done
  done
done
echo "##### TOP PROPS"
for f in "$D/qcom,kgsl-3d0@5900000/qcom,chipid" "$D/qcom,kgsl-3d0@5900000/qcom,gpu-model" "$D/qcom,kgsl-3d0@5900000/qcom,initial-pwrlevel" "$D/qcom,kgsl-3d0@5900000/qcom,ca-target-pwrlevel" "$D/qcom,cpufreq-hw/qcom,max-lut-entries" "$D/qcom,cpufreq-hw/reg" "$D/qcom,cpufreq-hw/qcom,no-accumulative-counter"; do
  [ -f "$f" ] && hexp "$f"
done
echo "##### STRINGS"
for f in "$D/qcom,kgsl-3d0@5900000/compatible" "$D/qcom,cpufreq-hw/compatible"; do
  echo "$(basename $f): $(cat $f | tr '\0' ',' )"
done
echo "##### OPP TABLE IN SOC (gpu-opp-table entries)"
for o in "$D/gpu-opp-table"/opp-*; do
  echo "--- $(basename "$o")"
  for f in "$o"/*; do [ -f "$f" ] && { printf '   '; hexp "$f"; }; done
done
echo "##### CPU NODES PRESENT"
ls /sys/firmware/devicetree/base/cpus/
echo "##### DONE"
