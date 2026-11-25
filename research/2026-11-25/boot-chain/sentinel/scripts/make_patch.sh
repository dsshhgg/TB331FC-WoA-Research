#!/bin/bash
# Build one patch that contains exactly the v9 edits (diffed against the .bak files
# that were taken before touching anything).
set -u
cd /root/woa/uefi-tb128fu || exit 1
O=/mnt/e/rom/work/woa/sentinel
P=$O/v9-sentinel.patch
: > "$P"

emit() {                       # $1 = original(.bak)  $2 = current  $3 = repo path
  {
    echo "diff --git a/$3 b/$3"
    diff -u "$1" "$2" | sed -e "1s|.*|--- a/$3|" -e "2s|.*|+++ b/$3|"
  } >> "$P"
}

emit BootShim/BootShim.S.bak-v9-20261125 BootShim/BootShim.S BootShim/BootShim.S
emit BootShim/Makefile.bak-v9-20261125   BootShim/Makefile   BootShim/Makefile
emit Silicon/Silicium/SiliciumPkg/Sec/Sec.c.bak-v9-20261125 \
     Silicon/Silicium/SiliciumPkg/Sec/Sec.c \
     Silicon/Silicium/SiliciumPkg/Sec/Sec.c

wc -l "$P"
grep -c '^diff --git' "$P"
