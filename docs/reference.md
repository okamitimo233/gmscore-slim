# 参考手册

查表用。开关全表、日志标记含义、状态文件布局、常用命令。

## 一、开关全表

开关文件：`/data/adb/gmscore-slim/config.sh`。`1` 开启，`0` 关闭。
改动后点 KSU 模块页的「操作」立即生效，重启后 overlay 生效。

### 1.1 sysconfig overlay 组

操作对象是 `/product/etc/sysconfig/google.xml`。原版 107 行，默认删 1 行后为 106 行。

| 开关 | 默认 | 删除的行 | 代价 |
|---|---|---|---|
| `FEATURE_SYSCONFIG` | 1 | 总开关。关掉后不再生成或更新 | 已生成的旧文件仍会被挂载，需卸载或删模块内产物 |
| `FEATURE_SC_LOCATION` | 1 | `allow-ignore-location-settings`（GMS 那行，第 11 行） | 位置记录、天气卡片；不影响推送、登录、商店 |
| `FEATURE_SC_POWERSAVE` | 0 | `allow-in-power-save`（第 8 行） | 中。深睡 FCM 延迟 2–3 分钟 |
| `FEATURE_SC_DATAUSAGE` | 0 | `allow-in-data-usage-save`（第 9 行） | 中。省流模式下不再有网络豁免 |
| `FEATURE_SC_UNTHROTTLE` | 0 | `allow-unthrottled-location`（第 10 行） | 低。定位受系统限流 |

### 1.2 运行时组

操作对象是系统数据库，每项改动都记进清单，可逐项回滚。

| 开关 | 默认 | 动作 | 风险 | 回滚 |
|---|---|---|---|---|
| `FEATURE_TELEMETRY` | 1 | `pm disable` 匹配 `MeasurementBroker`、`ClearcutDebug` 的组件 | 低 | `pm enable` |
| `FEATURE_TELEMETRY_ADS` | 0 | 追加包名含 `.ads.` 的组件（本机约 8 个） | 低 | 同上 |
| `FEATURE_PERSISTENT` | 0 | 禁 `IntegrityApiPersistent`、`LocationPersistentService`、`ClearcutDebug`、`magictether` 两个服务 | 中。牵扯 Play Integrity | 同上 |
| `FEATURE_DROIDGUARD` | 0 | 禁所有匹配 `DroidGuard` 的组件（本机 3 个，2 个原本已禁） | 高。银行、游戏可能不认设备 | 同上 |
| `FEATURE_PERM_SCAN` | 0 | `pm revoke` 5 个权限：`BLUETOOTH_SCAN`、`BLUETOOTH_ADVERTISE`、`UWB_RANGING`、`RANGING`、`ACCESS_LOCAL_NETWORK` | 中。附近分享、快速配对、投屏发现可能失灵 | `pm grant` |
| `FEATURE_PERM_PHONE` | 0 | `FEATURE_PERM_SCAN` 打开时追加 `READ_PHONE_STATE` | 中高。通话相关功能与设备标识检测 | 同上 |
| `FEATURE_PERM_BTCONNECT` | 0 | `FEATURE_PERM_SCAN` 打开时追加 `BLUETOOTH_CONNECT` | 高。破坏蓝牙连接本身 | 同上 |
| `FEATURE_ALARM_DELAY` | 0 | `device_config override alarm_manager/delay_nonwakeup_alarms_while_screen_off=true` | 中。与内核调优模块方向相反 | `clear_override` + `put` 回原值 |
| `FEATURE_DOZE_CONSTANTS` | 0 | `settings put global device_idle_constants` 为 `idle_to=1800000,light_idle_to=1800000,max_idle_to=21600000,min_time_to_alarm=600000` | 中。深睡推送延迟 | `settings put` 回原值，原本为空则 `delete` |
| `FEATURE_WHITELIST` | 0 | 删除 GMS 的 user 白名单条目（`cmd deviceidle whitelist -`） | 中。只能删 1 条，收益小 | 不需回滚，系统每次开机重建 |
| `FEATURE_APPOPS` | 0 | `RUN_ANY_IN_BACKGROUND`、`WAKE_LOCK`、`START_FOREGROUND` 设为 `ignore` | 中。本机 wakelock 总量仅 11.7 秒，收益有限 | `cmd appops reset` |

### 1.3 安全闸

| 开关 | 默认 | 行为 |
|---|---|---|
| `DRY` | 0 | 设为 1 时只打印 `DRY` 行，不写任何系统设置。仍会刷新 `/data/adb` 下的快照 |

### 1.4 依附关系

| 开关 | 依附于 | 说明 |
|---|---|---|
| `FEATURE_TELEMETRY_ADS` | `FEATURE_TELEMETRY` | 遥测总开关关闭时，本项不执行 |
| `FEATURE_PERM_PHONE` | `FEATURE_PERM_SCAN` | 同上，不执行 |
| `FEATURE_PERM_BTCONNECT` | `FEATURE_PERM_SCAN` | 同上，不执行 |

## 二、日志标记字典

日志：`/data/adb/gmscore-slim/log/last.log`，超过 256 KiB 轮转为 `prev.log`。

| 标记 | 含义 | 可信度 |
|---|---|---|
| `OK` | 写后回读**系统**等于期望值（appops / device_config / settings） | 真实结论 |
| `SET` | 命令已下达（组件、权限）。回读的是本地快照，不能证明系统接受 | 只是交代 |
| `VERIFY-OK` | 整轮结束时重新抓系统状态，与清单期望一致 | 真实结论 |
| `VERIFY-FAIL` | 同上，但系统实际值与期望不符，该项没生效 | 真实结论，需处理 |
| `FAIL` | 写后回读不等于期望值（appops / device_config / settings） | 平台拒绝或语法错 |
| `SKIP` | 现值已是目标值，或 GMS 已不在白名单 | 无动作 |
| `ABSENT` | 本机没有这个组件，或没声明这个权限 | 正常，跳过 |
| `LOCKED` | 该权限是 `SYSTEM_FIXED`，平台不允许改 | 无解，跳过 |
| `GUARD` | 命中核心保护名单，主动跳过 | 设计如此 |
| `DRY` | 沙盘模式，只打印计划 | 未落地 |
| `WARN` | 前置数据缺失，例如快照失败、`pm` 未就绪 | 相关类别的改动被跳过 |
| `NOTE` | 补充说明，例如白名单剩余条目的来源 | 信息 |
| `RESTORE` | 卸载回滚：已还原原值 | 成功 |
| `KEEP` | 卸载回滚：现值已非本模块所设，跳过 | 保留他人改动 |
| `SC-OK` | overlay 已生成，附行数变化 | 生成成功 |
| `SC-FAIL` | overlay 未通过自检，已放弃覆盖 | 不生成，系统不受影响 |
| `SC-REMOVED` | 本次删掉了哪几类行 | 信息 |
| `MOUNTED` | 系统读到的正是模块版本 | overlay 生效 |
| `NOT-MOUNTED` | 系统读到的仍是原版 | overlay 未生效 |
| `UNKNOWN` | 系统内容与模块版、原版都不同 | 可能被别的模块覆盖 |

## 三、文件布局

### 3.1 仓库

| 路径 | 用途 |
|---|---|
| `module/` | 模块本体，其内容就是 zip 的根 |
| `module/module.prop` | `id`、`version`、`versionCode`，版本号的唯一来源 |
| `module/lib/core.sh` | 通用层：日志、快照、各手段的读写原语、清单、回滚、真实复核 |
| `module/lib/apply.sh` | 策略层：目标清单与施加流程 |
| `module/lib/sysconfig.sh` | overlay 层：生成、自检、挂载判据 |
| `module/lib/config.sh` | 开关模板。首次安装复制到状态目录，之后改模板无效 |
| `module/customize.sh` | 安装期：权限、开关文件、生成 overlay |
| `module/service.sh` | 主施加时机（开机后） |
| `module/boot-completed.sh` | 开机完成后第二遍施加 + 记录 overlay 状态 |
| `module/action.sh` | KSU「操作」按钮：现状面板 + 重新生成 + 幂等复核 |
| `module/uninstall.sh` | 逐条回滚 |
| `module.yaml` | KernelSU Modules 展示元数据 |
| `.github/workflows/` | `ci.yml` 预检、`release.yml` 发布 |

`module/system/` 是 overlay 生成物，运行时产出，已被 `.gitignore` 排除。

### 3.2 设备上的状态目录

```
/data/adb/gmscore-slim/
├── config.sh                  # 生效中的开关（首次安装自模板复制）
├── lib/core.sh                # 卸载时的备用副本
├── state/
│   ├── manifest.tsv           # 改动清单，4 列 TAB 分隔
│   ├── available.txt          # 本机 GMS 组件全集
│   ├── disabled.txt           # 组件禁用状态快照
│   ├── perms.txt              # 权限状态快照，name=true/false
│   ├── perms-locked.txt       # SYSTEM_FIXED 权限名单
│   ├── target-telemetry.txt   # 本轮命中的遥测候选
│   ├── target-persistent.txt  # 本轮命中的常驻服务候选
│   ├── target-droidguard.txt  # 本轮命中的 DroidGuard 候选
│   ├── services.dump          # dumpsys activity services 的原始输出
│   ├── services.txt           # 其中解析出的组件名
│   └── .lock/                 # 运行锁，超过 600 秒视为残留并回收
├── backup/google.xml.orig     # 系统原版 google.xml，overlay 的基底
└── log/last.log, prev.log     # 日志
```

`manifest.tsv` 四列含义：

| 列 | 例子 | 含义 |
|---|---|---|
| 类型 | `comp` / `perm` / `appops` / `devconfig` / `settings` | 用哪种手段改的 |
| 键 | `com.google.android.gms/.foo.BarService` | 具体对象；`appops` 与 `devconfig` 用「段名 + 竖线 + 键名」拼接 |
| 原值 | `enabled` / `true` / `default:allow` | 首次施加系统里读到的值 |
| 写入值 | `disabled` / `false` / `ignore` | 本模块写进去的值 |

回滚判据：`现值 == 写入值` 才还原，否则记为 `KEEP`。

## 四、常用命令

```sh
# 立刻按当前开关重新施加（不需要重启）
sh /data/adb/modules/gmscore-slim/action.sh

# 只看本轮结论
tail -n 20 /data/adb/gmscore-slim/log/last.log

# 看挂载状态（每次开机 boot-completed.sh 会记一行）
grep 'sysconfig:' /data/adb/gmscore-slim/log/last.log

# 系统实际读到的 google.xml 行数
wc -l /product/etc/sysconfig/google.xml

# 定位豁免行是否还在（0 表示已删）
grep -c 'allow-ignore-location-settings package="com.google.android.gms"' \
  /product/etc/sysconfig/google.xml

# 看 GMS 是否还在定位
dumpsys location | grep -A2 thunderbird

# 看本模块的待机白名单残留
dumpsys deviceidle whitelist | grep -c com.google.android.gms
```

## 五、环境常量

| 常量 | 值 | 出处 |
|---|---|---|
| `MODID` | `gmscore-slim` | `core.sh` |
| `STATE_DIR` | `/data/adb/gmscore-slim` | `core.sh` |
| `GMS` | `com.google.android.gms` | `core.sh` |
| `SC_SRC` | `/product/etc/sysconfig/google.xml` | `sysconfig.sh` |
| `SC_DST_REL` | `system/product/etc/sysconfig/google.xml` | `sysconfig.sh` |

`STATE_DIR` 固定在 `/data/adb` 下，不能改成模块目录：magic mount 会把模块目录整块替换，写在里面的状态会丢。
