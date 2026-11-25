#!/system/bin/sh
# KernelSU: 模块卸载时清理（iptables 规则 + settings 复位）
MODDIR=${0%/*}
. "$MODDIR/common.sh"
resolve_uid
while iptables -w -C OUTPUT -m owner --uid-owner "$UID_" -j REJECT --reject-with icmp-port-unreachable 2>/dev/null; do
  iptables -w -D OUTPUT -m owner --uid-owner "$UID_" -j REJECT --reject-with icmp-port-unreachable
done
while ip6tables -w -C OUTPUT -m owner --uid-owner "$UID_" -j REJECT --reject-with icmp6-port-unreachable 2>/dev/null; do
  ip6tables -w -D OUTPUT -m owner --uid-owner "$UID_" -j REJECT --reject-with icmp6-port-unreachable
done
settings delete system virus_scan_install >/dev/null 2>&1
settings put secure miui_safe_mode 1
say "cleaned"
