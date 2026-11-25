import struct, io, gzip, hashlib, sys, json

path = sys.argv[1] if len(sys.argv) > 1 else '/root/woa/uefi-tb128fu/Mu-tb331fc.img'
d = open(path, 'rb').read()
out = {}
out['path'] = path
out['image_size'] = len(d)
out['sha256'] = hashlib.sha256(d).hexdigest()

# --- android boot image header (v1: kernel + ramdisk addr/size, then dtb) ---
magic = d[:8]
ks = struct.unpack('<I', d[8:12])[0]
ka = struct.unpack('<I', d[12:16])[0]
rs = struct.unpack('<I', d[16:20])[0]
ps = struct.unpack('<I', d[36:40])[0]
hv = struct.unpack('<I', d[40:44])[0]
out['android_magic'] = magic.decode('ascii', 'replace').rstrip('\x00')
out['header_version'] = hv
out['page_size'] = ps
out['kernel_size'] = ks
out['kernel_addr'] = hex(ka)
out['ramdisk_size'] = rs

# --- locate payload gzip stream from page 1 up to first FDT magic ---
off = d.find(b'\xd0\x0d\xfe\xed', ps, ps + ks)
gz = d[ps:off]
body = gzip.GzipFile(fileobj=io.BytesIO(gz)).read()
out['gzip_stream'] = len(gz)
out['gzip_decompressed'] = len(body)
out['dtb_offset'] = off
out['dtb_size'] = ks - (off - ps)

# gzip trailer ISIZE must equal decompressed length, and ABL walks the raw
# deflate stream only, so verify the stream we produced is exactly one member.
out['gzip_isize_ok'] = struct.unpack('<I', gz[-4:])[0] == len(body) & 0xFFFFFFFF

# --- arm64 Image header inside the payload (that is the boot shim) ---
out['shim_text_offset'] = hex(struct.unpack('<Q', body[8:16])[0])
out['shim_image_size_field'] = hex(struct.unpack('<Q', body[16:24])[0])
out['shim_arm64_magic'] = body[56:60].decode('ascii', 'replace')

# --- FD sits right behind the shim; find the FV header (_FVH) ---
fvh = body.find(b'_FVH', 0, 0x400)
out['fvh_at'] = hex(fvh)
out['fv_length'] = hex(struct.unpack('<Q', body[fvh - 8:fvh])[0])
out['shim_bytes'] = fvh - 0x28  # _FVH sits at FV header + 0x28

# --- the shim inside the payload must be byte-identical to BootShim.bin ---
shim = body[:out['shim_bytes']]
ref = open(sys.argv[2] if len(sys.argv) > 2 else
           '/root/woa/uefi-tb128fu/BootShim/BootShim.bin', 'rb').read()
out['shim_bin_bytes'] = len(ref)
out['shim_identical'] = shim == ref
out['shim_sha256'] = hashlib.sha256(shim).hexdigest()[:16]

# --- SEC's band colours should be present in the FD (advisory, not a gate) ---
fd = body[out['shim_bytes']:]
for name, imm in [('BLUESEC', 0xFF0000FF), ('YELLOWSEC', 0xFFFFFF00), ('ORANGESEC', 0xFFFF8000)]:
    out['fd_has_' + name] = fd.find(struct.pack('<I', imm)) >= 0

# --- single appended DTB check (ABL: fdt_check_header(p + totalsize)) ---
tot = struct.unpack('>I', d[off + 4:off + 8])[0]
out['dtb_totalsize'] = tot
nxt = d[off + tot:off + tot + 4]
out['bytes_after_dtb'] = nxt.hex()
out['single_dtb_ok'] = (nxt != b'\xd0\x0d\xfe\xed') and (tot == out['dtb_size'])
out['kernel_size_ok'] = ks == len(gz) + out['dtb_size']

for k, v in out.items():
    print('%-22s %s' % (k, v))
json.dump(out, open('/tmp/v9_verify.json', 'w'), indent=1)
