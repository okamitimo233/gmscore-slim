#!/bin/sh
# 检查 6：敏感信息扫描
#   防止把 token / 私钥 / 设备凭据提交进公开仓库。
#   本仓库是 PUBLIC 的，这一项尤其重要。
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

ROOT=$(repo_root)

check_init "敏感信息"

# 高置信度特征（宁可误报也要抓住）
# 注意：这些模式写成变量是为了让本文件自身不被扫描命中
_pat_gh_token='gh[pousr]_[A-Za-z0-9]\{20,\}'
_pat_gh_pat='github_pat_[A-Za-z0-9_]\{20,\}'
_pat_aws='AKIA[0-9A-Z]\{16\}'
_pat_privkey='BEGIN [A-Z ]*PRIVATE KEY'
_pat_slack='xox[baprs]-[0-9A-Za-z-]\{10,\}'
_pat_generic_token='[Tt]oken[[:space:]]*=[[:space:]]*["'"'"']\?[A-Za-z0-9_-]\{30,\}'

# 允许出现在期望位置的文件（文档里讲这些关键词是正常的）
_is_allowlisted() {
  case "$1" in
    scripts/check-secrets.sh)
      return 0
      ;;
  esac
  return 1
}

FOUND=0
for f in $(list_all_files); do
  [ -f "$ROOT/$f" ] || continue
  _is_allowlisted "$f" && continue

  for _pat in "$_pat_gh_token" "$_pat_gh_pat" "$_pat_aws" "$_pat_privkey" "$_pat_slack" "$_pat_generic_token"; do
    if LC_ALL=C grep -q "$_pat" "$ROOT/$f" 2>/dev/null; then
      check_fail "$f 疑似包含凭据" "命中模式：$(printf '%s' "$_pat" | cut -c1-30)...  请人工确认后从历史中清除"
      FOUND=1
      break
    fi
  done
done

if [ "$FOUND" = "0" ]; then
  check_pass
fi

# 额外：确认没有把 ssh 私钥或 gh 配置放进仓库
for _danger in id_rsa id_ed25519 hosts.yml .git-credentials .netrc; do
  _hit=$(list_all_files | grep -F "$_danger" 2>/dev/null)
  if [ -n "$_hit" ]; then
    check_fail "禁止提交凭据文件: $_danger" "$_hit"
    FOUND=1
  fi
done
[ "$FOUND" = "0" ] && check_pass

check_finish
