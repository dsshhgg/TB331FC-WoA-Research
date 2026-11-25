#!/bin/bash
cd /root/linux-tb331fc || exit 1
echo "=== does the real header exist? ==="
ls -la include/uapi/linux/input-event-codes.h | awk '{print $5, $9}'
grep -c 'define KEY_POWER' include/uapi/linux/input-event-codes.h
echo
echo "=== how does upstream link it? (check a sibling symlink that survived) ==="
find include/dt-bindings -type l | head -5 | while read -r l; do echo "$l -> $(readlink "$l")"; done
echo
echo "=== all 0-byte files under include/ and scripts/ (excluding generated) ==="
find include scripts -type f -size 0 2>/dev/null | grep -v 'generated' | head -20
echo
echo "=== total 0-byte files that look like broken symlinks (parent dir has similar real files) ==="
find . -maxdepth 4 -type f -size 0 -name '*.h' 2>/dev/null | head -20
