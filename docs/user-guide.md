# 使用指南

装好并重启后，模块只改两处：禁掉 GMS 的遥测组件，删掉 GMS 的定位豁免行。
其余能力都做成了开关，默认关闭，等你确认代价再开。

本篇讲怎么装、怎么开开关、怎么看结果。每个开关的细节在 [reference.md](reference.md)。

## 一、安装前确认

| 项 | 要求 | 怎么查 |
|---|---|---|
| Root 方案 | KernelSU（推荐）或 Magisk | 管理器能看到模块页 |
| overlay 能力 | 有 magic mount 或同类实现 | 管理器里有 magic_mount_rs 之类的模块 |
| 系统版本 | Android 12+ | 设置 → 关于手机 |
| 架构 | arm64-v8a | `getprop ro.product.cpu.abi` |
| GMS 版本 | 26.x 实测可用；版本差异只影响能匹配到哪些组件 | 设置 → 应用 → Google Play 服务 |

模块不改系统分区，但会调 `pm`、`appops`、`settings`、`device_config`。这些接口需要 Root 身份在开机后调用，模块通过 `service.sh` 自动完成。

## 二、安装

从 Releases 下载模块包，在 KernelSU 管理器的「模块」页刷入，重启。

包名规则是 `{id}-{versionCode}-{version}.zip`，例如 `gmscore-slim-3-v1.2.zip`。`version` 里的非 `A-Za-z0-9._-` 字符会被替换成 `_`，所以带括号或空格的版本号也能正常下载。

安装阶段只做三件事，都很快：

1. 修正脚本权限；
2. 首次安装时把开关模板复制成 `/data/adb/gmscore-slim/config.sh`；
3. 生成 overlay 文件到模块目录。此时 `/product` 还是原版，正好取基准。

安装阶段**不碰** `pm` / `cmd`，因为 system_server 可能尚未就绪。

## 三、重启后发生什么

```
开机
 └─ service.sh          等 sys.boot_completed（≤5 分钟）
                        等 /data 解密完成（≤2 分钟）
                        再等 15 秒让 PackageManager 就绪
                        取锁 → 施加全部已开启项 → 真实复核 → 放锁
 └─ boot-completed.sh   再等 30 秒
                        记录 overlay 挂载状态
                        取锁 → 同一套施加逻辑再跑一遍
```

跑两遍不是冗余。GMS 会自己把被 bind 的活跃服务重新启用，见 [platform-notes.md](platform-notes.md)。

## 四、默认配置的效果

默认 `FEATURE_TELEMETRY=1`、`FEATURE_SC_LOCATION=1`，overlay 总开关 `FEATURE_SYSCONFIG=1`，其余为 0。

| 改动 | 生效方式 | 你能看到什么 |
|---|---|---|
| 禁 `MeasurementBroker*`、`ClearcutDebug*` | `pm disable` | 日志里若干条 `SET comp ... disabled` |
| 删 `<allow-ignore-location-settings package="com.google.android.gms">` | overlay 换掉 `google.xml` | 该文件从 107 行变 106 行 |

第二项解决的是这个现象：系统定位总开关关着（`location_mode=0`），GMS 仍在定位。本机实测累计 `locations = 2848, duration = +1d2h53m`。
删掉豁免行后，GMS 在定位上受总开关约束。

**默认两项不碰** Play Integrity 依赖的组件，也不动账号、商店、备份的骨架。推送仍走 `GcmService`，`guard_core` 会拦住任何对它的操作。

## 五、按需开开关

开关文件是 `/data/adb/gmscore-slim/config.sh`（不是模块目录里那份模板，改模板对已装系统无效）。
改完两个动作，顺序不限：

```sh
# 1. 编辑
vi /data/adb/gmscore-slim/config.sh

# 2. KSU 模块页点「操作」→ 立即按新开关重新施加并重新生成 overlay
#    然后重启，让 overlay 生效
```

「操作」按钮等价于执行 `action.sh`：打印现状、重新生成 overlay、跑一遍施加流程。

### 三档推荐配置

| 档位 | 打开 | 收益 | 代价 |
|---|---|---|---|
| 保守（默认） | `TELEMETRY`、`SC_LOCATION` | 遥测被禁、定位受总开关约束 | 几乎无感 |
| 均衡 | 加 `PERSISTENT`、`SC_POWERSAVE` | 常驻服务被禁后 `startRequested` 从 52 降到 21；深睡更冷 | Play Integrity 可能受影响；深睡 FCM 延迟 2–3 分钟 |
| 激进 | 再加 `PERM_SCAN`、`ALARM_DELAY`、`DOZE_CONSTANTS` | 扫描类权限失效，闹钟与 Doze 窗口收紧 | 附近分享、快速配对、投屏发现可能失灵；闹钟与推送更迟 |

**不建议开**：`FEATURE_DROIDGUARD`（银行与游戏可能不认设备）、`FEATURE_PERM_BTCONNECT`（会破坏蓝牙连接本身）。

想先看会做什么、不落地，就把 `DRY=1`，点「操作」看日志里的 `DRY` 行。

## 六、验证装了有没有用

### 模块自己的账

```sh
cat /data/adb/gmscore-slim/log/last.log        # 完整一轮日志
tail -n 1 /data/adb/gmscore-slim/log/last.log  # 结尾的 VERIFY 结论
cat /data/adb/gmscore-slim/state/manifest.tsv  # 每项改动：类型 键 原值 写入值
```

日志结尾出现 `VERIFY 全部一致` 或 `VERIFY 有 N 项与系统实际状态不一致`，这是唯一可信的结论来源。

### 系统的账

| 指标 | 命令 | 本机基线 |
|---|---|---|
| GMS PSS | `dumpsys meminfo com.google.android.gms` | 95–186 MB，波动大 |
| oom_score_adj | `cat /proc/$(pidof com.google.android.gms)/oom_score_adj` | 100 |
| 起着的服务数 | `dumpsys activity services com.google.android.gms \| grep -c startRequested=true` | 未压制 52，压制后 21 |
| 告警唤醒 | `dumpsys alarm` | 166 次 / 5.5 秒 CPU |
| GMS 被杀次数 | `dumpsys activity exit-info` | 早先 4 天 8 次 |

基线是这台机器上的读数，不是承诺值。比较时用同一台机、同一套命令、开机后同样时长。

## 七、卸载与恢复

在管理器里卸载模块，重启。

- **overlay 部分**：magic mount 不再挂载，`/product/etc/sysconfig/google.xml` 自动回到原版，不需要脚本。
- **运行时部分**：`uninstall.sh` 逐条读清单回滚。组件重新 `pm enable`，权限重新 `pm grant`，`device_config` 先清 override 再写回原值，`settings` 写回原值。
- **被别人改过的项**：日志里是 `KEEP`，不动。

白名单（Doze）条目不需要回滚，每次开机会由系统重建。

## 八、升级

直接覆盖刷入新模块包，重启。

`customize.sh` 只在**首次**安装时生成 `config.sh`，升级会保留你改过的开关。overlay 会在安装期按当前开关重新生成。

## 九、什么情况下不要装或不要开

- 设备上跑着 Play Integrity 强校验的银行、支付、游戏：先只留默认两项，再逐个试。
- 你依赖深睡推送（手表、消息提醒）：不要同时开 `SC_POWERSAVE` 和 `DOZE_CONSTANTS`。
- 装了内核调优模块（如 hanamaki_kernel）：`FEATURE_ALARM_DELAY` 与它方向相反，二选一。
- 需要 Nearby Share、Fast Pair、无线投屏稳定：不要开 `PERM_SCAN`。
