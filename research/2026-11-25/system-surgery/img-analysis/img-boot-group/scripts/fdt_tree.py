#!/usr/bin/env python3
import sys, struct
sys.path.insert(0, '/mnt/e/rom/work/img-boot-group/tools')
import importlib.util
spec = importlib.util.spec_from_file_location('dtbo', '/mnt/e/rom/work/img-boot-group/tools/dtbo.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

path = sys.argv[1]
blob = open(path, 'rb').read()
fdt = m.parse_fdt(blob)
root = fdt['root']
print('header', fdt['header'])
print('nodes', fdt['nodes'], 'props', fdt['props'], 'rootprops', list(root['props'].keys()))
print('root children (%d):' % len(root['children']))
for c in root['children']:
    print('  -', repr(c['name']), 'props:', list(c['props'].keys()),
          'kids:', [k['name'] for k in c['children']][:8])
