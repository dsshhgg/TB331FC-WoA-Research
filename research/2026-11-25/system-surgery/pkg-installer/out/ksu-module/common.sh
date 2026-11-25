#!/system/bin/sh
# 公共函数：被 post-fs-data.sh / service.sh source
PKG=com.miui.packageinstaller
UID_=""
say() { echo "[zz_installer_block] $*"; }

resolve_uid() {
  UID_=$(cmd package list packages -U 2>/dev/null | grep -F "package:$PKG " | head -1 | sed 's/.*uid://')
  [ -n "$UID_" ] || UID_=$(dumpsys package "$PKG" 2>/dev/null | sed -n 's/^ *userId=\([0-9][0-9]*\).*/\1/p' | head -1)
  [ -n "$UID_" ]
}

apply_net() {
  [ -n "$UID_" ] || return 1
  iptables -w -C OUTPUT -m owner --uid-owner "$UID_" -j REJECT --reject-with icmp-port-unreachable 2>/dev/null || \
    iptables -w -I OUTPUT 1 -m owner --uid-owner "$UID_" -j REJECT --reject-with icmp-port-unreachable 2>/dev/null && say "ipv4 ok"
  ip6tables -w -C OUTPUT -m owner --uid-owner "$UID_" -j REJECT --reject-with icmp6-port-unreachable 2>/dev/null || \
    ip6tables -w -I OUTPUT 1 -m owner --uid-owner "$UID_" -j REJECT --reject-with icmp6-port-unreachable 2>/dev/null && say "ipv6 ok"
}

apply_settings() {
  settings put system virus_scan_install 0
  settings put secure miui_safe_mode 0
  settings put secure miui_security_mode_style normal
  settings put secure packageinstaller_forbidden_app_list ''
  settings put secure packageinstaller_forbidden_app_list_version 0
  say "settings ok"
}
