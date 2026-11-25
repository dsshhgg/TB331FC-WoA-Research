#!/usr/bin/env python3
import importlib.util, struct, sys
spec = importlib.util.spec_from_file_location('dtbo', '/mnt/e/rom/work/img-boot-group/tools/dtbo.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

def show(blob, label):
    fdt = m.parse_fdt(blob)
    print('##', label)
    for c in fdt['root']['children']:
        if c['name'] == 'chosen':
            for k, v in c['props'].items():
                print('   chosen/%s = %r' % (k, v[:400]))
        if c['name'] == 'memory':
            print('   memory: %s' % list(c['props'].items())[:1])

vb = open('/mnt/e/rom/work/of/v3/stock/vendor_boot_a.bin', 'rb').read()[11636736:11636736 + 1290690]
show(vb[:279505], 'vendor_boot FDT0 (base, dtb_idx=0)')
show(vb[279505:2 * 279505], 'vendor_boot FDT1')

hdr, entries, data = m.parse_dtbo('/mnt/e/rom/work/of/v3/stock/dtbo_a.bin')
for i in (2,):
    e = entries[i]
    blob = data[e['dtb_offset']:e['dtb_offset'] + e['dtb_size']]
    print('\n## dtbo entry', i)
    fdt = m.parse_fdt(blob)
    # print every fragment target/overlay head nodes
    for c in fdt['root']['children']:
        if c['name'] == 'chosen':
            for k, v in c['props'].items():
                print('   chosen/%s = %r' % (k, v[:300]))
    print('   fragments:')
    for c in fdt['root']['children']:
        if c['name'].startswith('fragment@'):
            ov = next((x for x in c['children'] if x['name'] == '__overlay__'), None)
            print('     %-11s target=%s  top-nodes=%s' % (c['name'],
                  c['props'].get('target', b'').hex(), [x['name'] for x in ov['children']] if ov else []))
