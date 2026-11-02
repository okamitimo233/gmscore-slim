#!/bin/sh
# 检查 5：禁止提交运行时产物与体积炸弹
#   sysconfig overlay 生成物、日志、备份、zip 都不该进版本库。
#   这些文件由 customize.sh / action.sh 在运行时产出。
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

ROOT=$(repo_root)

check_init "产物"

# 1) 不应被追踪的路径模式
_forbidden_patterns='
system/
state/
backup/
log/
*.log
*.zip
*.tar.gz
google.xml.orig
'

_bad=0
for p in $_forbidden_patterns; do
  # 用 git 检查是否已被追踪
  if command -v git >/dev/null 2>&1 && [ -d "$ROOT/.git" ]; then
    # shellcheck disable=SC2046  # $p 是受控模式串，按空格拆分正是本意
    _hit=$(cd "$ROOT" && git ls-files -- $(printf '%s' "$p") 2>/dev/null)
    if [ -n "$_hit" ]; then
      check_fail "禁止提交: $p" "已被追踪的文件：$(printf '%s' "$_hit" | tr '\n' ' ')"
      _bad=1
    fi
  fi
done
[ "$_bad" = "0" ] && check_pass

# 2) 单文件体积上限（500 KB）—— 模块脚本不该有这么大的文件
for f in $(list_all_files); do
  [ -f "$ROOT/$f" ] || continue
  _sz=$(wc -c <"$ROOT/$f" 2>/dev/null || echo 0)
  if [ "$_sz" -gt 512000 ]; then
    check_fail "$f 体积过大" "$((_sz / 1024)) KB，超过 500 KB 上限（模块应为轻量脚本集合）"
    _bad=1
  fi
done
[ "$_bad" = "0" ] && check_pass

# 3) .gitignore 必须存在
if [ -f "$ROOT/.gitignore" ]; then
  check_pass
else
  check_fail ".gitignore 缺失" "必须存在以阻止产物入库"
fi

check_finish
