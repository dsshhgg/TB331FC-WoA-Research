import struct, json, sys

path = r'E:\rom\work\overclock\dtbo_a.img'
data = open(path,'rb').read()
MAGIC = b'\xd0\x0d\xfe\xed'
offs=[]
i=0
while True:
    i = data.find(MAGIC, i)
    if i < 0: break
    tot = struct.unpack('>I', data[i+4:i+8])[0]
    offs.append((i,tot))
    i += 4
print('FDT count:', len(offs))
for o,t in offs[:10]:
    print(' off=0x%x tot=%d' % (o,t))

STRINGS = [b'qcom,board-id', b'qcom,msm-id', b'qcom,pmic-id', b'qcom,gpu-freq', b'qcom,gpu-pwrlevels', b'qcom,cpufreq-hw', b'model']
def fdt_info(base):
    hdr = data[base:base+40]
    totalsize, off_struct, off_strings, off_rsv, version, last_comp = struct.unpack('>IIIIII', hdr[4:28])
    return dict(total=totalsize, off_struct=off_struct, off_strings=off_strings, version=version)

for o,t in offs[:10]:
    inf = fdt_info(o)
    # read model string: scan all strings in struct block for printable names
    sblock = data[o+inf['off_struct']: o+inf['off_struct']+2000]
    strs = data[o+inf['off_strings']: o+inf['off_strings']+3000]
    found = [s for s in STRINGS if s in strs]
    # model: find "model" then next string-ish
    print('off=0x%x total=%d ver=%d strings=%s' % (o, inf['total'], inf['version'], found))
