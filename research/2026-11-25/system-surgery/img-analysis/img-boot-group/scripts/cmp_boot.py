#!/usr/bin/env python3
"""Compare boot images: stock vs device dump vs repack."""
import hashlib, struct

def rd(p, n=None):
    with open(p, 'rb') as f:
        return f.read() if n is None else f.read(n)

SALT_BOOT = bytes.fromhex('0b8f7e2fd96e1922090e393672502d6f0578446e15451c092721c68863957689')
DECL = bytes.fromhex('ad970718ab11fdbf7331b8a084809ab71d90da233d577ee7024079e43f21e3e5')

stock = rd('/mnt/e/rom/work/zui16_flash/image/boot.img')
dev = rd('/mnt/e/rom/work/a17dump/boot_a.img')
v3k = rd('/mnt/e/rom/work/of/v3/boot_tb331fc_v3_kernel_only.img')

print('stock size', len(stock), 'dev size', len(dev), 'v3kernel size', len(v3k))

h = hashlib.sha256(); h.update(SALT_BOOT); h.update(stock[:46841856])
print('stock[:46841856] digest', h.hexdigest(), 'MATCH' if h.digest() == DECL else 'MISMATCH')

h = hashlib.sha256(); h.update(SALT_BOOT); h.update(dev[:46841856])
print('dev[:46841856] digest  ', h.hexdigest(), 'MATCH' if h.digest() == DECL else 'MISMATCH')

print('dev[:len(v3k)] == v3k ?', dev[:len(v3k)] == v3k)
# where do dev and stock differ
n = min(len(dev), len(stock))
first_diff = next((i for i in range(n) if dev[i] != stock[i]), None)
print('first diff dev vs stock at', first_diff, hex(first_diff) if first_diff else '')
# tail of dev vs stock
print('dev[43098112:46841856] == stock[43098112:46841856] ?',
      dev[43098112:46841856] == stock[43098112:46841856])
# signature size field of stock
print('stock sig_size field @1580 =', struct.unpack_from('<I', stock, 1580)[0])
print('dev   sig_size field @1580 =', struct.unpack_from('<I', dev, 1580)[0])
print('stock kernel_size', struct.unpack_from('<I', stock, 8)[0])
print('dev   kernel_size', struct.unpack_from('<I', dev, 8)[0])
# stock header vs dev header bytes 0..1584
print('header equal?', stock[:1584] == dev[:1584])
for off in range(0, 1584, 4):
    a = struct.unpack_from('<I', stock, off)[0]; b = struct.unpack_from('<I', dev, off)[0]
    if a != b:
        print('  hdr diff @%d: stock=%d dev=%d' % (off, a, b))
