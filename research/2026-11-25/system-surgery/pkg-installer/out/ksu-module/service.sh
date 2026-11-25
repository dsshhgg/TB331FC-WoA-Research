#!/system/bin/sh
# KernelSU: service.sh —— boot_completed 之后跑，此时 uid 一定已分配、settings 服务可用
MODDIR=${0%/*}
. "$MODDIR/common.sh"

i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 120 ]; do
  sleep 1; i=$((i+1))
done

# 再等 5s，避免 PMS 尚未完成扫描时 settings 被安全模式初始化逻辑覆盖
sleep 5

resolve_uid && apply_net || say "uid 解析失败，跳过断网"
apply_settings
say "done (uid=$UID_)"
