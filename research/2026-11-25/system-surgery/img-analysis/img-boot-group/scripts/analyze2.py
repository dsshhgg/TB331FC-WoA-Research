#!/usr/bin/env python3
"""Cross-reference dtbo overlays against the vendor_boot base DTB:
 - which fixup symbols each overlay needs and whether base defines them
 - panel / touch node inventory per overlay
"""
import struct, json, importlib.util, os
spec = importlib.util.spec_from_file_location('dtbo', '/mnt/e/rom/work/img-boot-group/tools/dtbo.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

VB = '/mnt/e/rom/work/of/v3/stock/vendor_boot_a.bin'
DTBO = '/mnt/e/rom/work/of/v3/stock/dtbo_a.bin'

vb = open(VB, 'rb').read()[11636736:11636736 + 1290690]
base = m.parse_fdt(vb)
base_syms = set()
for c in base['root']['children']:
    if c['name'] == '__symbols__':
        base_syms = set(c['props'].keys())
print('base dtb: nodes=%d props=%d __symbols__=%d' % (base['nodes'], base['props'], len(base_syms)))

hdr, entries, data = m.parse_dtbo(DTBO)
all_needed = set()
panel_names, touch_names = set(), set()
per = []
for e in entries:
    blob = data[e['dtb_offset']:e['dtb_offset'] + e['dtb_size']]
    fdt = m.parse_fdt(blob)
    root = fdt['root']
    fixups = []
    syms = 0
    for c in root['children']:
        if c['name'] == '__fixups__':
            fixups = list(c['props'].keys())
        if c['name'] == '__symbols__':
            syms = len(c['props'])
    missing = [f for f in fixups if f not in base_syms]
    all_needed.update(fixups)
    panels = set()
    touches = set()
    for p, n in m.walk(root):
        low = p.lower()
        nm = n['name'].lower()
        if any(k in nm for k in ('panel', 'dsi')):
            panels.add(n['name'])
        if any(k in nm for k in ('touch', 'novatek', 'nt36', 'focaltech', 'ft5', 'goodix',
                                 'gt9', 'himax', 'synaptics', 'chipone', 'ilitek')):
            touches.add(n['name'])
    panel_names |= panels
    touch_names |= touches
    per.append(dict(i=e['i'], size=e['dtb_size'], nodes=fdt['nodes'], syms=syms,
                    fixups=len(fixups), missing=missing,
                    model=m.get_str(root, 'model'), panels=sorted(panels), touches=sorted(touches),
                    msm=m.summarize(blob, 'x')['msm_id'], board=m.summarize(blob, 'x')['board_id']))

for r in per:
    print('%2d %-52s nodes=%-4d syms=%-3d fix=%-3d missing=%d panels=%d touches=%d'
          % (r['i'], (r['model'] or '')[:52], r['nodes'], r['syms'], r['fixups'],
             len(r['missing']), len(r['panels']), len(r['touches'])))

print('\ndistinct fixup symbols needed by any overlay:', len(all_needed))
print('fixup symbols NOT defined in base __symbols__:',
      sorted(all_needed - base_syms)[:40])
print('base symbols unused by any overlay:', len(base_syms - all_needed))

print('\n=== panel node names (distinct) ===')
for n in sorted(panel_names):
    print(' ', n)
print('\n=== touch node names (distinct) ===')
for n in sorted(touch_names):
    print(' ', n)
json.dump(per, open('/mnt/e/rom/work/img-boot-group/dtbo_cross.json', 'w'), indent=1, default=str)
