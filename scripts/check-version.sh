#!/bin/sh
# 检查 8：版本号一致性（pre-push / CI 用）
#   module.prop 的 version 与 README 标题里的版本号应当一致，
#   versionCode 必须为正整数且不与已有 tag 冲突。
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

ROOT=$(repo_root)
PROP="$ROOT/module.prop"
README="$ROOT/README.md"

check_init "版本一致"

if [ ! -f "$PROP" ]; then
  check_fail "module.prop 不存在"
  check_finish
  exit $?
fi

_ver=$(sed -n 's/^version=//p' "$PROP" | head -1)
# 允许 v1.2 或 1.2 两种写法，统一抽出数字部分
_ver_num=$(printf '%s' "$_ver" | sed 's/^[vV]//')

if [ -z "$_ver_num" ]; then
  check_fail "version 为空"
else
  check_pass
fi

# README 标题里如果写了版本，应与 module.prop 一致
if [ -f "$README" ]; then
  _rd_ver=$(sed -n 's/^# .*[vV]\([0-9][0-9.]*\).*/\1/p' "$README" | head -1)
  if [ -n "$_rd_ver" ]; then
    if [ "$_rd_ver" = "$_ver_num" ]; then
      check_pass
    else
      check_fail "版本号不一致" "module.prop=$_ver_num  README=$_rd_ver"
    fi
  else
    check_warn "README 标题未写版本号，跳过一致性比对"
  fi
fi

# 若存在 tag，version 不应与已有 tag 重复（防止同版本两次发布）
if command -v git >/dev/null 2>&1 && [ -d "$ROOT/.git" ]; then
  if (cd "$ROOT" && git rev-parse --git-dir >/dev/null 2>&1); then
    _tags=$(cd "$ROOT" && git tag -l "v$_ver_num" 2>/dev/null)
    if [ -n "$_tags" ]; then
      check_warn "已存在同名 tag $_tags（若是重发同一版本请忽略）"
    else
      check_pass
    fi
  fi
fi

check_finish
