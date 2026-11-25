# -*- coding: utf-8 -*-
"""scan_e.py ROOT SKIP... -- per-top-level-child size+count for a drive root."""
import os, sys, time

REPARSE = 0x400
GB = 1024.0 ** 3
OUTDIR = os.path.dirname(os.path.abspath(__file__))

ROOT = sys.argv[1]
SKIP = set(a.lower() for a in sys.argv[2:])
LOGP = os.path.join(OUTDIR, 'scan-e.txt')

def w(line):
    with open(LOGP, 'a', encoding='utf-8') as f:
        f.write(line + "\n")

def is_reparse(entry):
    try:
        st = entry.stat(follow_symlinks=False)
        return bool(getattr(st, 'st_file_attributes', 0) & REPARSE)
    except OSError:
        return True

def du(top):
    total = 0; n = 0; stack = [top]
    while stack:
        d = stack.pop()
        try:
            it = os.scandir(d)
        except OSError:
            continue
        with it:
            for e in it:
                try:
                    if e.is_dir(follow_symlinks=False):
                        if not is_reparse(e):
                            stack.append(e.path)
                    elif e.is_file(follow_symlinks=False):
                        if is_reparse(e):
                            continue
                        total += e.stat(follow_symlinks=False).st_size
                        n += 1
                except OSError:
                    pass
    return total, n

open(LOGP, 'w', encoding='utf-8').close()
w("ROOT=%s" % ROOT)
rows = []
try:
    kids = sorted(os.scandir(ROOT), key=lambda k: k.name.lower())
except OSError as e:
    w("!! " + str(e)); sys.exit(1)
for k in kids:
    if k.name.lower() in SKIP:
        w("   SKIP (already measured)  %s" % k.name); continue
    try:
        if is_reparse(k):
            w("    LINK    %s" % k.name); continue
        if k.is_dir(follow_symlinks=False):
            s, n = du(k.path)
        else:
            s = k.stat(follow_symlinks=False).st_size; n = 1
    except OSError as ex:
        w("    ERR     %s  %s" % (k.name, ex)); continue
    rows.append((s, n, k.name))
    w("%9.3f GiB  %9d f  %s" % (s / GB, n, k.name))

rows.sort(key=lambda r: -r[0])
w("")
w("=== SORTED ===")
tot = 0
for s, n, name in rows:
    tot += s
    w("%9.3f GiB  %9d f  %s" % (s / GB, n, name))
w("")
w("TOTAL(excluding skipped) %.3f GiB over %d files" % (tot / GB, sum(r[1] for r in rows)))
print("DONE total=%.3f GiB" % (tot / GB))
