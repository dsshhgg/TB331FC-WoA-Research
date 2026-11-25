#!/system/bin/sh
D=/sys/firmware/devicetree/base
dump_node() {
  n="$1"
  [ -d "$n" ] || { echo "MISSING $n"; return; }
  echo "===== $n"
  for f in "$n"/*; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in
      # binary/u32 props
      reg|qcom,board-id|qcom,msm-id|qcom,chipid|qcom,gpu-model|compatible|qcom,gpu-pwrlevel-bins|qcom,initial-pwrlevel|qcom,bus-width|qcom,gpu-quirk-*) 
        printf 'BIN %s: ' "$(basename "$f")"; od -An -tu4 "$f" 2>/dev/null | tr '\n' ' '; echo ;;
      *)
        printf 'STR %s: ' "$(basename "$f")"; tr '\0' ' ' < "$f" 2>/dev/null | cut -c1-400; echo ;;
    esac
  done
  for d in "$n"/*/; do
    echo "----- SUB $d"
    for f in "$d"*; do
      [ -f "$f" ] || continue
      printf '  %s: ' "$(basename "$f")"
      od -An -tu4 "$f" 2>/dev/null | tr '\n' ' ' | cut -c1-200
      printf ' | '
      tr '\0' ' ' < "$f" 2>/dev/null | cut -c1-120
      echo
    done
  done
}
dump_node "$D/soc/qcom,kgsl-3d0@5900000"
echo
dump_node "$D/soc/qcom,kgsl-3d0@5900000/qcom,gpu-pwrlevels"
echo
dump_node "$D/soc/qcom,kgsl-3d0@5900000/qcom,gpu-pwrlevel-bins"
echo
dump_node "$D/soc/qcom,cpufreq-hw"
echo
dump_node "$D/soc/qcom,cpufreq-hw-debug@0f521000"
echo
dump_node "$D/cpus/cpu@0"
echo
dump_node "$D/cpus/cpu@4"
echo "===DONE"
