# shellcheck disable=SC2034  # 本文件是被 source 的配置，变量在使用方读取
# GMS Slim 开关（改完重启生效，或在 KSU 里点「操作」立即重新施加）
# 安装后真正生效的是 /data/adb/gmscore-slim/config.sh（首次安装生成，升级不覆盖）；
# 本文件只是模板，改它对已安装的系统没有影响。
# 1 = 开启，0 = 关闭。改动逐项记入清单，卸载时可逐项回滚。
# 依附关系：FEATURE_TELEMETRY_ADS 依附 FEATURE_TELEMETRY；
#           FEATURE_PERM_PHONE / FEATURE_PERM_BTCONNECT 依附 FEATURE_PERM_SCAN
# 例外：待机白名单不记清单，每次开机由系统重新施加
#
# 下面几条是本机（Android 17）实测出来的能力边界，模块能用哪些手段全由它决定。
#
# 可用：
#   pm disable <组件>                   压制效果最明显的一环
#   pm revoke <非 SYSTEM_FIXED 权限>    对应的 appop 会级联成 Uid mode ignore
#   cmd device_config override          能长期保持，优先级高于 put，不会被别人的 put 冲掉
#   settings put global                 写后读回一致
#   cmd appops set <非运行时 op>        可用（RUN_ANY_IN_BACKGROUND / WAKE_LOCK / START_FOREGROUND）
#
# 不可用：
#   cmd appops set <运行时 op>          平台拒绝：这类 op 由权限派生，不允许直接设置
#   pm revoke <SYSTEM_FIXED 权限>       返回 0 但仍 granted。GMS 上只有 4 个：三个定位权限和 ACTIVITY_RECOGNITION
#   deviceidle whitelist -system        没这个语法，只认 +/-/= 开头的包名
#
# 以上只在 Android 17 上验证过。换别的系统版本结论可能不同，以日志里的 OK / FAIL / VERIFY 为准。

# 遥测 / 统计组件：MeasurementBroker、ClearcutDebug
#   本机确认存在，可以禁；风险低
FEATURE_TELEMETRY=1

# 广告组件：包名里带 .ads. 的，本机大约 8 个
#   依附于 FEATURE_TELEMETRY：那个关掉时本项不生效
FEATURE_TELEMETRY_ADS=0

# 常驻服务压制：IntegrityApiPersistent、LocationPersistent、magictether 等
#   本机收益最大的一项。这些服务一直处于 startRequested，GMS 因此进不了 cached 状态
#   （禁掉 IntegrityApiPersistent、LocationPersistentService 和 magictether 的两个服务
#     之后，startRequested 从 52 降到 21）
#   风险中。本项没有分项开关，开了就是整套一起处理，包括 IntegrityApiPersistent。
#   它牵扯 Play Integrity，想避开就只能先不开本项
FEATURE_PERSISTENT=0

# DroidGuard（gms.unstable）
#   本机匹配到 3 个 DroidGuard 组件，其中 2 个此前已处于禁用状态
#   风险高：影响 Play Integrity，银行和游戏可能不认这台设备
FEATURE_DROIDGUARD=0

# 扫描类权限收紧：用 pm revoke 代替被拒的 appops 运行时 op
#   目标：BLUETOOTH_SCAN、BLUETOOTH_ADVERTISE、UWB_RANGING、RANGING、ACCESS_LOCAL_NETWORK
#   定位与活动识别权限属 SYSTEM_FIXED，revoke 不掉，所以不在目标里
#   代价：Nearby Share（附近分享）、Fast Pair（蓝牙耳机快速配对）、投屏发现可能受影响
FEATURE_PERM_SCAN=0

# 追加 READ_PHONE_STATE（读 IMEI、网络状态、通话状态）
#   代价：可能影响通话相关功能，以及依赖设备标识的检测，谨慎开
FEATURE_PERM_PHONE=0

# 追加 BLUETOOTH_CONNECT，不建议开
#   会破坏蓝牙连接本身（耳机、车机），默认关闭
FEATURE_PERM_BTCONNECT=0

# 熄屏后延迟非唤醒闹钟（device_config override）
#   注意：部分内核调优模块（如 hanamaki_kernel）会把同一个键写成 false，
#   两边方向相反，会互相覆盖。确认没有别的模块还在写这个键之后再开
FEATURE_ALARM_DELAY=0

# Doze 常量（settings put global device_idle_constants）
#   缩短深睡后的维护窗，减少 GMS 在 Doze 期间的活动机会
#   代价：深睡时推送可能延迟
FEATURE_DOZE_CONSTANTS=0

# 待机白名单
#   实际只能删掉 user 那一条。system 和 system-excidle 来自
#   /product/etc/sysconfig/google.xml 的 allow-in-power-save，命令行改不掉
#   单开这项收益很小，默认关。要让 system 条目失效，走下面的 sysconfig overlay，
#   把 allow-in-power-save 删掉（对应 FEATURE_SC_POWERSAVE）
FEATURE_WHITELIST=0

# 可写的非运行时 appop：RUN_ANY_IN_BACKGROUND、WAKE_LOCK、START_FOREGROUND
#   本机实测 GMS 的 wakelock 总量只有 11.7s，收益有限，默认关
FEATURE_APPOPS=0

# 安全闸：设成 1 只打印将要做什么，不改任何系统设置（仍会刷新 /data/adb 下的快照）
DRY=0

# ================= sysconfig overlay（改系统分区读到什么）=================
# 原理：用 magic mount 覆盖 /product/etc/sysconfig/google.xml，卸载模块自动恢复。
# 只动下面列的几行，其余原样保留。生成后会做完整性自检，不过就放弃覆盖。
# 注意：overlay 在安装时生成，重启后生效。改完开关点一次 KSU 里的「操作」
# 就会按新开关重新生成，再重启即可，不用重装。

# 总开关
FEATURE_SYSCONFIG=1

# 删 allow-ignore-location-settings：GMS 的 thunderbird 组件会无视系统定位总开关（location_mode=0 时仍在定位）
#   本机证据：location_mode=0 的情况下，GMS 仍累计定位 1d2h53m、2848 次
#   风险低到中。影响 Google 位置记录、天气卡片；不影响推送、登录、商店
FEATURE_SC_LOCATION=1

# 删 allow-in-power-save：这是 GMS 在 Doze 期间的保活豁免，删掉后它也会被正常冻结
#   风险中。深睡时 FCM 可能延迟 2-3 分钟，要盯着推送
FEATURE_SC_POWERSAVE=0

# 删 allow-in-data-usage-save：省流模式下的网络豁免
FEATURE_SC_DATAUSAGE=0

# 删 allow-unthrottled-location：定位不限流
FEATURE_SC_UNTHROTTLE=0
