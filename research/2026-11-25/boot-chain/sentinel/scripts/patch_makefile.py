import pathlib, sys
p = pathlib.Path('/root/woa/uefi-tb128fu/BootShim/Makefile')
t = p.read_text()
old = 'CFLAGS            = --target=$(TARGET)\n'
new = ('CFLAGS            = --target=$(TARGET)\n'
       '# 0 = the real image; 1 = control image that paints RED and stops before the\n'
       '# FD copy (see BootShim.S).  Defaults to 0, so an ordinary build is unchanged.\n'
       'SENTINEL_HALT    ?= 0\n'
       'CFLAGS           += -DSENTINEL_HALT=$(SENTINEL_HALT)\n')
if 'SENTINEL_HALT' in t:
    print('already patched')
    sys.exit(0)
if old not in t:
    print('anchor not found')
    sys.exit(1)
p.write_text(t.replace(old, new, 1))
print('Makefile patched')
