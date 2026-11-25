import re
P = r'E:\rom\work\woa\abl-hang-analysis\extract\Z17_9e21fd93_lz_f536d559_PE32_at_0xb4.bin'
d = open(P,'rb').read()
for m in re.finditer(rb'[ -~]{6,}', d):
    s = m.group().decode()
    if 'amdisk' in s or 'Ramdisk' in s or 'ramdisk' in s:
        print(hex(m.start()), s)
