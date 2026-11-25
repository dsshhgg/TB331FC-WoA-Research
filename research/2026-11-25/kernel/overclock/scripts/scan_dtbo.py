import struct, subprocess, os, re

data = open('/mnt/e/rom/work/overclock/dtbo_a.img', 'rb').read()
MAGIC = b'\xd0\x0d\xfe\xed'
offs = []
i = 0
while True:
    i = data.find(MAGIC, i)
    if i < 0:
        break
    tot = struct.unpack('>I', data[i + 4:i + 8])[0]
    offs.append((i, tot))
    i += 4

os.makedirs('/tmp/dt', exist_ok=True)
print('FDT count', len(offs))
rows = []
for o, t in offs:
    blob = data[o:o + t]
    p = '/tmp/dt/%05x.dtb' % o
    open(p, 'wb').write(blob)
    d = p.replace('.dtb', '.dts')
    subprocess.run(['dtc', '-I', 'dtb', '-O', 'dts', p, '-o', d, '-f'],
                   capture_output=True, text=True)
    model = ''
    bid = ''
    mid = ''
    gpu_max = None
    lut = None
    haskgsl = ''
    ok = os.path.exists(d)
    if ok:
        s = open(d, encoding='utf-8', errors='replace').read()
        m = re.search(r'model = "([^"]*)"', s)
        if m:
            model = m.group(1)
        m = re.search(r'qcom,board-id = <(0x[0-9a-f]+) (0x[0-9a-f]+)>', s)
        if m:
            bid = m.group(0)
        m = re.search(r'qcom,msm-id = <(0x[0-9a-f]+) (0x[0-9a-f]+)>', s)
        if m:
            mid = m.group(0)
        if 'qcom,kgsl-3d0' in s:
            haskgsl = 'kgsl'
        if 'qcom,gpu-freq' in s:
            freqs = re.findall(r'qcom,gpu-freq = <(0x[0-9a-f]+)>', s)
            if freqs:
                gpu_max = hex(max(int(x, 16) for x in freqs))
        m = re.search(r'qcom,max-lut-entries = <(0x[0-9a-f]+)>', s)
        if m:
            lut = m.group(1)
        m = re.search(r'qcom,chipid = <(0x[0-9a-f ]+)>', s)
        chipid = m.group(0) if m else ''
    else:
        chipid = ''
    rows.append((o, t, model, bid, mid, gpu_max, lut, haskgsl, chipid))

for r in rows:
    print('off=0x%05x tot=%6d model=%-42s %-22s %-22s gpu_max=%-12s lut=%-4s %s %s'
          % r)
