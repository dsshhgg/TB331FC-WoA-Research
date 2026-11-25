#!/system/bin/sh
# KernelSU: post-fs-data —— 最早阶段只做"尽力而为"的断网（此时 package 服务可能还没起来）
MODDIR=${0%/*}
. "$MODDIR/common.sh"
resolve_uid && apply_net
exit 0
