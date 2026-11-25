# -*- coding: utf-8 -*-
"""scan_shard.py N OF -- measure top-level children of a drive root, shard N of OF.
Uses cached DirEntry data only (no per-entry stat for dirs)."""
import os, sys, time

GB = 1024.0 ** 3
ROOT = "E:/"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "shard-%s.txt" % sys.argv[1])
N = int(sys.argv[1]); OF = int(sys.argv[2])
SKIP = {"rom"}

def w(line):
    with open(OUT, 'a', encoding='utf-8') as f:
        f.write(line + "\n")

try:
    kids = sorted(os.scandir(ROOT), key=lambda k: k.name.lower())
except OSError as e:
    w("!! " + str(e)); raise SystemExit(1)

mine = [k for i, k in enumerate(kids) if i % OF == N and k.name.lower() not in SKIP]
open(OUT, 'w', encoding='utf-8').close()

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
                    if e.is_symlink():
                        continue
                    if e.is_dir(follow_symlinks=False):
                        stack.append(e.path)
                    else:
                        st = e.stat(follow_symlinks=False)   # cached for files
                        total += st.st_size; n += 1
                except OSError:
                    pass
    return total, n

for k in mine:
    t0 = time.time()
    try:
        if k.is_symlink():
            w("    LINK    %s" % k.name); continue
        if k.is_dir(follow_symlinks=False):
            s, n = du(k.path)
        else:
            s = k.stat(follow_symlinks=False).st_size; n = 1
    except OSError as ex:
        w("    ERR     %s  %s" % (k.name, ex)); continue
    w("%9.3f GiB  %9d f  %7.1fs  %s" % (s / GB, n, time.time() - t0, k.name))
w("SHARD %d DONE" % N)
