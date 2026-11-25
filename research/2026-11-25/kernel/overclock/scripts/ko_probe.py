import struct, re

def u32_le_hits(path, values):
    data = open(path, 'rb').read()
    out = {}
    for v in values:
        pat = struct.pack('<I', v)
        idxs = []
        i = data.find(pat)
        while i >= 0:
            idxs.append(i)
            i = data.find(pat, i + 1)
        if idxs:
            out[v] = idxs[:8]
    return out, data

ko = '/mnt/e/rom/work/overclock/gpucc-khaje.ko'
freqs = [320000000, 465000000, 600000000, 745000000, 785000000, 820000000,
         900000000, 950000000, 980000000, 1025000000, 1114800000, 1260000000]
hits, data = u32_le_hits(ko, freqs)
print('== gpucc-khaje.ko freq hits (u32 LE) ==')
for k in freqs:
    print(' %10d  count=%2d offsets=%s' % (k, len(hits.get(k, [])),
          [hex(x) for x in hits.get(k, [])]))
print('module size', len(data))

# dump region around a known hit to reveal the freq_tbl structure
anchor = hits.get(1260000000, [None])[0]
if anchor:
    s = max(0, anchor - 64)
    print('hexdump around 1260MHz hit @0x%x' % anchor)
    for off in range(s, s + 128, 16):
        row = data[off:off+16]
        print(' 0x%05x  %s  %s' % (off, ' '.join('%02x' % b for b in row),
              ''.join(chr(b) if 32 <= b < 127 else '.' for b in row)))

dbg = '/mnt/e/rom/work/overclock/qcom-cpufreq-hw-debug.ko'
d = open(dbg, 'rb').read()
strs = re.findall(rb'[ -~]{4,64}', d)
print('\n== qcom-cpufreq-hw-debug.ko strings (filtered) ==')
keep = [s.decode() for s in strs if any(k in s.lower() for k in
        (b'lut', b'freq', b'debugfs', b'domain', b'entry', b'table'))]
for s in keep[:60]:
    print('  ', s)
