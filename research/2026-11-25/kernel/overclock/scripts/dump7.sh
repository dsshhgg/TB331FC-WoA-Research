#!/system/bin/sh
echo "===BOOST_FREQS"
echo "policy0: $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_boost_frequencies 2>/dev/null)"
echo "policy4: $(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_boost_frequencies 2>/dev/null)"
echo "===CPUINFO_CUR"
cat /sys/devices/system/cpu/cpufreq/policy0/cpuinfo_cur_freq /sys/devices/system/cpu/cpufreq/policy4/cpuinfo_cur_freq 2>/dev/null
echo "===KGSL_MODULE_PARAMS"
ls /sys/module/msm_kgsl/parameters 2>/dev/null
for f in /sys/module/msm_kgsl/parameters/*; do [ -f "$f" ] && echo "$(basename $f) = $(cat $f 2>/dev/null)"; done
echo "===CPUFREQ_HW_DEBUG_PARAMS"
ls /sys/module/qcom_cpufreq_hw_debug/parameters 2>/dev/null
for f in /sys/module/qcom_cpufreq_hw_debug/parameters/*; do [ -f "$f" ] && echo "$(basename $f) = $(cat $f 2>/dev/null)"; done
echo "===CPUFREQ_HW_PARAMS"
ls /sys/module/qcom_cpufreq_hw/parameters 2>/dev/null
for f in /sys/module/qcom_cpufreq_hw/parameters/*; do [ -f "$f" ] && echo "$(basename $f) = $(cat $f 2>/dev/null)"; done
echo "===QCOM_DCVS"
ls /sys/module/qcom_dcvs/ 2>/dev/null; ls /sys/module/qcom_dcvs/parameters 2>/dev/null
echo "===DEVFREQ_KGSL_FILES"
for f in /sys/class/devfreq/5900000.qcom,kgsl-3d0/*; do echo "$(basename $f)"; done
echo "===KGSL_THERMAL"
echo "thermal_pwrlevel=$(cat /sys/class/kgsl/kgsl-3d0/thermal_pwrlevel 2>/dev/null) throttling=$(cat /sys/class/kgsl/kgsl-3d0/throttling 2>/dev/null)"
echo "===CURRENT_TEMPS"
for z in 7 9 16 11 1; do echo "zone$z $(cat /sys/class/thermal/thermal_zone$z/type) = $(cat /sys/class/thermal/thermal_zone$z/temp)"; done
echo "===GPU_LEVELS_VIA_OPP?"
ls /sys/kernel/debug 2>/dev/null || echo NO_DEBUGFS
echo "===CPU_CAPACITY"
cat /sys/devices/system/cpu/cpu0/cpu_capacity /sys/devices/system/cpu/cpu4/cpu_capacity 2>/dev/null
echo "===WALT_TUNABLES"
for f in /sys/devices/system/cpu/cpufreq/policy4/walt/*; do echo "$(basename $f) = $(cat $f 2>/dev/null)"; done
echo "===DONE"
