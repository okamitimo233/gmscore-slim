#!/system/bin/sh
# 卸载时逐条回滚。只回滚现值仍等于本模块写入值的项。
# 优先用 /data/adb 下的 core.sh 副本（模块目录可能已被替换）
STATE_DIR=/data/adb/gmscore-slim
LIB="$STATE_DIR/lib/core.sh"
[ -f "$LIB" ] || LIB="${0%/*}/lib/core.sh"

if [ ! -f "$LIB" ]; then
  echo "找不到 core.sh，无法自动回滚。请手动检查 $STATE_DIR/state/manifest.tsv"
  exit 0
fi

. "$LIB"
echo "===== GMS Slim 卸载回滚 ====="
rollback_all

# 待机白名单重启后由系统重置，无需处理
echo "回滚完成。建议重启一次让 GMS 回到原始状态。"
echo "日志: $LOG_FILE"
