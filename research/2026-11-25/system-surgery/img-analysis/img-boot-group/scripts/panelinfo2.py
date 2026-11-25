#!/usr/bin/env python3
"""Panel timing + phandle map from the live dtbo overlay (entry 2)."""
import importlib.util, struct
spec = importlib.util.spec_from_file_location('dtbo', '/mnt/e/rom/work/img-boot-group/tools/dtbo.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

hdr, entries, data = m.parse_dtbo('/mnt/e/rom/work/of/v3/stock/dtbo_a.bin')
e = entries[2]
fdt = m.parse_fdt(data[e['dtb_offset']:e['dtb_offset'] + e['dtb_size']])
root = fdt['root']

# phandle -> path map
ph = {}
for p, n in m.walk(root):
    v = n['props'].get('phandle')
    if v and len(v) == 4:
        ph[struct.unpack('>I', v)[0]] = p

for k in (0x35, 0x36, 0x37, 0x33, 0x34, 0x30):
    print('phandle 0x%x -> %s' % (k, ph.get(k)))

want = ('qcom,mdss-dsi-panel-width', 'qcom,mdss-dsi-panel-height', 'qcom,mdss-dsi-h-front-porch',
        'qcom,mdss-dsi-h-back-porch', 'qcom,mdss-dsi-h-pulse-width', 'qcom,mdss-dsi-h-sync-skew',
        'qcom,mdss-dsi-v-back-porch', 'qcom,mdss-dsi-v-front-porch', 'qcom,mdss-dsi-v-pulse-width',
        'qcom,mdss-dsi-panel-framerate', 'qcom,mdss-dsi-panel-clockrate',
        'qcom,mdss-dsi-h-sync-pulse', 'qcom,mdss-dsi-traffic-mode', 'qcom,mdss-dsi-bllp-eof-power-mode',
        'qcom,mdss-dsi-bllp-power-mode', 'qcom,mdss-dsi-lane-0-state', 'qcom,mdss-dsi-lane-1-state',
        'qcom,mdss-dsi-lane-2-state', 'qcom,mdss-dsi-lane-3-state', 'qcom,mdss-dsi-t-clk-post',
        'qcom,mdss-dsi-t-clk-pre', 'qcom,mdss-dsi-dma-trigger', 'qcom,mdss-dsi-mdp-trigger',
        'qcom,mdss-dsi-panel-phy-timings', 'qcom,mdss-dsi-display-timings', 'qcom,mdss-dsi-timing-default',
        'qcom,mdss-dsi-panel-jitter', 'qcom,mdss-dsi-h-left-border', 'qcom,mdss-dsi-v-top-border',
        'qcom,mdss-dsi-panel-broadcast-mode')

for p, n in m.walk(root):
    if n['name'].startswith('qcom,mdss_dsi_panel_p255'):
        print('\n===', p)
        for k, v in n['props'].items():
            if k in ('qcom,mdss-dsi-panel-width', 'qcom,mdss-dsi-panel-height',
                     'qcom,mdss-dsi-panel-framerate', 'qcom,mdss-dsi-panel-clockrate',
                     'qcom,mdss-dsi-panel-phy-timings', 'qcom,mdss-dsi-timing-default',
                     'qcom,mdss-dsi-panel-type', 'qcom,mdss-dsi-panel-name'):
                print('   %-38s %r' % (k, v[:40]))
        for t in n['children']:
            print('   timings node:', t['name'], 'children:', [c['name'] for c in t['children']],
                  'props:', list(t['props'].keys()))
            for c in t['children']:
                print('     --', c['name'])
                for k, v in c['props'].items():
                    if k in want or k in ('clock-frequency', 'hactive', 'vactive', 'refresh-rate',
                                          'hfront-porch', 'hback-porch', 'hsync-len', 'vfront-porch',
                                          'vback-porch', 'vsync-len', 'qcom,mdss-dsi-panel-width',
                                          'qcom,mdss-dsi-panel-height', 'qcom,mdss-dsi-h-front-porch',
                                          'qcom,mdss-dsi-h-back-porch', 'qcom,mdss-dsi-h-pulse-width',
                                          'qcom,mdss-dsi-v-back-porch', 'qcom,mdss-dsi-v-front-porch',
                                          'qcom,mdss-dsi-v-pulse-width', 'qcom,mdss-dsi-panel-framerate',
                                          'qcom,mdss-dsi-panel-clockrate', 'qcom,mdss-dsi-panel-jitter',
                                          'qcom,mdss-dsi-t-clk-post', 'qcom,mdss-dsi-t-clk-pre',
                                          'qcom,mdss-dsi-panel-phy-timings'):
                        print('        %-40s %r' % (k, v[:60]))
