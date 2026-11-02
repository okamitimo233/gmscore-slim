#!/system/bin/sh
# 开机完成后的第二遍复核
# GMS 会自我恢复被禁用的组件（实测 MeasurementBrokerService 会自愈），
# 因此每轮开机再核一次，保证幂等
MODDIR=${0%/*}
[ -z "$MODDIR" ] && MODDIR=/data/adb/modules/gmscore-slim

. "$MODDIR/lib/core.sh"
. "$MODDIR/lib/apply.sh"
. "$MODDIR/lib/sysconfig.sh"

sleep 30

# sysconfig overlay 的挂载结果只在开机后才看得到，这里记一笔
load_config
if [ "${FEATURE_SYSCONFIG:-1}" = "1" ]; then
  log "sysconfig: $(sc_verify "$MODDIR" 2>&1)"
  log "  /product 读到 $(wc -l <"$SC_SRC" 2>/dev/null) 行；模块内版本 $(wc -l <"$MODDIR/$SC_DST_REL" 2>/dev/null) 行"
  if grep -q 'allow-ignore-location-settings package="com.google.android.gms"' "$SC_SRC" 2>/dev/null; then
    log "  定位豁免行仍存在（overlay 未生效）"
  else
    log "  定位豁免行已消失（overlay 生效）"
  fi
fi

if take_lock; then
  log "### boot-completed 复核 ###"
  run_all
  release_lock
else
  log "SKIP boot-completed：service.sh 仍在运行"
fi
