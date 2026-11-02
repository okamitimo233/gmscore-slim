# DEVNOTES — 开发笔记（不是使用者文档）

本文件记录**改这个模块时必须知道的平台约束**，以及踩过的坑。
使用者请看 [`README.md`](README.md)。

环境：Android 17 / SDK 37，HyperOS（`ro.build.type=user`），KernelSU + magic_mount_rs，GMS 26.43.30。

---

## Bug 1 — `cmd` / `pm` / `dumpsys` 的 stdout 不能是普通文件

**现象**
```sh
pm dump com.google.android.gms > /data/adb/gmscore-slim/state/gms.dump
# 文件只有 70 字节，内容是：
# cmd: Failure calling service package: Failed transaction (2147483646)
```
无论写 `/data/adb`、`/data/local/tmp` 还是 `/sdcard` 都一样失败；退出码 2。

**根因**
`cmd`/`pm`/`dumpsys` 会把 stdio 的 fd 通过 binder 传给 `system_server`。
当 stdout 是 root 打开在 `/data/adb`（context `adb_data_file`）下的普通文件时，system_server 无法写这个 fd，事务直接失败。

**正确写法**
```sh
pm dump com.google.android.gms </dev/null 2>/dev/null | cat >"$STATE_FILES/gms.dump"
```
先走管道交给子 shell，再由子 shell 重定向到文件。

**注意**：管道本身不能解决 stdin 的问题，见 Bug 2。

---

## Bug 2 — `while read < file` 里的 `cmd` 会静默失败（最阴的一个）

**现象**
回滚把「该还原」判定成「跳过」，日志显示：
```
KEEP appops com.google.android.gms|RUN_ANY_IN_BACKGROUND 现值 default:allow 已非本模块所设，跳过
```
但系统里该项明明是 `ignore`，且**同一行代码在循环外读就是对的**。

**根因**
```sh
while IFS="$TAB" read -r t k o w; do
  cur=$(cmd appops get ...)   # ← stdin 继承自清单文件
done <"$MANIFEST"
```
`cmd` 把 stdin（指向 `/data/adb` 下的普通文件）也传给 system_server，事务失败：

```
cmd: Failure calling service appops: Failed transaction (2147483646)
```

`appops_read` 里 `2>/dev/null` 把这条错误吞掉了，于是拿到空值 → 落到 `default:allow` 分支。
**结果不是崩溃，而是"看起来正常但判断错了"**，这是最危险的形态：回滚静默失效，用户的改动留在系统里出不去。

**正确写法（三选一，本模块用了第 1 条）**
```sh
# 1. 每个外部命令显式 </dev/null（core.sh 里全部如此）
cmd appops get "$pkg" "$op" </dev/null 2>/dev/null

# 2. 先把清单读进内存，再喂给循环（rollback_all 额外做了这层）
_mlist=$(cat "$MANIFEST"); printf '%s\n' "$_mlist" | while read ...

# 3. 循环体另开 fd
while read -r ... <&3; do ...; done 3<"$MANIFEST"
```

**通用规则**：在本项目里，任何调用 `cmd` / `pm` / `dumpsys` / `am` / `settings` 的地方，
都要假设它的 stdin 可能是普通文件 —— **显式 `</dev/null`**。

---

## Bug 3 — 组件禁用后回读用旧快照，误报 FAIL

**现象**
```sh
gms_snapshot                     # disabled.txt 里没有该组件
comp_change "$c" disabled        # pm disable 实际成功
# → FAIL comp ... 期望 disabled 实际 enabled
```
系统层面看该组件确实已禁用，`disabledComponents` 段里也有它。

**根因**
`comp_read()` 读的是 `state/disabled.txt` 这份**快照**，不是实时状态。
快照在 `gms_snapshot` 时生成，`pm disable` 之后没有更新，回读自然拿到旧值。

**正确写法**
每次写操作后同步本地快照（`core.sh` 的 `comp_cache_set`）：
```sh
comp_disable(){ pm disable "$GMS/$1" </dev/null >/dev/null 2>&1; }
# kv_write 的 comp 分支里紧跟一句：
comp_cache_set "$2" disabled   # 从 disabled.txt 增删该行
```
这样「写入 → 回读校验」才是同一份事实。

---

## 顺带记下的分析陷阱（不是代码 bug，但会误导结论）

### `grep -A N 'disabledComponents:'` 会把没禁用的组件也扫进来

`pm dump` 里 `disabledComponents:` 之后先列被禁组件，然后接**权限表**（几千行）。
用 `grep -A 3000` 抓会溢出，把权限名当组件、把其他包当 gms 组件。
实测误报：真实 103 个，按 `-A` 抓成 520 个，对外结论一度写成「已禁用 406 个」。

**正确写法**：按段落边界截取
```sh
sed -n '/^      disabledComponents:/,/^      [a-zA-Z]/p' "$dump"
```

### 声明组件语料里的写法是相对名

`pm dump` 的解析表写 `com.google.android.gms/.chimera.GmsApiService`，
`dumpsys activity services` 也写相对名。直接 `grep -oE 'com\.google\.android\.gms\.[A-Za-z0-9_.]+'`
抓不到，必须还原：
```sh
grep -oE 'com\.google\.android\.gms/[A-Za-z0-9_./]+' | sed -E 's|.*gms/||; s|^\.|com.google.android.gms.|'
```

### intent action 不是组件

`com.google.android.gms.usagereporting.GOOGLE_SETTINGS`、`...OPTIN_UR` 这些是 action 常量，
不是可 `pm disable` 的组件。用固定名单硬编码会得到一堆 `ABSENT`（或更糟：去 disable 不存在的名字）。
筛组件名要加后缀过滤：`grep -iE '(Service|Receiver|Activity|Provider|Alias)$'`。

### 社区 GMS 精简名单在 26.x 已大面积失效

`AppMeasurement*`、`CampaignTracking*` 在 GMS 26.43.30 上**不存在**；
`.analytics`、`.snet`、`.herrevad`、`.pseudonymous`、`.car` 本机**零组件**。
所以本模块不硬编码组件名，一律从 `pm dump` 动态生成候选，再过滤。

### GMS 会自愈被禁的活跃服务（实测，不是推测）

禁用 `MeasurementBrokerService` 后，过一段时间再查 `dumpsys activity services`，
它又出现了（14 处引用）。而 `ClearcutDebugDumpService` 被禁后保持不变。

**推论**：被 bind 的活跃服务会被 GMS 自己重新启用；纯遥测类不会。
这解释了为什么模块需要在 `boot-completed.sh` 里**再复核一遍**——不是冗余，是必要。
评估某个组件能否压住时，必须隔一段时间复查，不能只看禁用后那一刻。


---

## 本机 Android 17 的能力边界（实测，决定模块设计）

| 手段 | 结果 | 关键证据 |
|---|---|---|
| `pm disable <组件>` | ✅ 有效 | 禁 3 个常驻服务后 `startRequested` 52→21，enable 可还原 |
| `pm revoke <非SYSTEM_FIXED权限>` | ✅ 有效 | `BLUETOOTH_SCAN` granted→false，appops 级联 `Uid mode: ignore` |
| `cmd device_config override` | ✅ 有效且 sticky | 写入后 override 条目 +1；再 `put` 反值，`get` 仍返回 override 值 |
| `settings put global` | ✅ 有效 | `device_idle_constants` 写后读回一致 |
| `cmd appops set` 非运行时 op | ✅ 有效 | `RUN_ANY_IN_BACKGROUND`/`WAKE_LOCK`/`START_FOREGROUND` |
| `cmd appops set` 运行时 op | ❌ 拒绝 | `AppOpService: ...runtime op android:coarse_location should not be set directly` |
| `pm revoke` SYSTEM_FIXED | ❌ 无效 | 返回 0 但仍 `granted=true`；`pm set-permission-flags` 的 flag 白名单里没有 SYSTEM_FIXED |
| `deviceidle whitelist -system` | ❌ 无语法 | `Package must be prefixed with +, -, or =` |

**架构层面的原因**（来自 AOSP 源码核对）：
- Android 16+ 新权限框架里，runtime 权限映射的 op 不再存独立 mode，而是从权限 flags**派生**（`getUidModeFromPermissionState`）。
  所以 `setPackageMode` 直接 return，`setUidMode` 返回 false。**官方替代路径就是改权限本身**。
- `revokeRuntimePermissionInternal` 里判断的是 `callingAppId != SYSTEM_UID`（1000），**uid 0 也过不去**，
  所以 root 也无法 revoke SYSTEM_FIXED 权限。
- `pm set-permission-flags` 只接受 `review-required / revoked-compat / revoke-when-requested / user-fixed / user-set`，
  `updatePermissionFlags` 对非 SYSTEM_UID 还会把 `FLAG_PERMISSION_SYSTEM_FIXED` 从 mask 里清掉。→ 没有 CLI 能去掉它。

**device_config 的坑**：`put` 与 `override` 打通的是不同路径。`put` 写入普通值、会被服务端同步覆盖；
`override` 是 sticky 本地覆盖，优先级更高。本机 hanamaki_kernel 的 `activity_manager` 各项走的就是 override，
这也是它"看起来生效而你的 put 不生效"的原因。**施加用 override，回滚用 `clear_override` + `put`，否则会残留 sticky 条目。**

**sysconfig 是几件事的共同根源**：`/product/etc/sysconfig/google.xml`
```
8:  <allow-in-power-save package="com.google.android.gms" />          ← system 白名单
9:  <allow-in-data-usage-save package="com.google.android.gms" />     ← 数据流量豁免
10: <allow-unthrottled-location package="com.google.android.gms" />   ← 不限流定位
11: <allow-ignore-location-settings package="com.google.android.gms" attributionTag="...thunderbird" />  ← 忽略系统定位开关
```
这解释了为什么本机 `location_mode=0`、`is-location-enabled=false`，GMS 仍然持有并使用定位权限。
`/product` 是 `erofs (ro)`，`touch` 报 `Read-only file system`，只能靠 magic_mount_rs 做 systemless overlay（v2 计划）。


---

## sysconfig overlay 的三个必须注意点

### 1. 必须以「原始备份」为基底，否则重复生成会累积删除

若每次都从 `/product/etc/sysconfig/google.xml` 读基底，而模块已挂载，读到的其实是**自己上一轮的产物**，
`sed` 会在已删过的基础上再删，行数一路递减。

做法：首次从系统读一份存到 `/data/adb/gmscore-slim/backup/google.xml.orig`，之后一律以备份为基底。
实测连续生成 3 次恒为 106 行（不累积）。

### 2. 生成后必须做完整性自检，不通过就放弃覆盖

`google.xml` 里有一批**删了会真出事**的行，最容易误伤的是：
- `update-ownership package="com.google.android.gms" installer="com.android.vending"`
  → 删了 Play 商店无法升级 GMS
- `backup-transport-whitelisted-service` → 备份/换机迁移失效
- `app-data-isolation-whitelisted-app`、`<app-link>`

另外 `allow-ignore-location-settings` 有**两行**：gms 的和 `com.google.android.dialer` 的，
按前缀模糊匹配会连 dialer 一起删（影响紧急呼叫定位）。

自检锚点：`update-ownership` 在、`<config>` 在、`dialer` 在、`backup-transport` 条数对。
任一不满足就 `rm` 掉生成物不覆盖。

### 3. 判断「是否已挂载」不能用「两文件是否不同」

处理版和原版本来就不同，这个判据恒真，会误报 MOUNTED（本模块第一版就犯了这个错，测试复现）。

正确判据：
- 系统实际读到的 md5 == 模块内生成版 md5 → 已挂载
- == 备份原版 md5 → 未挂载
- 都不是 → UNKNOWN（可能被别的模块覆盖）

### 另外：`SYSTEM_FIXED` 权限与 overlay 无关

sysconfig XML 是**只读系统分区**的文件，能被 magic mount 覆盖；
而权限状态在 `/data/misc_de/0/apexdata/com.android.permission/access.abx`（Android 17 已是 ABX 二进制，
`runtime-permissions.xml` 只剩 shared-user 名单），属 `/data` 可写区，overlay 碰不到。
所以「UGD 用 overlay 解决了权限问题」这个印象是错的——UGD 改的是 Doze 白名单，从来不是权限。

## 仓库结构：改用 KernelSU 官方模板与发布工具

原先 `scripts/build.sh` 自己打 zip、自己 unzip 校验权限，`.github/workflows/ci.yml` 里又有
一套 `softprops/action-gh-release` 发布 + 再手写一遍权限检查。这些都是官方已经做好的事，已删除。

现在对齐 [KernelSU-Modules/example-module](https://github.com/KernelSU-Modules/example-module)：

| 以前（手搓） | 现在（官方现成） |
|---|---|
| `scripts/build.sh` 打 zip + unzip 查权限 | `module-release` action 的 `module-dir: module` |
| 自写权限自检 | 官方 validator（`@kernelsu-modules/validator`）发布前预检，不过就不发 |
| `softprops/action-gh-release` | 同一个 action 按 draft → 上传 → 发布，产出 immutable release |
| 自己维护更新检查 | `module.prop` 的 `updateJson` 指向 KernelSU Modules 托管地址 |
| `scripts/setup.sh` 包一层 npm install | 直接 `npm install`（husky 的 `prepare` 钩子） |

目录也换成官方布局：模块内容进 `module/`，`module.yaml`、`README.md`、`assets/icon.png`
留在仓库根。模块内脚本对 `lib/` 的相对引用不变——zip 根仍是模块根。

两个 workflow 里的 `module-release` 和 `actions/checkout` 都 pin 到完整 commit SHA：
前者那一步带 `contents: write`，不能跟分支走。

本地不再有打包命令。要验证包结构就推 PR，CI 的 `precheck` 用同一个 action 跑 `dry-run: true`。

## 组件的「回读校验」曾经是自证

`comp_read` / `perm_read` 读的是 `/data/adb/gmscore-slim/state/` 下的本地快照，而不是系统。
`kv_write` 在真正执行 `pm disable` / `pm revoke` 之后，会立刻调 `comp_cache_set` / `perm_cache_set`
把快照改成目标值。所以下面这段里的回读永远成功：

```sh
kv_write comp "$_c" "$_w"   # 内部：pm disable 然后改快照
_v=$(comp_read "$_c")       # 读的是刚改过的快照
[ "$_v" = "$_w" ] && log "OK ..."   # 恒成立
```

结果就是日志里的 `OK comp ...` 只说明快照写成功了。`pm disable` 明明失败了，也照样打 OK。
`perm` 同理。这和 README 里「失败不静默」的说法对不上，是个真 bug，不是措辞问题。

改法：

- 组件和权限的单条日志由 `OK` 改成 `SET`，含义是「命令已下达」，不再假装校验过了。
- 新增 `verify_real()`，在 `run_all` 结尾重新抓一次系统状态（组件走 `gms_snapshot`
  的 `pm dump`，权限走 `perm_snapshot` 的 `dumpsys package`），再拿清单里本模块写入的值
  逐条比对，输出 `VERIFY-OK` / `VERIFY-FAIL`。一轮只多两次 dump，不是每项一次。
- `appops` / `device_config` / `settings` 三类的回读本来就读系统（`cmd appops get`、
  `cmd device_config get`、`settings get`），`OK` 是真实结论，保持不变。

判据用实测验证过：在 `/data/local/tmp` 造一份清单，写两个确实已禁用的组件和一个没有禁用的，
`verify_real` 给出 2 个 `VERIFY-OK`、1 个 `VERIFY-FAIL`，返回码 1；权限那条同样能区分
`BLUETOOTH_SCAN`（真实已授予）与 `ACCESS_FINE_LOCATION`（期望 false、实际 true）。

顺带确认：本机 HyperOS 上 `cmd package get-component-enabled-setting` 和
`pm check-permission` 都不存在（返回 `Unknown command`），所以单点真实查询做不到，
只能整包 dump 再解析。
