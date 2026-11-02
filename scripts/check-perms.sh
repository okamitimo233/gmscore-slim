#!/bin/sh
# 检查 2：文件权限
#   .sh 必须是 100755（KernelSU 的 service.sh / action.sh 等需要可执行）
# 这是本仓库的实测教训：/sdcard 会抹掉可执行位，提交后 clone 下来跑不了。
#
# 同时检查两个来源，任一不合规即报错：
#   - git 索引（决定 clone 出来的权限）
#   - 工作区实际权限（防止 add 之后又 chmod 的窗口漏过去）
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

ROOT=$(repo_root)
FILES=$(list_shell_files)

check_init "权限"

if [ -z "$FILES" ]; then
  check_fail "未找到任何 .sh 文件"
  check_finish
  exit $?
fi

for f in $FILES; do
  _ok=1

  # 1) 工作区实际权限
  if [ -f "$ROOT/$f" ]; then
    if [ -x "$ROOT/$f" ]; then
      check_pass
    else
      check_fail "$f 工作区缺少可执行位" "修复：chmod +x $f"
      _ok=0
    fi
  else
    check_fail "$f 文件不存在" "索引里有记录但磁盘上找不到"
    continue
  fi

  # 2) git 索引权限（决定 clone 后的结果）
  if command -v git >/dev/null 2>&1 && [ -d "$ROOT/.git" ]; then
    _mode=$(cd "$ROOT" && git ls-files -s -- "$f" 2>/dev/null | cut -d' ' -f1)
    case "$_mode" in
      100755)
        check_pass
        ;;
      100644)
        check_fail "$f 索引记录为 100644" "clone 后无法执行。修复：chmod +x $f && git add $f"
        _ok=0
        ;;
      '')
        check_fail "$f 未加入版本管理" "修复：git add $f"
        _ok=0
        ;;
      *)
        check_fail "$f 索引权限异常" "当前 $_mode，期望 100755"
        _ok=0
        ;;
    esac
  fi

  [ "$_ok" = "1" ] || :
done

check_finish
