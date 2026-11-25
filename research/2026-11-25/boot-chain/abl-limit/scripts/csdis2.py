import sys
from capstone import *
PE = sys.argv[3] if len(sys.argv)>3 else r'E:\rom\work\woa\abl-hang-analysis\extract\Z17_9e21fd93_lz_f536d559_PE32_at_0xb4.bin'
d = open(PE,'rb').read()
lo = int(sys.argv[1],0); hi = int(sys.argv[2],0)
md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
for ins in md.disasm(d[lo:hi], lo):
    print('0x%x: %-8s %s' % (ins.address, ins.mnemonic, ins.op_str))
