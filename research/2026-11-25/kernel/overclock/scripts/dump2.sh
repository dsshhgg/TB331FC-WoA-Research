#!/system/bin/sh
echo "===MOUNTS_DEBUG"
mount | grep -Ei 'debugfs|tracefs' 
ls /sys/kernel/debug 2>/dev/null | head -30
echo "===DEVICETREE_TOP"
ls /sys/firmware/devicetree/base/ 2>/dev/null | head -60
echo "===FIND_OPP"
find /sys/firmware/devicetree/base -maxdepth 3 -iname '*opp*' 2>/dev/null | head -40
echo "===CPUFREQ_NODE"
ls /sys/firmware/devicetree/base/soc/ 2>/dev/null | head -80
echo "===CPU_OPP_DUMP"
for n in /sys/firmware/devicetree/base/soc/*opp* /sys/firmware/devicetree/base/opp-table* /sys/firmware/devicetree/base/cpus/*opp*; do
  [ -e "$n" ] || continue
  echo "--- $n"
  ls "$n"
done
echo "===GPU_PWRLEVELS"
ls /sys/firmware/devicetree/base/soc/5900000.qcom,kgsl-3d0/ 2>/dev/null
for f in /sys/firmware/devicetree/base/soc/5900000.qcom,kgsl-3d0/*; do
  case "$f" in
    *pwrlevel*|*freq*|*clock*|*volt*|*speed*|*bin*)
      echo "--- $f"; od -An -tu4 "$f" 2>/dev/null | head -20;;
  esac
done
echo "===KGSL_DETAIL"
for f in num_pwrlevels default_pwrlevel max_pwrlevel min_pwrlevel thermal_pwrlevel pwrscale throttling temp idle_timer min_clock_mhz max_clock_mhz freq_table_mhz clock_mhz bcl acd ifpc popp; do
  echo "$f = $(cat /sys/class/kgsl/kgsl-3d0/$f 2>/dev/null)"
done
echo "===KGSL_BCL"
ls /sys/class/kgsl/kgsl-3d0/bcl 2>/dev/null
for f in /sys/class/kgsl/kgsl-3d0/bcl/*; do echo "$f = $(cat $f 2>/dev/null)"; done
echo "===MSMPERF_PARAMS"
ls -la /sys/kernel/msm_performance 2>/dev/null
find /sys/kernel/msm_performance -maxdepth 2 2>/dev/null | head -40
echo "===CORE_CTL"
ls /sys/devices/system/cpu/core_ctl* 2>/dev/null
for f in /sys/devices/system/cpu/core_ctl*/[a-z]*; do echo "$f = $(cat $f 2>/dev/null)"; done
echo "===BOOST"
ls /sys/devices/system/cpu/cpu_boost 2>/dev/null || echo no cpu_boost
echo "===WALT"
ls /sys/devices/system/cpu/cpufreq/policy0/walt 2>/dev/null
echo "===CPU_STATS"
cat /sys/devices/system/cpu/cpufreq/policy4/stats 2>/dev/null
echo "===SENSOR_THERMAL_LIMITS"
find /sys/class/thermal/thermal_zone0 -maxdepth 1 2>/dev/null
echo "===TRIP_POINTS"
for z in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24; do
  echo "zone$z: $(ls /sys/class/thermal/thermal_zone$z/ 2>/dev/null | tr '\n' ' ')"
done
echo "===COOLING_TYPES"
for c in 0 5 10 15 20 25 30 35; do echo "cooling_device$c type=$(cat /sys/class/thermal/cooling_device$c/type 2>/dev/null) cur=$(cat /sys/class/thermal/cooling_device$c/cur_state 2>/dev/null) max=$(cat /sys/class/thermal/cooling_device$c/max_state 2>/dev/null)"; done
echo "===POWER_SUPPLY_EXT"
for f in /sys/class/power_supply/battery/*; do
  case "$f" in
    */voltage_now|*/current_now|*/temp|*/capacity|*/status|*/health|*/charge_counter|*/voltage_max|*/constant_charge_current_max|*/input_current_limit|*/system_temp_level|*/battery_charging_enabled|*/power_online|*/cycle_count) echo "$f = $(cat $f 2>/dev/null)";;
  esac
done
echo "===SC89601"
ls -d /sys/class/power_supply/* 2>/dev/null
ls /sys/bus/iio/devices 2>/dev/null
echo "===DONE"
