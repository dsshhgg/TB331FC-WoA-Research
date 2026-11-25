#!/bin/bash
cd /root/linux-tb331fc || exit 1
f=include/dt-bindings/input/linux-event-codes.h
echo "=== $f ==="
ls -la "$f" 2>/dev/null || echo MISSING
echo "size: $(stat -c%s "$f" 2>/dev/null)"
echo "KEY_POWER present? $(grep -c 'KEY_POWER' "$f" 2>/dev/null)"
echo "--- head 6 ---"; head -6 "$f" 2>/dev/null
echo "--- tail 4 ---"; tail -4 "$f" 2>/dev/null
echo
echo "=== other suspicious 0-byte or truncated headers under include/dt-bindings ==="
find include/dt-bindings -type f -size 0 2>/dev/null | head -20
echo "count of 0-byte files: $(find include/dt-bindings -type f -size 0 | wc -l)"
echo
echo "=== compare: does upstream have KEY_POWER in that file? (expected ~1) ==="
grep -n 'define KEY_POWER' "$f" 2>/dev/null | head -2
