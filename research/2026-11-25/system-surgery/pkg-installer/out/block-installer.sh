#!/system/bin/sh
# =============================================================================
# block-installer.sh — 澎湃4(A17) com.miui.packageinstaller 断网 + 关安全检测
#
# 需要 root（KernelSU / APatch / Magisk；本机实测 adb shell 已是 uid=0 u:r:ksu:s0）
# 幂等：重复执行不会叠加规则
# 回滚：out/rollback-installer.sh
#
# 原理（全部有反编译证据，见 REPORT.md §2）：
#   1. 联网    -> iptables/ip6tables 按 uid REJECT（CloudResult.NoNetworkError 分支保证不卡安装）
#   2. 病毒扫描 -> Settings.System.virus_scan_install（i2/n.java:315，o2/h.java:1594 是总闸）
#   3. 安全模式 -> Settings.Secure.miui_safe_mode（i2/n.java:360-370）
#   4. 云黑名单 -> Settings.Secure.packageinstaller_forbidden_app_list(_version)
#   5. 验签/推荐 -> shared_prefs/common.xml 的 secure_verify_enable / app_store_recommend
# =============================================================================
set -u

PKG=com.miui.packageinstaller
BK=/data/local/tmp/installer-shared_prefs.bak
say() { echo "[installer-block] $*"; }

# ---- uid --------------------------------------------------------------------
UID_=$(cmd package list packages -U 2>/dev/null | grep -F "package:$PKG " | head -1 | sed 's/.*uid://')
if [ -z "${UID_:-}" ]; then
  UID_=$(dumpsys package "$PKG" 2>/dev/null | sed -n 's/^ *userId=\([0-9][0-9]*\).*/\1/p' | head -1)
fi
if [ -z "${UID_:-}" ]; then
  say "!! 找不到 $PKG 的 uid，中止（确认包名/设备）"; exit 2
fi
say "uid=$UID_"

# ---- 1. 网络：IPv4 / IPv6，REJECT 而不是 DROP（DROP 会把云端调用拖到 20s 超时）--
add4() {
  iptables -w -C OUTPUT -m owner --uid-owner "$UID_" -j REJECT --reject-with icmp-port-unreachable 2>/dev/null && { say "ipv4 rule exists"; return 0; }
  iptables -w -I OUTPUT 1 -m owner --uid-owner "$UID_" -j REJECT --reject-with icmp-port-unreachable && say "ipv4 rule added"
}
add6() {
  ip6tables -w -C OUTPUT -m owner --uid-owner "$UID_" -j REJECT --reject-with icmp6-port-unreachable 2>/dev/null && { say "ipv6 rule exists"; return 0; }
  ip6tables -w -I OUTPUT 1 -m owner --uid-owner "$UID_" -j REJECT --reject-with icmp6-port-unreachable && say "ipv6 rule added"
}
add4 || say "!! ipv4 规则失败"
add6 || say "!! ipv6 规则失败"

# ---- 2/3/4. settings 开关 ----------------------------------------------------
set_get() { settings get "$1" "$2"; }
set_put() { settings put "$1" "$2" "$3" && say "settings put $1 $2 = $3"; }

set_put system virus_scan_install 0                       # 病毒扫描总闸（默认 true）
set_put secure miui_safe_mode 0                           # 安全模式/纯净模式（真机原本=1）
set_put secure miui_security_mode_style normal
set_put secure packageinstaller_forbidden_app_list ''     # 云黑名单（VPN 类拦截源）
set_put secure packageinstaller_forbidden_app_list_version 0

# ---- 5. shared_prefs（验签 / 应用商店推荐 / 关安全模式标记）------------------
D=/data/data/$PKG
P=$D/shared_prefs/common.xml
if [ -f "$P" ]; then
  mkdir -p "$BK"
  cp -p "$P" "$BK/common.xml.$(date +%Y%m%d-%H%M%S)" && say "prefs 备份 -> $BK"
  am force-stop "$PKG" 2>/dev/null
  sed -i \
    -e 's/name="secure_verify_enable" value="true"/name="secure_verify_enable" value="false"/' \
    -e 's/name="app_store_recommend" value="true"/name="app_store_recommend" value="false"/' \
    "$P"
  grep -q 'name="user_close_security_mode_flag"' "$P" || \
    sed -i 's#</map>#    <boolean name="user_close_security_mode_flag" value="true" />\n</map>#' "$P"
  OWNER=$(stat -c '%u:%g' "$D" 2>/dev/null || echo 0:0)   # toybox 不一定有 chown --reference
  chown "$OWNER" "$P" 2>/dev/null || true
  chmod 660 "$P"
  say "prefs 已改：secure_verify_enable=false app_store_recommend=false user_close_security_mode_flag=true"
else
  say "!! $P 不存在（应用没跑过？），跳过 prefs"
fi

# ---- 结果 ----------------------------------------------------------------
say "---- 现状 ----"
say "iptables : $(iptables -w -S OUTPUT 2>/dev/null | grep -- "--uid-owner $UID_" | head -1)"
say "ip6tables: $(ip6tables -w -S OUTPUT 2>/dev/null | grep -- "--uid-owner $UID_" | head -1)"
say "virus_scan_install = $(set_get system virus_scan_install)"
say "miui_safe_mode     = $(set_get secure miui_safe_mode)"
say "done. 重启后规则会丢 -> 用 out/ksu-module 持久化"
