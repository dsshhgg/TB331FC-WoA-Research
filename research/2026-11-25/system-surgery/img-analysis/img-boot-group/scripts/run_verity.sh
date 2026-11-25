#!/bin/bash
cd /mnt/e/rom/work/img-boot-group/tools || exit 1
for f in system_ext_a system_a product_a; do
  python3 verity_fast.py "/mnt/e/rom/work/a17dump/${f}.img" 0000000000000000000000000000000000000000000000000000000000000001
done
