#!/system/bin/sh
# KernelSU 管理器点「操作」时执行：打印现状 → 幂等复核 → 提示日志位置
MODDIR=${0%/*}
[ -z "$MODDIR" ] && MODDIR=/data/adb/modules/gmscore-slim

. "$MODDIR/lib/core.sh"
. "$MODDIR/lib/apply.sh"
. "$MODDIR/lib/sysconfig.sh"

load_config

echo "===== 运行时现状 ====="
_pid=$(pidof "$GMS" 2>/dev/null)
echo "GMS pid:        ${_pid:-未运行}"
if [ -n "$_pid" ]; then
  echo "oom_score_adj:  $(cat "/proc/$_pid/oom_score_adj" 2>/dev/null)"
  echo "VmRSS:          $(grep VmRSS "/proc/$_pid/status" 2>/dev/null | tr -s ' ' | cut -d' ' -f2-)"
fi
echo "GMS PSS:        $(dumpsys meminfo "$GMS" </dev/null 2>/dev/null | sed -n 's/^ *TOTAL PSS: *\([0-9]*\).*/\1/p' | head -n1) kB"
echo "待机分组:       $(am get-standby-bucket "$GMS" </dev/null 2>/dev/null)（10 活跃 / 20 工作集 / 30 常用 / 40 少用 / 45 限制）"
echo "白名单条数:     $(wl_count)（剩下的多半是 sysconfig 的 system / system-excidle 条目，CLI 只能删 user 那条）"
echo "startRequested: $(dumpsys activity services "$GMS" </dev/null 2>/dev/null | grep -c 'startRequested=true')"
echo "清单项数:       $([ -f "$MANIFEST" ] && wc -l <"$MANIFEST" || echo 0)"

echo
echo "===== 权限状态（可 revoke 的目标；READ_PHONE_STATE 需开 FEATURE_PERM_PHONE）====="
perm_snapshot >/dev/null 2>&1
for _p in BLUETOOTH_SCAN BLUETOOTH_ADVERTISE UWB_RANGING RANGING ACCESS_LOCAL_NETWORK READ_PHONE_STATE; do
  _s=$(perm_read "$_p")
  if perm_locked "$_p"; then _tag="锁定(SYSTEM_FIXED)"
  elif [ "$_s" = "true" ]; then _tag="已授予"
  elif [ "$_s" = "false" ]; then _tag="已撤销"
  else _tag="未声明"; fi
  printf '  %-24s %-8s %s\n' "$_p" "${_s:-?}" "$_tag"
done

echo
echo "===== 系统参数现值 ====="
echo "  alarm_manager.delay_nonwakeup_alarms_while_screen_off = $(dc_read alarm_manager delay_nonwakeup_alarms_while_screen_off)"
echo "  override 列表里含 alarm 的条目数 = $(cmd device_config list_local_overrides </dev/null 2>&1 | grep -c alarm)"
echo "  device_idle_constants = $(set_read device_idle_constants)"

echo
echo "===== sysconfig overlay ====="
if [ "${FEATURE_SYSCONFIG:-1}" = "1" ]; then
  echo "  开关: LOCATION=$FEATURE_SC_LOCATION  POWERSAVE=$FEATURE_SC_POWERSAVE  DATAUSAGE=$FEATURE_SC_DATAUSAGE  UNTHROTTLE=$FEATURE_SC_UNTHROTTLE"
  echo "  挂载状态: $(sc_verify "$MODDIR" 2>&1)"
  echo "  /product 实际读到: $(wc -l <"$SC_SRC" 2>/dev/null) 行"
  if [ -f "$MODDIR/$SC_DST_REL" ]; then
    echo "  模块内生成版:     $(wc -l <"$MODDIR/$SC_DST_REL" 2>/dev/null) 行"
  else
    echo "  模块内生成版:     未生成"
  fi
  # 按当前开关重新生成（改完开关点操作即可，不用重装）
  if [ "${DRY:-0}" = "1" ]; then
    echo "  DRY：跳过重新生成"
  else
    _r=$(sc_build "$MODDIR" 1 2>&1)
    case "$_r" in
      *SC-OK*) echo "  --> 已按当前开关重新生成，重启后生效" ;;
      *)       echo "  --> 生成失败: $_r" ;;
    esac
  fi
else
  echo "  已关闭（FEATURE_SYSCONFIG=0）"
[ -f "$MODDIR/$SC_DST_REL" ] && echo "  ! 模块内仍残留旧的 overlay 文件，重启后照样会被挂载；卸载重装可彻底清除"
fi

echo
echo "===== 开关 ====="
echo "  TELEMETRY=$FEATURE_TELEMETRY  TELEMETRY_ADS=$FEATURE_TELEMETRY_ADS"
echo "  PERSISTENT=$FEATURE_PERSISTENT  DROIDGUARD=$FEATURE_DROIDGUARD"
echo "  PERM_SCAN=$FEATURE_PERM_SCAN  PERM_PHONE=$FEATURE_PERM_PHONE  PERM_BTCONNECT=$FEATURE_PERM_BTCONNECT"
echo "  ALARM_DELAY=$FEATURE_ALARM_DELAY  DOZE_CONSTANTS=$FEATURE_DOZE_CONSTANTS"
echo "  WHITELIST=$FEATURE_WHITELIST  APPOPS=$FEATURE_APPOPS"
echo "  开关文件: /data/adb/gmscore-slim/config.sh"

echo
echo "===== 幂等复核（立即重新施加一遍）====="
if take_lock; then
  run_all
  release_lock
else
  log "已有实例在运行，本次跳过"
fi

echo
echo "本次处理过的候选清单（target-*.txt）："
for f in target-telemetry.txt target-persistent.txt target-droidguard.txt; do
  [ -s "$STATE_FILES/$f" ] && { echo "  [$f]"; sed 's/^/    /' "$STATE_FILES/$f"; }
done

echo
echo "详细日志: $LOG_FILE"
