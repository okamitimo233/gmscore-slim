#!/bin/sh
# 检查 7：提交信息规范（Conventional Commits）
#   格式：<type>(<scope>): <subject>
#   type 限 feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert
#
# 用法：
#   scripts/check-commit-msg.sh <commit-msg 文件路径>
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

check_init "commit-msg"

MSG_FILE=${1:-}
if [ -z "$MSG_FILE" ] || [ ! -f "$MSG_FILE" ]; then
  check_fail "未提供提交信息文件" "用法：scripts/check-commit-msg.sh <path>"
  check_finish
  exit $?
fi

# 取第一行非空、非注释的内容作为 subject
SUBJECT=$(sed -e '/^#/d' -e '/^[[:space:]]*$/d' "$MSG_FILE" | head -1)

if [ -z "$SUBJECT" ]; then
  check_fail "提交信息为空" "需要一句话说明改了什么"
  check_finish
  exit $?
fi

# 放行 git 自动生成的合并/revert 提交
case "$SUBJECT" in
  "Merge "*|"Revert "*|"fixup! "*|"squash! "*)
    check_pass
    check_finish
    exit $?
    ;;
esac

# 主规则：type(scope): subject  或  type: subject
if printf '%s' "$SUBJECT" | grep -Eq '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9._-]+\))?: .+'; then
  check_pass
else
  check_fail "提交信息不符合 Conventional Commits" "当前：$SUBJECT"
  printf '    %s合法 type：feat fix docs style refactor perf test build ci chore revert%s\n' "$C_DIM" "$C_RST"
  printf '    %s示例：feat(sysconfig): 支持只删单行豁免%s\n' "$C_DIM" "$C_RST"
fi

# subject 长度（超过 72 字符在 git log 里会折行）
SUB_LEN=$(printf '%s' "$SUBJECT" | wc -c | tr -d ' ')
if [ "$SUB_LEN" -gt 72 ]; then
  check_fail "subject 过长（$SUB_LEN 字符）" "建议不超过 72 字符"
else
  check_pass
fi

# subject 不应以句号结尾（半角与全角都要拦）
case "$SUBJECT" in
  *.|*。)
    check_fail "subject 不应以句号结尾" "当前：$SUBJECT"
    ;;
  *)
    check_pass
    ;;
esac

check_finish
