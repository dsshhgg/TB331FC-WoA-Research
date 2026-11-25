#!/usr/bin/env python3
"""Fast streaming dm-verity root recompute (sequential big reads, low syscall count)."""
import sys, os, hashlib, struct

BLOCK = 4096
SALT = bytes.fromhex(sys.argv[2]) if len(sys.argv) > 2 else b''

def root_of(path, data_size, salt):
    h = hashlib.sha256
    level = []
    with open(path, 'rb', buffering=1024 * 1024) as f:
        remaining = data_size
        while remaining > 0:
            n = min(64 * 1024 * 1024, remaining)
            buf = f.read(n)
            if not buf:
                raise IOError('short read')
            for i in range(0, len(buf), BLOCK):
                blk = buf[i:i + BLOCK]
                if len(blk) < BLOCK:
                    blk = blk + b'\x00' * (BLOCK - len(blk))
                level.append(h(salt + blk).digest())
            remaining -= len(buf)
    while len(level) > 1:
        nxt = []
        for i in range(0, len(level), 128):
            blk = b''.join(level[i:i + 128])
            if len(blk) < BLOCK:
                blk = blk + b'\x00' * (BLOCK - len(blk))
            nxt.append(h(salt + blk).digest())
        level = nxt
    return level[0].hex()

if __name__ == '__main__':
    path = sys.argv[1]
    footer = None
    size = os.path.getsize(path)
    with open(path, 'rb') as f:
        f.seek(size - 64)
        tail = f.read(64)
        if tail[:4] == b'AVBf':
            footer = struct.unpack_from('>Q', tail, 12)[0]
    data_size = footer or size
    r = root_of(path, data_size, SALT)
    print('%s data_size=%d root=%s' % (os.path.basename(path), data_size, r))
