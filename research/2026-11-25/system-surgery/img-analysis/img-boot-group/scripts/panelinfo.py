#!/usr/bin/env python3
"""Print selected display/touch props from the live dtbo overlay (entry 2)."""
import importlib.util, struct
spec = importlib.util.spec_from_file_location('dtbo', '/mnt/e/rom/work/img-boot-group/tools/dtbo.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

hdr, entries, data = m.parse_dtbo('/mnt/e/rom/work/of/v3/stock/dtbo_a.bin')
e = entries[2]
fdt = m.parse_fdt(data[e['dtb_offset']:e['dtb_offset'] + e['dtb_size']])

def find(node, name, path=''):
    out = []
    for p, n in m.walk(node, path):
        if n['name'] == name:
            out.append((p, n))
    return out

root = fdt['root']
for target in ('qcom,dsi-display-primary', 'qcom,dsi-display-secondary'):
    for p, n in find(root, target):
        print('##', p)
        for k, v in n['props'].items():
            if k in ('compatible',):
                print('   %-32s %r' % (k, v.rstrip(b'\x00')))
            elif len(v) <= 64:
                print('   %-32s %r' % (k, v if len(v) <= 40 else v[:40]))

for nm in ('qcom,mdss_dsi_panel_p255_hx83102j_fhd_video',
           'qcom,mdss_dsi_panel_p255_inx_fhd_video',
           'qcom,mdss_dsi_panel_p255_csot_fhd_video'):
    for p, n in find(root, nm):
        keys = [k for k in n['props'] if any(s in k for s in
                ('panel-name', 'panel-width', 'panel-height', 'panel-framerate', 'panel-type',
                 'panel-physical', 'panel-timing', 'panel-reset', 'panel-rotation', 'bl-max',
                 'bl-min', 'panel-init-sequence', 'panel-exit', 'panel-hbm', 'dsi-panel',
                 'panel-te', 'panel-lane', 'panel-on', 'panel-off', 'panel-bpp', 'panel-fps'))]
        print('\n## panel node', p, '(children=%d)' % len(n['children']))
        for k in sorted(keys):
            v = n['props'][k]
            print('   %-38s len=%-4d %r' % (k, len(v), v[:48]))
        for c in n['children']:
            print('     child:', c['name'], '(%d props)' % len(c['props']))
