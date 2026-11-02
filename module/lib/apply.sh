#!/system/bin/sh
# 策略层：目标清单与施加流程。由 service.sh / boot-completed.sh / action.sh 引用。
# 依赖调用方先 source lib/core.sh 并设好 MODDIR。

load_config() {
  # shellcheck disable=SC1091  # 运行时路径，shellcheck 无法静态解析
  . "$MODDIR/lib/config.sh"
  # shellcheck disable=SC1091
  [ -f "$STATE_DIR/config.sh" ] && . "$STATE_DIR/config.sh"
}

# 等 pm / cmd 真正可用（system_server 起来但 PackageManager 可能还在扫描）
wait_cmd_ready() {
  _i=0
  while [ $_i -lt 6 ]; do
    [ -n "$(cmd appops get "$GMS" WAKE_LOCK </dev/null 2>/dev/null)" ] && return 0
    sleep 10
    _i=$((_i + 1))
  done
  return 1
}

# 施加一项 appops / device_config / settings：读现值 -> 不同才写 -> 写清单 -> 回读
# 这三类回读的是系统本身，所以 OK 就代表系统已经接受
apply_change() {
  _t=$1; _k=$2; _w=$3
  _cur=$(kv_read "$_t" "$_k")
  if [ "$_cur" = "$_w" ]; then
    log "SKIP  $_t $_k 已是 $_w"
    return 0
  fi
  if [ "${DRY:-0}" = "1" ]; then
    log "DRY   $_t $_k : $_cur -> $_w"
    return 0
  fi
  man_has "$_t" "$_k" || man_add "$_t" "$_k" "$_cur" "$_w"
  kv_write "$_t" "$_k" "$_w"
  _v=$(kv_read "$_t" "$_k")
  if [ "$_v" = "$_w" ]; then
    log "OK    $_t $_k : $_cur -> $_w"
  else
    log "FAIL  $_t $_k 期望 $_w 实际 $_v（平台可能拒绝该 op）"
  fi
}

# 组件类改动：先确认组件真的存在，再动
comp_change() {
  _c=$1; _w=$2
  if ! comp_exists "$_c"; then
    log "ABSENT $_c 本机无此组件，跳过"
    return 0
  fi
  _cur=$(comp_read "$_c")
  if [ "$_cur" = "$_w" ]; then
    log "SKIP  comp $_c 已是 $_w"
    return 0
  fi
  if [ "${DRY:-0}" = "1" ]; then
    log "DRY   comp $_c : $_cur -> $_w"
    return 0
  fi
  man_has comp "$_c" || man_add comp "$_c" "$_cur" "$_w"
  kv_write comp "$_c" "$_w"
  # comp_read 读的是本地快照，写入时已被改成目标值，所以这里只能证明「命令已下达」。
  # 系统有没有真的接受，由 run_all 结尾的 verify_real 重新抓一次系统状态来判定
  log "SET   comp $_c : $_cur -> $_w"
}

# 核心域保护名单：遥测、常驻两项在禁用前都会过一遍，命中就跳过
# 注意：DroidGuard 分支专治 *.droidguard.*，不经过这个检查（过了等于把整个分支跳空）
guard_core() {
  case "$1" in
    *Gcm*|*GCM*|*.auth.*|*.common.*|*Chimera*|*.droidguard.*) return 0 ;;
  esac
  return 1
}

# ---------- 遥测/统计组件 ----------
# 注：社区名单里的 AppMeasurement* / CampaignTracking* 在 GMS 26.x 已不存在，
# usagereport 那些只是 intent action 而非组件。这里只留实测存在的。
do_telemetry() {
  log "--- 遥测与统计组件 ---"
  if [ ! -s "$STATE_FILES/available.txt" ]; then
    log "WARN 无组件快照，跳过"
    return 0
  fi
  _list=$STATE_FILES/target-telemetry.txt
  match_components "$STATE_FILES/available.txt" \
    "MeasurementBroker" "ClearcutDebug" >"$_list" 2>/dev/null
  if [ "${FEATURE_TELEMETRY_ADS:-0}" = "1" ]; then
    grep -i '\.ads\.' "$STATE_FILES/available.txt" >>"$_list" 2>/dev/null
  fi
  sort -u "$_list" -o "$_list" 2>/dev/null
  _n=0
  while read -r _c; do
    [ -z "$_c" ] && continue
    if guard_core "$_c"; then log "GUARD 保护核心组件，跳过 $_c"; continue; fi
    comp_change "$_c" disabled
    _n=$((_n + 1))
  done <"$_list"
  log "遥测候选 $_n 个，明细见 $_list"
}

# ---------- 常驻服务压制 ----------
do_persistent() {
  log "--- 常驻服务压制 ---"
  # dumpsys 里活动服务写作 com.google.android.gms/.foo.BarService（相对名），需还原全名
  dumpsys activity services "$GMS" </dev/null 2>/dev/null | cat >"$STATE_FILES/services.dump"
  grep -oE 'com\.google\.android\.gms/[A-Za-z0-9_./]+' "$STATE_FILES/services.dump" \
    | sed -E 's|.*com\.google\.android\.gms/||' \
    | sed -E 's|^\.|com.google.android.gms.|' \
    | sort -u >"$STATE_FILES/services.txt" 2>/dev/null
  _list=$STATE_FILES/target-persistent.txt
  # 目标从「声明组件全集」里匹配，而不是只匹配当前活动服务：
  # 服务未运行时活动列表里就没有它，那样会导致目标漂移、每轮结果不一致
  # GmsCoreStatsService 位于 .common 核心域，即使命中也会被 guard_core 拦下，故不列入
  match_components "$STATE_FILES/available.txt" \
    "IntegrityApiPersistent" "LocationPersistentService" "ClearcutDebug" \
    "magictether.service.TetherService" "magictether.wifisync.WifiSyncService" >"$_list" 2>/dev/null
  _active=$(grep -cF -f "$_list" "$STATE_FILES/services.txt" 2>/dev/null)
  [ -z "$_active" ] && _active=0
  log "其中当前处于活动状态: $_active 个"
  if [ ! -s "$_list" ]; then
    log "WARN 组件快照里没有匹配到常驻服务目标，跳过"
    return 0
  fi
  while read -r _c; do
    [ -z "$_c" ] && continue
    if guard_core "$_c"; then log "GUARD 保护核心组件，跳过 $_c"; continue; fi
    comp_change "$_c" disabled
  done <"$_list"
}

# ---------- DroidGuard ----------
do_droidguard() {
  log "--- DroidGuard（高风险）---"
  if [ ! -s "$STATE_FILES/available.txt" ]; then
    log "WARN 无组件快照，跳过"
    return 0
  fi
  _list=$STATE_FILES/target-droidguard.txt
  match_components "$STATE_FILES/available.txt" "DroidGuard" >"$_list" 2>/dev/null
  while read -r _c; do
    [ -z "$_c" ] && continue
    comp_change "$_c" disabled
  done <"$_list"
}

# ---------- 可写的非运行时 appops ----------
do_appops() {
  log "--- appops: 非运行时 op ---"
  while read -r _op _mode; do
    [ -z "$_op" ] && continue
    apply_change appops "$GMS|$_op" "$_mode"
  done <<EOF
RUN_ANY_IN_BACKGROUND ignore
WAKE_LOCK ignore
START_FOREGROUND ignore
EOF
}

# ---------- 扫描类权限收紧（替代被拒的 appops 运行时 op）----------
do_perm_scan() {
  log "--- 权限: 扫描类（pm revoke）---"
  if [ ! -s "$STATE_FILES/perms.txt" ]; then
    log "WARN 无权限快照，跳过"
    return 0
  fi
  _list="BLUETOOTH_SCAN BLUETOOTH_ADVERTISE UWB_RANGING RANGING ACCESS_LOCAL_NETWORK"
  [ "${FEATURE_PERM_PHONE:-0}" = "1" ]      && _list="$_list READ_PHONE_STATE"
  [ "${FEATURE_PERM_BTCONNECT:-0}" = "1" ]  && _list="$_list BLUETOOTH_CONNECT"
  for _p in $_list; do
    if perm_locked "$_p"; then
      log "LOCKED $_p 是 SYSTEM_FIXED，平台不允许 revoke，跳过"
      continue
    fi
    _cur=$(perm_read "$_p")
    case "$_cur" in
      true|false) ;;
      *) log "ABSENT $_p 本机未声明/未授予，跳过"; continue ;;
    esac
    if [ "$_cur" = "false" ]; then
      log "SKIP  perm $_p 已未授予"
      continue
    fi
    if [ "${DRY:-0}" = "1" ]; then
      log "DRY   perm $_p : true -> false"
      continue
    fi
    man_has perm "$_p" || man_add perm "$_p" "$_cur" "false"
    kv_write perm "$_p" "false"
    # 同 comp：回读读的是快照，真实结果由 verify_real 判定
    log "SET   perm $_p : true -> false"
  done
}

# ---------- 熄屏延迟非唤醒闹钟（device_config override）----------
do_alarm_delay() {
  log "--- device_config: 熄屏延迟非唤醒闹钟（override）---"
  apply_change devconfig "alarm_manager|delay_nonwakeup_alarms_while_screen_off" "true"
}

# ---------- Doze 常量 ----------
do_doze_constants() {
  log "--- settings: device_idle_constants ---"
  # 缩短深睡后的维护窗与 idle 停留时间，减少 GMS 在 Doze 期间获得执行机会
  _want="idle_to=1800000,light_idle_to=1800000,max_idle_to=21600000,min_time_to_alarm=600000"
  apply_change settings "device_idle_constants" "$_want"
}

# ---------- 待机白名单 ----------
# 不写清单：白名单每次开机由系统重建，本项每轮重新施加
do_whitelist() {
  log "--- 待机白名单 ---"
  _before=$(wl_count)
  if [ "$_before" = "0" ]; then
    log "SKIP  gms 已不在白名单"
    return 0
  fi
  if [ "${DRY:-0}" = "1" ]; then
    log "DRY   whitelist -$GMS（当前 $_before 条）"
    return 0
  fi
  wl_remove
  sleep 1
  _after=$(wl_count)
  log "结果: 移除前 $_before 条 -> 移除后 $_after 条"
  if [ "$_after" != "0" ]; then
    log "NOTE  剩余 $_after 条来自 /product/etc/sysconfig/google.xml，CLI 无 -system 语法，需 overlay 才能去掉"
  fi
}

run_all() {
  load_config
  mkdir -p "$STATE_DIR/lib" 2>/dev/null
  cp -f "$MODDIR/lib/core.sh" "$STATE_DIR/lib/core.sh" 2>/dev/null
  log "=== GMS Slim 执行（DRY=${DRY:-0}）==="
  wait_cmd_ready || log "WARN pm/cmd 未就绪，继续尝试"
  gms_snapshot || log "WARN 组件快照失败，组件类改动将跳过"
  perm_snapshot || log "WARN 权限快照失败，权限类改动将跳过"
  [ "${FEATURE_TELEMETRY:-0}"    = "1" ] && do_telemetry
  [ "${FEATURE_PERSISTENT:-0}"   = "1" ] && do_persistent
  [ "${FEATURE_DROIDGUARD:-0}"   = "1" ] && do_droidguard
  [ "${FEATURE_PERM_SCAN:-0}"    = "1" ] && do_perm_scan
  [ "${FEATURE_ALARM_DELAY:-0}"  = "1" ] && do_alarm_delay
  [ "${FEATURE_DOZE_CONSTANTS:-0}" = "1" ] && do_doze_constants
  [ "${FEATURE_APPOPS:-0}"       = "1" ] && do_appops
  [ "${FEATURE_WHITELIST:-0}"    = "1" ] && do_whitelist
  # 前面各类 SET 都只代表「命令已下达」，这里重新读一次系统给出真实结论
  if [ "${DRY:-0}" = "1" ]; then
    log "DRY 跳过真实状态复核"
  else
    verify_real
  fi
  log "=== 执行结束 ==="
}
