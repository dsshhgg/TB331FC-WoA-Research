import re, sys
# usage: refs_any.py <pefile> <string-substr>
PE = sys.argv[1]
SUB = sys.argv[2].encode()
d = open(PE,'rb').read()
pos = d.find(SUB)
print('string at', hex(pos))
# disassemble whole .text with capstone and look for target match
from capstone import *
md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
md.detail = False
adrp = {}
hits = []
for ins in md.disasm(d[0x1000:0xc0000], 0x1000):
    if ins.mnemonic == 'adrp':
        m = re.match(r'(x\d+), #0x([0-9a-f]+)', ins.op_str)
        if m: adrp[m.group(1)] = int(m.group(2),16)
    elif ins.mnemonic == 'add':
        m = re.match(r'(x\d+), (x\d+), #0x([0-9a-f]+)', ins.op_str)
        if m and m.group(2) in adrp and adrp[m.group(2)] + int(m.group(3),16) == pos:
            hits.append(ins.address)
print('refs', [hex(h) for h in hits])
