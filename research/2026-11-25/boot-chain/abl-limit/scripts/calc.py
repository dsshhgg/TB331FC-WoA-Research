P = 4096
TOP = 0x40000000 + 0x5700000      # KernelBaseAddr + KernelSize  = 0x45700000
BASE = 0x40000000
KL_RAW = BASE                      # uncompressed Image: KL = base + text_offset(0)
KL_GZ  = BASE + 0x80000            # compressed path: base + 0x80000

DTSZ = 0x200000
INIT_RD_RAW = 2005893
VEND_RD = 11628676
STOCK_REC = 14572954

def au(x, p=P):
    return (x + p - 1) // p * p

def compute(kernel_image_size, kl, init_rd=INIT_RD_RAW, vend=VEND_RD, rec=STOCK_REC):
    T = au(init_rd) + vend + rec
    R = TOP - au(T) - P
    Dtb = R - (P + DTSZ)
    avail = Dtb - (TOP - (TOP - kl))  # placeholder
    avail = Dtb - kl
    return dict(T=T, R=R, Dtb=Dtb, avail=avail, ok=avail >= kernel_image_size,
                slack=avail - kernel_image_size)

def tmax(kernel_image_size, kl):
    # largest T with avail >= image_size
    A = (TOP - kl) - 2*P - DTSZ - kernel_image_size
    A = A // P * P                    # T must satisfy align_up(T) <= A
    return A

def rmax(kernel_image_size, kl, init_rd=INIT_RD_RAW, vend=VEND_RD):
    T = tmax(kernel_image_size, kl)
    fixed = au(init_rd) + vend
    # need align_up(fixed+R) <= T
    R = T - fixed
    while au(fixed + R) > T:
        R -= 1
    return R, T

kernels = [
    ('stock ZUI16 boot.img (A14)',   0x2D50000),
    ('KSU boot-main 1.3.2 / a17 dump', 0x29C0000),
    ('linux-boot boot_a-linux',      0x25F0000),
]

print('TOP = 0x%X (%d)' % (TOP, TOP))
print('top-KL(raw) = 0x%X = %d' % (TOP-KL_RAW, TOP-KL_RAW))
print()
for name, isz in kernels:
    r, t = rmax(isz, KL_RAW)
    print('%-32s image_size=0x%X (%d)' % (name, isz, isz))
    print('    T_max=%d (0x%X) %.2f MB   recovery_rd_max=%d (0x%X) %.3f MB'
          % (t, t, t/1048576, r, r, r/1048576))
print()
print('--- 实测三点（KSU 内核 = 0x29C0000）---')
for label, rec in [('原厂 recovery 14,572,954', STOCK_REC),
                   ('30,000,000', 30000000),
                   ('47,628,167', 47628167)]:
    for kn, isz in [('KSU', 0x29C0000), ('stock', 0x2D50000)]:
        c = compute(isz, KL_RAW, rec=rec)
        print('%-26s [%-5s img=0x%X] T=%d(0x%X) R=0x%X Dtb=0x%X avail=%d(%.2fMB) slack=%+d %s'
              % (label, kn, isz, c['T'], c['T'], c['R'], c['Dtb'], c['avail'], c['avail']/1048576,
                 c['slack'], 'PASS' if c['ok'] else 'FAIL'))
print()
print('--- 仅 Dtb>KL 的绝对上界 ---')
print('T_abs = %d (0x%X)' % ((TOP-KL_RAW) - 2*P - DTSZ, (TOP-KL_RAW) - 2*P - DTSZ))
print('recovery_rd_abs = %d' % (((TOP-KL_RAW) - 2*P - DTSZ) - (au(INIT_RD_RAW)+VEND_RD)))
