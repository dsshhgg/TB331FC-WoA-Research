#!/system/bin/sh
# 90s CPU load probe (read-only: spawns busy loops, samples sysfs)
N=8
i=0
while [ $i -lt $N ]; do
  sh -c 'while :; do :; done' &
  i=$((i+1))
done
echo "started $N busy loops, t=0"
T=0
while [ $T -le 90 ]; do
  P0=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null)
  P4=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_cur_freq 2>/dev/null)
  G=$(cat /sys/class/devfreq/5900000.qcom,kgsl-3d0/cur_freq 2>/dev/null)
  TZ7=$(cat /sys/class/thermal/thermal_zone7/temp 2>/dev/null)
  TZ11=$(cat /sys/class/thermal/thermal_zone11/temp 2>/dev/null)
  TZ16=$(cat /sys/class/thermal/thermal_zone16/temp 2>/dev/null)
  TZ1=$(cat /sys/class/thermal/thermal_zone1/temp 2>/dev/null)
  D=$(cat /sys/kernel/qcom-cpufreq-hw/print_cpufreq_debug_regs 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g')
  B=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null)
  V=$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null)
  BT=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)
  echo "t=$T policy0=$P0 policy4=$P4 gpu=$G cpu10=$TZ7 cpuss0=$TZ11 gpu_z=$TZ16 mapss=$TZ1 batt_uA=$B batt_uV=$V batt_temp=$BT"
  echo "    lut: $D"
  sleep 10
  T=$((T+10))
done
kill $(jobs -p) 2>/dev/null
wait 2>/dev/null
echo "load stopped"
echo "=== big cluster time_in_state after load"
cat /sys/devices/system/cpu/cpufreq/policy4/stats/time_in_state 2>/dev/null
echo "=== little cluster time_in_state"
cat /sys/devices/system/cpu/cpufreq/policy0/stats/time_in_state 2>/dev/null
echo "=== DONE"
