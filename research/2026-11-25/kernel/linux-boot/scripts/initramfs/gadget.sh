#!/bin/sh
# USB gadget for the TB331FC mainline port: CDC-ACM serial console.
# (RNDIS/USB-net intentionally left out of the minimal image; add it back the
#  moment you have a userspace that wants networking.)
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

G=/sys/kernel/config/usb_gadget/tb331fc

echo "[gadget] setting up CDC-ACM"
mkdir -p /sys/kernel/config 2>/dev/null
mount -t configfs none /sys/kernel/config 2>/dev/null

if [ -d "$G" ]; then
    echo "" > "$G/UDC" 2>/dev/null
    rm -f "$G/configs/c.1/acm.GS0" 2>/dev/null
    rmdir "$G/functions/acm.GS0" 2>/dev/null
    rmdir "$G/configs/c.1/strings/0x409" "$G/configs/c.1" 2>/dev/null
    rmdir "$G/strings/0x409" 2>/dev/null
    rmdir "$G" 2>/dev/null
fi

mkdir -p "$G" || exit 1
cd "$G" || exit 1
echo 0x1d6b > idVendor
echo 0x0104 > idProduct
echo 0x0100 > bcdDevice
echo 0x0200 > bcdUSB
mkdir -p strings/0x409
echo "TB331FCLINUX0001" > strings/0x409/serialnumber
echo "Lenovo"            > strings/0x409/manufacturer
echo "TB331FC mainline"  > strings/0x409/product
mkdir -p configs/c.1
mkdir -p configs/c.1/strings/0x409
echo "CDC ACM" > configs/c.1/strings/0x409/configuration
echo 500 > configs/c.1/MaxPower
mkdir -p functions/acm.GS0
ln -sf functions/acm.GS0 configs/c.1/ 2>/dev/null

UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
if [ -z "$UDC" ]; then
    echo "[gadget] no UDC - USB gadget not attached (check USB_DWC3_QCOM / extcon)"
    exit 1
fi
echo "$UDC" > UDC
echo "[gadget] attached to $UDC"

for i in 1 2 3 4 5 6 7 8 9 10; do
    [ -c /dev/ttyGS0 ] && { echo "[gadget] /dev/ttyGS0 ready"; exit 0; }
    sleep 1
done
echo "[gadget] ttyGS0 did not appear"
exit 1
