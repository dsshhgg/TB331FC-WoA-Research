#!/bin/bash
cd /root/linux-tb331fc || exit 1
echo "=== porting effort estimate: sm6225 drivers vs their upstream sm6115 twins ==="
for pair in "drivers/clk/qcom/gcc-sm6225.c drivers/clk/qcom/gcc-sm6115.c" \
            "drivers/clk/qcom/dispcc-sm6225.c drivers/clk/qcom/dispcc-sm6115.c" \
            "drivers/clk/qcom/gpucc-sm6225.c drivers/clk/qcom/gpucc-sm6115.c"; do
  set -- $pair
  a=$1; b=$2
  if [ -f "$a" ] && [ -f "$b" ]; then
    n=$(diff "$b" "$a" | grep -c '^[<>]')
    printf "%-34s vs %-34s changed lines: %s\n" "$(basename $a)" "$(basename $b)" "$n"
  else
    echo "missing: $a or $b"
  fi
done
echo
echo "=== identical-line ratio for gcc (how mechanical is the port) ==="
a=drivers/clk/qcom/gcc-sm6225.c; b=drivers/clk/qcom/gcc-sm6115.c
echo "sm6225 lines: $(wc -l < $a)  sm6115 lines: $(wc -l < $b)"
diff --unchanged-group-format='%=' --old-group-format='' --new-group-format='' --changed-group-format='' "$b" "$a" | wc -l
echo
echo "=== pinctrl-sm6225 vs pinctrl-sm6115 ==="
ls -la drivers/pinctrl/qcom/pinctrl-sm6225.c drivers/pinctrl/qcom/pinctrl-sm6115.c 2>/dev/null | awk '{print $5,$9}'
diff drivers/pinctrl/qcom/pinctrl-sm6115.c drivers/pinctrl/qcom/pinctrl-sm6225.c 2>/dev/null | grep -c '^[<>]'
echo
echo "=== interconnect sm6225 vs sm6115 ==="
diff drivers/interconnect/qcom/sm6115.c drivers/interconnect/qcom/sm6225.c 2>/dev/null | grep -c '^[<>]'
