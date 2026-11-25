#!/system/bin/sh
echo "===SOC_NODES_MATCH"
ls /sys/firmware/devicetree/base/soc/ | grep -Ei 'gpu|kgsl|3d0|f521000|5990000|5900000|cpufreq'
echo "===GPU_NODE_LIST"
for n in /sys/firmware/devicetree/base/soc/*3d0* /sys/firmware/devicetree/base/soc/*kgsl*; do
  [ -d "$n" ] || continue
  echo "--- $n"
  ls "$n"
done
echo "===GPU_NODE_STRS"
for n in /sys/firmware/devicetree/base/soc/*3d0*; do
  [ -d "$n" ] || continue
  for f in "$n"/*; do
    case "$f" in
      */compatible|*/qcom,gpu-model|*/qcom,gpu-pwrlevel-bins|*/nvmem-cell-names|*/qcom,chipid|*/qcom,gpu-quirk-*|*/qcom,initial-pwrlevel|*/qcom,ca-busy-ratio|*/qcom,gpu-freq-*|*/qcom,idle-timeout|*/qcom,bus-width)
        echo "-- $(basename $f): $(tr '\0' ' ' < $f 2>/dev/null | head -c 400)";;
      */qcom,gpu-pwrlevels/*)
        echo "-- $(basename $f): $(tr '\0' ' ' < $f 2>/dev/null | head -c 200)";;
    esac
  done
done
echo "===GPU_PWRLEVEL_SUBDIR"
for n in /sys/firmware/devicetree/base/soc/*3d0*/qcom,gpu-pwrlevels; do
  [ -d "$n" ] || continue
  echo "--- $n"
  for f in "$n"/*; do
    echo "  $(basename $f) = $(tr '\0' ' ' < $f 2>/dev/null | head -c 300)"
  done
done
echo "===GPU_OPP_NODE"
for n in /sys/firmware/devicetree/base/soc/gpu-opp-table; do
  echo "--- $n"
  for f in "$n"/*; do
    echo "  $(basename $f)"
    for g in "$f"/*; do echo "    $(basename $g) = $(tr '\0' ' ' < $g 2>/dev/null | head -c 200)"; done
    case "$f" in
      */clock-latency-ns|*/opp-hz|*/opp-level|*/opp-microvolt*|*/opp-supported-hw|*/required-opps|*/opp-suspend) echo "    val=$(tr '\0' ' ' < $f 2>/dev/null | head -c 200)";;
    esac
  done
done
echo "===CPUFREQ_HW_NODE"
for n in /sys/firmware/devicetree/base/soc/cpufreq*; do
  echo "--- $n"; ls "$n"
  for f in "$n"/*; do
    case "$f" in
      */compatible|*/reg|*/reg-names|*/nvmem-cells|*/nvmem-cell-names|*/clock-latency-ns|*/qcom,*|*/interrupts) echo "  $(basename $f) = $(tr '\0' ' ' < $f 2>/dev/null | head -c 300)";;
    esac
  done
done
echo "===CPU_NODES"
for c in 0 4; do
  n=/sys/firmware/devicetree/base/cpus/cpu@$c
  [ -d "$n" ] || continue
  echo "--- $n"; ls "$n"
  for f in "$n"/*; do
    case "$f" in
      */compatible|*/device_type|*/reg|*/clock-frequency|*/operating-points*|*/qcom,freq-domain|*/qcom,latency|*/qcom,level|*/capacity-dmips-mhz|*/dynamic-power-coefficient) echo "  $(basename $f) = $(tr '\0' ' ' < $f 2>/dev/null | head -c 300)";;
    esac
  done
done
echo "===MSMPERF_READ"
for f in /sys/kernel/msm_performance/parameters/* /sys/kernel/msm_performance/notify/*; do
  echo "$f = $(cat $f 2>/dev/null | head -c 500)"
done
echo "===DMESG_CPUFREQ"
dmesg | grep -Ei 'cpufreq|opp|kgsl|adreno|gpu|speed.?bin|lmh' | head -80
echo "===MODULES_DIR"
ls /vendor/lib/modules/ 2>/dev/null | head -40
ls /vendor_dlkm/lib/modules/ 2>/dev/null | head -40
echo "===KERNEL_VERMAGIC"
cat /proc/version
echo "===DTBO_PART"
ls -l /dev/block/by-name/ | grep -Ei 'dtbo|boot|vendor_boot'
echo "===DT_MODEL"
tr '\0' ' ' < /sys/firmware/devicetree/base/model; echo
echo "===DT_BOARDID"
od -An -tu4 /sys/firmware/devicetree/base/qcom,board-id 2>/dev/null
od -An -tu4 /sys/firmware/devicetree/base/qcom,msm-id 2>/dev/null
echo "===DONE"
