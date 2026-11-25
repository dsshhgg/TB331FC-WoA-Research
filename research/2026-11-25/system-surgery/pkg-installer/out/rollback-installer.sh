#!/system/bin/sh
# 回滚 block-installer.sh：删 iptables 规则 + settings 复位 + （可选）恢复 prefs 备份
set -u
PKG=com.miui.packageinstaller
BK=/data/local/tmp/installer-shared_prefs.bak
say() { echo "[installer-rollback] $*"; }

UID_=$(cmd package list packages -U 2>/dev/null | grep -F "package:$PKG " | head -1 | sed 's/.*uid://')
[ -z "${UID_:-}" ] && { say "找不到 uid"; exit 2; }

while iptables -w -C OUTPUT -m owner --uid-owner "$UID_" -j REJECT --reject-with icmp-port-unreachable 2>/dev/null; do
  iptables -w -D OUTPUT -m owner --uid-owner "$UID_" -j REJECT --reject-with icmp-port-unreachable && say "ipv4 rule removed"
done
while ip6tables -w -C OUTPUT -m owner --uid-owner "$UID_" -j REJECT --reject-with icmp6-port-unreachable 2>/dev/null; do
  ip6tables -w -D OUTPUT -m owner --uid-owner "$UID_" -j REJECT --reject-with icmp6-port-unreachable && say "ipv6 rule removed"
done

settings delete system virus_scan_install >/dev/null 2>&1 && say "virus_scan_install 复位(默认 true)"
settings put secure miui_safe_mode 1 && say "miui_safe_mode = 1"
settings put secure miui_security_mode_style normal

LAST=$(ls -1t "$BK"/common.xml.* 2>/dev/null | head -1)
if [ -n "${LAST:-}" ]; then
  P=/data/data/$PKG/shared_prefs/common.xml
  am force-stop "$PKG" 2>/dev/null
  OWNER=$(stat -c '%u:%g' /data/data/$PKG 2>/dev/null || echo 0:0)
  cp -p "$LAST" "$P" && chown "$OWNER" "$P" && chmod 660 "$P"
  say "prefs 已从 $LAST 恢复"
else
  say "没有 prefs 备份，跳过"
fi
say "done"
