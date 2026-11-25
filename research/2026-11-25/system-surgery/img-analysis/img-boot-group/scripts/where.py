#!/usr/bin/env python3
"""Which tree carries panel/touch strings: vendor_boot base DTB vs dtbo live entry."""
import importlib.util
spec = importlib.util.spec_from_file_location('dtbo', '/mnt/e/rom/work/img-boot-group/tools/dtbo.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

vb = open('/mnt/e/rom/work/of/v3/stock/vendor_boot_a.bin', 'rb').read()
base = vb[11636736:11636736 + 1290690]
KEYS = [b'p255_hx83102j', b'p255_inx', b'p255_csot', b'nt36523', b'hx83102', b'himax,hxcommon',
        b'novatek,NVT-ts-spi', b'novatek,NVT-ts', b'synaptics,tcm', b'qcom,dsi-default-panel',
        b'dsi_panel_pwr_supply_no_labibb', b'qcom,dsi-display-primary', b'msm_drm.dsi_display0']
print('== vendor_boot dtb blob (all 6 FDTs) ==')
for k in KEYS:
    print('   %-34s %d' % (k.decode(), base.count(k)))
hdr, entries, data = m.parse_dtbo('/mnt/e/rom/work/of/v3/stock/dtbo_a.bin')
e = entries[2]
live = data[e['dtb_offset']:e['dtb_offset'] + e['dtb_size']]
print('== dtbo entry 2 (live, dtbo_idx=2) ==')
for k in KEYS:
    print('   %-34s %d' % (k.decode(), live.count(k)))
