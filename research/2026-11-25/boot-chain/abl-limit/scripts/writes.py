import re, sys
P=r'E:\rom\work\woa\abl-jump-analysis\full.asm'
lo = int(sys.argv[1],0) if len(sys.argv)>1 else 0
hi = int(sys.argv[2],0) if len(sys.argv)>2 else 0x1000000
needle = sys.argv[3] if len(sys.argv)>3 else '#0x98]'
lines=open(P,errors='replace').read().splitlines()
pat=re.compile(r'^\s*([0-9a-fA-F]+):\s*(.*)$')
n=0
for ln in lines:
    m=pat.match(ln)
    if not m: continue
    a=int(m.group(1),16); body=m.group(2).strip()
    if needle in body and lo<=a<=hi:
        op=body.split()[0]
        if op in ('str','stp','strb','strh','strd','stur','sturb'):
            print(hex(a), body); n+=1
print('count',n)
