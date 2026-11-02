#!/system/bin/sh
# late_start service：主施加时机
# 依据本机既有约定（hanamaki_kernel / playintegrityfix）：等 sys.boot_completed + 用户解密后再动 pm/settings
MODDIR=${0%/*}
[ -z "$MODDIR" ] && MODDIR=/data/adb/modules/gmscore-slim

. "$MODDIR/lib/core.sh"
. "$MODDIR/lib/apply.sh"

# 1) 等系统启动完成（最多 5 分钟）
_i=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
  sleep 5
  _i=$((_i+5))
  [ $_i -gt 300 ] && break
done

# 2) 等 /data 解密完成（Direct Boot 未结束时 pm 无法工作）
_i=0
while [ ! -d /data/data/android ]; do
  sleep 3
  _i=$((_i+3))
  [ $_i -gt 120 ] && break
done

# 3) 再给 PackageManager 一点时间
sleep 15

if take_lock; then
  run_all
  release_lock
else
  log "SKIP 已有实例在运行，本轮跳过"
fi
