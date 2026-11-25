#!/system/bin/sh
echo "===FIND_MODULES"
find /vendor/lib/modules /vendor_dlkm/lib/modules -maxdepth 3 -name '*cpufreq*' 2>/dev/null
find /vendor/lib/modules /vendor_dlkm/lib/modules -maxdepth 3 -name '*kgsl*' 2>/dev/null
echo "===MODULE_DIRS"
ls -d /vendor/lib/modules/*/ 2>/dev/null
ls -d /vendor_dlkm/lib/modules/*/ 2>/dev/null
echo "===QCOM_CPUFREQ_HW_MODULE"
ls /sys/module/qcom_cpufreq_hw 2>/dev/null
echo "refcnt=$(cat /sys/module/qcom_cpufreq_hw/refcnt 2>/dev/null)"
echo "coresize=$(cat /sys/module/qcom_cpufreq_hw/coresize 2>/dev/null)"
echo "initstate=$(cat /sys/module/qcom_cpufreq_hw/initstate 2>/dev/null)"
echo "initsize=$(cat /sys/module/qcom_cpufreq_hw/initsize 2>/dev/null)"
echo "===MODULE_SECTIONS_HINT"
ls /sys/module/qcom_cpufreq_hw/notes 2>/dev/null && echo has_notes
echo "===DONE"
