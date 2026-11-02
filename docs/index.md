# GMS Slim 文档

GMS Slim 是一个 KernelSU 模块，用来压制 Google Play services（下称 GMS）的后台唤醒、遥测与常驻服务。
它做两件事：用 `pm`、`appops`、`settings`、`device_config` 这些运行时接口改状态；用 systemless overlay 换掉系统读到的 `google.xml`。
两件事都不写系统分区，卸载模块即可复原。

## 阅读路径

| 你想 | 读这篇 | 大约需要 |
|---|---|---|
| 装上、看一眼有没有效果 | [user-guide.md](user-guide.md) | 10 分钟 |
| 查某个开关到底是什么、值不值得开 | [reference.md](reference.md) | 按需查表 |
| 改代码前搞懂它为什么这样写 | [design.md](design.md) | 20 分钟 |
| 遇到「改了没反应」「组件自己回来了」 | [troubleshooting.md](troubleshooting.md) | 按症状查 |
| 想弄清 Android 16/17 到底允许什么 | [platform-notes.md](platform-notes.md) | 20 分钟 |
| 提交代码、发版本 | [contributing.md](contributing.md) | 10 分钟 |

## 一页速览

- **适配**：Android 12 及以上（`androidMinApi: 31`）、arm64-v8a、KernelSU 或 Magisk，并且需要 magic mount 支持 overlay。
- **实测环境**：Android 17 / SDK 37、HyperOS V816、KernelSU 3.3.1 + magic_mount_rs、GMS 26.43.30。其他版本未必一致。
- **默认只开两项**：禁遥测组件、删 GMS 的定位豁免行。overlay 总开关默认为 1，其余 14 个开关为 0。
- **状态外置**：所有改动记在 `/data/adb/gmscore-slim/state/manifest.tsv`，不在模块目录。
- **失败不静默**：日志里 `OK` 表示系统回读一致；`FAIL`、`VERIFY-FAIL` 表示那一项没生效。
- **回滚只碰自己**：卸载时只还原「现值仍等于本模块写入值」的项，被别人改过的一律保留。

## 装完先跑这三条

```sh
tail -n 40 /data/adb/gmscore-slim/log/last.log        # 本轮做了什么，结尾是 VERIFY
grep -c 'VERIFY-FAIL' /data/adb/gmscore-slim/log/last.log   # 期望 0
wc -l /product/etc/sysconfig/google.xml               # 挂上后是 106（原版 107）
```

逐条对：

- [ ] 日志结尾出现 `VERIFY` 行，而不是停在最后一条 `SET`
- [ ] `VERIFY-FAIL` 计数为 0
- [ ] `google.xml` 是 106 行

三条都勾上，说明模块已经在工作。任何一条勾不上，去 [troubleshooting.md](troubleshooting.md) 按症状查。

## 文档清单

根目录的 [`README.md`](../README.md) 是仓库首页，同时是模块详情页的展示内容。它只保留安装、默认行为、验证三条命令和一张索引表，细节都在 `docs/`。

| 文件 | 内容 | 主要读者 |
|---|---|---|
| [user-guide.md](user-guide.md) | 安装、默认配置、怎么开开关、验证、卸载 | 使用者 |
| [reference.md](reference.md) | 17 个开关全表、日志标记字典、状态文件布局 | 使用者 / 维护者 |
| [design.md](design.md) | 分层架构、执行时序、清单与回滚、真实复核、overlay 判据 | 维护者 |
| [platform-notes.md](platform-notes.md) | Android 16/17 的能力边界、AOSP 依据、实战坑与解析陷阱 | 维护者 |
| [troubleshooting.md](troubleshooting.md) | 症状 → 诊断命令 → 处置 | 使用者 |
| [contributing.md](contributing.md) | 工具链、代码约定、提交规范、发布流程 | 贡献者 |

## 版本与授权

当前模块版本见 `module/module.prop` 的 `version` / `versionCode`，作者与许可证见同目录的 `module.yaml` 与 `LICENSE`。发布资源名由工具按 `{id}-{versionCode}-{version}.zip` 生成。
