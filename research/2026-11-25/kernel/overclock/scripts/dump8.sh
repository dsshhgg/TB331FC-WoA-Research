#!/system/bin/sh
echo "===SYS_KERNEL_TOP"
ls /sys/kernel | sort
echo "===CPUFREQ_HW_KOBJ"
for d in /sys/kernel/cpufreq_hw /sys/kernel/cpufreqhw /sys/kernel/cpufreq; do
  echo "== $d"
  ls "$d" 2>/dev/null || echo "none"
done
echo "===FIND_ATTR"
find /sys/kernel -maxdepth 2 -iname '*hwregs*' -o -maxdepth 2 -iname '*cpufreq*' 2>/dev/null
echo "===DUMP_IF_EXISTS"
for f in /sys/kernel/cpufreq_hw/* /sys/kernel/cpufreqhw/*; do
  [ -f "$f" ] && { echo "--- $f"; cat "$f" 2>/dev/null; }
done
echo "===DONE"
