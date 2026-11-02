#!/bin/sh
# 检查脚本共用的小工具：统一的输出格式与失败计数
# 被 scripts/check-*.sh 与 scripts/verify.sh 引用
#
# 用法（在检查脚本里）：
#   . "$(dirname "$0")/lib.sh"
#   check_init "名称"
#   check_fail "文件" "说明"     # 记录一条失败
#   check_pass "说明"            # 记录一条通过
#   check_finish                 # 打印汇总并返回合适退出码

# 让输出在非终端环境下不带颜色
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$(printf '\033[31m')
  C_GRN=$(printf '\033[32m')
  C_YEL=$(printf '\033[33m')
  C_DIM=$(printf '\033[2m')
  C_RST=$(printf '\033[0m')
else
  C_RED=''
  C_GRN=''
  C_YEL=''
  C_DIM=''
  C_RST=''
fi

FAIL_COUNT=0
PASS_COUNT=0
CHECK_NAME=''

check_init() {
  CHECK_NAME=$1
  FAIL_COUNT=0
  PASS_COUNT=0
  printf '%s[%s]%s ' "$C_DIM" "$CHECK_NAME" "$C_RST"
}

check_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '\n  %s✗%s %s\n' "$C_RED" "$C_RST" "$1"
  [ -n "${2:-}" ] && printf '    %s%s%s\n' "$C_DIM" "$2" "$C_RST"
}

check_warn() {
  printf '\n  %s!%s %s\n' "$C_YEL" "$C_RST" "$1"
  [ -n "${2:-}" ] && printf '    %s%s%s\n' "$C_DIM" "$2" "$C_RST"
}

check_pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
}

# 返回 0 表示全过；非 0 表示有失败
check_finish() {
  if [ "$FAIL_COUNT" -eq 0 ]; then
    printf '%s✓%s %s 项通过\n' "$C_GRN" "$C_RST" "$PASS_COUNT"
    return 0
  fi
  printf '%s✗ %s 项失败%s' "$C_RED" "$FAIL_COUNT" "$C_RST"
  [ "$PASS_COUNT" -gt 0 ] && printf ' %s(%s 项通过)%s' "$C_DIM" "$PASS_COUNT" "$C_RST"
  printf '\n'
  return 1
}

# 取仓库根目录（脚本放在 scripts/ 下，根目录是上一级）
repo_root() {
  _d=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
  printf '%s' "$_d"
}

# 列出所有受版本管理的 shell 脚本（不依赖 git 的兜底实现）
# 除了 *.sh，还要包含 .githooks/ 与 .husky/ 下的无后缀钩子脚本
list_shell_files() {
  _r=$(repo_root)
  if command -v git >/dev/null 2>&1 && [ -d "$_r/.git" ]; then
    (cd "$_r" && git ls-files '*.sh' '.githooks/*' '.husky/*')
  else
    (cd "$_r" && find . -name '*.sh' -not -path './.git/*' | sed 's|^\./||')
    for _dir in .githooks .husky; do
      [ -d "$_r/$_dir" ] || continue
      for _h in "$_r/$_dir"/*; do
        [ -f "$_h" ] || continue
        case "$_h" in
          *.sample|*/_|*/_/*) continue ;;
        esac
        printf '%s/%s\n' "$_dir" "${_h##*/}"
      done
    done
  fi
}

# 列出所有受版本管理的文件
list_all_files() {
  _r=$(repo_root)
  if command -v git >/dev/null 2>&1 && [ -d "$_r/.git" ]; then
    (cd "$_r" && git ls-files)
  else
    (cd "$_r" && find . -type f -not -path './.git/*' | sed 's|^\./||')
  fi
}
