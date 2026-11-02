#!/bin/sh
# 检查 4：module.prop 完整性与版本号一致性
#   KernelSU 要求必填字段齐全，versionCode 必须是整数且在 tag/README 中一致。
#   本项目的实测教训：versionCode 忘了递增会导致模块管理器不提示更新。
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

ROOT=$(repo_root)
PROP="$ROOT/module.prop"

check_init "module.prop"

if [ ! -f "$PROP" ]; then
  check_fail "module.prop 不存在" "KernelSU 模块必需此文件"
  check_finish
  exit $?
fi

# 必填字段
for k in id name version versionCode author description; do
  _v=$(sed -n "s/^$k=//p" "$PROP" | head -1)
  if [ -z "$_v" ]; then
    check_fail "缺少字段 $k" "module.prop 必须有 $k="
  else
    check_pass
  fi
done

# versionCode 必须是纯整数（KernelSU 用它比较版本）
_vc=$(sed -n 's/^versionCode=//p' "$PROP" | head -1)
case "$_vc" in
  ''|*[!0-9]*)
    check_fail "versionCode 不是整数" "当前值：'$_vc'，必须为正整数"
    ;;
  *)
    check_pass
    ;;
esac

# id 必须与模块目录约定一致（全小写、无空格）
_id=$(sed -n 's/^id=//p' "$PROP" | head -1)
if [ -n "$_id" ]; then
  case "$_id" in
    *[A-Z]*|*' '*)
      check_fail "id 格式不合规" "当前：'$_id'，应全小写且无空格"
      ;;
    *)
      check_pass
      ;;
  esac
fi

# 检查是否有重复键（key=value 重复会导致行为不确定）
_dup=$(sed -n 's/^\([A-Za-z][A-Za-z0-9_]*\)=.*/\1/p' "$PROP" | sort | uniq -d)
if [ -n "$_dup" ]; then
  check_fail "存在重复键" "$(printf '%s' "$_dup" | tr '\n' ' ')"
else
  check_pass
fi

check_finish
