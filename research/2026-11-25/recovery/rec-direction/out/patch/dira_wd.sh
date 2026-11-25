#!/system/bin/sh
# Direction-A watchdog.  Runs as its own oneshot service so it survives whatever
# /system/bin/recovery does.  Everything goes to /dev/kmsg == ttyMSM0 ==
# ramoops PSTORE_CONSOLE, i.e. readable AFTER the device hangs (next boot, and even
# from the mission-2-style eMMC pull if boot ever fails).
#
# Absolute paths only: this rc file inherits init's environment, which in the stock
# ramdisk does not export PATH (only OrangeFox's init.rc does that).
T=/system/bin/toybox
SLEEP="$T sleep"
GETPROP="$T getprop"
K=/dev/kmsg

log() { echo "<0>DIRA: $*" > $K 2>/dev/null; }

upt() { echo "$("$T" cat /proc/uptime | "$T" cut -d' ' -f1)"; }

log "watchdog started pid=$$ uptime=$(upt)"

REC=$("$GETPROP" init.svc.recovery)
ADB=$("$GETPROP" init.svc.adbd)
USB=$("$GETPROP" sys.usb.config)
log "pre  recovery=[$REC] adbd=[$ADB] usb=[$USB]"

n=1
while [ $n -le 8 ]; do
    "$SLEEP" 5
    REC=$("$GETPROP" init.svc.recovery)
    ADB=$("$GETPROP" init.svc.adbd)
    USB=$("$GETPROP" sys.usb.config)
    log "t=$((n*5))s recovery=[$REC] adbd=[$ADB] usb=[$USB]"
    [ "$REC" = running ] || log "recovery service not running at t=$((n*5))s"
    case "$USB" in
        adb*|mtp,adb*) ;;
        *) log "forcing sys.usb.config=adb (stock functionfs gadget already built by init.rc)"
           "$T" setprop sys.usb.config adb ;;
    esac
    n=$((n+1))
done

# TWRP keeps its log in /tmp (tmpfs -> dies on the reboot that follows a hang).
# Push a tail of it into the kernel console so pstore keeps it.
if [ -f /tmp/recovery.log ]; then
    log "---- /tmp/recovery.log begin ----"
    "$T" tail -n 400 /tmp/recovery.log 2>/dev/null | while read -r line; do
        echo "<0>DIRA:   |$line" > $K 2>/dev/null
    done
    log "---- /tmp/recovery.log end ----"
else
    log "no /tmp/recovery.log (recovery never created it)"
fi

log "watchdog done uptime=$(upt)"
