#!/bin/sh
# 检查 3：换行符与末尾换行
#   CRLF 会让 Android 上的模块脚本报 "bad interpreter"，
#   是本项目最需要防的低级事故之一。
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

ROOT=$(repo_root)
FILES=$(list_all_files)

check_init "换行"

for f in $FILES; do
  [ -f "$ROOT/$f" ] || continue

  # 跳过已知二进制
  case "$f" in
    *.png|*.jpg|*.jpeg|*.zip|*.gz|*.deb)
      continue
      ;;
  esac

  # 含 CR 即视为 CRLF
  if LC_ALL=C grep -q "$(printf '\r')" "$ROOT/$f" 2>/dev/null; then
    check_fail "$f 含 CRLF" "Android 上会报 bad interpreter。修复：sed -i 's/\r$//' $f 或 dos2unix $f"
    continue
  fi

  # 文本文件应以换行结尾
  if [ -s "$ROOT/$f" ]; then
    _last=$(tail -c 1 "$ROOT/$f" 2>/dev/null | od -An -c 2>/dev/null | tr -d ' ')
    if [ "$_last" != '\n' ] && [ "$_last" != '012' ]; then
      check_fail "$f 结尾缺少换行" "POSIX 要求文本文件以换行结尾。修复：printf '\\n' >> $f"
      continue
    fi
  fi

  check_pass
done

check_finish
