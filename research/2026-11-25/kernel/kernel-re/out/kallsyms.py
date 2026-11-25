#!/usr/bin/env python3
"""
kallsyms.py -- standalone extractor for the compressed kallsyms table embedded in a
raw Linux kernel image (arm64 Image / x86 vmlinux), CONFIG_KALLSYMS=y,
CONFIG_KALLSYMS_BASE_RELATIVE=y (the normal Android/GKI setting).

Only the raw blob + Python stdlib: no Ghidra, no IDA, no ELF needed.

Table layout emitted by scripts/kallsyms.c (Linux 5.x/6.x, base relative):

    kallsyms_offsets[]       u32 per symbol, address = kallsyms_relative_base + offset
    kallsyms_relative_base   pointer (8 bytes on LP64)
    kallsyms_num_syms        u32
    kallsyms_names[]         per symbol: 1 length byte + token indexes  (2 byte length
                             with bit 7 set for "big" symbols on newer kernels)
    kallsyms_markers[]       u32, one entry per 256 symbols = byte offset in names[]
    kallsyms_token_table[]   256 NUL terminated substrings
    kallsyms_token_index[]   256 u16 = byte offset of each token in the table

Algorithm (self locating, no addresses hardcoded):
  1. kallsyms_markers: 4-aligned u32 run that starts with 0 and strictly increases.
     The run ends exactly where kallsyms_token_table begins.
  2. kallsyms_token_table: 256 NUL terminated strings, validated through the u16 index
     array that follows (every index must land on a token start).
  3. kallsyms_names ends at kallsyms_markers (optionally closed by a zero length
     entry). Walk all byte offsets backwards and keep those from which the length
     prefixed chain lands exactly on that end (reachability DP).
  4. for each candidate start: num_syms = u32 at start-8; offsets[] must be a non
     decreasing u32 array of num_syms entries starting at 0, followed by an 8 byte
     kernel pointer (kallsyms_relative_base) and then by the count itself; finally
     all num_syms names are decoded through the token table and must end exactly at
     the markers.
  5. emit "address type name".

Usage:
    python3 kallsyms.py <raw-kernel> <out.map> [-v]
"""
import sys, struct, argparse

def u32(d, o):
    return struct.unpack_from('<I', d, o)[0]

def read_tokens(d, pos):
    toks, p, n = [], pos, len(d)
    for _ in range(256):
        s = p
        while p < n and d[p] != 0:
            p += 1
        if p >= n:
            return None
        toks.append(d[s:p])
        p += 1
        if p - pos > 4096:
            return None
    return toks, p

def check_token_index(d, toks, tok_start, p):
    starts, q = set(), tok_start
    for t in toks:
        starts.add(q - tok_start)
        q += len(t) + 1
    for pad in range(0, 17):
        if p + pad + 512 > len(d):
            return False
        idx = struct.unpack_from('<256H', d, p + pad)
        if all(v in starts for v in idx):
            return True
    return False

def find_markers_candidates(d, verbose=False):
    n, out = len(d), []
    for off in range(0, n - 40, 4):
        if d[off:off+4] != b'\x00\x00\x00\x00':
            continue
        vals = [0]
        p = off + 4
        while p + 4 <= n:
            v = u32(d, p)
            if v <= vals[-1] or v > 0x4000000:
                break
            vals.append(v)
            p += 4
        if len(vals) >= 32:
            out.append((off, p, len(vals)))
    if verbose:
        print("[*] %d marker-run candidate(s)" % len(out))
    return out

def names_start_candidates(d, markers_start, limit=12 << 20):
    terminal = markers_start - 1 if d[markers_start - 1] == 0 else markers_start
    good = {markers_start, terminal}
    cands = []
    lo = max(0, markers_start - limit)
    for p in range(markers_start - 1, lo - 1, -1):
        b = d[p]
        if b == 0:
            continue
        if b & 0x80:
            if p + 1 >= len(d):
                continue
            ln = (b & 0x7f) | (d[p + 1] << 7); hdr = 2
        else:
            ln = b; hdr = 1
        if (p + hdr + ln) in good:
            good.add(p)
            cands.append(p)
    return cands

def plausible_base(v):
    return (0xffffff0000000000 <= v <= 0xffffffffffffffff) or (0x30000000 <= v <= 0x80000000)

def try_candidate(d, p, markers_start, toks, verbose=False):
    if p < 64:
        return None
    n = u32(d, p - 8)
    if not (5000 < n < 600000):
        return None
    st0 = p - 8 - 4 * n
    if st0 < 0:
        return None
    # cheap prefilter: decode the first symbol and require it to be "_text" (every
    # Linux kallsyms table starts with it) before doing any expensive work
    ln = d[p]
    if ln == 0 or ln & 0x80:
        return None
    if p + 1 + ln >= len(d):
        return None
    if b''.join(toks[b] for b in d[p + 1:p + 1 + ln])[1:] != b'_text':
        return None
    base, st = 0, 0
    # offsets[] may be separated from kallsyms_relative_base by a few bytes of
    # alignment padding, so scan a small window around the nominal position
    for pad in range(-40, 41, 4):
        cs = st0 + pad
        if cs < 0 or cs + 4 * n > p or u32(d, cs) != 0:
            continue
        prev, ok = 0, True
        for i in range(0, n, max(1, n // 8192)):
            x = u32(d, cs + 4 * i)
            if x < prev or x > 0x4000000:
                ok = False
                break
            prev = x
        if not ok or u32(d, cs + 4 * (n - 1)) > 0x4000000:
            continue
        for bp in range(0, 20, 4):
            if cs + 4 * n + bp + 8 > p:
                break
            v = struct.unpack_from('<Q', d, cs + 4 * n + bp)[0]
            if plausible_base(v):
                base, st = v, cs
                break
        if base:
            break
    if not base:
        return None
    names, pos, nf = [], p, len(d)
    for _ in range(n):
        if pos >= nf:
            return None
        ln = d[pos]; pos += 1
        if ln & 0x80:
            ln = (ln & 0x7f) | (d[pos] << 7); pos += 1
        if ln == 0 or pos + ln > nf:
            return None
        names.append(b''.join(toks[b] for b in d[pos:pos + ln]))
        pos += ln
    terminal = markers_start - 1 if d[markers_start - 1] == 0 else markers_start
    if pos != terminal and not (markers_start - 4 <= pos <= markers_start):
        return None
    if verbose:
        print("[+] kallsyms_offsets @0x%x n=%d relative_base=0x%x names @0x%x..0x%x" %
              (st, n, base, p, pos))
    return dict(offsets=st, n=n, base=base, names=names)

def emit(d, lay, out):
    rows, st, base = [], lay['offsets'], lay['base']
    for i, nm in enumerate(lay['names']):
        if not nm:
            continue
        rows.append(((base + u32(d, st + 4 * i)) & 0xffffffffffffffff,
                     chr(nm[0]), nm[1:].decode('latin1')))
    rows.sort()
    with open(out, 'w', encoding='utf-8') as f:
        for addr, t, name in rows:
            f.write('%016x %s %s\n' % (addr, t, name))
    print("[+] wrote %s : %d symbols" % (out, len(rows)))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('kernel')
    ap.add_argument('out')
    ap.add_argument('-v', '--verbose', action='store_true')
    a = ap.parse_args()
    d = open(a.kernel, 'rb').read()
    print("[*] %s  %d bytes" % (a.kernel, len(d)))
    for mstart, tok_start, nvals in find_markers_candidates(d, a.verbose):
        r = read_tokens(d, tok_start)
        if not r:
            continue
        toks, tok_end = r
        if not check_token_index(d, toks, tok_start, tok_end):
            continue
        if a.verbose:
            print("[+] kallsyms_markers @0x%x (%d entries, ~%d syms)" % (mstart, nvals, nvals * 256))
            print("[+] kallsyms_token_table @0x%x (%d bytes)" % (tok_start, tok_end - tok_start))
        cands = names_start_candidates(d, mstart)
        if a.verbose:
            print("[*] %d candidate names starts" % len(cands))
        for p in sorted(cands):
            lay = try_candidate(d, p, mstart, toks, a.verbose)
            if lay:
                emit(d, lay, a.out)
                return 0
    print("[-] no consistent kallsyms layout found")
    return 1

if __name__ == '__main__':
    sys.exit(main())
