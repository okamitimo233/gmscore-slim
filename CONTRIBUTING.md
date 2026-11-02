# 贡献与开发规范

本项目是 KernelSU 模块，全部逻辑用 POSIX shell 实现。目标是**在 Android 设备上可靠运行**，
因此规范的重点是防止那些在桌面看不出来、到手机上才炸的问题。

## 快速开始

```sh
git clone git@github.com:okamitimo233/gmscore-slim.git
cd gmscore-slim
./scripts/setup.sh        # 安装依赖（husky 钩子随 npm install 自动装好）
```

## 工具链

提交约束由成熟工具组成，不自造轮子：

| 工具 | 作用 |
|---|---|
| [husky](https://typicode.github.io/husky/) | 管理 git hooks |
| [lint-staged](https://github.com/lint-staged/lint-staged) | 只检查暂存的文件，快 |
| [shellcheck](https://www.shellcheck.net/) | shell 静态分析（本项目最重要的检查） |
| [commitlint](https://commitlint.js.org/) | 提交信息规范 |

钩子：

- **pre-commit** → `npx lint-staged` → 对暂存的 `.sh` 跑 shellcheck
- **commit-msg** → `npx commitlint --edit` → 校验 Conventional Commits

## 常用命令

```sh
npm run lint      # 手动跑 shellcheck（全部 .sh）
npm run build     # 打包可刷入的 zip
npx lint-staged   # 手动对暂存文件跑检查
```

## 为什么重点是 shellcheck

模块脚本跑在 Android 的 busybox ash / toybox 上，语法错误 = 模块开机直接失效，
而且这类错误在桌面很难靠肉眼发现。shellcheck 能提前抓出：

- 引号缺失导致的 glibc 分词问题
- 不可移植的 bash 语法
- 未使用变量、未定义变量
- `[` 与 `[[` 的误用

**提交前务必让 shellcheck 零告警。** 确属误报时用精准的
`# shellcheck disable=SCxxxx`（附原因），不要用全局 `-e`。

## 代码约定

- **POSIX sh**，不用 bash 扩展（目标环境是 busybox ash / toybox）
- 缩进 2 空格，LF 换行（`.gitattributes` 强制）
- 变量一律加引号；但调用 `cmd`/`pm`/`dumpsys` 时**必须显式 `</dev/null`**，原因见 [DEVNOTES](DEVNOTES.md)
- 新增功能要有对应开关，默认关闭高风险项
- 涉及系统改动的，必须能在 `uninstall.sh` 里回滚

## 提交信息

遵循 [Conventional Commits](https://www.conventionalcommits.org/)：

```
<type>(<scope>): <subject>
```

- **type**：`feat` `fix` `docs` `style` `refactor` `perf` `test` `build` `ci` `chore` `revert`
- **scope**：可选，如 `sysconfig`、`perms`、`core`
- **subject**：不超过 72 字符

```
feat(sysconfig): 支持只删单行豁免
fix(core): 回滚时清除 device_config override 残留
docs: 补充 overlay 挂载验证步骤
```

规则在 `commitlint.config.mjs` 里，基于 `@commitlint/config-conventional`。

## 分支与版本

- `main` 保持可发布
- 功能分支：`feat/xxx`、`fix/xxx`
- 改 `module.prop` 的 `version` 时，`versionCode` 必须同时 +1
  （模块管理器靠 `versionCode` 判断更新）
- 发布：打 tag `v<version>`，CI 自动构建 zip 并创建 Release

## 发布流程

```sh
# 1. 改 module.prop：version 与 versionCode 同步递增
# 2. 本地验证
npm run lint && npm run build
# 3. 提交并打 tag
git commit -am "chore(release): v1.3"
git tag v1.3
git push && git push --tags
```

## 跳过检查

```sh
git commit --no-verify
```

但 CI 会跑同样的检查，绕过本地钩子过不了 GitHub Actions。
