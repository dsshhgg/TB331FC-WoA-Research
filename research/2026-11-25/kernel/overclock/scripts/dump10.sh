#!/system/bin/sh
echo "===ALL_REGULATORS"
for r in /sys/class/regulator/regulator.*/; do
  n=$(cat "$r/name" 2>/dev/null)
  echo "$(basename $r) name=$n state=$(cat $r/state 2>/dev/null) uV=$(cat $r/microvolts 2>/dev/null) min=$(cat $r/min_microvolts 2>/dev/null) max=$(cat $r/max_microvolts 2>/dev/null) num_users=$(cat $r/num_users 2>/dev/null)"
done
echo "===SUM"
echo "count=$(ls -d /sys/class/regulator/regulator.*/ | wc -l)"
echo "===DONE"
