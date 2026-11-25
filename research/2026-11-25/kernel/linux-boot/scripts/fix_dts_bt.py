#!/usr/bin/env python3
"""fix_dts_bt.py - correct the Qualcomm Bluetooth node in the TB331FC DTS.

Why: the tree currently declares  compatible = "qcom,wcn3988-bt".
That selects QCA_WCN3988 in hci_qca.c, and btqca.c then requests
    qca/apbtfw<rom>.tlv / qca/apnv<rom>.bin
while this device's BTFM partition carries
    qca/crbtfw21.tlv  (227 KB) / qca/crnv21.bin (4.8 KB)
which is the QCA_WCN3990 family naming (btqca.c line 827: QCA_WCN3990 ->
"qca/crbtfw%02x.tlv").  The rom_ver math differs too (3988 shifts by 5,
3990 by 4), so even the file *number* would be wrong.

Usage:  fix_dts_bt.py [dts-path] [--diff out.diff]
Exit 0 = already correct or patched, 1 = pattern not found.
"""
import sys, os, difflib

DTS = '/root/linux-tb331fc/arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dts'

OLD = '''				bluetooth {
					compatible = "qcom,wcn3988-bt";
					vddio-supply = <0x4c>;
					vddxo-supply = <0x59>;
					vddrf-supply = <0xa8>;
					vddch0-supply = <0xa9>;
					max-speed = <0x30d400>;
					swctrl-gpios = <0x28 0x57 0x00>;
				};'''

NEW = '''				bluetooth {
					/* BTFM partition carries crbtfw21.tlv + crnv21.bin
					 * (WCN3990 naming). Do NOT use wcn3988-bt here:
					 * that path asks for apbtfw21.tlv/apnv21.bin and
					 * uses a different rom_ver shift.
					 */
					compatible = "qcom,wcn3990-bt";
					vddio-supply = <0x4c>;
					vddxo-supply = <0x59>;
					vddrf-supply = <0xa8>;
					vddch0-supply = <0xa9>;
					max-speed = <0x30d400>;
					/* GPIO 87 is the WCN3990 SW_CTRL *status* line -
					 * hci_qca requests it GPIOD_IN, so no output flag. */
					swctrl-gpios = <0x28 0x57 0x00>;
				};'''

OLD_BOOTARGS = '\t\tbootargs = "root=/dev/sda18 rw rootwait noinitrd init=/sbin/init console=tty0 PMOS_NOSPLASH";'

NEW_BOOTARGS = ('\t\t/* Fallback only: ABL rewrites /chosen/bootargs from the vendor_boot\n'
                '\t\t * header cmdline on every boot (proven on this device - the\n'
                '\t\t * reference port booted with the stock string below still\n'
                '\t\t * present). Kept benign on purpose: "noinitrd" would make the\n'
                '\t\t * kernel ignore the initramfs, "root=/dev/sda18" would make it\n'
                '\t\t * wait for a rootfs we do not ship.\n'
                '\t\t */\n'
                '\t\tbootargs = "console=tty0 keep_bootcon loglevel=8 rdinit=/init '
                'clk_ignore_unused pd_ignore_unused";')


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    path = args[0] if args else DTS
    diff_out = None
    if '--diff' in sys.argv:
        diff_out = sys.argv[sys.argv.index('--diff') + 1]

    src = open(path, encoding='utf-8', errors='replace').read()
    out = src

    # fix 1: bluetooth compatible
    if 'qcom,wcn3988-bt' in out:
        if OLD not in out:
            print('FAIL: expected bluetooth node not found in %s' % path)
            return 1
        out = out.replace(OLD, NEW, 1)
        print('patched: qcom,wcn3988-bt -> qcom,wcn3990-bt')
    else:
        print('ok: bluetooth already wcn3990')

    # fix 2: neutralize the inherited TB128FU bootargs
    if OLD_BOOTARGS in out:
        out = out.replace(OLD_BOOTARGS, NEW_BOOTARGS, 1)
        print('patched: /chosen/bootargs (dropped noinitrd + root=/dev/sda18)')
    elif 'noinitrd' in out:
        print('WARN: bootargs still contain noinitrd but the exact string did not match')
    else:
        print('ok: bootargs already benign')

    if out == src:
        print('already correct: %s' % path)
        return 0
    if diff_out:
        d = difflib.unified_diff(src.splitlines(True), out.splitlines(True),
                                 fromfile='a/' + os.path.basename(path),
                                 tofile='b/' + os.path.basename(path), n=3)
        open(diff_out, 'w', encoding='utf-8').write(''.join(d))
        print('diff -> %s' % diff_out)
    if not os.path.exists(path + '.orig-bt'):
        open(path + '.orig-bt', 'w', encoding='utf-8').write(src)
    open(path, 'w', encoding='utf-8').write(out)
    print('wrote %s' % path)
    return 0

if __name__ == '__main__':
    sys.exit(main())
