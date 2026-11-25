#!/usr/bin/env python3
"""DTBO / FDT deep parser (read-only). Parses the dt_table_header, extracts every
embedded DTB, walks the FDT structure block and reports overlay targets,
__symbols__ counts and panel/touch related nodes."""
import sys, os, struct, json, io

FDT_MAGIC = 0xd00dfeed
DTBO_MAGIC = 0xd7b7ab1e


# ---------------- FDT ----------------
def parse_fdt(blob):
    (magic, totalsize, off_struct, off_strings, off_rsvmap, version,
     last_comp, boot_cpuid, size_strings, size_struct) = struct.unpack_from('>10I', blob, 0)
    assert magic == FDT_MAGIC, hex(magic)
    strings = blob[off_strings:off_strings + size_strings]

    def s(off):
        e = strings.find(b'\x00', off)
        return strings[off:e].decode('utf-8', 'replace')

    pos = off_struct
    stack = []
    root = {'name': '/', 'props': {}, 'children': [], 'parent': None}
    cur = root
    nodes = 0
    props = 0
    while True:
        tok = struct.unpack_from('>I', blob, pos)[0]
        pos += 4
        if tok == 1:  # BEGIN_NODE
            e = blob.find(b'\x00', pos)
            name = blob[pos:e].decode('utf-8', 'replace')
            pos = (e + 4) & ~3
            node = {'name': name, 'props': {}, 'children': [], 'parent': cur}
            cur['children'].append(node)
            cur = node
            nodes += 1
        elif tok == 2:  # END_NODE
            cur = cur['parent'] if cur['parent'] is not None else cur
        elif tok == 3:  # PROP
            ln, nameoff = struct.unpack_from('>II', blob, pos)
            pos += 8
            val = blob[pos:pos + ln]
            pos = (pos + ln + 3) & ~3
            cur['props'][s(nameoff)] = val
            props += 1
        elif tok == 4:
            pass
        elif tok == 9:
            break
        else:
            raise ValueError('bad fdt token %x at %x' % (tok, pos))
    return {'header': {'totalsize': totalsize, 'version': version, 'last_comp': last_comp,
                       'boot_cpuid': boot_cpuid, 'size_strings': size_strings,
                       'size_struct': size_struct, 'off_struct': off_struct,
                       'off_strings': off_strings, 'off_rsvmap': off_rsvmap},
            'root': (root['children'][0] if root['children'] and root['children'][0]['name'] == '' else root),
            'nodes': nodes, 'props': props}


def get_str(node, key):
    v = node['props'].get(key)
    if not v:
        return None
    if key in ('model', 'compatible') and v.count(b'\x00') > 1:
        return ' | '.join(x.decode('utf-8', 'replace') for x in v.split(b'\x00') if x)
    return v.rstrip(b'\x00').decode('utf-8', 'replace')


def walk(node, path=''):
    yield path or '/', node
    for c in node['children']:
        yield from walk(c, path + '/' + c['name'])


# ---------------- DTBO table ----------------
def parse_dtbo(path):
    data = open(path, 'rb').read()
    (magic, total_size, header_size, entry_size, entry_count,
     entries_off, page_size, version) = struct.unpack_from('>8I', data, 0)
    assert magic == DTBO_MAGIC, hex(magic)
    hdr = dict(magic=hex(magic), total_size=total_size, header_size=header_size,
               entry_size=entry_size, entry_count=entry_count,
               entries_off=entries_off, page_size=page_size, version=version,
               file_size=len(data))
    entries = []
    for i in range(entry_count):
        o = entries_off + i * entry_size
        dtb_size, dtb_offset, did, rev = struct.unpack_from('>4I', data, o)
        custom = list(struct.unpack_from('>4I', data, o + 16))
        entries.append(dict(i=i, dtb_size=dtb_size, dtb_offset=dtb_offset,
                            id=did, rev=rev, custom=custom))
    return hdr, entries, data


PANEL_KEYS = ('panel', 'dsi', 'display', 'backlight', 'pwm', 'lcd')
TOUCH_KEYS = ('touch', 'novatek', 'focaltech', 'ft5', 'goodix', 'gt9', 'himax', 'synaptics',
              'chipone', 'ilitek', 'nt36', 'ts_int', 'ts_reset')


def classify(path, node):
    """Return list of matched subsystem tags for a node path/props."""
    tags = []
    hay = (path + ' ' + ' '.join(node['props'].keys())).lower()
    for v in node['props'].values():
        if len(v) < 200:
            hay += ' ' + v.decode('latin1').lower()
    if any(k in hay for k in PANEL_KEYS):
        tags.append('panel/display')
    if any(k in hay for k in TOUCH_KEYS):
        tags.append('touch')
    return tags


def summarize(blob, label):
    fdt = parse_fdt(blob)
    root = fdt['root']
    frags = []
    symbols = 0
    sym_node = None
    fixups = 0
    for child in root['children']:
        if child['name'].startswith('fragment@'):
            tgt = get_str(child, 'target-path')
            tgt_ph = child['props'].get('target')
            target_ph = struct.unpack('>I', tgt_ph)[0] if tgt_ph and len(tgt_ph) == 4 else None
            ov = next((c for c in child['children'] if c['name'] == '__overlay__'), None)
            frags.append(dict(name=child['name'], target_path=tgt, target_phandle=target_ph,
                              overlay_nodes=len(ov['children']) if ov else 0))
        elif child['name'] == '__symbols__':
            sym_node = child
            symbols = len(child['props'])
        elif child['name'] == '__fixups__':
            fixups = len(child['props'])
    hits = []
    for p, n in walk(root):
        tags = classify(p, n)
        if tags:
            hits.append((p, tags))

    def u32arr(key):
        v = root['props'].get(key)
        if not v:
            return None
        return list(struct.unpack('>%dI' % (len(v) // 4), v[:len(v) // 4 * 4]))

    return dict(label=label, totalsize=fdt['header']['totalsize'], nodes=fdt['nodes'],
                props=fdt['props'], model=get_str(root, 'model'),
                compatible=get_str(root, 'compatible'),
                msm_id=u32arr('qcom,msm-id'), board_id=u32arr('qcom,board-id'),
                pmic_id=u32arr('qcom,pmic-id'),
                fragments=frags, symbols=symbols, fixups=fixups, hits=hits[:60],
                hit_count=len(hits), header=fdt['header'],
                top_children=[c['name'] for c in root['children']][:12])


def main():
    dtbo_path = '/mnt/e/rom/work/of/v3/stock/dtbo_a.bin'
    hdr, entries, data = parse_dtbo(dtbo_path)
    print(json.dumps(hdr, indent=2))
    outdir = '/mnt/e/rom/work/img-boot-group/dtbo_extract'
    os.makedirs(outdir, exist_ok=True)
    total_syms = 0
    rows = []
    for e in entries:
        blob = data[e['dtb_offset']:e['dtb_offset'] + e['dtb_size']]
        ok = blob[:4] == b'\xd0\x0d\xfe\xed'
        if not ok:
            rows.append(dict(i=e['i'], id=e['id'], rev=e['rev'], size=e['dtb_size'],
                             offset=e['dtb_offset'], err='not an FDT'))
            continue
        info = summarize(blob, 'dtb%02d' % e['i'])
        info.update(i=e['i'], id=e['id'], rev=e['rev'], size=e['dtb_size'], offset=e['dtb_offset'])
        total_syms += info['symbols']
        rows.append(info)
        fn = os.path.join(outdir, 'dtb_%02d_id%d_rev%d_size%d.dtb' % (e['i'], e['id'], e['rev'], e['dtb_size']))
        open(fn, 'wb').write(blob)
    print('\n=== entries ===')
    for r in rows:
        if 'err' in r:
            print('%2d id=0x%08x rev=0x%08x size=%-7d ERR %s' % (r['i'], r['id'], r['rev'], r['size'], r['err']))
            continue
        tgts = sorted(set((f['target_path'] or ('phandle:0x%x' % f['target_phandle'] if f['target_phandle'] else '?'))
                          for f in r['fragments']))
        print('%2d id=0x%x rev=0x%x size=%-7d nodes=%-4d syms=%-3d fix=%-3d frags=%-2d hits=%-3d' %
              (r['i'], r['id'], r['rev'], r['size'], r['nodes'], r['symbols'],
               r['fixups'], len(r['fragments']), r['hit_count']))
        print('     model=%s' % (r['model'],))
        print('     compatible=%s' % (r['compatible'],))
        print('     msm-id=%s board-id=%s pmic-id=%s' % (r['msm_id'], r['board_id'], r['pmic_id']))
        print('     targets(%d): %s' % (len(tgts), ','.join(tgts)))
    print('\nTOTAL symbols across all dtbs:', total_syms)
    json.dump(rows, open('/mnt/e/rom/work/img-boot-group/dtbo_entries.json', 'w'), indent=1, default=str)


if __name__ == '__main__':
    main()
