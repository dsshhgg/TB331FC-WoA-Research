#!/usr/bin/env python3
"""Verify vbmeta hash descriptors against on-disk partition images (read-only)."""
import sys, os, struct, hashlib
sys.path.insert(0, '/mnt/e/rom/work/tools')
import avbtool

def load(path):
    avb = avbtool.Avb()
    ih = avbtool.ImageHandler(path, read_only=True)
    footer, header, descs, size = avb._parse_image(ih)
    return footer, header, descs, size

def hash_desc_check(desc, path, limit=None):
    data = open(path, 'rb').read()
    n = desc.image_size
    blob = data[:n]
    h = hashlib.sha256()
    h.update(desc.salt)
    h.update(blob)
    return h.digest() == desc.digest, h.hexdigest(), len(data), n

MAP = {
    'boot': '/mnt/e/rom/work/a17dump/boot_a.img',
    'dtbo': '/mnt/e/rom/work/of/v3/stock/dtbo_a.bin',
    'init_boot': '/mnt/e/rom/work/zui16_flash/image/init_boot.img',
    'vendor_boot': '/mnt/e/rom/work/of/v3/stock/vendor_boot_a.bin',
    'recovery': '/mnt/e/rom/work/of/v3/recovery_of_tb331fc_v3.img',
    'system': '/mnt/e/rom/work/a17dump/system_a.img',
    'product': '/mnt/e/rom/work/a17dump/product_a.img',
    'system_ext': '/mnt/e/rom/work/a17dump/system_ext_a.img',
}

for vmp in ('/mnt/e/rom/work/a17dump/vbmeta_a.img', '/mnt/e/rom/work/a17dump/vbmeta_system_a.img'):
    print('###', vmp)
    footer, header, descs, size = load(vmp)
    print('image_size=%d rollback=%d flags=%d algo=%d loc=%d' % (size, header.rollback_index, header.flags,
                                                                  header.algorithm_type, header.rollback_index_location))
    for d in descs:
        t = type(d).__name__
        if t == 'AvbHashDescriptor':
            p = MAP.get(d.partition_name)
            print('HASH  %-12s image_size=%-12d salt=%s' % (d.partition_name, d.image_size, d.salt.hex()))
            print('      declared_digest=%s  flags=%d' % (d.digest.hex(), d.flags))
            if p and os.path.exists(p):
                ok, actual, fsz, n = hash_desc_check(d, p)
                print('      file=%s size=%d  NEEDS=%d  actual=%s  => %s'
                      % (os.path.basename(p), fsz, n, actual, 'MATCH' if ok else 'MISMATCH'))
            else:
                print('      file=NOT AVAILABLE')
        elif t == 'AvbHashtreeDescriptor':
            print('TREE  %-12s image_size=%-12d tree_off=%d tree_size=%d salt=%s' %
                  (d.partition_name, d.image_size, d.tree_offset, d.tree_size, d.salt.hex()))
            print('      root=%s block=%d/%d fec_roots=%d flags=%d' %
                  (d.root_digest.hex(), d.data_block_size, d.hash_block_size, d.fec_num_roots, d.flags))
        elif t == 'AvbChainPartitionDescriptor':
            print('CHAIN %-12s rollback_loc=%d flags=%d pkl=%d pubkey_sha1=%s' %
                  (d.partition_name, d.rollback_index_location, d.flags, len(d.public_key),
                   hashlib.sha1(d.public_key).hexdigest()))
        elif t == 'AvbPropertyDescriptor':
            print('PROP  %s = %r' % (d.key, d.value))
        else:
            print('OTHER', t)
    print()
