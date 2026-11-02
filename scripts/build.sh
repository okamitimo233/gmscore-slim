#!/bin/sh
# 打包成可刷入的 KernelSU 模块 zip
# 只包含模块运行必需的文件，不含仓库自身的开发配置（scripts/、.githooks/ 等）
#
# 用法：scripts/build.sh [输出目录]
#       默认输出到仓库根目录
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

ROOT=$(repo_root)
OUT_DIR=${1:-$ROOT}

# 版本号
VER=$(sed -n 's/^version=//p' "$ROOT/module.prop" | head -1)
if [ -z "$VER" ]; then
  printf '错误：module.prop 缺少 version 字段\n' >&2
  exit 1
fi

ZIP_NAME="gmscore-slim-$VER.zip"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"

command -v zip >/dev/null 2>&1 || { printf '错误：需要 zip 命令（apt install zip）\n' >&2; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT INT TERM

# 模块运行必需的文件
for f in module.prop customize.sh service.sh boot-completed.sh action.sh uninstall.sh README.md; do
  [ -f "$ROOT/$f" ] && cp -a "$ROOT/$f" "$STAGE/"
done
[ -d "$ROOT/lib" ] && cp -a "$ROOT/lib" "$STAGE/"

# 权限必须是 755，否则刷入后跑不起来
chmod 755 "$STAGE"/*.sh "$STAGE"/lib/*.sh 2>/dev/null
chmod 644 "$STAGE"/README.md "$STAGE"/module.prop 2>/dev/null

printf '打包 %s ...\n' "$ZIP_NAME"
rm -f "$ZIP_PATH"
( cd "$STAGE" && zip -r -9 -q "$ZIP_PATH" . -x '.*' )

# 自检：包里脚本的可执行位
BAD=0
for f in service.sh action.sh customize.sh boot-completed.sh uninstall.sh; do
  MODE=$(unzip -Z "$ZIP_PATH" "$f" 2>/dev/null | awk '{print $1}')
  case "$MODE" in
    -rwxr-xr-x) ;;
    *) printf '  ✗ %s 权限为 %s，应为 -rwxr-xr-x\n' "$f" "$MODE" >&2; BAD=1 ;;
  esac
done

printf '  大小: %s\n' "$(wc -c <"$ZIP_PATH" | tr -d ' ') 字节"
printf '  路径: %s\n' "$ZIP_PATH"
if [ "$BAD" = "0" ]; then
  printf '  ✓ 脚本权限正确\n'
else
  printf '  ✗ 存在权限问题\n' >&2
  exit 1
fi
