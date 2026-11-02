#!/bin/sh
# 一键跑全部检查。pre-commit 钩子与 GitHub Actions 都调用本脚本，
# 保证「本地能过 = CI 能过」，规则只有一份实现。
#
# 用法：
#   scripts/verify.sh            # 全部检查
#   scripts/verify.sh --quick    # 跳过较慢的版本一致性检查
#
# 退出码：0 = 全过，非 0 = 有失败（数量即失败项数）
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

QUICK=0
for a in "$@"; do
  case "$a" in
    --quick) QUICK=1 ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done

printf '%s──── GMS Slim 仓库校验 ────%s\n' "$C_DIM" "$C_RST"

TOTAL_FAIL=0
run() {
  _name=$1
  shift
  if "$@" ; then
    :
  else
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi
}

run "shell"     "$SCRIPT_DIR/check-shell.sh"
run "perms"     "$SCRIPT_DIR/check-perms.sh"
run "eol"       "$SCRIPT_DIR/check-eol.sh"
run "module"    "$SCRIPT_DIR/check-module.sh"
run "artifacts" "$SCRIPT_DIR/check-artifacts.sh"
run "secrets"   "$SCRIPT_DIR/check-secrets.sh"

if [ "$QUICK" = "0" ]; then
  run "version" "$SCRIPT_DIR/check-version.sh"
fi

echo
if [ "$TOTAL_FAIL" -eq 0 ]; then
  printf '%s全部检查通过%s\n' "$C_GRN" "$C_RST"
  exit 0
fi
printf '%s%s 组检查未通过，请修复后重试%s\n' "$C_RED" "$TOTAL_FAIL" "$C_RST"
exit "$TOTAL_FAIL"
