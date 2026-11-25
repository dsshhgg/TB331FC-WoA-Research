import re, sys
P=r'E:\rom\work\woa\abl-jump-analysis\full.asm'
lo = int(sys.argv[1],0)
hi = int(sys.argv[2],0)
needle = sys.argv[3]
lines=open(P,errors='replace').read().splitlines()
pat=re.compile(r'^\s*([0-9a-fA-F]+):\s*(.*)$')
for ln in lines:
    m=pat.match(ln)
    if not m: continue
    a=int(m.group(1),16); body=m.group(2).strip()
    if lo<=a<=hi and needle in body:
        print(hex(a), body)
