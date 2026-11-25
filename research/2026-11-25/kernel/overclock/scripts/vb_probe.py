paths = [r'E:\rom\work\of\v3\stock\vendor_boot_a.bin']
needles = [b'qcom_cpufreq_hw', b'qcom-cpufreq-hw', b'gpucc-khaje', b'msm_kgsl', b'kgsl-3d0', b'lut']
for p in paths:
    data = open(p,'rb').read()
    print('file', p, 'size', len(data))
    for n in needles:
        c = data.count(n)
        first = data.find(n)
        print('  %-20s count=%d first_off=%s' % (n.decode(), c, hex(first) if first>=0 else 'none'))
