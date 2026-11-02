# GMS Slim 开关（改完重启生效）
# 也可改 /data/adb/gmscore-slim/config.sh，优先于本文件生效（升级不丢）
# 1 = 开启，0 = 关闭。每项独立可回滚。
#
# ===== 本机（Android 17）实测的能力边界，决定了模块能用哪些手段 =====
#   ✅ pm disable <组件>              —— 有效，最有力的一环
#   ✅ pm revoke <非SYSTEM_FIXED权限> —— 有效，且会把对应 appop 级联成 Uid mode ignore
#   ✅ cmd device_config override     —— 有效且 sticky（put 会被覆盖，override 不会）
#   ✅ settings put global            —— 有效
#   ✅ cmd appops set <非运行时op>     —— 有效（RUN_ANY_IN_BACKGROUND / WAKE_LOCK / START_FOREGROUND）
#   ❌ cmd appops set <运行时op>       —— 平台拒绝（19+ 由权限派生，不允许直写）
#   ❌ pm revoke <SYSTEM_FIXED权限>    —— 无效（GMS 上仅 4 个：三个定位 + ACTIVITY_RECOGNITION）
#   ❌ deviceidle whitelist -system    —— 无此语法，system 条目只能靠 overlay

# ③ 遥测/统计组件（MeasurementBroker、ClearcutDebug）
#    实测存在且可禁；风险低
FEATURE_TELEMETRY=1

# ③b 广告组件（.ads. 前缀，本机约 8 个）
FEATURE_TELEMETRY_ADS=0

# ⑦ 常驻服务压制（IntegrityApiPersistent / LocationPersistent / magictether 等）
#    实测最有效：这些是 GMS 拿不到 cached 状态的直接原因（实测 startRequested 52->21）
#    风险：中。IntegrityApiPersistent 与 Play Integrity 相关，建议先只开
#    LocationPersistent + magictether，观察 3 天再决定是否动 Integrity
FEATURE_PERSISTENT=0

# ⑧ DroidGuard（gms.unstable）
#    本机 3 个中已有 2 个处于禁用
#    风险高：影响 Play Integrity，银行/游戏可能不认设备
FEATURE_DROIDGUARD=0

# ① 扫描类权限收紧（用 pm revoke，替代被拒的 appops 运行时 op）
#    目标：BLUETOOTH_SCAN、BLUETOOTH_ADVERTISE、UWB_RANGING、RANGING、ACCESS_LOCAL_NETWORK
#    SYSTEM_FIXED 的定位/感知权限会自动跳过（改不了，不白费力气）
#    代价：Nearby Share、Fast Pair、蓝牙耳机快速配对、投屏发现可能受影响
FEATURE_PERM_SCAN=0

# ①b 追加 READ_PHONE_STATE（读 IMEI/网络状态/通话状态）
#    代价：可能影响通话相关功能与部分依赖设备标识的检测，谨慎
FEATURE_PERM_PHONE=0

# ①c 追加 BLUETOOTH_CONNECT —— 不建议开
#    会破坏蓝牙连接本身（连接耳机、车机），默认关闭
FEATURE_PERM_BTCONNECT=0

# ⑤ 熄屏延迟非唤醒闹钟（device_config override，实测 sticky 有效）
#    注意：hanamaki_kernel 当前把它设为 false，本项与之方向相反，两者会互相覆盖
#    建议只在确认 hanamaki 不再是唯一主导者时开
FEATURE_ALARM_DELAY=0

# ⑤b Doze 常量（settings put global device_idle_constants）
#    缩短深睡维护窗、降低 GMS 在 Doze 期间的活跃机会
#    代价：深睡时推送延迟可能增加
FEATURE_DOZE_CONSTANTS=0

# ⑥ 待机白名单
#    实测只能移除 user 那一条，system / system-excidle 来自
#    /product/etc/sysconfig/google.xml（第 8 行 allow-in-power-save），CLI 改不掉
#    因此单独开这项收益很小，本版默认关；要彻底生效需 v2 做 sysconfig overlay
FEATURE_WHITELIST=0

# ①x 可写的非运行时 appop（RUN_ANY_IN_BACKGROUND / WAKE_LOCK / START_FOREGROUND）
#    GMS 实测 wakelock 总量仅 11.7s，收益有限，默认关
FEATURE_APPOPS=0

# 安全闸：1 时只打印将要做什么，绝不写入
DRY=0

# ================= sysconfig overlay（改系统分区可见内容）=================
# 原理：magic mount 覆盖 /product/etc/sysconfig/google.xml，卸载模块自动恢复。
# 只影响指定行，其余内容原样保留；生成后有完整性自检，不通过就不覆盖。
# 注意：这几项在安装时生效，改完开关要点「操作」重新生成并重启。

# 总开关
FEATURE_SYSCONFIG=1

# 删 allow-ignore-location-settings（GMS thunderbird 无视系统定位总开关）
# 本机证据：location_mode=0 时 GMS 仍累计定位 1d2h53m / 2848 次
# 风险：低-中。影响 Google 位置记录、天气卡片；不影响推送/登录/商店
FEATURE_SC_LOCATION=1

# 删 allow-in-power-save（Doze 免死金牌，即 UGD 的做法）
# 风险：中。深睡时 FCM 可能延迟 2-3 分钟，需要观察推送
FEATURE_SC_POWERSAVE=0

# 删 allow-in-data-usage-save（数据省流模式下的网络豁免）
FEATURE_SC_DATAUSAGE=0

# 删 allow-unthrottled-location（定位不限流）
FEATURE_SC_UNTHROTTLE=0
