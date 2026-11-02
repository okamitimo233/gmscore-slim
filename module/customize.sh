# KernelSU / Magisk 安装脚本
# 本模块的运行时改动不碰系统分区；sysconfig 部分走 systemless overlay

ui_print "- GMS Slim 安装中"
ui_print "- 目标：com.google.android.gms（Google Play services）"

STATE_DIR=/data/adb/gmscore-slim

mkdir -p "$STATE_DIR/state" "$STATE_DIR/log" "$STATE_DIR/lib" "$STATE_DIR/backup"

# 脚本统一权限与 LF 换行（安装期不做任何 pm/cmd 操作，那些必须等开机后）
set_perm_recursive "$MODPATH" 0 0 0755 0644
for _f in service.sh boot-completed.sh uninstall.sh action.sh customize.sh; do
  [ -f "$MODPATH/$_f" ] && set_perm "$MODPATH/$_f" 0 0 0755
done
for _f in core.sh apply.sh config.sh sysconfig.sh; do
  [ -f "$MODPATH/lib/$_f" ] && set_perm "$MODPATH/lib/$_f" 0 0 0644
done

# 备份 core.sh 到外部状态目录，卸载时即使模块目录已被替换也能回滚
cp -f "$MODPATH/lib/core.sh" "$STATE_DIR/lib/core.sh" 2>/dev/null
set_perm "$STATE_DIR/lib/core.sh" 0 0 0644

# 首次安装才生成可编辑的开关文件，升级不覆盖用户配置
if [ ! -f "$STATE_DIR/config.sh" ]; then
  cp -f "$MODPATH/lib/config.sh" "$STATE_DIR/config.sh"
  set_perm "$STATE_DIR/config.sh" 0 0 0644
  ui_print "- 已生成开关文件：/data/adb/gmscore-slim/config.sh"
else
  ui_print "- 保留已有开关文件：/data/adb/gmscore-slim/config.sh"
fi

# ---------- sysconfig overlay ----------
# 加载开关后生成覆盖文件。安装期 /product 是原始内容，适合取基准。
_i=0
while [ ! -f "$STATE_DIR/config.sh" ] && [ $_i -lt 5 ]; do sleep 1; _i=$((_i+1)); done
# shellcheck disable=SC1091  # 运行时路径，shellcheck 无法静态解析
. "$STATE_DIR/config.sh" 2>/dev/null

if [ "${FEATURE_SYSCONFIG:-1}" = "1" ]; then
  . "$MODPATH/lib/sysconfig.sh"
  ui_print "- 正在生成 sysconfig overlay…"
  sc_build "$MODPATH" 0 2>/dev/null | while read -r _line; do
    case "$_line" in
      SC-OK*)      ui_print "  ${_line#SC-OK }" ;;
      SC-REMOVED*) ui_print "  已删除：$(printf '%s' "${_line#SC-REMOVED}" | sed 's/^ *//')" ;;
      SC-FAIL*)    ui_print "  ! ${_line#SC-FAIL }" ;;
    esac
  done
  if [ -f "$MODPATH/system/product/etc/sysconfig/google.xml" ]; then
    ui_print "- overlay 已就位，重启后生效"
  else
    ui_print "- ! overlay 未生成，本次只做运行时改动"
  fi
else
  ui_print "- sysconfig overlay 已关闭（FEATURE_SYSCONFIG=0）"
fi

ui_print "- 默认只开两项：遥测组件压制、定位豁免行，其余需手动开"
ui_print "- 重启生效；日志：/data/adb/gmscore-slim/log/last.log"
ui_print "- 卸载模块即自动恢复系统文件"
