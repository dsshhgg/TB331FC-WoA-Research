#!/system/bin/sh
echo "===VENDORMOD_COUNT"
ls /vendor/lib/modules | wc -l
echo "===CPUFREQ_MODS"
ls /vendor/lib/modules | grep -Ei 'cpufreq|kgsl|devfreq|bwmon|thermal|lmh'
echo "===VENDOR_DLKM"
ls /vendor_dlkm/lib/modules 2>/dev/null | head -30
echo "===SYS_MODULE_MATCH"
ls /sys/module | grep -Ei 'cpufreq|kgsl|walt|qcom'
echo "===VERSION"
cat /proc/version
echo "===KGSL_MODINFO"
modinfo msm_kgsl 2>/dev/null | head -14
echo "===CPUFREQ_MODINFO"
modinfo qcom_cpufreq_hw 2>/dev/null | head -10
modinfo qcom-cpufreq-hw 2>/dev/null | head -10
echo "===TRIP_POINTS_KEY_ZONES"
for z in 1 7 8 9 10 11 12 13 16; do
  echo "--- zone$z type=$(cat /sys/class/thermal/thermal_zone$z/type)"
  for t in /sys/class/thermal/thermal_zone$z/trip_point_*_temp; do
    [ -f "$t" ] || continue
    n=$(basename "$t")
    idx=${n#trip_point_}
    idx=${idx%_temp}
    echo "   trip$idx temp=$(cat $t) type=$(cat /sys/class/thermal/thermal_zone$z/trip_point_${idx}_type 2>/dev/null)"
  done
done
echo "===LMH"
for c in /sys/class/thermal/cooling_device*; do
  t=$(cat $c/type 2>/dev/null)
  case "$t" in
    *lmh*|*cpufreq*|*devfreq*) echo "$(basename $c) type=$t cur=$(cat $c/cur_state 2>/dev/null) max=$(cat $c/max_state 2>/dev/null)";;
  esac
done
echo "===CPUFREQ_CDEV"
ls -d /sys/devices/system/cpu/cpufreq 2>/dev/null
ls /sys/devices/system/cpu/cpufreq/policy4/*.cdev 2>/dev/null
echo "===POLICY4_FILES"
ls /sys/devices/system/cpu/cpufreq/policy4/
echo "===CPUFREQ_STATS"
cat /sys/devices/system/cpu/cpufreq/policy0/stats/time_in_state 2>/dev/null
cat /sys/devices/system/cpu/cpufreq/policy4/stats/time_in_state 2>/dev/null
echo "===KERNEL_LOGFREQ"
dmesg | grep -Ei 'cpufreq|qcom-cpufreq|OPP|kgsl|adreno|speed_bin|binning' | tail -40
echo "===DONE"
