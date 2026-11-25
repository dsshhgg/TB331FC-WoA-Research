#!/usr/bin/env python3
d = open('/mnt/e/rom/work/zui16_flash/image/boot.img', 'rb').read()
a, b = 46825472, 46841856
print('stock boot: 16 KiB tail', a, b, 'len', b - a, 'nonzero', sum(1 for x in d[a:b] if x))
print('head of tail:', d[a:a + 64].hex())
print('at image_size 46841856:', d[b:b + 64].hex())
print('nonzero after image_size .. EOF:', sum(1 for x in d[b:] if x))
