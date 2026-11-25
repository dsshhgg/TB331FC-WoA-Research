#!/bin/bash
D=/root/linux-tb331fc/arch/arm64/boot/dts/qcom
cd "$D" || exit 1

line_of() { grep -n "$1" "$2" | head -3; }

echo "############ sm6225.dtsi : status disabled occurrences with context ############"
awk '/status = "disabled"/{print NR": "$0}' sm6225.dtsi | head -60
echo
echo "############ node name preceding each disabled block (crude) ############"
python3 - <<'PY'
import re
p='/root/linux-tb331fc/arch/arm64/boot/dts/qcom/sm6225.dtsi'
src=open(p).read().splitlines()
# track brace stack with node labels
stack=[]
cur=None
out=[]
for i,l in enumerate(src,1):
    s=l.strip()
    m=re.match(r'^([A-Za-z0-9_@\-]+)\s*(?::\s*([A-Za-z0-9_@\-]+))?\s*\{\s*$', s)
    if m:
        name=m.group(1)
        stack.append(name); cur=stack[-1]; continue
    if s.startswith('};'):
        if stack: stack.pop()
        cur=stack[-1] if stack else None
        continue
    if 'status = "disabled"' in s:
        out.append((i, cur or '?', len(stack)))
for i,name,d in out:
    print(f"{i:6d}  depth{d}  {name}")
PY
echo
echo "############ subsystem node presence (sm6225.dtsi vs sm6115.dtsi) ############"
for pat in ufs dsi mdss display-subsystem gpu@ usb@ dwc3 bluetooth wifi wcn remoteproc camss sound q6asm q6adm adsp mpss cdsp lpass i2c@ spmi@ tsens llcc cpufreq opp-table; do
  a=$(grep -c "$pat" sm6225.dtsi 2>/dev/null); b=$(grep -c "$pat" sm6115.dtsi 2>/dev/null)
  printf "%-22s sm6225=%-4s sm6115=%-4s\n" "$pat" "$a" "$b"
done
