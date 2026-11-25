import re, sys, json
P = r'E:\rom\work\woa\abl-jump-analysis\full.asm'
lines = open(P, errors='replace').read().splitlines()
pat = re.compile(r'^\s*([0-9a-fA-F]+):\s*(\S+)\s*(.*)$')
insns = []
for ln in lines:
    m = pat.match(ln)
    if not m: continue
    insns.append((int(m.group(1),16), m.group(2), m.group(3).strip()))

# build adrp map per register lazily: track last adrp for each reg
target = int(sys.argv[1], 0)
last_adrp = {}
out = []
for i,(a,op,ops) in enumerate(insns):
    if op == 'adrp':
        mm = re.match(r'(x\d+), 0x([0-9a-f]+)', ops)
        if mm:
            last_adrp[mm.group(1)] = int(mm.group(2),16)
    elif op == 'add':
        mm = re.match(r'(x\d+), (x\d+), #0x([0-9a-f]+)', ops)
        if mm:
            dst, src, imm = mm.group(1), mm.group(2), int(mm.group(3),16)
            if src in last_adrp and last_adrp[src] + imm == target:
                out.append((a, ops))
print('refs to', hex(target), len(out))
for a,ops in out:
    print(hex(a), ops)
