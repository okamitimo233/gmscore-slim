#!/system/bin/sh
# sysconfig overlay：生成 systemless 覆盖用的 google.xml
# 原理：magic mount 把 $MODPATH/system/product/... 挂到 /product/etc/... 之上，
#      系统读到的是我们生成的版本。卸载模块即自动恢复，无需回滚脚本。
#
# 只改 /product/etc/sysconfig/google.xml 里 GMS 的 4 行，其余 103 行原样保留。
# 绝对不能删的行：update-ownership（删了 Play 商店无法升级 GMS）、
#                backup-transport-whitelisted-service、app-data-isolation-whitelisted-app。

SC_SRC=/product/etc/sysconfig/google.xml
SC_DST_REL=system/product/etc/sysconfig/google.xml
SC_BACKUP=$STATE_DIR/backup/google.xml.orig

# 原始文件必须同时具备这两个锚点，否则说明读到的不是原版（可能已被别的模块覆盖）
sc_sane() {
  [ -f "$1" ] || return 1
  grep -q 'update-ownership package="com.google.android.gms"' "$1" || return 1
  grep -q 'backup-transport-whitelisted-service' "$1" || return 1
  grep -q '<config>' "$1" || return 1
  return 0
}

# 准备一份可信的原始文件：优先用备份，其次从系统读并校验
sc_ensure_source() {
  if sc_sane "$SC_BACKUP"; then
    printf '%s' "$SC_BACKUP"
    return 0
  fi
  if ! sc_sane "$SC_SRC"; then
    return 1
  fi
  mkdir -p "$STATE_DIR/backup" 2>/dev/null
  cp -af "$SC_SRC" "$SC_BACKUP" 2>/dev/null
  sc_sane "$SC_BACKUP" || return 1
  printf '%s' "$SC_BACKUP"
  return 0
}

# 生成到模块目录。$1=模块根目录  $2=是否静默（1=不打印）
sc_build() {
  _mod=$1
  _quiet=${2:-0}
  _say() { [ "$_quiet" = "1" ] || printf '%s\n' "$*"; }

  _src=$(sc_ensure_source)
  if [ -z "$_src" ]; then
    _say "SC-FAIL 找不到可信的原始 google.xml，放弃 overlay"
    return 1
  fi

  _dst="$_mod/$SC_DST_REL"
  mkdir -p "${_dst%/*}" 2>/dev/null

  # 以原始文件为基底，按开关逐条删行（用内容匹配，不用行号，避免版本差异）
  cp -af "$_src" "$_dst" 2>/dev/null || { _say "SC-FAIL 复制失败"; return 1; }

  _removed=""
  if [ "${FEATURE_SC_LOCATION:-1}" = "1" ]; then
    sed -i '/allow-ignore-location-settings package="com.google.android.gms"/d' "$_dst" 2>/dev/null
    _removed="$_removed ignore-location-settings"
  fi
  if [ "${FEATURE_SC_POWERSAVE:-0}" = "1" ]; then
    sed -i '/allow-in-power-save package="com.google.android.gms"/d' "$_dst" 2>/dev/null
    _removed="$_removed allow-in-power-save"
  fi
  if [ "${FEATURE_SC_DATAUSAGE:-0}" = "1" ]; then
    sed -i '/allow-in-data-usage-save package="com.google.android.gms"/d' "$_dst" 2>/dev/null
    _removed="$_removed allow-in-data-usage-save"
  fi
  if [ "${FEATURE_SC_UNTHROTTLE:-0}" = "1" ]; then
    sed -i '/allow-unthrottled-location package="com.google.android.gms"/d' "$_dst" 2>/dev/null
    _removed="$_removed allow-unthrottled-location"
  fi

  # 生成后自检：关键行必须还在，XML 结构必须完整，否则不覆盖（宁可不出效果也不能弄坏系统）
  if ! sc_sane "$_dst"; then
    rm -f "$_dst"
    _say "SC-FAIL 生成结果未通过完整性校验，已放弃（不会覆盖系统文件）"
    return 1
  fi
  if ! grep -q 'com.google.android.dialer' "$_dst"; then
    rm -f "$_dst"
    _say "SC-FAIL dialer 的 ignore-location-settings 被误删，已放弃"
    return 1
  fi

  chmod 0644 "$_dst" 2>/dev/null
  _o=$(wc -l <"$_src" 2>/dev/null)
  _n=$(wc -l <"$_dst" 2>/dev/null)
  _say "SC-OK 已生成 overlay：${_o} 行 -> ${_n} 行"
  _say "SC-REMOVED${_removed}"
  return 0
}

# 验证 overlay 是否真的挂上了（开机后调用）
# $1=模块根目录，省略则用 /data/adb/modules/<id>
# 判据：系统实际读到的文件 == 模块内生成版 => 已挂载；
#       == 备份原版 => 未挂载。不能只比"两者是否不同"，因为处理版和原版本来就不同。
sc_verify() {
  _mod=${1:-/data/adb/modules/$MODID}
  _mf="$_mod/$SC_DST_REL"
  if [ ! -f "$_mf" ]; then
    printf '未生成 overlay 文件\n'
    return 1
  fi
  _m_md5=$(md5sum "$_mf" 2>/dev/null | cut -d' ' -f1)
  _s_md5=$(md5sum "$SC_SRC" 2>/dev/null | cut -d' ' -f1)
  _o_md5=$(md5sum "$SC_BACKUP" 2>/dev/null | cut -d' ' -f1)
  if [ -z "$_m_md5" ] || [ -z "$_s_md5" ]; then
    printf '无法计算校验值\n'
    return 1
  fi
  if [ -n "$_o_md5" ] && [ "$_s_md5" = "$_o_md5" ]; then
    printf 'NOT-MOUNTED 系统仍是原版（overlay 未生效）\n'
    return 1
  fi
  if [ "$_s_md5" = "$_m_md5" ]; then
    printf 'MOUNTED 系统读到的正是模块版本（%s 行）\n' "$(wc -l <"$_mf" 2>/dev/null)"
    return 0
  fi
  printf 'UNKNOWN 系统内容与模块版、原版都不同（可能被其他模块覆盖）\n'
  return 1
}
