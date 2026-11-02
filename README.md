# GMS Slim v1.2（方向 B：唤醒与服务压制 + sysconfig overlay）

针对 Google Play services 后台开销的 KernelSU 模块。
**不修改系统分区**，只用 `appops` / `pm` / `deviceidle` / `device_config` / `settings` 运行时接口，每项改动写入外部清单，卸载逐条回滚。

## 一、本机能力矩阵（模块设计的全部依据，均为本机实测）

| 手段 | 结果 | 证据 |
|---|---|---|
| `pm disable <组件>` | ✅ 有效 | 禁 3 个常驻服务后 `startRequested` 52→21，enable 可还原 |
| `pm revoke <非SYSTEM_FIXED权限>` | ✅ 有效 | `BLUETOOTH_SCAN` granted→false，appop 级联成 `Uid mode: ignore` |
| `cmd device_config override` | ✅ 有效且 sticky | 写入后 `list_local_overrides` 有记录；再 `put` 反值，`get` 仍返回 override 值 |
| `settings put global` | ✅ 有效 | `device_idle_constants` 写入后读回一致 |
| `cmd appops set <非运行时op>` | ✅ 有效 | `RUN_ANY_IN_BACKGROUND` / `WAKE_LOCK` / `START_FOREGROUND` |
| `cmd appops set <运行时op>` | ❌ 平台拒绝 | logcat：`appop state for runtime op ... should not be set directly` |
| `pm revoke <SYSTEM_FIXED权限>` | ❌ 无效 | 本机 GMS 仅 4 个：三个定位 + `ACTIVITY_RECOGNITION`，`pm revoke` 返回 0 但仍 granted |
| `cmd deviceidle whitelist -system` | ❌ 无此语法 | 只认 `+`/`-`/`=` 前缀的包名，返回 `Package must be prefixed with +, -, or =` |

> 关键结论：Android 16+ 起 appops 的运行时 op 由权限 flags 派生，不能再直写；**替代路径是改权限本身**（`pm revoke` 会级联 appop）。而 GMS 真正想压的那 4 个定位/感知权限恰好都是 `SYSTEM_FIXED`，改不掉。

## 二、开关（改 `/data/adb/gmscore-slim/config.sh`，重启生效）

| 开关 | 默认 | 内容 | 风险 |
|---|---|---|---|
| `FEATURE_TELEMETRY` | 1 | 禁 `MeasurementBrokerService`、`ClearcutDebugDumpService` | 低 |
| `FEATURE_TELEMETRY_ADS` | 0 | 再禁 `.ads.` 前缀组件（本机约 8 个） | 低 |
| `FEATURE_PERSISTENT` | 0 | 禁 `IntegrityApiPersistent` / `LocationPersistent` / `magictether.*` | 中 |
| `FEATURE_DROIDGUARD` | 0 | 禁剩余 `DroidGuardService` | 高（影响 Play Integrity） |
| `FEATURE_PERM_SCAN` | 0 | `pm revoke` 蓝牙扫描/广播、UWB、RANGING、本地网络 | 中（影响 Nearby/Fast Pair/投屏发现） |
| `FEATURE_PERM_PHONE` | 0 | 追加 `READ_PHONE_STATE` | 中高 |
| `FEATURE_PERM_BTCONNECT` | 0 | 追加 `BLUETOOTH_CONNECT`，会破坏蓝牙连接本身 | 高，不建议 |
| `FEATURE_ALARM_DELAY` | 0 | `device_config override` 熄屏延迟非唤醒闹钟 | 中，与 hanamaki 冲突 |
| `FEATURE_DOZE_CONSTANTS` | 0 | 缩短 `device_idle_constants` 维护窗 | 中，深睡推送延迟 |
| `FEATURE_WHITELIST` | 0 | 移除 GMS 的 user 待机白名单条目（只能删 1/3） | 中 |
| `FEATURE_APPOPS` | 0 | `RUN_ANY_IN_BACKGROUND` / `WAKE_LOCK` / `START_FOREGROUND` 设 ignore | 中 |
| `DRY` | 0 | 设 1 只打印计划，不写入 | — |

**硬性保护**：`GcmService`、`.auth.`、`.common.`、`.chimera.`、`.droidguard.` 在组件类操作中一律被 `guard_core` 拦下。权限类操作会自动跳过 `SYSTEM_FIXED`（本机 4 个）与未声明的权限。

## 三、执行时机

| 脚本 | 作用 |
|---|---|
| `customize.sh` | 安装期只设权限，**不碰 pm/cmd**（system_server 可能未起） |
| `service.sh` | 等 `sys.boot_completed=1` → 等 `/data/data/android`（解密完成）→ sleep 15 → 施加 |
| `boot-completed.sh` | 开机完成后再复核（GMS 会自我恢复组件/权限，重复是有意的） |
| `action.sh` | KSU 点「操作」：现状面板 + 候选清单 + 立即幂等复核 |
| `uninstall.sh` | 逐条回滚 |

## 四、安全设计

1. **状态外置**：清单在 `/data/adb/gmscore-slim/state/manifest.tsv`，不在模块目录（magic mount 会整块替换）。
2. **先读后写再校验**：每项记录原值 → 写 → 回读，失败记 `FAIL` 不静默。
3. **只回滚自己的改动**：现值已被别人改过的项跳过并保留。
4. **回滚不留痕迹**：`device_config` 施加用 `override`（sticky），回滚走 `clear_override` + `put`，验证过 override 条目数回到 0，不会钉住键位妨碍其他模块。
5. **不盲改**：组件名与权限名先从 `pm dump` / `dumpsys package` 生成快照，不存在或不可改的记 `ABSENT` / `LOCKED`。
6. **不做的事**：不 `pm disable-user`/`suspend` GMS 本体，不杀进程，不改 `backup_transport`/`credential_service`。

> 要改这个模块的代码，先读 [`DEVNOTES.md`](DEVNOTES.md)：那里记了必须以特定写法规避的平台坑，不知道会踩。

## 五、验证

```
cat /data/adb/gmscore-slim/log/last.log        # 本模块做了什么
cat /data/adb/gmscore-slim/state/manifest.tsv  # 每项改动：类型 键 原值 现值
```

基线（改动前先记一次，改后用同样命令对比）：

| 指标 | 命令 | 基线 |
|---|---|---|
| GMS PSS | `dumpsys meminfo com.google.android.gms` | 95–186 MB（波动大，重启后 10 分钟内会明显下降） |
| oom_score_adj | `cat /proc/$(pidof com.google.android.gms)/oom_score_adj` | 100 |
| startRequested 数 | `dumpsys activity services com.google.android.gms \| grep -c startRequested=true` | 52 |
| 告警唤醒 | `dumpsys alarm` | 166 wakeups / 5.5 s CPU |
| gms.unstable 被杀 | `dumpsys activity exit-info` | 4 天 8 次 |

## 六、已知限制

- **定位/感知类权限改不掉**：`ACCESS_FINE_LOCATION`、`ACCESS_COARSE_LOCATION`、`ACCESS_BACKGROUND_LOCATION`、`ACTIVITY_RECOGNITION` 都是 `SYSTEM_FIXED`，`pm revoke` 与 `pm set-permission-flags` 都无解（CLI 的 flag 白名单里没有 `SYSTEM_FIXED`）。**这不是 overlay 能解决的**——权限状态在 `/data/misc_de/0/apexdata/com.android.permission/access.abx`（二进制），不在只读系统分区。但下面第七节有等效出路。
- **和 `hanamaki_kernel` 的关系**：它已把 `activity_manager` 改成"不许回收/不许冻结"，并把 `alarm_manager.delay_nonwakeup_alarms_while_screen_off` 设为 `false`。本模块不碰 `activity_manager`；`FEATURE_ALARM_DELAY` 与之方向相反，默认关闭。
- **HyperOS 可能另有一层**：`com.miui.powerkeeper` 的云端 `doze_whitelist_apps` 有覆盖用户白名单的迹象（社区报告，未在本机验证）。若发现白名单"删了又回来"，先怀疑这一层。

## 七、sysconfig overlay

这是绕开 `SYSTEM_FIXED` 的等效路子：不改权限，改**让 GMS 无视定位总开关的那个豁免**。

### 为什么有效

`/product/etc/sysconfig/google.xml` 第 11 行：

```xml
<allow-ignore-location-settings package="com.google.android.gms" attributionTag="...thunderbird" />
```

本机实测：`location_mode=0`、`is-location-enabled=false`（定位全局关闭），
但 `dumpsys location` 里 GMS 仍注册为客户端并持续定位：

```
com.google.android.gms[.thunderbird]
fused_location_provider:   locations = 2848, duration = +1d2h53m
network_location_provider: locations = 2848, duration = +1d2h40m
```

删掉这行，GMS 就失去"无视总开关"的特权。

### 实现与安全

- 模块内放 `system/product/etc/sysconfig/google.xml`，由 magic mount 覆盖；**卸载模块自动恢复**，无需回滚脚本。
- 以 `/product` 原文件为基底，`sed` 按**内容**删行（不用行号，避免版本差异）。
- 原文件备份在 `/data/adb/gmscore-slim/backup/google.xml.orig`，重复生成不累积删除（实测连续 3 次恒为 106 行）。
- 生成后强制自检：`update-ownership`、`backup-transport-whitelisted-service`、`<config>` 必须存在，`dialer` 那行不能被误删；任一不满足则**放弃覆盖**，宁可无效果也不弄坏系统。

### 开关

| 开关 | 默认 | 删除的行 | 风险 |
|---|---|---|---|
| `FEATURE_SC_LOCATION` | 1 | `allow-ignore-location-settings`（GMS 无视定位开关） | 低-中 |
| `FEATURE_SC_POWERSAVE` | 0 | `allow-in-power-save`（Doze 免死金牌，UGD 的做法） | 中：深睡 FCM 延迟 |
| `FEATURE_SC_DATAUSAGE` | 0 | `allow-in-data-usage-save` | 中 |
| `FEATURE_SC_UNTHROTTLE` | 0 | `allow-unthrottled-location` | 低 |

**绝不能删**：`update-ownership ... installer="com.android.vending"`（删了 Play 商店无法升级 GMS）、
`backup-transport-whitelisted-service`（备份/换机迁移）、`app-data-isolation-whitelisted-app`、`<app-link>`。

改开关后点 KSU 里的「操作」会按新开关重新生成，重启生效。

### 验证

```sh
# 1. 挂载是否生效（模块每次开机会自己判断并写进日志）
grep -c 'allow-ignore-location-settings package="com.google.android.gms"' \
  /product/etc/sysconfig/google.xml      # 期望 0

# 2. 看 GMS 是否还在定位
dumpsys location | grep -A2 thunderbird
```

`boot-completed.sh` 每次开机会在日志记一行 `sysconfig: MOUNTED / NOT-MOUNTED / UNKNOWN`。
