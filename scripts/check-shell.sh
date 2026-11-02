#!/bin/sh
# 检查 1：shell 语法与静态分析
#   有 shellcheck 时跑 shellcheck（严格），否则退化为 sh -n
#   这是本仓库最重要的一项 —— 模块脚本在 Android 上跑，语法错误等于模块失效
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

ROOT=$(repo_root)
FILES=$(list_shell_files)

check_init "shell"

if [ -z "$FILES" ]; then
  check_fail "未找到任何 .sh 文件"
  check_finish
  exit $?
fi

HAVE_SC=0
command -v shellcheck >/dev/null 2>&1 && HAVE_SC=1

for f in $FILES; do
  # 语法检查（所有环境都做）
  if ! sh -n "$ROOT/$f" 2>/dev/null; then
    msg=$(sh -n "$ROOT/$f" 2>&1 | head -3)
    check_fail "$f 语法错误" "$msg"
    continue
  fi

  # 静态分析（仅在装了 shellcheck 时）
  if [ "$HAVE_SC" = "1" ]; then
    # -x 让 shellcheck 跟踪 source 的文件（做跨文件分析）
    # -P 指定 source 搜索路径，解决 lib/ 与 scripts/ 两处引用的解析
    _out=$(cd "$ROOT" && shellcheck -s sh -x -P . -P lib -P scripts -f gcc "$f" 2>&1)
    if [ -n "$_out" ]; then
      check_fail "$f shellcheck 告警" "$(printf '%s' "$_out" | head -5)"
      continue
    fi
  fi

  check_pass
done

if [ "$HAVE_SC" = "0" ]; then
  check_warn "未安装 shellcheck，仅做了语法检查（建议 apt install shellcheck）"
fi

check_finish
