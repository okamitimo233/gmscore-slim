<p align="center"><img src="assets/icon.png" width="96" alt="icon"></p>

# GMS Slim

压制 Google Play services 后台开销的 KernelSU 模块。

它用两条路径改系统，都不写系统分区，卸载即复原：

| 路径 | 手段 | 改的是什么 |
|---|---|---|
| 运行时 | `pm` / `appops` / `settings` / `device_config` | 系统数据库里的状态 |
| 文件 | systemless overlay 覆盖 `google.xml` | 系统读到的只读配置 |

每项运行时改动都写进外部清单，卸载时逐条回滚；overlay 靠 magic mount 消失即恢复。

## 设计原则

- **不写系统分区**。全部改动走运行时接口或 overlay。
- **状态外置**。清单在 `/data/adb/gmscore-slim/state/manifest.tsv`，不在模块目录——挂载会整块替换模块目录。
- **失败不静默**。日志结尾的 `VERIFY` 行是唯一可信结论；出现 `FAIL` / `VERIFY-FAIL` 就说明那一项没生效。
- **只回滚自己**。卸载时只还原「现值仍等于本模块写入值」的项，被别人改过的一律保留。
- **不盲改**。组件名与权限名先 `pm dump` / `dumpsys package` 取快照，不存在或不可改的记 `ABSENT` / `LOCKED`。

## 适配环境

| 项 | 要求 |
|---|---|
| Android | 12 及以上（`androidMinApi: 31`） |
| 架构 | arm64-v8a |
| Root | KernelSU 或 Magisk，需具备 magic mount（overlay 部分依赖） |

本模块的结论全部来自单机实测：Android 17 / SDK 37、HyperOS V816、KernelSU 3.3.1 + magic_mount_rs、GMS 26.43.30。换系统版本结论可能不同，以本机日志为准。

## 安装

从 [Releases](https://github.com/okamitimo233/gmscore-slim/releases) 下载模块包，在 KernelSU 管理器的模块页刷入，重启。

模块包名由发布工具按 `{id}-{versionCode}-{version}.zip` 生成，`version` 取自 `module.prop` 并清理成文件名安全形式。按现在仓库里的 `module.prop`（`version=v1.2`、`versionCode=3`）会得到 `gmscore-slim-3-v1.2.zip`；发版前改了这两个字段，包名随之变化。

安装阶段只做三件事：修脚本权限、首次生成开关文件、生成 overlay。**不调 `pm` / `cmd`**，因为那时 system_server 可能还没起来。

## 默认只开两项

| 改动 | 手段 | 效果 |
|---|---|---|
| 禁遥测组件 `MeasurementBroker*`、`ClearcutDebug*` | `pm disable` | 遥测链路断掉 |
| 删 `allow-ignore-location-settings`（GMS 那行） | overlay | GMS 重新受系统定位总开关约束 |

第二项针对的现象：系统定位总开关关着（`location_mode=0`），GMS 仍在定位。本机实测累计 `locations = 2848`、`duration = +1d2h53m`。

其余开关默认关闭。要开的话改 `/data/adb/gmscore-slim/config.sh`，点管理器里的「操作」，再重启。完整开关表见 [docs/reference.md](docs/reference.md)。

## 验证

```sh
tail -n 20 /data/adb/gmscore-slim/log/last.log           # 结尾应是 VERIFY
grep -c VERIFY-FAIL /data/adb/gmscore-slim/log/last.log  # 期望 0
wc -l /product/etc/sysconfig/google.xml                  # 挂上后 106（原版 107）
```

三条都对，说明模块在工作。不对就去 [docs/troubleshooting.md](docs/troubleshooting.md) 按症状查。

## 卸载

在管理器里卸载模块，重启。overlay 不再挂载，系统文件自动回原版；运行时改动由 `uninstall.sh` 按清单逐条还原，被别人改过的项保持不动。

## 文档

| 文件 | 内容 |
|---|---|
| [docs/index.md](docs/index.md) | 总索引与一页速览 |
| [docs/user-guide.md](docs/user-guide.md) | 安装、开机时序、三档配置、验证、升级 |
| [docs/reference.md](docs/reference.md) | 开关全表、日志标记字典、文件布局、常用命令 |
| [docs/design.md](docs/design.md) | 分层架构、施加流程、清单回滚、真实复核 |
| [docs/platform-notes.md](docs/platform-notes.md) | Android 16/17 能力边界、AOSP 依据、实战坑 |
| [docs/troubleshooting.md](docs/troubleshooting.md) | 症状到处置的排障表 |
| [docs/contributing.md](docs/contributing.md) | 工具链、代码约定、提交规范、发布流程 |

README 同时是模块详情页的展示文档（`module.yaml` 的 `description` 指向它），细节都在 `docs/`。

## 开发与发布

```sh
git clone git@github.com:okamitimo233/gmscore-slim.git
cd gmscore-slim
npm install     # husky / lint-staged / commitlint 就位
npm run lint    # shellcheck 全量检查
```

发布不需要本地打包脚本：打 `v*` tag 由 `module-release` action 打包 `module/`、跑官方 validator 预检、发布 immutable release。细节见 [docs/contributing.md](docs/contributing.md)。

## 许可

[MIT](LICENSE)
