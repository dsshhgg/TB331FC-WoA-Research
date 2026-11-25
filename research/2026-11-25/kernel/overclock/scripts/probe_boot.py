import struct, io, sys
p = r'E:\rom\work\port_tools\TB331FC-Kernel-main\boot_a.img'
data = open(p,'rb').read()
print('size', len(data))
# Android boot image v3/v4 header magic
print('magic', data[:8])
# find all FDT magics
for mag in (b'\xd0\x0d\xfe\xed',):
    offs=[]
    i=0
    while True:
        i=data.find(mag,i)
        if i<0: break
        tot = struct.unpack('>I', data[i+4:i+8])[0]
        offs.append((i,tot))
        i+=4
    print('FDT magic candidates:', offs[:20], 'count', len(offs))
