import sys
P = r'E:\rom\work\woa\abl-hang-analysis\extract\Z17_9e21fd93_lz_f536d559_PE32_at_0xb4.bin'
data = open(P,'rb').read()
for a in sys.argv[1:]:
    v = int(a,0)
    end = data.find(b'\x00', v)
    print(a, '->', repr(data[v:end].decode('utf-8','replace')))
