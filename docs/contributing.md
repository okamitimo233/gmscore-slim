# 贡献者指南

模块全部逻辑是 POSIX shell，跑在 Android 的 busybox ash / toybox 上。
这类代码在桌面上看不出问题，到手机上可能整轮失效。规范的重点就在这里。

## 一、准备环境

```sh
git clone git@github.com:okamitimo233/gmscore-slim.git
cd gmscore-slim
npm install     # 装 husky / lint-staged / commitlint，prepare 钩子自动就位
npm run lint    # 对全部 .sh 跑 shellcheck
```

需要 Node 18+、shellcheck。PR 里允许零告警，不允许「先合进去再修」。

| 工具 | 作用 |
|---|---|
| husky | 管理 git hooks |
| lint-staged | 只检查暂存的文件 |
| shellcheck | shell 静态分析，本项目最重要的检查 |
| commitlint | 提交信息规范 |
| KernelSU `module-release` | 打包 `module/`、官方 validator 预检、发布 |

钩子：`pre-commit` 跑 `npx lint-staged`，`commit-msg` 跑 `npx commitlint --edit`。

shellcheck 之所以是本项目最重要的检查：模块脚本跑在 busybox ash 上，一个引号缺失或一处 bash 扩展，在桌面上看不出来，到手机上就是整轮静默失效。它能提前抓出漏引号导致的词分割、不可移植的 bash 语法、未定义变量、`[` 与 `[[` 的误用。

## 二、代码约定

- **POSIX sh**，不用 bash 扩展。目标解释器是 busybox ash / toybox。
- 缩进 2 空格，LF 换行（`.gitattributes` 强制）。
- 变量一律加引号。
- 调 `cmd` / `pm` / `dumpsys` / `am` / `settings` 时**显式 `</dev/null`**。原因见 [platform-notes.md](platform-notes.md#三坑一cmd--pm--dumpsys-的-stdio-fd)。
- 新增功能必须有对应开关，高风险项默认 0。
- 涉及系统改动的，必须能在 `uninstall.sh` 里回滚，并写进 `manifest.tsv`。
- 状态只能写 `/data/adb/gmscore-slim/`，不能写模块目录。
- shellcheck 误报用精准的 `# shellcheck disable=SCxxxx` 并注明原因，不要用全局 `-e`。

## 三、加一个开关的检查清单

以新增 `FEATURE_FOO` 为例，六处都要动，漏一处就是半成品。

| # | 文件 | 改什么 |
|---|---|---|
| 1 | `module/lib/config.sh` | 加开关，写清默认值、代价、依附关系。这份是模板 |
| 2 | `module/lib/apply.sh` | 写 `do_foo()`，目标从快照里匹配，逐个调 `apply_change` / `comp_change` |
| 3 | `module/lib/apply.sh` 的 `run_all` | 加一行 `[ "${FEATURE_FOO:-0}" = "1" ] && do_foo` |
| 4 | `module/action.sh` | 现状面板的「开关」段加一行显示当前值 |
| 5 | `module/uninstall.sh` | 无需改代码，但要确认新项写进了 `manifest.tsv`，否则回滚不到 |
| 6 | `docs/reference.md` | 开关全表加一行：默认值、动作、代价、回滚方式 |

提交前自查三项：

- [ ] `DRY=1` 跑一遍，输出只打印、不写系统
- [ ] 连跑两遍，第二遍全部 `SKIP`
- [ ] 卸载后，系统回到施加前的值

## 四、提交信息

遵循 Conventional Commits：`<type>(<scope>): <subject>`。

- **type**：`feat` `fix` `docs` `style` `refactor` `perf` `test` `build` `ci` `chore` `revert`
- **scope**：可选，如 `sysconfig`、`perms`、`core`
- **subject**：不超过 72 字符

```
feat(sysconfig): 支持只删单行豁免
fix(core): 回滚时清除 device_config override 残留
docs: 补充 overlay 挂载验证步骤
```

规则在 `commitlint.config.mjs`，基于 `@commitlint/config-conventional`。

## 五、分支

- `main` 保持可发布。
- 功能分支 `feat/xxx`，修复分支 `fix/xxx`，文档分支 `docs/xxx`。
- 改 `module/module.prop` 的 `version` 时，`versionCode` 必须同时 +1。KernelSU 只接受更大的 `versionCode`，发布过的值不能复用。

## 六、验证改动

桌面能做的检查：

```sh
npm run lint                                    # shellcheck 全量
node -e 'require("fs").readFileSync("module/module.prop")'  # 顺手确认文件没坏
```

设备上必须做的检查（改动了施加逻辑时）：

```sh
# 1. 沙盘跑一遍
sed -i 's/^DRY=0/DRY=1/' /data/adb/gmscore-slim/config.sh
sh /data/adb/modules/gmscore-slim/action.sh

# 2. 正式跑，看结尾 VERIFY
sed -i 's/^DRY=1/DRY=0/' /data/adb/gmscore-slim/config.sh
sh /data/adb/modules/gmscore-slim/action.sh | tail -n 15

# 3. 再跑一遍，确认幂等（应全部 SKIP）
sh /data/adb/modules/gmscore-slim/action.sh | tail -n 15
```

改 `sysconfig.sh` 还要看行数：原版 107 行，默认删 1 行后应为 106 行，连续生成三次不应递减。

## 七、打包与发布

本地没有打包脚本。`release.yml` 用 KernelSU Modules 官方的 `module-release` action 打包 `module/`、跑官方 validator 预检、发布 immutable release。

发布的资源名由工具按 `{id}-{versionCode}-{version}.zip` 生成，不手工命名：

| 来源 | 取值 |
|---|---|
| `id` | `module.prop` 的 `id` |
| `versionCode` | `module.prop` 的 `versionCode` |
| `version` | `module.prop` 的 `version`，清理成文件名安全形式：`A-Za-z0-9._-` 之外的字符变 `_`，去掉首尾的 `.` `_` `-`，截到 64 字符 |

`module.yaml` 的 `release.assetPattern` 要能匹配它，当前是 `gmscore-slim-*.zip`。改 `id` 的话这个模式也要跟着改。

```sh
# 1. 改 module/module.prop：version 与 versionCode 同步递增
# 2. 本地验证
npm run lint
# 3. 提交并打 tag
git commit -am "chore(release): v1.3"
git tag v1.3
git push && git push --tags
```

`ci.yml` 的 `precheck` 用同一个 action 跑 `dry-run: true`，所以推 PR 就能看到包结构检查结果，不必等发布。

两个 workflow 里的 `module-release` 与 `actions/checkout` 都 pin 到完整 commit SHA。前者带 `contents: write`，不能跟分支走。

## 八、跳过检查

```sh
git commit --no-verify
```

可以绕过本地钩子，但 CI 会跑同样的检查。绕过只在调试时用。

## 九、文档

文档在 `docs/`，按读者分册，见 [index.md](index.md)。改行为时必须同步改：

| 改了什么 | 同步哪篇 |
|---|---|
| 开关的默认值或动作 | `docs/reference.md` 开关全表 |
| 日志标记 | `docs/reference.md` 标记字典 |
| 状态文件、目录布局 | `docs/reference.md` 文件布局 |
| 施加时序、回滚策略 | `docs/design.md` |
| 平台限制的新发现 | `docs/platform-notes.md` |
| 新的失败模式 | `docs/troubleshooting.md` |
| 安装步骤、默认配置、文档索引 | `README.md`（同时是模块详情页）与 `docs/index.md` |

`module.yaml` 的 `description` 指向 `README.md`，所以 README 里不要堆细节，细节放进 `docs/`，README 只保留安装、默认行为、验证三条命令和一张文档索引表。
