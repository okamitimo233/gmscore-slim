#!/bin/sh
# 一次性安装本仓库的 git 钩子与本地配置
# 克隆仓库后执行一次即可：./scripts/setup.sh
#
# 选择 core.hooksPath 而不是 husky 的原因：
#   本仓库是纯 shell 的 KernelSU 模块，引入 node_modules 会让仓库从 ~300KB 膨胀到十几 MB，
#   且在 Android 侧完全用不上。core.hooksPath 是 git 原生能力（2.9+），零依赖、可版本化。
set -u

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1

printf '安装 GMS Slim 仓库钩子...\n'

if [ ! -d .git ]; then
  printf '错误：当前目录不是 git 仓库\n' >&2
  exit 1
fi

# 1) 指向仓库内的钩子目录（钩子随代码一起版本化，克隆即得）
git config core.hooksPath .githooks
printf '  core.hooksPath = %s\n' "$(git config core.hooksPath)"

# 2) 保留文件权限位（/sdcard 等 FUSE 挂载会抹掉可执行位，此项确保 git 记录 755）
git config core.fileMode true
printf '  core.fileMode  = %s\n' "$(git config core.fileMode)"

# 3) 确保钩子可执行
for h in .githooks/pre-commit .githooks/commit-msg .githooks/pre-push; do
  [ -f "$h" ] && chmod +x "$h"
done
chmod +x scripts/*.sh 2>/dev/null

# 4) 提示缺少的工具
printf '\n依赖检查：\n'
if command -v shellcheck >/dev/null 2>&1; then
  printf '  ✓ shellcheck %s\n' "$(shellcheck --version 2>/dev/null | sed -n 's/^version: //p')"
else
  printf '  ! shellcheck 未安装（静态分析将降级为纯语法检查）\n'
  printf '    Debian/Ubuntu: apt install shellcheck\n'
fi
command -v git >/dev/null 2>&1 && printf '  ✓ git %s\n' "$(git --version | sed 's/git version //')"

# 5) 自检
printf '\n运行一次完整校验：\n'
if ./scripts/verify.sh --quick >/dev/null 2>&1; then
  printf '  ✓ 校验通过\n'
else
  printf '  ! 校验有未通过项，请运行 ./scripts/verify.sh 查看详情\n'
fi

printf '\n完成。提交时会自动运行 pre-commit 与 commit-msg 钩子。\n'
printf '紧急跳过：git commit --no-verify（CI 仍会检查）\n'
