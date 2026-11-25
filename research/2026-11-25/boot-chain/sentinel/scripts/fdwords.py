import struct, sys
d = open(sys.argv[1], 'rb').read()
for base, n in [(0x1e5c, 10), (0x26e0, 5), (0x20e0, 6)]:
    print('--- FD %#x ---' % base)
    for i in range(n):
        o = base + 4 * i
        w = struct.unpack_from('<I', d, o)[0]
        print('  %#08x  %08x' % (o, w))
