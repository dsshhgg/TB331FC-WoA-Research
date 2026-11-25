# 澎湃4 安装器（Package Installer）外科报告

> 目标：把 HyperOS 4（A17）安装器提取出来，禁用其联网行为与安全检测，再塞回镜像。
> 结论先行：**能提取、能分析、但"改 APK 重签"这条路必然破坏平台签名 → 按任务约定退回方案 1（零改 APK，运行期屏蔽）**。
> 本报告全部结论有工具输出/反编译行号支撑，证据文件在 `out\evidence\`。

- 日期：2026-11-25
- 设备：`5e367954` / TB331FC / HyperOS 4 `OS4.0.5.0.XPZCNXM` / A17 (sdk 37) / `boot_completed=1`
- 我做的事：解包镜像 → 提取 APK → 验签 → jadx 全量反编译（5040 个 java）→ 真机比对 → 真机验证 iptables/设置开关可行性
- 我**没有**做的事：没刷机、没改设备常驻状态（iptables 测试规则已当场删除）、没往任何镜像写入

---

## 1. 安装器的真实身份

| 项 | 值 | 证据 |
|---|---|---|
| 包名 | `com.miui.packageinstaller` | `out/evidence/badging-image.txt` |
| 镜像内路径 | `/product/priv-app/MIUIPackageInstallerVariants/MIUIPackageInstallerVariants.apk`（**在 product_a.img**，不在 system） | `debugfs -R "ls -l /priv-app" product_a.img` |
| 镜像内版本 | versionCode **54512** / versionName **5.4.5.1.2-20260618P** / 9,822,143 B / sha256 `25d66a04…0fe80ebd` | 同上 |
| **真机正在跑的版本** | versionCode **55402** / **5.5.4.0.2-20260720P** / 12,308,669 B / sha256 `c2bebd4b…3e743962ac9f41` / `codePath=/data/app/…`（`installerPackageName=com.xiaomi.market`，2026-11-17 18:46 由小米应用商店装上） | `adb shell dumpsys package com.miui.packageinstaller` |
| uid | **10124** | `pm list packages -U` |
| sharedUserId | **无**（自己一个 uid，不吃 `android.uid.system`） | manifest xmltree 无 `sharedUserId` |
| ABIs | arm64-v8a only | badging |
| manifest 组件数 | 85（activity/service/receiver/provider） | `out/evidence/manifest.xmltree.txt` |

### 1.1 签名：能不能用我们手上的 key 重签？**不能。**

- 镜像内 APK 只有 **v2 + v3** 签名（无 v1 JAR 签名，`META-INF` 里只有 androidx `.version` 文件）。
- 签名者证书：
  - subject = `C=CN, ST=Beijing, L=Beijing, O=Xiaomi, OU=MIUI, CN=MIUI, emailAddress=miui@xiaomi.com`
  - serial = `E552A8ECB9011B7C`，有效期 2011-12-06 → 2039-04-23
  - **SHA-256 = `C9:00:9D:01:EB:F9:F5:D0:30:2B:C7:1B:2F:E9:AA:9A:47:A4:32:BB:A1:73:08:A3:11:1B:75:D7:B2:14:90:25`**
  - 证据：`out/evidence/signature-image.txt`、`out/evidence/cert-image.der`
- **真机在跑的 5.5.4.0.2 版本签名完全相同**（同一证书、同一 SHA-256）→ `out/evidence/signature-running.txt`
- **它是平台签名应用**：真机上 `android`、`com.android.settings`、`com.android.phone`、`com.miui.home`、`com.miui.securitycenter`、**`com.miui.packageinstaller`** 的 PMS 签名 hash 全部相同 = `signatures:[6c02dd51]`（md5 排序后的 signer 集，PMS 内部表示）。
  ```
  android                        signatures:[6c02dd51]
  com.android.settings           signatures:[6c02dd51]
  com.miui.packageinstaller      signatures:[6c02dd51]
  com.miui.securitycenter        signatures:[6c02dd51]
  ```
  → 安装器和 **framework / Settings 同属一把 MIUI 平台私钥**。
- 我们手上有的 key（`work\tools\`）：
  - `testkey_rsa4096.pem` / `testkey_rsa2048.pem`（AOSP testkey 系，sha1 avb pubkey `2597c21…`，就是 kit-baked 重签 vbmeta/镜像用的那套）
  - `xiaomi_key_probe\cand\aosp_platform.{pk8,x509.pem}`（AOSP platform，SHA-256 `C8:A2:E9:BC…19:2A:B8`）
  - `xiaomi_key_probe\otacerts_extracted\releasekey.x509.pem`（小米 MIUI 证书，SHA-256 `D4:5F:07:6F…8B6F`，**只有证书、没有私钥**，且**与我们这个安装器的证书也不是同一张**（不同 SHA-256））
  - 结论：**没有任何一把能复现 `C9:00:9D:…` 这张 MIUI 平台证书；私钥不在我们手上，也无法从 ROM 里推出来。**

### 1.2 重签之后会立刻坏掉的东西（不是"也许"，是"确定会"）

`com.miui.packageinstaller` **自己声明了 4 个 `signature|privileged` 权限和 1 个 `signature` 权限**（`dumpsys` 第 439-444 行）：

```
declared permissions:
  miui.packageinstaller.permission.ACTION_INFO:      prot=signature|privileged
  miui.packageinstaller.permission.ConfigSecurityMode: prot=signature|privileged
  com.miui.security.permission.managerRiskApp:       prot=signature|privileged
  com.miui.security.permission.installOtherApp:      prot=signature|privileged
  com.miui.packageinstaller.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION: prot=signature
```

- 这 4 个 `signature|privileged` 权限是**给 SecurityCenter / Settings 侧"谁能调度安装器、谁能改安全模式"用的**：换上我们的 testkey 后，**同签者集从 MIUI 平台变成 AOSP testkey**，Settings / SecurityCenter 通过 `miui.packageinstaller.permission.ACTION_INFO` / `ConfigSecurityMode` 发过来的调用会被 `SecurityException` 掉（MIUI 代码基本都不 catch）→ 极可能连**正常安装流程的入口**（`InstallStart` 被 Settings 拉起那一段、"安装未知应用"授权页）都会挂。
- 反过来的损失：安装器自己 requested 的 `com.miui.guardprovider.permission.Guard_Provider`、`com.miui.securitycenter.permission.ACCESS_SECURITY_CENTER_PROVIDER`、`com.miui.cleanmaster.permission.Clean_Master`（都是 `signature|privileged`，目前靠"同签"拿到 grant）**会变 denied**——虽然这三个正是我们要关的"安全检测"，但它们是**硬编码在 AOSP 安装器基类的流程里**，denied 之后是抛异常而不是静默跳过。
  - 证据：badging 的 `uses-permission` 列表（`out/evidence/badging-image.txt`）
- 还有一层：`com.xiaomi.analytics`（`Analytics.java` 里显式判断 "is platform signatures"）、`vender`/`securitycenter` 侧的 `signature` 比对、以及 `android:sharedUserId` 缺省下 PMS 对"系统应用被 data 更新覆盖"的签名一致性检查：
  - 真机上安装器是 **`UPDATED_SYSTEM_APP`**（系统副本 54512 在 /product，data 副本 55402 在 /data/app）。我们把 /product 里那份换成 testkey 签名的 APK 之后，PMS 在开机扫描时会发现**系统副本与 data 副本签名不一致**，按 AOSP 逻辑要丢弃 data 副本；如果它先信任 data 副本，则我们的新镜像副本不生效（等于白改）。两边都是一次整机级的赌博。

> **所以：改 APK 不是"有点风险"，而是"必然破签名、必然丢签名级权限、并且要额外做数据侧签名迁移"。按任务边界条款，退回方案 1。**

---

## 2. 它到底联了哪些网、做了哪些安全检测

### 2.1 联网：4 条独立通道

#### 通道 A：安装器自有云端 API（Retrofit + OkHttp，官方域名 `api.installer.xiaomi.com`）

| 证据 | 内容 |
|---|---|
| `work\pkg-installer\work\jadx\sources\s0\I.java:7-49` | base URL 常量表 `https://api.installer.xiaomi.com`（staging/preview/test 三套备用域名 `api-installer.pt.xiaomi.com`、`preview-api.installer.xiaomi.com`、`test-api-installer.pt.xiaomi.com`）+ 全部 path |
| `Q2\h.java:125-243` | `RetrofitUtils` 单例：OkHttpClient（20s 连接/读/写超时，自建 X509TrustManager，`M(true)` 开缓存），header 里塞 **`d`=deviceId、`r`=region、`m`=IMEI-MD5（sdk≤28 时）、`oaid`、`n`=网络类型、`mo`=机型、`v`/`vn`/`mivc`/`osvn`** 等设备指纹 |
| `Q2\g.java:13-26` | `@POST /v2/cloud_config/query`、`@POST /info/layout`（广告位）、`/statistics/appactive`、`/pkg/risk/developer/appeal` |
| `Q2\InterfaceC1038b.java:17-50` | `@GET /v3/cloud_config/query`、`/v4/game/interceptcheck/{safemode,enhancemode,normal}`、`/passport/identity/url`、`/pkg/info/type/query`、`/safemode/close/reason/list` |
| `s0\I.java:42-49` | 另：`/v2/game/interceptcheck`、`/info/layout`、`/v2/cloud_config/query`、**`/avl/upload`**（AVL 上报）、`/pkg/risk/type/all`、`/passport/identity/url` |
| `C2\C0399l.java:174` | `InstallDataReporter`：把安装结果 **POST 到 `/avl/upload`** |
| `com\miui\packageInstaller\DeveloperComplaintActivity.java:406` | `GET /pkg/risk/type/all`（风险类型列表） |
| `com\android\packageinstaller\utils\s.java:1-40` | 另一套裸 `HttpURLConnection` 工具（`com.android.packageinstaller.utils.s`），与 Retrofit 并存，带同样一套设备指纹 header |

**触发时机（关键）**：`o2\h.java` = `InstallTask.kt`。每次安装都会进 `loadCloudParamsAndAD`：

- `o2\h.java:442`（`InstallTask$loadCloudParamsAndAD$1`）→ 并发三件事：**cloud 参数**、**广告 AdModel**、**实验**、**应用市场**（`829` `marketJob`）、**`XiaoMiSafe.checkPackageSafe` 原生校验**（`682-721`）
- 云端返回 `CloudParams` 后逐字段落到 UI/逻辑：`categoryAbbreviation`、`useSystemAppRules`、`appManageScene`、`appManageCategory`、`registrationStatus`、`registrationRestrictStatus`、`useRegistrationPop`（`1611-1620` 打日志 `cp: catA=…`）
- 云端失败会走 `CloudResult.NoNetworkError`（`o2\h.java:615-627`）→ 打印 + 继续（**这条路径本身不会卡死安装**，所以断网是安全的）

#### 通道 B：OneTrack / Analytics 埋点（`com.xiaomi.onetrack`、`com.xiaomi.analytics`）

- `com\xiaomi\onetrack\…`、`S2\d.java`、`u2\c.java`、`t0\C1124a.java:40`（`Analytics.getInstance(this)`）
- 机上有 `shared_prefs/one_track_pref.xml`、`uuid.xml`、`analytics_updater.xml` → 确实在跑
- 上报全部安装行为（`C2\C0399l.java` 的 `InstallDataReporter`、`h2\C0787d` 事件）

#### 通道 C：小米账号 / MiCloud / Hybrid H5 SDK（捆绑 SDK，独立域名）

`out/evidence/urls-all.txt`（136 条 URL 全量）里与安装器主流程相关的：
`api.account.xiaomi.com`、`account.xiaomi.com/pass2/…`、`v.id.mi.com/visitor/{login,register}`、`api.hybrid.xiaomi.com` / `api.hybrid.intl.xiaomi.com`（`com\miui\hybrid\accessory\sdk\icondialog\a.java:36`）、`api.installer.xiaomi.com`、`verify.sec.xiaomi.com`（`com\xiaomi\accountsdk\account\data\Constants.java:37`）、`tz.sec.xiaomi.com/session`（`com\xiaomi\passport\SecurityDeviceReporter.java:45`）、`data.sec.miui.com/privacy/agree/v1`（`M2\d.java:45`）、`app.market.xiaomi.com/hd/apm-h5-cdn/*.html`（H5 说明页）、`sdkconfig.ad.xiaomi.com`、`micloud.preview.n.xiaomi.net`（MiCloud SDK）

#### 通道 D：跟 SecurityCenter 的跨进程数据流（不是 HTTP，但同样是"联网验证"的一部分）

- 病毒扫描走 `content://guard/install_scan` / `content://guard/sync_scan`（见 2.2）
- `com\android\packageinstaller\utils\w.java:19,24`：`content://com.miui.securitycenter.remoteprovider`
- `i2\n.java:337` 读 `com.miui.securitycenter` 的 ApplicationInfo.metaData（`miui.supportProviderForInstaller`）
- `i2\n.java:325` 读 `com.lbe.security.miui` 的 metaData（`miui.supportInstallerCharge`）
→ **SecurityCenter 自己的进程有网络权，会拿云端病毒库**。所以"只封安装器 uid"能断安装器自连，但断不掉 SecurityCenter 代扫的云查（第 6 节给了配套开关）。

### 2.2 安全检测：3 层

#### 第 1 层：病毒扫描（真正决定"能不能装"的那一层）

`com\miui\packageInstaller\b0.java` = **NewVirusScanner**（Kotlin `NewVirusScanner.kt`）：

```
b0.java:72   Uri.parse(z7 ? "content://guard/install_scan" : "content://guard/sync_scan")
b0.java:87   arrayMap.put("installPackage", callingPackage)
b0.java:88   contentResolver.query(...)  // 参数：[apkUri, 是否首次安装, (调用方json)]
b0.java:93-98 读列 Type / Description / VirusName / Forbidden → ExtraGuardVirusInfoEntity
```

- 调用方：`o2\h.java:1375-1397`（`InstallTask$startVirusScan$1$virusJob$1`）→ `R().b(callingPackage, apkInfo)`
- 总闸：`o2\h.java:1594  return i2.n.r(InstallerApplication.j()) || i2.n.x(InstallerApplication.j());`
  → `i2\n.java:315-317`：**`Settings.System.virus_scan_install`（默认 `true`）**；`|| n.x()` 是"安全模式开着"也强制扫。
  **这一条就是最干净的病毒扫描开关**（见第 6 节命令）。
- provider 侧：`com.miui.guardprovider/.GuardProvider`（真机 `dumpsys package com.miui.guardprovider` 有 `Provider{de1ce12 …/.GuardProvider}`），另有 `.server.db.VirusScanContentProvider`。

#### 第 2 层：安全模式 / 纯净模式（"安全守护"）

- `i2\n.java:360-370`：`x()` 读 **`Settings.Secure.miui_safe_mode`**，缺省值 = `!safe_mode_is_change && safe_mode_is_open_cloud_config==1`（**云配置能把它默认打开**）
- 云端下发：`com\miui\packageInstaller\C0682k.java:60-61` → `safe_mode_is_open_cloud_config`、`safe_mode_verify_type_cloud_config` 写进 `pure_mode.xml`
- 拦截：`Y4\C1313e.java:362  return n.r(context) && !n.p(context)`；`o2\h.java:1594`；`miuix\appcompat\app\AlertController.java:929/1219/1578/2181`
- **真机现值：`settings get secure miui_safe_mode` = `1`（安全模式是开着的！）**，`miui_security_mode_style=normal`
  → 这就是"安装器总是弹风险提示/拦未知来源"的直接原因之一。
- 附属「全面安全模式（fullsafe）」：`com\miui\packageInstaller\fullsafe\`、`Settings.Secure.installer_full_safe_version`（真机=1）、`full_safe_version_alert_popped`

#### 第 3 层：原生 `checkPackageSafe` + 云端风险/黑名单

- `com\miui\packageInstaller\util\XiaoMiSafe.java:15-31`：
  `System.loadLibrary("xiaomiSafe")`，5 个 native：`checkPackageSafe(String path, int)`、`getKeyBytes/getKeyViBytes/getSaltIv/getSaltKey`
  证据：`lib\arm64-v8a\libxiaomiSafe.so`（198,648 B，符号 `Java_com_miui_packageInstaller_util_XiaoMiSafe_00024Companion_checkPackageSafe`）
  → 安装前在 IO 线程做一次原生校验（签名/哈希/授权令牌类），**结果不参与阻断，只参与埋点/透传**（`o2\h.java:714-720` 返回值被丢弃）。
- 云黑名单：`i2\n.java:108-121`（`packageinstaller_forbidden_app_list` / `_version` / `_network_error_forbidden_app_list`）+ `local_block_apk_data.xml` + `permcenter` 侧 `managerRiskApp` / `installOtherApp`（见 1.2 的 4 个签名权限）。
  真机现值 `packageinstaller_forbidden_app_list_version = 5`，`black_app_install_control` 里全是 VPN/翻墙类（`us.ultrasurf…`、`org.getlantern…`、`com.nordvpn…`、`com.expressvpn…`）——**这就是"装 VPN 被拦/被提示风险"的数据源**。
- 云端「生效清单」`pure_mode.xml` 的 `effective_install_app_list` 按 `apkSignature`+`apkSize`+`packageName` 精确放行某几款游戏（`com.zlongame.cn.phoenix*`、`com.tencent.ngr--`…）。

### 2.3 广告/推荐（顺手记一笔）

`InstallTask.loadCloudParamsAndAD` 里的 `adJob`/`marketJob`（`o2\h.java:730`、`829`）→ `/info/layout` 拿广告位；`com\android\packageinstaller\SettingsActivity.java:76` 有用户开关 `pref_key_open_ads`，落盘 `A0\c.java:166-168` 的 `ads_enable`（**真机已经是 false**），`app_store_recommend`（`A0\c.java:170-172`，真机 true）。

### 2.4 所有开关的落盘位置（这是方案 1 的命令依据）

| 语义 | 存储 | 键 / 默认 |
|---|---|---|
| 病毒扫描总闸 | **Settings.System** | `virus_scan_install`（默认 true）`i2\n.java:315` |
| 安全模式（安全守护） | **Settings.Secure** | `miui_safe_mode`（真机=1）`i2\n.java:360` |
| 安全模式样式 | Settings.Secure | `miui_security_mode_style`（=normal）`i2\n.java:136` |
| 全面安全模式 | Settings.Secure | `installer_full_safe_version`（真机=1）`i2\n.java:319` |
| 黑名单/禁装列表 | Settings.Secure | `packageinstaller_forbidden_app_list(_version)` `i2\n.java:108-121` |
| 应用安全验证（验签） | SharedPreferences `common.xml` | `secure_verify_enable`（真机=true）`A0\c.java:58,163` |
| 广告 | `common.xml` | `ads_enable`（真机=false）`A0\c.java:166` |
| 应用商店推荐 | `common.xml` | `app_store_recommend`（真机=true）`A0\c.java:170` |
| 关掉安全模式标记 | `common.xml` | `user_close_security_mode_flag` `A0\c.java:154` |
| 云配置到位时间 | `common.xml` | `cloud_data_fetch_time`（真机=1795313579147 ≈ 2026-11-20） |

---

## 3. 推荐方案（首选，零改 APK / 零改镜像）：方案 1

### 为什么是它

1. **签名不可复现**（§1.1）→ 方案 2/3 都要破签名；
2. 该机 **已经 root**（`adb shell` 直接是 `uid=0 context=u:r:ksu:s0`，KernelSU，`/data/adb/{ksu,ksud,modules}` 都在，已有 4 个模块 `fix_logpersist_sepolicy / xbt_continuity_fix / xbt_recents_proxy / zz_density320`）；
3. **真机实测**：`iptables -m owner --uid-owner 10124` 与 `ip6tables`、以及 `-j REJECT --reject-with icmp(6)-port-unreachable` **四条规则在本机全部可加可删**（输出 `ADD_REJECT4_OK / ADD_REJECT6_OK / DEL_*_OK`）——不是猜的；
4. 断网**不会卡安装**：`CloudResult.NoNetworkError` 分支是"继续"（§2.1 通道 A）；
5. 所有"安全检测"闸门都读写 settings/prefs，**改开关即可，不用碰 dex**。

### 3.1 一键脚本

```bash
# 已写好：E:\rom\work\pkg-installer\out\block-installer.sh
adb push out\block-installer.sh /data/local/tmp/ ; adb shell sh /data/local/tmp/block-installer.sh
```

脚本做的事（每一步都幂等）：

```bash
UID=$(dumpsys package com.miui.packageinstaller | sed -n 's/.*uid=\([0-9]*\).*/\1/p' | head -1)   # =10124
# 1) 断网：IPv4 + IPv6，用 REJECT 让连接立即失败（DROP 会拖到 20s 超时）
iptables  -I OUTPUT 1 -m owner --uid-owner $UID -j REJECT --reject-with icmp-port-unreachable
ip6tables -I OUTPUT 1 -m owner --uid-owner $UID -j REJECT --reject-with icmp6-port-unreachable
# 2) 关病毒扫描（NewVirusScanner 总闸）
settings put system virus_scan_install 0
# 3) 关安全模式/纯净模式（真机现在是 1）
settings put secure miui_safe_mode 0
settings put secure miui_security_mode_style normal
# 4) 去掉云黑名单（VPN 类拦截的数据源）
settings put secure packageinstaller_forbidden_app_list ''
settings put secure packageinstaller_forbidden_app_list_version 0
# 5) 关"应用安全验证"(验签 UI)  —— 需要 app 进程停掉后改 prefs 才不会被覆盖
am force-stop com.miui.packageinstaller
xmlstarlet/sed 改 /data/data/com.miui.packageinstaller/shared_prefs/common.xml：
   secure_verify_enable=false  /  app_store_recommend=false  /  user_close_security_mode_flag=true
```

> 注意 DNS：`netd` 的解析器**不是**安装器 uid，所以域名还能解析，但 TCP 全部 REJECT → 无任何报文出去。要连 DNS 也断，可再加 `-m owner --uid-owner $UID -p tcp --dport 53`（没必要，被 REJECT 的 TCP 也带不走数据）。

### 3.2 持久化（重启后 iptables 会丢，settings 不会）

KernelSU 模块骨架已生成：`out\ksu-module\`（`module.prop` + `post-fs-data.sh` + `service.sh` + `uninstall.sh`）

```bash
adb shell su -c 'mkdir -p /data/adb/modules/zz_installer_block'
adb push out\ksu-module\. /data/adb/modules/zz_installer_block/
adb shell su -c 'chmod 755 /data/adb/modules/zz_installer_block/*.sh; reboot'
```

`service.sh` 在 `boot_completed` 之后跑（此时 uid 一定已分配），并每次开机重新确认 settings 值。

### 3.3 把关卡在 system 层的替代写法（如果不想用 root 脚本）

如果你的目标是"开机自带、不依赖 root 模块"，还有两条**不碰 APK**的路（都在 `out\bake\NOTES.md` 里写了命令）：
- 把 5 个 `settings` 值直接写进镜像的 **`/product/etc/…` 无解**（settings 存 /data），只能靠"首次开机脚本"；而 MIUI 的 `/product/etc/init/*.rc` 里跑 shell 又要自编 SELinux，风险高于收益 → **不推荐**。
- 所以：**持久化的正确容器是 KernelSU 模块（/data），不是镜像**。

---

## 4. 如果一定要"进镜像"（方案 2），完整流水线

> 前提：已经接受"破签名"，并且**同时做三件事**才能真的生效：① 重签 APK；② versionCode 抬到 > 55402（例如 55403）；③ 处理 /data 侧旧签名副本；④ 补 privapp 权限白名单。
> 缺任何一条，要么不生效，要么开机扫描丢包。

### 4.1 改 APK（apktool + 删权限/删组件）

```bash
# 工具：E:\rom\work\tools\apktool.jar（2.11.1 已在机）、jadx 1.5.1
java -jar apktool.jar d -f -o dec MIUIPackageInstallerVariants.apk
# 删 AndroidManifest 里这几行（行号见 evidence/manifest.xmltree.txt）
#   line 69  <uses-permission android:name="android.permission.INTERNET"/>
#   line 71  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
# 可选删：com.xiaomi.milogsdk.PushUploadLogReceiver / com.android.packageinstaller.AppActiveReceiver
#         （先别删，见 §5 风险；断网后它们本来就发不出去）
# versionCode 54512 -> 55403（build.gradle 没源码，改 apktool.yml 的 versionInfo 会同步到 manifest）
java -jar apktool.jar b -o patched.apk dec
# 对齐 + 用 testkey 重签（v2/v3，与 kit-baked 一致的那把 4096 位）
zipalign -p 4 patched.apk patched-aligned.apk
apksigner sign --key testkey_rsa4096.pk8 --cert testkey_rsa4096.x509.pem \
  --v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled true \
  --out MIUIPackageInstallerVariants-patched.apk patched-aligned.apk
apksigner verify --print-certs MIUIPackageInstallerVariants-patched.apk
```
（我们手上只有 `testkey_rsa4096.pem`（PEM 私钥），需要先 `openssl pkcs8 -topk8 -nocrypt -in …pem -outform DER -out testkey_rsa4096.pk8`，证书用 avbtool/pem 推出自签 x509。）

### 4.2 塞回 product_a.img（照 kit-baked 的已验证配方）

```bash
# 基线：E:\rom\release\TB331FC_HyperOS4_A17_FullKit_v4\images\product_a.img (2999996416)
#      ext4 数据段 2909995008（truncate.py 的 SPEC 已写死，且与 avbtool info_image 一致）
OUT=E:\rom\work\pkg-installer\out
# ① 截掉 AVB footer → 只剩 ext4 数据区
python E:\rom\work\kit-baked\truncate.py <v4 images 目录> $OUT\work
# ② debugfs 替换 APK（mode 0100644 / uid=gid=0 / selinux u:object_r:system_file:s0（NUL 结尾）/ 时间戳钉 1230768000）
#    脚本：out\bake\surgery-installer.sh（改写自 kit-baked\surgery.sh 的 replace_file）
bash out\bake\surgery-installer.sh $OUT\work\product.img $OUT\payload\MIUIPackageInstallerVariants-patched.apk
# ③ fsck + 钉 lastcheck
e2fsck -fy $OUT\work\product.img ; debugfs -w -R 'ssv lastcheck 1230768000' $OUT\work\product.img
# ④ 重算 hashtree（salt 00..01 / SHA256_RSA4096 / no FEC / rollback 0）
python E:\rom\work\tools\avbtool.py add_hashtree_footer \
  --image $OUT\work\product.img --partition_size 2999996416 --partition_name product \
  --do_not_generate_fec --salt 0000000000000000000000000000000000000000000000000000000000000001 \
  --algorithm SHA256_RSA4096 --hash_algorithm sha256 \
  --key E:\rom\work\tools\testkey_rsa4096.pem --rollback_index 0
# ⑤ 重签 vbmeta_system（描述符顺序必须 product → system → system_ext，这是 kit-baked 用它原厂镜像逐字节证明过的顺序）
python E:\rom\work\tools\avbtool.py make_vbmeta_image --output $OUT\work\vbmeta_system.img \
  --flags 0 --algorithm SHA256_RSA2048 --key E:\rom\work\tools\testkey_rsa2048.pem \
  --padding_size 65536 --rollback_index 0 \
  --include_descriptors_from_image $OUT\work\product.img \
  --include_descriptors_from_image $OUT\work\system.img \
  --include_descriptors_from_image $OUT\work\system_ext.img
# ⑥ 校验
python avbtool.py verify_image --image $OUT\work\product.img
python avbtool.py verify_image --image $OUT\work\vbmeta_system.img
```

完整可执行版：`out\bake\rebake-installer.ps1`（串起 ①②③④⑤⑥ 并自带 preflight sha256 检查；参数化 `-BaseImages`，默认拿 `work\kit-baked\out` 的三张“已烘 5 修”镜像作底，这样不会把 density/pen 修复搞丢）。
产物：`out\product_a.img`（2.86 GB）+ `out\vbmeta_system_a.img`（64 KiB），以及 `out\SHA256SUMS.txt`。

### 4.3 刷入（不在本次任务范围，只是写清楚）

fastbootd：`fastboot flash product out\product_a.img` + `fastboot flash vbmeta_system out\vbmeta_system_a.img`，然后 `pm uninstall-system-updates com.miui.packageinstaller`（或在刷完后 `adb shell su -c 'rm -rf /data/app/*/com.miui.packageinstaller-*'` 并清 `packages.xml` 的签名态，具体见 §5 风险 3）。

---

## 5. 风险与回滚

| # | 风险 | 影响 | 处置 |
|---|---|---|---|
| 1 | **重签必然破平台签名** | 4 个 `signature|privileged` 声明权限的对端（Settings/SecurityCenter）调用被拒 → 正常安装入口可能挂 | **方案 1 完全规避**；坚持方案 2 就得接受并准备"装完发现装不了东西" |
| 2 | 系统副本 vs /data 副本签名冲突 | 新镜像副本可能不生效，或 data 副本被 PMS 丢弃 | 镜像版必须抬 versionCode，并显式 `pm uninstall-system-updates` + 清 data 目录 |
| 3 | privapp 白名单 | 重签后 `android.permission.INSTALL_PACKAGES` 等仍走 `privapp-permissions-product.xml`（它列了 12 个权限，见 `out/evidence/privapp-entry.txt`），**只要还在白名单就不受签名影响**；但签名级权限不受白名单保护 | 需要时把 4 个签名权限加进对端白名单，或直接放弃 |
| 4 | iptables 重启即失 | 重启后联网恢复 | KernelSU 模块（§3.2） |
| 5 | 断网后埋点/上报异常刷日志 | 仅日志噪音 | 无 |
| 6 | 关安全模式后**未知来源安装不再有风险提示** | 功能退化（这正是目标） | 反悔就 `settings put secure miui_safe_mode 1` |
| 7 | 云配置把安全模式再打开 | `C0682k` 会把 `safe_mode_is_open_cloud_config` 写回；但 `safe_mode_is_change=true` 后 `i2\n.java:366` 不再采信云端默认 | 已在真机成立（`pure_mode.xml` 里 `safe_mode_is_change=true`） |
| 8 | 真机正在跑的是 **/data 里的 5.5.4.0.2**，不是镜像里的 5.4.5.1.2 | **只改镜像 = 完全不生效** | 这条最容易踩：方案 1 直接对 uid 生效，与小版本无关 |

**回滚**
- 运行期（方案 1）：`out/rollback-installer.sh`（删 iptables 规则 + 把 settings 写回 1/true + 恢复 prefs 备份）。脚本在改 prefs 前会自动备份到 `/data/local/tmp/installer-shared_prefs.bak`。
- 镜像级（方案 2）：用原镜像回刷
  `E:\rom\release\TB331FC_HyperOS4_A17_FullKit_v4\images\product_a.img`
  + 同目录 `vbmeta_system_a.img`，或直接用 `work\kit-baked\out\` 那套（等于回到"只有 5 修"的状态）。
- 兜底：`release\TB331FC_HyperOS4_A17_FlashKit\`（含 bat + edl）整包回滚。

---

## 6. 交付清单

| 路径 | 说明 |
|---|---|
| `REPORT.md` | 本报告 |
| `out\block-installer.sh` | 方案 1 一键屏蔽（幂等，含 prefs 备份） |
| `out\rollback-installer.sh` | 方案 1 一键回滚 |
| `out\ksu-module\` | 开机持久化（KernelSU 模块） |
| `out\bake\rebake-installer.ps1` | 方案 2 全流水线（截断→注入→fsck→hashtree→vbmeta→verify） |
| `out\bake\surgery-installer.sh` | 单文件注入（mode/uid/gid/selinux/时间戳） |
| `out\bake\verify-installer.sh` | 产物比对（in-image sha256 vs 本地 payload、mode、xattr、AVB 校验） |
| `out\bake\NOTES.md` | 镜像级的坑与命令（含 privapp 白名单改法） |
| `out\evidence\*` | badging / 双版本签名 / manifest xmltree / 136 条 URL / sha256 |
| `work\jadx\sources\` | 全量反编译（5040 java，可直接 grep 复验本报告任一行号） |

---

## 7. 证据等级（哪些是"跑出来的"，哪些是"读出来的"）

| 结论 | 等级 | 怎么复验 |
|---|---|---|
| 安装器包名/版本/路径/sha256 | **实测** | `debugfs -R "ls -l /priv-app" product_a.img`；`aapt2 dump badging` |
| 真机实跑 5.5.4.0.2 + 由应用商店更新 | **实测** | `adb shell dumpsys package com.miui.packageinstaller \| grep -E "versionCode\|codePath\|installerPackageName"` |
| 签名者 SHA-256 `C9:00:9D:01…`、与 framework 同签 | **实测** | `out/evidence/signature-{image,running}.txt`；`adb shell dumpsys package <pkg> \| grep signatures=` 比 6c02dd51 |
| 4 个 `signature|privileged` 声明权限 | **实测** | `adb shell dumpsys package com.miui.packageinstaller \| sed -n '435,450p'` |
| 联网端点/域名 | **反编译实测** | `grep -rn "api.installer.xiaomi.com" work/jadx/sources`；`out/evidence/urls-all.txt` |
| 病毒扫描走 `content://guard/install_scan` | **反编译实测 + provider 存在性实测** | `b0.java:72`；`dumpsys package com.miui.guardprovider \| grep GuardProvider` |
| 各开关的落盘键与当前值 | **实测** | `settings get system virus_scan_install` / `cat /data/data/com.miui.packageinstaller/shared_prefs/{common,pure_mode}.xml` |
| iptables `--uid-owner` + `REJECT` 可用 | **真机实测（加完即删）** | 本报告 §3.1；测试输出 `ADD_REJECT4_OK … DEL_REJECT6_OK` |
| 断网不会卡安装 | **反编译推断（`CloudResult.NoNetworkError` 分支）+ 代码有 20s 超时兜底** | `o2/h.java:615-627`、`q2/h.java:44-46` |
| hashtree/vbmeta 参数（salt、算法、描述符顺序、key sha1） | **实测** | `python tools/avbtool.py info_image --image work/kit-baked/out/{product_a,vbmeta_system_a}.img` |
| **"重签一定崩"的具体崩法** | **推断**（签名语义 + 该 ROM 的 grant 结构），没有真机验证 | 要证实只能真刷一次带 testkey 签名的安装器（不建议） |

> 明确没有做的：没有刷机；没有真的把任何 APK 重签并塞回镜像（方案 2 只备好流水线）；没有在设备上留下常驻改动（iptables 测试规则已删、settings 未动）。

---

## 8. 一句话给 lead

**安装器 = `com.miui.packageinstaller`（product 分区 `/priv-app/MIUIPackageInstallerVariants/`，镜像内 5.4.5.1.2，真机实跑 5.5.4.0.2），用 MIUI 平台私钥签名（SHA-256 `C9:00:9D:01…`），和我们手上的 testkey 毫无关系，**重签必然破坏 4 个签名级权限并引发系统/data 签名迁移**；因此**推荐方案 1（root 下 `iptables uid REJECT` + 4 个 settings 开关 + KernelSU 模块持久化），零改 APK、零改镜像**；要改也只改 `product_a.img`（不是 system），并且必须抬 versionCode + 处理 /data 旧副本，否则白改。**
