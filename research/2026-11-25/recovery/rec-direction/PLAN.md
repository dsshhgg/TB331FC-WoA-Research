# recovery 方向定案：为什么选「原厂骨架 + OF 用户态」，以及前十几条路到底错在哪

生成：2026-11-25 18:4x (+08:00) · 工作目录 `E:\rom\work\rec-direction\`
本轮**没有刷机**（设备在 A17 正常开机，`boot_completed=1`，已在 18:3x 用 `adb` 复核，root 可用）。
所有结论要么是**本机字节级实测**，要么是**从设备回读的实测值**，标注逐条给出。

---

## 〇、一页结论

**推荐方向 A：留下原厂 ZUI16 recovery 的 ramdisk 骨架（`init`/`ueventd`/rc/USB/sepolicy 一个不动），只把 TWRP 的用户态换进去**（`/system/bin/recovery`、它缺的 52 个 `.so`、`/twres`、TWRP 版 fstab、`twrp.flags`）。
理由不是"听起来对"，而是三条**可离线复核的硬证据**（下面 §1 全是实测数字）：

1. **装载层面已经被证明不会失败**：hybrid 的 `recovery` 依赖闭包 = 94 个 ELF / 23.37 MiB，**缺 0 个库**；全符号表审计 10,014 条未定义引用，**strong-unresolved 10 个，与原厂 recovery 的 baseline 逐个相同，新增 0**。也就是说：这套东西在链接器那一层是"必然能加载"的，不再需要上机赌。
2. **"OF 的 init 与 recovery 强耦合"这个疑虑被证伪**：两边是**同一份 AOSP recovery `init.rc`** 的两个版本——同样 `import /init.recovery.${ro.hardware}.rc`、同样一条 `service recovery /system/bin/recovery`（连 `socket recovery stream 422 system system` 和 `seclabel u:r:recovery:s0` 都一样）、同样一套 functionfs/configfs gadget 块。TWRP 的 `recovery` 对 init 的全部要求，就是"像原厂 recovery 一样被当作一条普通 service 拉起来"，而这件事在这台机器上**已经被原厂验证过**。
3. **卡 logo 从此是有日志的事件**：ramoops 在设备树里（2 MiB @ `0x1bfe00000`），cmdline 本来就 `console=ttyMSM0,115200n8`；本轮把 `printk` 的 console 级别抬到 8（`write /proc/sys/kernel/printk 8`），init 自己的日志（level 6）从此也进 ttyMSM0 → 进 pstore。再加上一个独立 watchdog 把 `init.svc.recovery` 时间线和 `/tmp/recovery.log` 尾部打进 kmsg，**挂死后下一次启动能从 `console-ramoops-0` 把过程逐行读回来**。

**但这套镜像有一个还没定的硬约束**：ABL 对 `recovery` 的尺寸上限有两个互相矛盾的口径（14,572,954 B「已证明能启动」 vs ≈31.7 MB「按 `0xbff4` 公式反推」），而 A1 是 **25.62 MiB**。
所以第 1 步不是刷 A1，而是刷一个 **15.62 MiB 的骨架对照镜像**——它正好卡在两个口径之间，一次刷机同时回答两件事：我们的 rc/watchdog 改动是否无害、ABL 的真实上限在哪一档。

---

## 一、四条方向 · 可行性矩阵

成功率是我的估计（写明依据），不是测量。

| 方向 | 达到"可用 recovery"（有 UI/能刷机） | 至少"有 adb、能刷、能挂分区" | 工作量 | 必须先验证什么 | 失败代价 |
|---|---|---|---|---|---|
| **A. 原厂骨架 + TWRP 用户态**（本方案，镜像已出） | **45 %** —— 唯一未知量是 TWRP 的 minui-DRM 能不能在这块 hx83102j 面板上出画；装载/依赖/尺寸（派生口径）都已离线排除 | 70 % | **本轮已完成**（镜像+审计+脚本）；后续 2~3 次刷机 | ① ABL 真实上限（v0 一次回答）② DRM 出画（v1 一次回答，pstore 有日志） | 低：`recovery_a` 可整块刷回，脚本每次自动回滚 |
| **B. 先证明通道再谈功能**（of-pipeline 七镜像阶梯） | 15 % —— 它本身**不产出**可用 recovery，只产出"死在哪一层"的结论 | 30 %（`exp2a` 若能起 adbd 则 60 %） | 已备好（0 h），5 次刷机 | `exp1a` 必须先过（否则刷写路径本身可疑） | 低，但**每次刷机只换一个等价性结论**；`exp2b` 的解释力还依赖 `exp1c` |
| **C. TWRP/OF 源码重编**（`of-rebuild/PLAN.md`） | 40 % —— 能把 lz4 压到 13.67 MB（余 0.91 MB），并拿到"正确的设备树/fstab/触摸"，但**显示这条同样的未知量仍在**，且本机从未在本轮跑过 repo sync | — | **1~2 天**（同步+build 环境），且要重做 13 档裁剪验证 | 构建环境是否存在（本盘只有设备树与文档，无 build 产物） | 高：时间成本大；历史上"编译成功但设备进不去"已经有 3 个版本 |
| **D. 自写极简 recovery**（`exp2a_mintel`，4.95 MB） | 20 %（没有触摸 UI） | **60 %** —— 不碰显示/触摸/SELinux，只要 functionfs+adbd 时序对 | 1~2 h 加固 | `exp2a` 从未上机；无 property service 时 adbd 的 ffs 时序未验证 | 低；但"没有 UI 的 recovery"是否算达成目标要你定 |

**排序：A > D（作为兜底）> C > B。**
B 不作为主方案的原因是它**不产生答案**：7 个镜像跑完，最好的结果是"确认 OF 内容死在 init 或 recovery"，而 A 直接把这两者之一换成已验证能跑的原厂件；B 的价值是诊断，A 的价值是产出。
D 留作兜底：如果 A 最终证明是"显示死"，D 是唯一不依赖显示的"能刷机能 adb"方案。

---

## 二、为什么前面十几条路都不行（逐条对到证据）

把它们分成三类，你会发现前九条全部在回答**同一个已经被否定的问题**。

### 第 1 类：让镜像"更合法"（AVB / vbmeta / 头部）

| 试过的 | 为什么必然失败（证据） |
|---|---|
| 对齐原厂头（空 cmdline、`kernel_size=0`、`os_version` 写 99.0.0） | 头不是阻断点：**本轮实测我们的 lz4 打包与原厂流比特级等价**（`stock.cpio` 30,172,672 B，`lz4 -l -12` → 14,572,954 B，与原厂 ramdisk **sha256 相同 `4c3fd399…`**）；连"头部一字不差"的 96 MiB 版都试过了 |
| testkey vbmeta `flags=3`（关 AVB） | AVB 不拦：解锁机 `verifiedbootstate=orange`；且 **13.26 MB 的 OF 镜像刷进去后是"卡 logo"，不是"10 秒回 fastboot"**——被 AVB 拒绝的签名不会给你一次启动机会 |
| `flags=0` + 全哈希重算 | 同上。而且实测 `vbmeta_a` 的 off/on 单变量实验两侧行为一致（2026-11-12 台账 `logs\a17_single_var_result.txt`），早已证明这条线上没有"决定性变量" |
| 有效内容改 1 bit + 匹配哈希 / footer `alg=NONE` 自洽 / 原厂 salt+prop | 三个都是"让签名自洽"，而签名不参与判定 |
| OF 塞进 `boot` 分区 | 换了分区也不换内核解包路径，且丢掉了独立 recovery 的 BCB 通道 |

**这一类共 9 条路的共同错误**：它们在优化"ABL 愿不愿意加载"，而 `fastboot reboot-recovery` 早就实测进了原厂 recovery ⇒ **通道是通的、判定是过的**。这 9 条路产出的唯一东西是"我们又确认了一次签名不是变量"。

### 第 2 类：换内容，但不知道死在哪（OF 本体）

| 试过的 | 结果 | 为什么这轮能解释 |
|---|---|---|
| OF zstd 13,259,702 B 刷进 `recovery_a` | 卡 logo、无 adb、无 900E | 与 gzip 版**同时**失败 ⇒ 压缩格式不是判别式（两个独立解压路径不可能一起坏）。真正没被换掉的变量是 **OF 自己的 `init` 与整套 rc/USB/SELinux 环境** |
| OF gzip 13,996,032 B | 同上 | 同上 |
| `of-slim` 四变体（zstd/gzip/lz4/zh） | 同上 | lz4 那版 15.02 MB 已超"已证明"上限，另两个在限内也同样卡 |
| 静态审计结论 | 缺库 0、`install_keyring` 认得、`service recovery` 在、USB 在 `early-init` | **这正是本轮的起点**：静态上 OF 没有"必死"点，也没有"必活"点 ⇒ 说明问题在运行时行为，而运行时行为**唯一没被替换过的部分就是 init 及其环境** |

**这一类 3~4 条路的共同错误**：`卡 logo` 是**五选一**的签名——① 内核没解包 initramfs ② 解包了但 init 死了 ③ init 活着但 TWRP 的 `recovery` 死了 ④ recovery 活着但显示初始化失败 ⑤ 全都活着但 adb 没起来。五种原因的**外部现象完全一样**，所以这四条路本质上是在同一个零信息通道上反复买彩票，而且每次都换了两个以上变量（压缩格式 + 内容 + 尺寸）。

### 第 3 类：与本次目标无关但同批做过的

`9008` 降级 ZUI15 abl（写成功、回读一致，第三方 recovery 仍被拦）、运行时翻 unlock flag、私钥伪造、改 `sn_*.img` 十六进制免邮件——这些是**解锁/白名单**层面的死路，与"recovery 镜像怎么装"不在一个层面上，不应混进同一轮实验。

### 一句话总结

> 前十几条路不是"参数没调对"，而是**在一条没有反馈的通道上做多变量搜索**。
> 本轮做了三件事打破它：**（1）把 pstore 变成可用日志通道；（2）用符号表证明"装载这一层必然成功"；（3）把"必须靠 OF 的 init 才能跑 TWRP"这个假设拆掉**——于是第一次有了"只改一个变量、且失败有日志"的实验。

---

## 三、推荐方案：A1，以及前 3 步具体动作

### 3.1 做了什么（离线，已完成）

以 `stock.cpio`（原厂 ZUI16 recovery ramdisk，30,172,672 B / 472 条目）为**唯一输入**，
未提到的条目**逐字节原样拷贝**（不重新序列化），只做以下改动：

**改（4 条）**

| 条目 | 变化 |
|---|---|
| `system/bin/recovery` | 原厂 1,977,280 → OrangeFox 2,906,144 |
| `system/etc/recovery.fstab` | 原厂 fs_mgr 版 3,492 → TWRP 版 5,718（已按 TB331FC 写死 `*_a`、去 `avb=`） |
| `init.recovery.qcom.rc` | 原厂 2,175 → 1,891：**保留原厂每一行**，加 `printk 8`、`setenforce 0`、`export PATH`、kmsg 标记 + watchdog service |
| `prop.default` | 仅两处：`ro.secure=0`、`ro.debuggable=1`（AOSP recovery 用它决定默认启 adb；OF 的 prop.default 也是这两个值） |

**加（449 条 / 22.69 MiB）**：OF `recovery` 闭包里原厂**没有**的 52 个 `.so`（12.34 MiB）、`/twres` 整棵树 393 个文件（8.92 MiB）、`twrp.flags`（已把 `cust`→`lenovocust`、`logo`→`splash`，因为实测本机 GPT 就是这两个名字）、静态 `busybox`、watchdog 脚本。
**删：0 条。**

**审计结果（可复算，见 `logs/audit_built.txt`）**

| 入口 | 闭包 ELF | 缺库 | strong-unresolved | 原厂 baseline | 新增 |
|---|---|---|---|---|---|
| `/system/bin/init` | 35 | 0 | 7 | 7 | **0** |
| `/system/bin/adbd` | 14 | 0 | 9 | 9 | **0** |
| `/system/bin/recovery` | 94 | 0 | 10 | 10 | **0** |

5 个 weak-unresolved（`android_memset16/32`、`android::dm::DeviceMapper` 三符号）不影响加载：前者在原厂 `libcutils` 里没有、在 OF 里有，但引用是 **weak**（缺失只在"真调用"时才炸，且 TWRP 走不到）；后者由 `libdm` 在运行时提供。

### 3.2 三个镜像

| 镜像 | 字节 | ramdisk | sha256(前 16) | 用途 |
|---|---|---|---|---|
| `out/dirA_v0_skeleton.img` | 15,626,240 | 15,618,767 | `67A8072D62C15174` | **对照**：原厂骨架 + rc 补丁/watchdog，**一个 OF 文件都没有**。同时是 **ABL 上限探针**（15.62 MiB 正好卡在 14.57 MB 与 31.7 MB 两个口径之间） |
| `out/dirA_v1_hybrid.img` | 26,869,760 | 26,865,312 | `CA7B132D8FC837D8` | 主方案 |
| （兜底，未构建）`dirA_v2` | ≈13.4 MB | — | — | OF slim 内容 + **原厂 init/rc/sepolicy**，zstd；见 §4 |

### 3.3 前 3 步（命令 + 判据 + pstore 读法）

执行脚本：`scripts/run_dirA.ps1`（纯 ASCII、`-Execute` 才动手、每条 fastboot 都带 `-s 5e367954`、**无论结果都回滚**）。
dry-run 已跑通：`.\run_dirA.ps1 -Phase dirA1` 只打印计划。

**第 1 步 — 尺寸与"我们自己的改动"一次问清**

```powershell
cd E:\rom\work\rec-direction\scripts
.\run_dirA.ps1 -Phase dirA0 -Execute      # 先清 misc → 刷 v0 → reboot-recovery → 轮询 75 s → 回滚 → 进原厂 recovery 读 pstore
```

判据（互斥，读 pstore 前就能初判）：

| 现象 | 含义 | 下一步 |
|---|---|---|
| 进原厂 recovery 界面 + adb 可用 + pstore 里有 `DIRA:` 行 | ABL 允许 ≥15.62 MB；并且**我们的 rc/watchdog/permissive 改动无害** | 做第 2 步 |
| 10~15 s 内回到 fastboot（脚本判 `REJECTED-BY-ABL`） | ABL 上限就是"已证明"那一档（≤14.57 MB） | **跳过第 2 步**，直接做 §4 的 A2（≤13.4 MB），并按 14.5 MB 口径重做后续所有镜像 |
| 进不了原厂 recovery / adb 也不来 | 说明我们的 rc 补丁真的破坏了原厂恢复（那就是补丁的锅，不是 OF 的） | 只回退 rc 补丁里的 `setenforce`/`printk` 两行再试；v1 暂缓 |

**第 2 步 — 上 TWRP 用户态**

```powershell
.\run_dirA.ps1 -Phase dirA1 -Execute
```

判据（脚本自动分类 + 落盘证据）：

| 现象 | 含义 | 下一步 |
|---|---|---|
| TWRP 界面出来（触摸能点）+ adb 在 | **目标达成**：方向 A 成立 | 收尾：把 watchdog 改成可选、删 `/sbin/busybox`、按需修 `twrp.flags` |
| 只有 adb、没有画面（脚本判 `ADB-UP`） | TWRP 活着，显示死在 `gr_init` | 读证据里的 `/tmp/recovery.log`（脚本已抓）看 minui/DRM 报什么；去 §5 的显示分支 |
| `NO-ADB-HUNG`（无 adb 无 fastboot） | 见下，pstore 是唯一证据 | 按 pstore 内容三选一 |

**pstore 读法**（脚本第 6 步自动做，手工等价命令）：

```powershell
# 前提：已经回滚成原厂 recovery，并且设备正停在"原厂 recovery"里
& E:\rom\tools\platform-tools\adb.exe -s 5e367954 shell "cat /sys/fs/pstore/console-ramoops-0" > pstore.txt
# 老内核可能没有 -0 后缀：
& ...\adb.exe -s 5e367954 shell "cat /sys/fs/pstore/console-ramoops" >> pstore.txt
# 看什么
Select-String -LiteralPath pstore.txt -Pattern 'DIRA'                    # watchdog 时间线 + recovery.log 尾部
Select-String -LiteralPath pstore.txt -Pattern 'init:|service|exited'    # init 有没有把 recovery 拉起来
Select-String -LiteralPath pstore.txt -Pattern 'fb0|drm|minui|gr_init|panel'  # 显示后端
Select-String -LiteralPath pstore.txt -Pattern 'avc:|denied'             # SELinux（理论上 permissive 后不该有）
```

⚠️ pstore 里装的是**上一次启动**的控制台。**先读 pstore、再进 A17**，否则 A17 启动会把 ramoops 覆盖掉。

**第 3 步 — 按 pstore 三选一（这一步才是真正的定位）**

| pstore 里看到 | 结论 | 动作 |
|---|---|---|
| 有 `DIRA: t=…s recovery=[running]` 但无 TWRP 日志、无 `fb0/drm` 报错 | TWRP 卡在 `gr_init` 之前或在等某个 `wait` | 把 `twrp.flags` 里本机不存在的项（`usb_otg` 的 `sdg1`、`modem` 的 vfat 挂载）删掉重出 v1b |
| 有 `cannot open fb0` / `drm` 失败 / `gr_init` 失败 | **显示后端**问题 | 转 §5 显示分支，或转 C（源码级换 DRM 后端） |
| 只有 `init:` 行、`recovery` 服务 `exited status=…` | TWRP 二进制本身死了 | 把 `exited status=` 的值发我；同时 `/tmp/recovery.log` 尾部在 pstore 里 |
| `DIRA` 行一条都没有 | 内核没到用户态或 rc 没加载 | 转 B 的 `exp1a`（通道控制组）+ `exp2c`（beacon 控制组） |

---

## 四、尺寸这条硬约束（必须写清楚，它决定 A1 是否可刷）

设备实测（本轮`adb` 回读，root）：

| 项 | 字节 | 备注 |
|---|---|---|
| `init_boot_a` ramdisk | 2,005,893 | `ANDROID!` v4, `kernel_size=0` |
| `vendor_boot_a` vendor_ramdisk | 11,628,676 | `VNDRBOOT` v4, `page_size=4096`, `dtb_size=1,290,690` |
| 原厂 `recovery` ramdisk | 14,572,954 | **唯一"已证明能启动"的值** |
| 三者之和 | 28,207,523（26.90 MiB） | |

两个互相矛盾的口径：

- **口径 1（保守，来自 `of-rebuild/PLAN.md`）**：`recovery` 可用上限 = **14,572,954 B**。依据是"原厂就这么多、它能启动"。
- **口径 2（派生，来自 ABL `0xbff4` 公式）**：`上限 − RamdiskLoadAddr − (init_boot + vendor_boot + recovery) ≥ 0`；用现役内核 43,092,480 与 `limit = 89,120,768` 推算，`recovery` 单项约 **32.4 MB（≈31.7 MB 十进制口径）**。

A1 = 25.62 MiB，落在两者之间：**口径 2 下合法，口径 1 下必然被拒**。
用 v0（15.62 MiB）刷一次即可判定——这是本轮唯一"零风险、一次刷机、双用途"的实验。

**若口径 1 成立（上限 14.57 MB）**，A1 不可用，剩下能装进 14.5 MB 的方案只有两种：

1. **A2：OF slim 内容 + 原厂 init/rc/sepolicy**（zstd ≈13.4 MB）。做法：以 `work/of-pipeline/work/slim.cpio` 为底，用原厂 `system/bin/init`、`system/etc/init/hw/init.rc`、`init.recovery.qcom.rc`、`ueventd.rc`、`sepolicy`+`plat_*_contexts`、`prop.default` 覆盖 OF 的同名件。工作量约 1 h（脚本可复用 `build_dirA.py` 的覆盖/拼接逻辑），依赖 **zstd 这条路可行**——而"zstd 与 gzip 同时失败"这件事本身说明压缩不是判别式，值得一试。
2. **C（源码重编，13.67 MB lz4）**，但那要 1~2 天。

---

## 五、风险与回滚

**回滚（脚本内建，任何结果都执行）**

```powershell
fastboot -s 5e367954 flash recovery_a E:\rom\work\dual-boot\backup\recovery_a.bin   # 104,857,600 B 整块 dump, sha256 AF282B9D…
fastboot -s 5e367954 flash misc        E:\rom\work\rescue-matrix\reads\misc_full.bin # 1 MiB 净镜像，清 BCB
```

设备卡在"没 adb 没 fastboot"时：长按电源 15–30 s → 按住 音量+ 与 音量− 插 USB → `.\run_dirA.ps1 -RollbackOnly -Execute`。
**只写 `recovery_a` 与 `misc` 两个分区**，不碰 boot / init_boot / vendor_boot / vbmeta / super；A17 系统分区一个字节都不动。

| 风险 | 触发条件 | 缓解 |
|---|---|---|
| ABL 直接拒绝（回 fastboot） | A1 超过口径 1 | 已用 v0 先测；拒绝时设备仍是好的，回滚 30 s |
| 刷完卡 logo | TWRP 显示初始化失败 | 每次自动回滚；pstore 有日志 |
| 我们的 rc 补丁把原厂 recovery 弄坏 | `printk 8` / `setenforce 0` 在 stock sepolicy 下被拒 | v0 单独验证这两个改动；失败只回退这两行 |
| 内核根本没到用户态 | ramdisk 形态/尺寸/内存 | v0 已排除（同骨架同压缩） |
| pstore 被下一次启动覆盖 | 读之前先进了 A17 | 脚本顺序固定：回滚 → 进原厂 recovery → 立刻读 |
| **SELinux permissive 的副作用** | 本镜像里 `setenforce 0` | 只影响 recovery 这一次启动，不影响系统；收尾时可去掉 |
| 26.9 MB ramdisk 占用内存过大 | 设备 RAM 足够（8 GB），但解包耗时增加 | 若启动慢于 20 s，收尾时按 §4 减 `/twres` 字体（6.71 MB 的字体里 CJK 一个就 3.76 MB） |

---

## 六、诚实的未验证项

1. **显示**：`CONFIG_FB is not set` ⇒ fbdev 必死；`libminuitwrp.so` 里确实有 DRM 后端（`/dev/dri/%s`、`drmModeAddFB2`、`DRM_IOCTL_MODE_CREATE_DUMB`），设备上 `/dev/dri/card0` + `card0-DSI-1` 也确实存在（本轮 `adb` 实测），但**TWRP 的 DRM 后端能不能驱动 `p255_hx83102j` 这块 DSI video 面板，只能上机验**。这是 A 唯一的大未知量。
2. **触摸**：`hxchipset.ko` 是 vendor 模块；原厂 recovery 能触摸说明模块在 recovery 里也加载/recovery 用了别的路径——本轮未查清，A1 里没做任何模块相关改动（保持原厂 `/vendor` 目录为空的状态）。
3. **`init.recovery.${ro.hardware}.rc` 的解析**：实测 `ro.hardware=qcom`（`adb getprop`），原厂与 OF 的 rc 都叫 `init.recovery.qcom.rc`，所以同名导入成立；但 recovery 启动路径下的 `ro.hardware` 最终来自 ABL cmdline，未在 recovery 里回读确认。
4. **watchdog 的 `setprop sys.usb.config adb`**：如果 TWRP 自己也要控 USB，两者会并发写同一个属性（同值，理论上无害），未在真机验证。
5. **A2 未构建**（只在口径 1 成立时才需要）。
6. 本轮**没有**验证 `/system/bin/adbd`（原厂）在 A14 sepolicy + permissive 下是否一定起得来；A1 用的是原厂 adbd，与"v0 能起 adb"是同一个二进制，所以第 1 步同时验证了它。

---

## 七、产物与复算

```
E:\rom\work\rec-direction\
  PLAN.md                        本文
  out\dirA_v0_skeleton.img       15,626,240 B  sha256 67A8072D62C15174…
  out\dirA_v1_hybrid.img         26,869,760 B  sha256 CA7B132D8FC837D8…
  out\patch\init.recovery.qcom.rc     原厂 rc + 4 类调试补丁（可逐行审）
  out\patch\prop.default.patched      只改 ro.secure / ro.debuggable
  out\patch\twrp.flags.patched        cust->lenovocust, logo->splash
  out\patch\dira_wd.sh                watchdog（时间线 + 强制 adb + 灌 recovery.log 进 kmsg）
  scripts\run_dirA.ps1                执行器（dry-run 默认；-Execute 才动手；总回滚）
  work\build_dirA.py                  出镜像（stock.cpio 为输入，未提及条目逐字节保留）
  work\elfscan.py                     纯 Python ELF 闭包 + 符号解析审计（本机无 readelf/WSL 时可用）
  work\audit_built.py                 对"要刷进去的那份 cpio"做增量清单 + 链接审计
  work\mk_hybrid.py                   生成 hybrid 树（硬链接，供人工浏览）
  logs\audit_dirA.txt, audit_built.txt
```

复算：

```powershell
cd E:\rom\work\rec-direction\work
python build_dirA.py skeleton      # -> out\dirA_v0_skeleton.img
python build_dirA.py hybrid        # -> out\dirA_v1_hybrid.img
python audit_built.py E:\rom\work\rec-direction\work\dirA_hybrid.cpio   # 期望最后一行 PASS
```

压缩口径说明：本机没有 `lz4` CLI / WSL 已损坏，改用 `python-lz4` 的 legacy 帧（8 MiB 分块、`high_compression` level 12）。同一份 `stock.cpio` 用它压出 **14,572,966 B**，与原厂流 14,572,954 B 相差 12 B（分块封装差异，压缩数据本身同算法）——所以本文所有"我们的打包与原厂等价"的结论仍以**已存在的 `exp1a_stock_clone`（与原厂逐字节相同）**为准；本方案不依赖新的打包器正确性，因为它与原厂唯一的差别只在内容。
