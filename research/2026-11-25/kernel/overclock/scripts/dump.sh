#!/system/bin/sh
echo "===KERNEL"
uname -a
echo "===PLATFORM"
getprop ro.board.platform
getprop ro.soc.model
getprop ro.soc.manufacturer
getprop ro.hardware
getprop ro.product.device
getprop ro.build.fingerprint
echo "===CPUINFO_TOP"
grep -Ei 'Processor|Hardware|Revision|implementer|part' /proc/cpuinfo | head -30
echo "===POLICY_DIRS"
ls -la /sys/devices/system/cpu/cpufreq/ 2>/dev/null
echo "===CPU0"
ls /sys/devices/system/cpu/cpu0/cpufreq/ 2>/dev/null
for d in /sys/devices/system/cpu/cpufreq/*/; do
  echo "--- $d"
  for f in scaling_driver scaling_governor scaling_available_governors \
           scaling_available_frequencies cpuinfo_min_freq cpuinfo_max_freq \
           scaling_min_freq scaling_max_freq scaling_cur_freq \
           affected_cpus related_cpus; do
    v=$(cat "$d$f" 2>/dev/null)
    echo "$f = $v"
  done
done
echo "===CPUS_ONLINE"
cat /sys/devices/system/cpu/online 2>/dev/null
cat /sys/devices/system/cpu/possible 2>/dev/null
echo "===CPU_MAXSLOT"
for c in 0 1 2 3 4 5 6 7; do
  echo "cpu$c online=$(cat /sys/devices/system/cpu/cpu$c/online 2>/dev/null)" \
       "maxfreq=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_max_freq 2>/dev/null)" \
       "cur=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq 2>/dev/null)"
done
echo "===KGSL"
ls /sys/class/kgsl/kgsl-3d0/ 2>/dev/null
for f in gpu_model gpu_busy_percentage gpu_clock gpu_freq gpu_available_frequencies \
         gpu_available_governors gpu_governor gpu_min_clock gpu_max_clock \
         gpu_clock_stats devfreq/available_frequencies devfreq/available_governors \
         devfreq/governor devfreq/min_freq devfreq/max_freq devfreq/cur_freq \
         devfreq/trans_stat max_gpuclk min_gpuclk; do
  v=$(cat "/sys/class/kgsl/kgsl-3d0/$f" 2>/dev/null)
  echo "$f = $v"
done
echo "===KGSL_DEVICES"
ls -la /sys/class/kgsl/ 2>/dev/null
echo "===DEVFREQ"
ls /sys/class/devfreq/ 2>/dev/null
for d in /sys/class/devfreq/*/; do
  echo "--- $d"
  echo "name=$(cat $d/name 2>/dev/null)"
  echo "governor=$(cat $d/governor 2>/dev/null)"
  echo "avail_gov=$(cat $d/available_governors 2>/dev/null)"
  echo "avail_freq=$(cat $d/available_frequencies 2>/dev/null)"
  echo "cur_freq=$(cat $d/cur_freq 2>/dev/null)"
  echo "min_freq=$(cat $d/min_freq 2>/dev/null)"
  echo "max_freq=$(cat $d/max_freq 2>/dev/null)"
done
echo "===THERMAL_ZONES"
for z in /sys/class/thermal/thermal_zone*/; do
  echo "$z type=$(cat $z/type 2>/dev/null) temp=$(cat $z/temp 2>/dev/null) mode=$(cat $z/mode 2>/dev/null)"
done
echo "===COOLING_DEVICES"
ls /sys/class/thermal/ 2>/dev/null | head -80
echo "===THERMAL_MESSAGE"
ls /sys/class/thermal/thermal_message 2>/dev/null || echo "NO thermal_message"
echo "===MSM_PERFORMANCE"
ls -la /sys/module/msm_performance/parameters 2>/dev/null
find /sys -maxdepth 4 -iname "*msm_perf*" 2>/dev/null | head -20
echo "===BATTERY"
for b in /sys/class/power_supply/*/; do
  echo "--- $b"
  echo "type=$(cat $b/type 2>/dev/null) name=$(cat $b/name 2>/dev/null)"
  echo "status=$(cat $b/status 2>/dev/null) cap=$(cat $b/capacity 2>/dev/null) volt=$(cat $b/voltage_now 2>/dev/null) cur=$(cat $b/current_now 2>/dev/null) temp=$(cat $b/temp 2>/dev/null)"
  echo "health=$(cat $b/health 2>/dev/null)"
done
echo "===OPP_TABLES_SYSFS"
ls /sys/kernel/debug/opp 2>/dev/null || echo "NO /sys/kernel/debug/opp"
ls /sys/devices/system/cpu/cpu0/ | head -30
find /sys/devices -maxdepth 3 -iname "opp*" 2>/dev/null | head
echo "===REGULATOR"
ls /sys/class/regulator/ 2>/dev/null | head -40
for r in /sys/class/regulator/regulator.*/; do
  n=$(cat $r/name 2>/dev/null)
  case "$n" in
    *vdd*|*VDD*|*cpu*|*gpu*|*cx*|*CX*|*l2*|*L2*|*ebi*|*EBI*|*mx*|*MX*)
      echo "--- $r name=$n min=$(cat $r/min_microvolts 2>/dev/null) max=$(cat $r/max_microvolts 2>/dev/null) cur=$(cat $r/microvolts 2>/dev/null) state=$(cat $r/state 2>/dev/null)"
      ;;
  esac
done
echo "===DONE"
