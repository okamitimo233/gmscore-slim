#!/system/bin/sh
# 通用层：日志、状态目录、清单（manifest）读写、各类回滚原语
# 状态一律外置到 /data/adb/<id>/，不能写模块目录（magic mount 下会被整块替换）
#
# 【重要经验】cmd / pm / dumpsys 会把 stdio fd 通过 binder 传给 system_server：
#   - stdout 指向 /data/adb 下的普通文件 -> "Failed transaction (2147483646)"
#   - stdin  指向普通文件（例如 while read < manifest 时）-> 同样失败
# 因此：输出一律走管道再重定向，输入一律显式 </dev/null。

MODID=gmscore-slim
STATE_DIR=/data/adb/$MODID
LOG_DIR=$STATE_DIR/log
STATE_FILES=$STATE_DIR/state
MANIFEST=$STATE_FILES/manifest.tsv
GMS=com.google.android.gms
TAB=$(printf '\t')
LOG_FILE=$LOG_DIR/last.log

mkdir -p "$STATE_FILES" "$LOG_DIR" "$STATE_DIR/backup" "$STATE_DIR/lib" 2>/dev/null

if [ -f "$LOG_FILE" ]; then
  _sz=$(wc -c <"$LOG_FILE" 2>/dev/null || echo 0)
  [ "$_sz" -gt 262144 ] && mv -f "$LOG_FILE" "$LOG_DIR/prev.log" 2>/dev/null
fi

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >>"$LOG_FILE" 2>/dev/null
  printf '%s\n' "$*"
}

# ---------- 锁 ----------
take_lock() {
  mkdir "$STATE_FILES/.lock" 2>/dev/null && return 0
  _m=$(stat -c %Y "$STATE_FILES/.lock" 2>/dev/null || echo 0)
  _age=0
  [ "$_m" != "0" ] && _age=$(( $(date +%s) - _m ))
  if [ "$_age" -gt 600 ]; then
    rm -rf "$STATE_FILES/.lock"
    mkdir "$STATE_FILES/.lock" 2>/dev/null && return 0
  fi
  return 1
}
release_lock() { rm -rf "$STATE_FILES/.lock"; }

# ---------- appops ----------
# 注意：Android 16 起，由运行时权限支撑的 op（WIFI_SCAN/MONITOR_LOCATION/
# BLUETOOTH_SCAN/ACTIVITY_RECOGNITION 等）会被平台拒绝写入，set 静默无效。
# 本模块因此只使用实测可写的非运行时 op。
appops_read() { # $1 pkg $2 op -> allow / ignore / deny / default:allow
  _out=$(cmd appops get "$1" "$2" </dev/null 2>/dev/null)
  _m=$(printf '%s\n' "$_out" | sed -n 's/^[A-Za-z_0-9]*: *\([a-z]*\).*/\1/p' | head -n1)
  if [ -z "$_m" ] || [ "$_m" = "default" ]; then
    _d=$(printf '%s\n' "$_out" | sed -n 's/.*Default mode: *\([a-z]*\).*/\1/p' | head -n1)
    _m="default:${_d:-allow}"
  fi
  printf '%s' "$_m"
}
appops_set()   { cmd appops set "$1" "$2" "$3" </dev/null >/dev/null 2>&1; }
appops_reset() { cmd appops reset "$1" "$2" </dev/null >/dev/null 2>&1; }

# ---------- GMS 组件快照 ----------
gms_snapshot() {
  _d=$STATE_FILES
  _ok=0
  _try=0
  while [ "$_try" -lt 3 ]; do
    pm dump "$GMS" </dev/null 2>/dev/null | cat >"$_d/gms.dump"
    if [ -s "$_d/gms.dump" ] && ! grep -q "Failed transaction" "$_d/gms.dump" 2>/dev/null; then
      _ok=1
      break
    fi
    _try=$((_try + 1))
    sleep 3
  done
  if [ "$_ok" != "1" ]; then
    log "WARN pm dump 失败，改用 dumpsys package"
    dumpsys package "$GMS" </dev/null 2>/dev/null | cat >"$_d/gms.dump"
    if [ ! -s "$_d/gms.dump" ]; then
      log "WARN 组件快照彻底失败，组件类改动将跳过"
      rm -f "$_d/gms.dump"
      return 1
    fi
  fi
  # 1) 解析表里的相对名 com.google.android.gms/.foo.Bar -> 全名
  grep -oE 'com\.google\.android\.gms/\.[A-Za-z0-9_.]+' "$_d/gms.dump" \
    | sed -E 's|com\.google\.android\.gms/\.|com.google.android.gms.|' >"$_d/.rel"
  # 2) 全名形式
  grep -oE 'com\.google\.android\.gms\.[A-Za-z0-9_.]+' "$_d/gms.dump" >"$_d/.full"
  # 3) 只保留像组件名的（滤掉 intent action 之类的字符串）
  cat "$_d/.rel" "$_d/.full" | sort -u \
    | grep -iE '(Service|Receiver|Activity|Provider|Alias)$' >"$_d/available.txt"
  # 4) 已禁用清单必须按段落边界截取；grep -A 会溢出到权限表，把没禁用的也误算进去
  sed -n '/^      disabledComponents:/,/^      [a-zA-Z]/p' "$_d/gms.dump" 2>/dev/null \
    | grep -oE 'com\.google\.android\.gms\.[A-Za-z0-9_.]+' | sort -u >"$_d/disabled.txt"
  rm -f "$_d/.rel" "$_d/.full" "$_d/gms.dump"
  return 0
}
comp_exists() { [ -s "$STATE_FILES/available.txt" ] && grep -qxF "$1" "$STATE_FILES/available.txt"; }
comp_read()   { grep -qxF "$1" "$STATE_FILES/disabled.txt" 2>/dev/null && echo disabled || echo enabled; }
comp_disable(){ pm disable "$GMS/$1" </dev/null >/dev/null 2>&1; }
comp_enable() { pm enable  "$GMS/$1" </dev/null >/dev/null 2>&1; }

# 改动后同步本地快照，否则回读校验会拿到旧值、误报 FAIL
comp_cache_set() { # $1 组件 $2 disabled|enabled
  _f=$STATE_FILES/disabled.txt
  [ -f "$_f" ] || : >"$_f"
  case "$2" in
    disabled)
      grep -qxF "$1" "$_f" || printf '%s\n' "$1" >>"$_f"
      ;;
    enabled)
      grep -vxF "$1" "$_f" >"$_f.tmp"
      mv -f "$_f.tmp" "$_f"
      ;;
  esac
  sort -u "$_f" -o "$_f" 2>/dev/null
}

match_components() {
  _f=$1; shift
  for _p in "$@"; do
    grep -i -- "$_p" "$_f" 2>/dev/null
  done | sort -u
}

# ---------- 权限（替代被平台拒绝的 appops 运行时 op）----------
# Android 16+ 起 appops 的运行时 op 由权限 flags 派生，不允许直接 set。
# 官方替代路径是改权限本身：pm revoke/grant 会把对应 op 级联成 Uid mode ignore/allow。
# 注意：SYSTEM_FIXED 权限 revoke 不掉（检查的是 callingAppId != SYSTEM_UID，uid 0 也不行），
# 本机只有 4 个：ACCESS_FINE/COARSE/BACKGROUND_LOCATION、ACTIVITY_RECOGNITION。
perm_snapshot() {
  _d=$STATE_FILES
  dumpsys package "$GMS" </dev/null 2>/dev/null | cat >"$_d/gms.pkgdump"
  if [ ! -s "$_d/gms.pkgdump" ]; then
    log "WARN 权限快照失败"
    return 1
  fi
  sed -n '/runtime permissions:/,/^    [a-z]/p' "$_d/gms.pkgdump" \
    | sed -n 's/^ *android\.permission\.\([A-Z_]*\): granted=\([a-z]*\).*/\1=\2/p' \
    | sort -u >"$_d/perms.txt"
  # 同时记录哪些是 SYSTEM_FIXED（改不了的，永远跳过）
  sed -n '/runtime permissions:/,/^    [a-z]/p' "$_d/gms.pkgdump" \
    | grep "SYSTEM_FIXED" \
    | sed -n 's/^ *android\.permission\.\([A-Z_]*\):.*/\1/p' \
    | sort -u >"$_d/perms-locked.txt"
  rm -f "$_d/gms.pkgdump"
  return 0
}
perm_read()  { grep "^$1=" "$STATE_FILES/perms.txt" 2>/dev/null | head -1 | cut -d= -f2; }  # -> true/false
perm_locked(){ grep -qxF "$1" "$STATE_FILES/perms-locked.txt" 2>/dev/null; }
perm_grant() { pm grant  "$GMS" "android.permission.$1" </dev/null >/dev/null 2>&1; }
perm_revoke(){ pm revoke "$GMS" "android.permission.$1" </dev/null >/dev/null 2>&1; }
perm_cache_set() { # $1 权限名 $2 true|false
  _f=$STATE_FILES/perms.txt
  [ -f "$_f" ] || : >"$_f"
  grep -v "^$1=" "$_f" >"$_f.tmp" 2>/dev/null
  printf '%s=%s\n' "$1" "$2" >>"$_f.tmp"
  sort -u "$_f.tmp" -o "$_f" 2>/dev/null
  rm -f "$_f.tmp"
}

# ---------- device_config（用 override 才是 sticky）----------
# 本机实测：put 会被服务端/其他模块同步覆盖；override 优先级更高且持久
# （hanamaki_kernel 的 activity_manager 各项就是 override 写入的）
dc_read()       { cmd device_config get "$1" "$2" </dev/null 2>/dev/null; }
dc_override()   { cmd device_config override "$1" "$2" "$3" </dev/null >/dev/null 2>&1; }
dc_clear_ovr()  { cmd device_config clear_override "$1" "$2" </dev/null >/dev/null 2>&1; }
dc_put()        { cmd device_config put "$1" "$2" "$3" </dev/null >/dev/null 2>&1; }

# ---------- settings global ----------
set_read()   { settings get global "$1" </dev/null 2>/dev/null; }
set_put()    { settings put global "$1" "$2" </dev/null >/dev/null 2>&1; }
set_delete() { settings delete global "$1" </dev/null >/dev/null 2>&1; }

# ---------- 待机白名单 ----------
# shell 只能移除 user 条目；system / system-excidle 来自 /product/etc/sysconfig/google.xml，
# 实测 CLI 不接受 `-system` 语法（只认 +/-/= 前缀的包名），要彻底去掉只能做 overlay
wl_count()   { dumpsys deviceidle whitelist </dev/null 2>/dev/null | grep -c "com.google.android.gms"; }
wl_remove()  { cmd deviceidle whitelist -"$GMS" </dev/null >/dev/null 2>&1; }
wl_add()     { cmd deviceidle whitelist +"$GMS" </dev/null >/dev/null 2>&1; }

# ---------- 清单 ----------
man_has() {
  [ -f "$MANIFEST" ] || return 1
  while IFS="$TAB" read -r _t _k _o _w; do
    [ "$_t" = "$1" ] && [ "$_k" = "$2" ] && return 0
  done <"$MANIFEST"
  return 1
}
man_add() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"$MANIFEST"; }

# ---------- 统一读写（键格式见各分支）----------
kv_read() {
  case "$1" in
    appops)    appops_read "${2%%|*}" "${2#*|}" ;;
    comp)      comp_read "$2" ;;
    perm)      perm_read "$2" ;;
    devconfig) dc_read "${2%%|*}" "${2#*|}" ;;
    settings)  set_read "$2" ;;
  esac
}
kv_write() {
  case "$1" in
    appops)
      case "$3" in
        default:*) appops_reset "${2%%|*}" "${2#*|}" ;;
        *)         appops_set "${2%%|*}" "${2#*|}" "$3" ;;
      esac ;;
    comp)
      case "$3" in
        disabled) comp_disable "$2"; comp_cache_set "$2" disabled ;;
        enabled)  comp_enable  "$2"; comp_cache_set "$2" enabled ;;
      esac ;;
    perm)
      case "$3" in
        true)  perm_grant  "$2" ;;
        false) perm_revoke "$2" ;;
      esac
      perm_cache_set "$2" "$3" ;;
    devconfig)
      # 施加用 override：本机实测 sticky，不会被服务端或其他模块的 put 覆盖
      # （hanamaki_kernel 的 activity_manager 各项就是 override 写入的）
      case "$3" in
        ""|null) dc_clear_ovr "${2%%|*}" "${2#*|}" ;;
        *)       dc_override  "${2%%|*}" "${2#*|}" "$3" ;;
      esac ;;
    settings)
      case "$3" in
        ""|null) set_delete "$2" ;;
        *)       set_put "$2" "$3" ;;
      esac ;;
  esac
}

# 回滚专用：把值恢复成原样，且不留下 sticky 痕迹
kv_restore() {
  case "$1" in
    devconfig)
      # 先清掉自己写的 override（否则会残余 sticky 记录，妨碍其他模块改同一键），
      # 再按原值 put 回去；原本为空则清掉了事
      dc_clear_ovr "${2%%|*}" "${2#*|}"
      case "$3" in
        ""|null) : ;;
        *)       dc_put "${2%%|*}" "${2#*|}" "$3" ;;
      esac ;;
    *)
      kv_write "$1" "$2" "$3" ;;
  esac
}

# ---------- 回滚 ----------
# 只回滚「现值仍等于本模块写入值」的项，被别人改过的一律保留
rollback_all() {
  if [ ! -f "$MANIFEST" ] || [ ! -s "$MANIFEST" ]; then
    log "没有需要回滚的清单项"
    return 0
  fi
  _tmp=$STATE_FILES/manifest.rollback
  : >"$_tmp"
  _n=0
  # 先把清单读进内存，避免循环 stdin 与 cmd 的 fd 冲突
  _mlist=$(cat "$MANIFEST")
  printf '%s\n' "$_mlist" | while IFS="$TAB" read -r _t _k _o _w; do
    [ -z "$_t" ] && continue
    _cur=$(kv_read "$_t" "$_k")
    if [ "$_cur" = "$_w" ]; then
      kv_restore "$_t" "$_k" "$_o"
      _v=$(kv_read "$_t" "$_k")
      log "RESTORE $_t $_k : $_w -> $_o (现在 $_v)"
      printf 'RESTORED\n' >>"$_tmp"
    else
      log "KEEP    $_t $_k 现值 $_cur 已非本模块所设，跳过"
      printf '%s\t%s\t%s\t%s\n' "$_t" "$_k" "$_o" "$_w" >>"$_tmp.keep"
    fi
  done
  _n=$(grep -c RESTORED "$_tmp" 2>/dev/null)
  [ -z "$_n" ] && _n=0
  if [ -s "$_tmp.keep" ]; then mv -f "$_tmp.keep" "$MANIFEST"; else rm -f "$_tmp.keep" "$MANIFEST"; fi
  rm -f "$_tmp"
  log "已回滚 $_n 项"
}

# ---------- 真实状态复核 ----------
# comp_read / perm_read 读的是本地快照，写入时就被改成目标值了，
# 所以它们只能证明「命令已下达」，证明不了系统真的接受。
# 这里重新抓一次系统状态（组件走 pm dump，权限走 dumpsys package），
# 再和清单里本模块写入的值逐条比对。SET 之后紧跟的这一段才是可信结论。
verify_real() {
  _n=0
  _bad=0
  _m="$STATE_FILES/manifest.verify"
  cat "$MANIFEST" >"$_m" 2>/dev/null || : >"$_m"

  if gms_snapshot >/dev/null 2>&1 && [ -s "$STATE_FILES/disabled.txt" ]; then
    while IFS="$TAB" read -r _t _k _o _w; do
      [ "$_t" = "comp" ] || continue
      _n=$((_n + 1))
      _real=$(comp_read "$_k")
      if [ "$_real" = "$_w" ]; then
        log "VERIFY-OK   comp $_k = $_w"
      else
        log "VERIFY-FAIL comp $_k 期望 $_w，系统实际 $_real"
        _bad=$((_bad + 1))
      fi
    done <"$_m"
  else
    log "VERIFY-FAIL 无法重新读取组件状态，本次不做组件复核"
    _bad=$((_bad + 1))
  fi

  if perm_snapshot >/dev/null 2>&1 && [ -s "$STATE_FILES/perms.txt" ]; then
    while IFS="$TAB" read -r _t _k _o _w; do
      [ "$_t" = "perm" ] || continue
      _n=$((_n + 1))
      _real=$(perm_read "$_k")
      if [ "$_real" = "$_w" ]; then
        log "VERIFY-OK   perm $_k = $_w"
      else
        log "VERIFY-FAIL perm $_k 期望 $_w，系统实际 $_real"
        _bad=$((_bad + 1))
      fi
    done <"$_m"
  else
    log "VERIFY-FAIL 无法重新读取权限状态，本次不做权限复核"
    _bad=$((_bad + 1))
  fi

  rm -f "$_m"

  if [ "$_n" = "0" ]; then
    log "VERIFY 清单里没有组件/权限类改动，跳过复核"
    return 0
  fi
  if [ "$_bad" = "0" ]; then
    log "VERIFY 全部一致（$_n 项）"
    return 0
  fi
  log "VERIFY 有 $_bad 项与系统实际状态不一致（共 $_n 项），这几项没有生效"
  return 1
}
