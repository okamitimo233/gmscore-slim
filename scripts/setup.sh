#!/bin/sh
# 一次性初始化开发环境
# 克隆仓库后执行：./scripts/setup.sh
#
# 做的事只有安装依赖（husky 的 prepare 钩子会自动装好 git hooks），
# 其余检查配置都在 package.json / commitlint.config.mjs 里。
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

printf '初始化开发环境...\n\n'

if ! command -v node >/dev/null 2>&1; then
  printf '错误：需要 Node.js >= 18\n' >&2
  exit 1
fi

printf 'Node %s / npm %s\n\n' "$(node -v)" "$(npm -v)"

printf '安装依赖（husky / lint-staged / commitlint）...\n'
npm install

printf '\n依赖检查：\n'
if command -v shellcheck >/dev/null 2>&1; then
  printf '  ✓ shellcheck %s\n' "$(shellcheck --version | sed -n 's/^version: //p')"
else
  printf '  ! 未安装 shellcheck，提交时无法检查脚本\n'
  printf '    Debian/Ubuntu: sudo apt install shellcheck\n'
  printf '    macOS:         brew install shellcheck\n'
fi

printf '\n钩子：\n'
printf '  core.hooksPath = %s\n' "$(git config core.hooksPath)"
for h in .husky/*; do
  case "${h##*/}" in
    _) continue ;;
  esac
  [ -f "$h" ] && printf '  %s\n' "${h##*/}"
done

printf '\n完成。\n'
printf '  pre-commit  → lint-staged（shellcheck 检查暂存的 .sh）\n'
printf '  commit-msg  → commitlint（Conventional Commits）\n'
printf '\n紧急跳过：git commit --no-verify（CI 仍会检查）\n'
