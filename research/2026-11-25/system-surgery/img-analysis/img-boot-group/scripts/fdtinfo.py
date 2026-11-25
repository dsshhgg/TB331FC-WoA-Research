#!/usr/bin/env python3
"""Summarize a standalone DTB (optionally embedded at offset/size)."""
import sys, json, struct, importlib.util
spec = importlib.util.spec_from_file_location('dtbo', '/mnt/e/rom/work/img-boot-group/tools/dtbo.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

path = sys.argv[1]
off = int(sys.argv[2]) if len(sys.argv) > 2 else 0
size = int(sys.argv[3]) if len(sys.argv) > 3 else None
blob = open(path, 'rb').read()[off:off + size if size else None]
info = m.summarize(blob, path)
print(json.dumps({k: v for k, v in info.items() if k != 'hits'}, indent=1, default=str))
print('--- panel/touch hits (%d) ---' % info['hit_count'])
for p, tags in info['hits']:
    print('  %-90s %s' % (p[:90], ','.join(tags)))
