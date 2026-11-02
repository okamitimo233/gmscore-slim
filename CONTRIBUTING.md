# 贡献与开发规范

本项目是 KernelSU 模块，全部逻辑用 POSIX shell 实现。目标是**在 Android 设备上可靠运行**，
因此规范的重点是防止那些在桌面看不出来、到手机上才炸的问题。

## 快速开始

```sh
git clone git@github.com:okamitimo233/gmscore-slim.git
cd gmscore-slim
./scripts/setup.sh        # 安装 git 钩子 + 依赖检查
```

`setup.sh` 会做三件事：设置 `core.hooksPath=.githooks`、确保脚本可执行、跑一次校验。

## 检查什么，为什么

提交时自动运行，也可以用 `./scripts/verify.sh` 手动跑。

| 检查 | 防的问题 |
|---|---|
| `check-shell.sh` | 语法错误 → 模块开机直接失效。装了 shellcheck 时还会做静态分析 |
| `check-perms.sh` | `.sh` 丢了可执行位 → 刷入后脚本跑不起来。**同时查工作区与 git 索引** |
| `check-eol.sh` | CRLF → Android 上报 `bad interpreter` |
| `check-module.sh` | `module.prop` 字段缺失或 `versionCode` 非整数 → 模块管理器不认 |
| `check-artifacts.sh` | 产物入库（`system/`、日志、zip）→ 仓库膨胀且会覆盖别人的文件 |
| `check-secrets.sh` | token / 私钥进公开仓库 |
| `check-version.sh` | `module.prop` 与 `README` 版本号不一致、同版本重复发 tag |

每条规则都来自实际踩过的坑，细节记在 [`DEVNOTES.md`](DEVNOTES.md)。

## 提交信息

遵循 [Conventional Commits](https://www.conventionalcommits.org/)：

```
<type>(<scope>): <subject>
```

- **type**：`feat` `fix` `docs` `style` `refactor` `perf` `test` `build` `ci` `chore` `revert`
- **scope**：可选，如 `sysconfig`、`perms`、`core`
- **subject**：不超过 72 字符，不以句号结尾

```
feat(sysconfig): 支持只删单行豁免
fix(core): 回滚时清除 device_config override 残留
docs: 补充 overlay 挂载验证步骤
```

`Merge`、`Revert`、`fixup!`、`squash!` 开头的提交自动放行。

## 代码约定

- **POSIX sh**，不用 bash 扩展（目标环境是 Android 的 busybox ash / toybox）
- 缩进 2 空格，LF 换行（`.gitattributes` 已强制）
- 变量一律加引号；但调用 `cmd`/`pm`/`dumpsys` 时**必须显式 `</dev/null`**，原因见 DEVNOTES
- 新增功能要有对应的开关，默认关闭高风险项
- 涉及系统改动的，必须在 `uninstall.sh` 里能回滚

## 分支与版本

- `main` 保持可发布
- 功能分支：`feat/xxx`、`fix/xxx`
- 改 `module.prop` 的 `version` 时，`versionCode` 必须同时 +1（模块管理器靠它判断更新）
- 发布：打 tag `v<version>`，CI 会自动构建 zip 并创建 Release

## 关于 husky

本仓库**默认不用 husky**，而用 git 原生的 `core.hooksPath`：

- 零依赖，克隆后一条命令生效
- 钩子随代码版本化，改规则不用重新安装
- 不引入 `node_modules`

如果你习惯 npm 工作流，也提供了 `package.json` 和 `.husky/` 包装器：

```sh
npm install        # 装 husky
npx husky          # 接管 core.hooksPath
```

`.husky/pre-commit` 等内容只是转发到 `.githooks/`，所以**规则只有一份实现**，
两种安装方式行为完全一致。

## 跳过检查

紧急情况：

```sh
git commit --no-verify
git push --no-verify
```

但 CI 会跑同样的检查，绕过本地钩子过不了 GitHub Actions。

## 发布流程

```sh
# 1. 改 module.prop：version 与 versionCode 同步递增
# 2. 本地验证
./scripts/verify.sh && ./scripts/build.sh
# 3. 提交并打 tag
git commit -am "chore(release): v1.3"
git tag v1.3
git push && git push --tags
```

CI 在 tag 推上去后自动构建并发布 Release。
