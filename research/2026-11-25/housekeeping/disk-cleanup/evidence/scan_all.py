# -*- coding: utf-8 -*-
"""scan_all.py  -- single-pass walk of E:\rom.
Emits: depth1/2/3 size+filecount buckets, big-file list (>=LIMIT), exceptions.
Reparse points (junctions/symlinks) are not followed and are reported separately.
"""
import os, sys, time, json

REPARSE = 0x400
GB = 1024.0 ** 3
MB = 1024.0 ** 2

ROOT = sys.argv[1] if len(sys.argv) > 1 else r"E:\rom"
BIG_LIMIT = 500 * 1024 * 1024
OUT = os.path.dirname(os.path.abspath(__file__))

def is_reparse(entry):
    try:
        st = entry.stat(follow_symlinks=False)
        return bool(getattr(st, 'st_file_attributes', 0) & REPARSE)
    except OSError:
        return True

buckets = {}          # relpath (depth<=3) -> [bytes, files]
big = []              # (bytes, mtime, relpath)
links = []
errors = []

t0 = time.time()
nfiles = 0
nbytes = 0
stack = [(ROOT, ())]   # (abspath, rel components tuple, depth already)
while stack:
    d, parts = stack.pop()
    try:
        it = os.scandir(d)
    except OSError as e:
        errors.append("%s : %s" % (d, e))
        continue
    with it:
        for e in it:
            rel_parts = parts + (e.name,)
            try:
                if e.is_dir(follow_symlinks=False):
                    if is_reparse(e):
                        links.append("\\".join(rel_parts))
                        continue
                    if len(rel_parts) <= 3:
                        key = "\\".join(rel_parts)
                        buckets.setdefault(key, [0, 0])
                    stack.append((e.path, rel_parts))
                elif e.is_file(follow_symlinks=False):
                    if is_reparse(e):
                        links.append("\\".join(rel_parts) + "  [file-link]")
                        continue
                    st = e.stat(follow_symlinks=False)
                    sz = st.st_size
                    nfiles += 1
                    nbytes += sz
                    for k in range(1, min(len(rel_parts), 4)):
                        key = "\\".join(rel_parts[:k])
                        b = buckets.get(key)
                        if b is None:
                            b = buckets[key] = [0, 0]
                        b[0] += sz
                        b[1] += 1
                    if sz >= BIG_LIMIT:
                        big.append((sz, st.st_mtime, "\\".join(rel_parts)))
            except OSError as ex:
                errors.append("%s : %s" % (e.path, ex))

elapsed = time.time() - t0

def w(path, text):
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)

lines = []
lines.append("ROOT=%s  files=%d  bytes=%d  %.3f GiB  elapsed=%.1fs"
             % (ROOT, nfiles, nbytes, nbytes / GB, elapsed))
lines.append("")
lines.append("=== buckets (depth<=3) sorted by size ===")
rows = sorted(buckets.items(), key=lambda kv: -kv[1][0])
for k, (b, n) in rows:
    lines.append("%9.3f GB  %9d f  %s" % (b / GB, n, k))
lines.append("")
lines.append("=== files >= %.0f MB (%d) sorted by size ===" % (BIG_LIMIT / MB, len(big)))
big.sort(key=lambda x: -x[0])
for b, mt, p in big:
    lines.append("%9.3f GB  %8.1f MB  %s  %s"
                 % (b / GB, b / MB, time.strftime('%Y-%m-%d %H:%M', time.localtime(mt)), p))
lines.append("")
lines.append("=== reparse points NOT followed (%d) ===" % len(links))
lines.extend(sorted(links))
lines.append("")
lines.append("=== errors (%d) ===" % len(errors))
lines.extend(errors[:400])
w(os.path.join(OUT, 'scan-all.txt'), "\n".join(lines) + "\n")
print("done files=%d bytes=%.3f GiB elapsed=%.1fs buckets=%d big=%d links=%d errors=%d"
      % (nfiles, nbytes / GB, elapsed, len(buckets), len(big), len(links), len(errors)))
