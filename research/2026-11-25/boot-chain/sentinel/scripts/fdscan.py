import struct, sys
d = open(sys.argv[1], 'rb').read()
print('FD size', len(d), hex(len(d)))
for name, w in [('orange_movz', 0x52900000), ('white_movn', 0x12800000),
                ('oldgreen_movz', 0x52A01FE0), ('blue_movz', 0x52801FE0),
                ('yellow_movn', 0x12801FE0)]:
    print('%-14s %#010x  at %s' % (name, w, [hex(i) for i in [d.find(struct.pack('<I', w))]]))
