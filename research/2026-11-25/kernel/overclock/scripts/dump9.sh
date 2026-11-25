#!/system/bin/sh
echo "===CORE_CTL_LIST"
ls /sys/devices/system/cpu/cpu0/core_ctl 2>/dev/null
echo "---values"
for f in /sys/devices/system/cpu/cpu0/core_ctl/*; do [ -f "$f" ] && echo "$(basename $f) = $(cat $f 2>/dev/null)"; done
echo "===CORE_CTL_BIG"
ls /sys/devices/system/cpu/cpu7/core_ctl 2>/dev/null
for f in /sys/devices/system/cpu/cpu7/core_ctl/*; do [ -f "$f" ] && echo "$(basename $f) = $(cat $f 2>/dev/null)"; done
echo "===MSMPERF_VALUES"
for f in /sys/kernel/msm_performance/parameters/*; do echo "$(basename $f) = $(cat $f 2>/dev/null)"; done
echo "===HOTPLUG"
ls /sys/devices/system/cpu/hotplug 2>/dev/null
for f in /sys/devices/system/cpu/hotplug/*; do [ -f "$f" ] && echo "$(basename $f) = $(cat $f 2>/dev/null)"; done
echo "===SMT_NOTNEEDED"
echo "===GPU_PERF_LEVEL"
echo "max_pwrlevel=$(cat /sys/class/kgsl/kgsl-3d0/max_pwrlevel) min_pwrlevel=$(cat /sys/class/kgsl/kgsl-3d0/min_pwrlevel) default_pwrlevel=$(cat /sys/class/kgsl/kgsl-3d0/default_pwrlevel) thermal_pwrlevel=$(cat /sys/class/kgsl/kgsl-3d0/thermal_pwrlevel)"
echo "devfreq max=$(cat /sys/class/devfreq/5900000.qcom,kgsl-3d0/max_freq) min=$(cat /sys/class/devfreq/5900000.qcom,kgsl-3d0/min_freq) cur=$(cat /sys/class/devfreq/5900000.qcom,kgsl-3d0/cur_freq) mod_percent=$(cat /sys/class/devfreq/5900000.qcom,kgsl-3d0/mod_percent) gpu_load=$(cat /sys/class/devfreq/5900000.qcom,kgsl-3d0/gpu_load)"
echo "===GPU_CLOCK_STATS_AGAIN"
cat /sys/class/kgsl/kgsl-3d0/gpu_clock_stats
echo "===UPTIME"
cat /proc/uptime
echo "===DONE"
