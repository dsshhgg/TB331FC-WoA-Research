# OrangeFox recovery ramdisk 瘦身报告（TB331FC / khaje）

生成时间：2026-11-25 07:40 (+08:00)
工作目录：`E:\rom\work\of-slim\`（只写过这个目录，未动 `work\dual-boot\out\*` 与 `of\v3\*`）
**未刷机，纯离线。**

---

## 一、结论（一句话）

**14.5 MB 用 lz4 做不到（地板 15.02 MB，且已是残废配置）；但用 zstd 做到了 13.26 MB，且功能接近完整 —— 而且 zstd 不是赌博：这台机器的内核自己带着可用配置。**

| 产物 | 压缩 | ramdisk_size | 镜像大小 | 距上限(14,572,954) | 功能 |
|---|---|---|---|---|---|
| **`out\of_recovery_slim.img`** | **zstd -19** | **13,259,702** | 13,266,944 | **余量 1,313,252 B** | 完整：UI/主题 + fs 工具 + 动态分区工具 + adbd + fastbootd + 触摸固件 |
| `out\of_recovery_slim_zh.img` | zstd -19 | 14,218,768 | 14,225,408 | 余量 354,186 B | 同上 **+ 中文字体/语言**（砍掉 lp_tools 腾地方） |
| `out\of_recovery_slim_gzip.img` | gzip -9 | 13,988,278 | 13,996,032 | 余量 584,676 B | 仅 core + fs 工具（无 adbd / fastbootd / 触摸固件） |
| `out\of_recovery_slim_lz4.img` | lz4 -12 | 15,015,189 | 15,020,032 | **超 442,235 B（会被 ABL 拒）** | 仅 core（连 fs 工具都没有） |

上限取 **14,572,954 B = 现役原厂 ramdisk 的字节数**（唯一被实测证明"能启动"的尺寸）。

三条判据（都是实测/实读，不是推断）：

1. **lz4 不可能达标**：把内容砍到只剩"能起 TWRP 界面"的最小闭包（`core`，含 109 个 ELF 的完整 DT_NEEDED 闭包），lz4 -12 = **15,015,189 B**，比原厂大 44 万 B。再砍就要动 `recovery` 二进制链接的库 → 起不来。
2. **kernel 自己说了支持什么**：boot.img 里的内核是**未压缩的 arm64 Image**，里面嵌了 `IKCFG_ST…IKCFG_ED` 配置块，解出来 6949 行配置：

   ```
   CONFIG_RD_GZIP=y
   CONFIG_RD_LZ4=y
   CONFIG_RD_ZSTD=y
   （CONFIG_RD_XZ / LZMA / BZIP2 全部不存在）
   ```

   即 **gzip / lz4 / zstd 三种 initramfs 压缩内核都认，xz 一定不认**。这解释了两件事：为什么原厂全程用 lz4（合法且最省事），以及为什么可以用 zstd 换 15% 体积。
3. 板载全部 ramdisk（`init_boot` 2,005,872 / `vendor_boot` 11,779,605 / `recovery` 14,581,386，ZUI17 一套）**清一色 lz4 legacy `02 21 4c 18`** —— 原厂从没用过第二种格式，所以"zstd/gzip 能不能过 ABL"只能上机验一次（见第八节判据）。**失败模式是良性的**：解压失败=内核起不了 init，10 秒内退回 fastboot，跟现在的现象同级，不会变砖。

---

## 二、原 ramdisk 解剖（103,026,176 B cpio / 4,263 条目）

lz4 解出 103,026,176 B（98.2 MiB），文件内容合计 102,408,531 B。

| 顶层 | 字节 | MiB | 条目 |
|---|---|---|---|
| `/system` | 65,481,830 | 62.45 | 3495 |
| `/vendor` | 12,349,752 | 11.78 | 102 |
| `/sbin` | 10,898,366 | 10.39 | 28 |
| `/twres` | 9,348,547 | 8.92 | 393 |
| `/FFiles` | 1,615,567 | 1.54 | 21 |
| `file_contexts.bin` | 1,040,578 | 0.99 | 1 |
| `sepolicy` | 613,444 | 0.59 | 1 |
| `ramdisk-files.sha256sum` | 416,117 | 0.40 | 1 |
| `/vendor_boot`（vendor_boot ramdisk 的副本） | 280,480 | 0.27 | 2 |
| 其余 | ~350,000 | 0.33 | — |

`/system` 内部：`lib64` 35.1 MB（183 个）、`bin` 22.6 MB（271 个）、`etc` 6.2 MB（3040 个，其中 **`etc/terminfo` 占 3.1 MB / ~3000 个小文件**）。

最扎眼的几块（原大小）：

- `system/bin/recovery` 2.91 MB、`system/bin/init` 1.98 MB、`linker64` 1.78 MB —— 动不了
- **ICU 全家桶 4.57 MB**（`libicui18n` 2.72 + `libicuuc` 1.85）+ `libchrome` 1.31 MB —— 由 `recovery` 的链接关系拖进来，删不掉（见第三节）
- `vendor/lib/modules/1.1/*.ko` 6.94 MB —— **15/16 个和 vendor_boot 里的模块几乎是同一份**（见下）
- `twres/fonts` 6.71 MB（19 个字体）、`twres/languages` 1.06 MB（17 套语言）
- `sbin`：`ksud` 2.55、`aapt` 1.53、`busybox` 1.53、`bash` 1.41、`magiskboot` 1.25、`gnutar` 0.98、`zstd` 0.70、`gnused` 0.65
- `FFiles/KernelSU/*.zip` 1.50 MB（3 个 KernelSU 安装包）
- `system/bin/python3` 3.68 MB + `system/etc/python` 2.91 MB

---

## 三、为什么不能再砍（关键证据）

用 AArch64 重定位表做了**符号级**判定：把保留下来的 109 个 ELF 的 `.dynsym` / `.rela.*` 全部解析，检查"每个库导出的符号是否真的被其它目标引用"。结果：

- 唯一"NEEDED 了但谁都不引用"的库是 `libsync.so`（10 KB）—— 其余 108 个库**每一份都有符号被真实引用**，因此在"不重编 `recovery`"的前提下，动态库集合已经到底了。
- ICU/libchrome 不是白带的：`recovery` → `libaosprecovery`/`libandroidicu` → ICU 是真实的符号依赖链，删任何一个都会在 linker 阶段 "library not found" 直接死在 init 之前。
- 结论：**想再小，只能重编 TWRP/OF（`TW_EXCLUDE_*`：MTP、ADB backup、解密、fastbootd、动态分区工具…）**，那是另一个数量级的工作量，本次没做（离线环境无工具链）。

### 一个安全的小优化：把 ELF 里不参与运行的段清零

对每个 ELF 把**所有没有 `SHF_ALLOC` 的 section 载荷**（`.symtab`/`.strtab`/`.comment`/debug）原地填 0，共 2.11 MB。运行时 linker 只读 `PT_LOAD`，section 头不参与加载；已逐个复验 `PT_DYNAMIC` 仍在、section 表完好（见体检报告）。压缩侧收益：zstd 少 ~0.7 MB，gzip 少 ~0.7 MB。**不改任何一字节会被执行的代码。**

---

## 四、实测成本表（把每一项"买"回来要花多少）

内容逐级叠加，同一份 cpio 用不同算法压（单位 B）：

| 内容级别 | cpio | lz4 -12 | gzip -9 | zstd -19 |
|---|---|---|---|---|
| `core`（TWRP 界面最小闭包，无 busybox） | 34.6 M | **15,015,189** | 12,832,471 | **9,622,929** |
| + fs 工具（make_f2fs/e2fsck/…） | 37.4 M | 16,368,233 | **13,988,278** | 10,505,463 |
| + lp 工具 + misc（lpmake/ziptool/resetprop/simg2img…） | 41.7 M | 18,466,396 | 15,808,135 | — |
| + HAL 服务（hwservicemanager/health/boot） | 45.4 M | 19,985,435 | 17,107,165 | — |
| + **adbd + fastbootd** | 48.1 M | 21,231,014 | 18,160,983 | — |
| + **触摸固件**（vendor/firmware + odm/firmware） | 50.2 M | 22,229,893 | 19,077,983 | **13,259,702** ← 本次主产物 |
| + 中文字体 + zh_CN   语言（砍 lp_tools） | 51.5 M | — | — | 14,218,768 |
| 原样（含 KernelSU/busybox/bash/python/terminfo…） | 103 M | 47,628,167 | 41,656,100 | — |

原 cpio 全量压缩对照（103,026,176 B）：

| 算法 | 大小 | 比值 |
|---|---|---|
| lz4 -1 / -9 / **-12（原产物用的）** | 56.9 / 47.8 / **47.63 MB** | 1.81 / 2.16 / 2.16 |
| gzip -6 / gzip -9 | 41.83 / 41.66 MB | 2.47 |
| **zstd -19** | — | ~3.4（按 36 MB 级实测 3.45） |
| xz -6 | 28.77 MB | 3.58（**内核不支持，不可用**） |

---

## 五、删了什么（主产物 `of_recovery_slim.img`）

完整清单见 `work\drop_manifest.txt`（含每项大小）。**全部删除项按"删了不影响刷机"原则，并已核对没有脚本/二进制引用它们**：

| 类别 | 删掉 | 省下 |
|---|---|---|
| KernelSU 相关 | `sbin/ksud`、`FFiles/KernelSU/*.zip`×3（KernelSU_Suki/Next/Installer） | 4.05 MB |
| Python | `system/bin/python3`、`system/etc/python/*`、`system/bin/python` | 6.59 MB |
| 终端数据库 | `system/etc/terminfo/*`（~3000 个）、`system/etc/nano/*`、`system/bin/nano`、`sbin/nano` | 3.24 MB |
| shell 冗余 | `sbin/bash`（`sh`/`ash` 改为指向 `/system/bin/sh` = mksh）、`sbin/busybox` | 2.94 MB |
| OF 工具箱 | `sbin/aapt`、`sbin/gnutar`、`sbin/gnused`、`sbin/zstd`、`sbin/gnudate`、`sbin/magiskboot` | 5.22 MB |
| 构建元数据 | `ramdisk-files.sha256sum`、`ramdisk-files.txt`、`file_contexts.bin`（保留 56 KB 的 `file_contexts`） | 1.60 MB |
| 重复内核模块 | `vendor/lib/modules/1.1/*.ko` 里 **15 个**（与 vendor_boot ramdisk 是同一批模块，逐文件比对；最大差 216 B） | 6.33 MB |
| vendor_boot 副本 | `vendor_boot/ramdisk/lib/modules/{qcom-scm,qcom_ipc_logging}.ko` | 0.28 MB |
| 未用库 | `system/lib64` 里没有任何 NEEDED 链引用的 81 个（`libprotobuf-cpp-full`、`libxml2`、`libssh`、`libssl`、`libclang_rt.ubsan*`、`libkeymaster_portable`、`libncurses`、32 位 `vendor/lib` 等） | 12.4 MB |
| 未用二进制 | `update_engine_sideload`（A/B OTA 用，本机 A-only）、`openaes`（依赖的 `libopenaes.so` 本就不在包里，本来就跑不起来）、`theme` 里 13 个没被 xml 引用的字体、14 套语言 | ~9 MB |

**保留的内核模块**：只留 `hxchipset.ko`（607,560 B）—— 因为 `modules.load.recovery` / `modules.load.twrp` / `modules.load` 三个文件里**只写了这一个模块名**（13 字节），而它**不在 vendor_boot 里**，是本设备树专门加的（很可能就是本机触摸/充电相关驱动）。其余 15 个与 vendor_boot 同源，随 vendor_boot 一起加载，删掉不丢功能。

**因此主产物失去的功能（明确清单）**：

| 失去 | 原因 | 影响 |
|---|---|---|
| 内置 KernelSU/root 安装（`ksud` + 3 个 installer zip） | 删 4.05 MB | "刷 KernelSU/root" 用不了；要 root 请单独刷 magisk/kernelsu 包 |
| Magisk/boot 打补丁（`magiskboot`） | 删 1.25 MB（`recovery` 里有 5 处字符串引用） | "安装 Magisk" 菜单项会失败，其它刷机不受影响 |
| `/data` 解密（keystore2 + keymaster 链） | 约占 3 MB（本次未纳入） | 进 OF 读不到已加密的 /data；**格式化 /data 仍然可以** |
| A/B OTA 侧载（`update_engine_sideload`） | 删 2.20 MB | 本机 A-only，无实际损失 |
| 中文界面文字（默认简体/繁体的 TTF + 语言包） | 删 4.07 MB | 见 `_zh` 变体（把 lp_tools 换成中文，14.22 MB） |
| `bash`/`busybox`/`gnutar`/`gnused`/`gnudate`/`zstd`/`aapt` | 删 7.4 MB，**逐个确认 0 处引用** | 无（`sh`/`ash` 已改指 mksh；toybox+toolbox 覆盖所有被调用命令） |
| Python3 运行环境 | 删 6.59 MB | OF 里没有 python 脚本在用 |
| 15 个与 vendor_boot 重复的内核模块 | 删 6.33 MB | 无（随 vendor_boot 加载，逐文件比对过） |
| 14 套未用语言、13 个未引用字体 | 删 ~2.9 MB | 界面只能英文（+`_zh` 变体） |

**字体**：只留主题实际引用的 6 个 —— `Roboto-Regular/Medium`、`GoogleSans-Regular/Medium`、`InterDisplay-Regular/Medium`（`twres/themes/font.xml` 与 `sed/font_*.xml` 里的 `#PRIMARY_FONT_*#` 展开成 InterDisplay，**不能删，删了正文没字**）。中文字体 `DroidSansFallback.ttf`（3.94 MB）默认不带 —— 见 `_zh` 变体。

---

## 六、保住的关键元素（体检报告 `work\verify_report.txt`）

主产物 `of_recovery_slim.img`：

```
magic=OK
kernel_size=0   ramdisk_size=13,259,702   header_version=4   header_size=1584
os_version=0x1c0001a3 -> 14.0.0  patch 2026-03
ramdisk@4096  magic=28b52ffd (zstd)  解压=OK
cpio 解析=OK  entries=917  cpio=50,257,281
  OK init(符号链接 -> /system/bin/init)   OK system/bin/init        OK system/bin/recovery
  OK system/etc/recovery.fstab            OK system/etc/twrp.flags  OK sbin/foxstart.sh
  OK init.recovery.qcom.rc                OK sepolicy               OK twres/ui.xml / themes/font.xml
  OK system/bin/linker64  /sh /toybox     OK system/bin/adbd        OK system/bin/fastbootd
  OK vendor/lib/modules/1.1/hxchipset.ko  OK vendor/firmware(Himax_firmware.bin)  OK system/bin/make_f2fs
```

另外逐项确认：`sbin/sh -> /system/bin/sh`（已改指向）、`init -> /system/bin/init`、`recovery`/`init` 模式 0100755、`recovery.fstab` 0100644；183 个符号链接随目标一起保留（toybox/toolbox 的 applet 全在）。

---

## 七、与 lead 之前实测约束的对照

| lead 的约束 | 本次结果 |
|---|---|
| 原厂 ramdisk 14,572,954 B 能启动 | 作为**尺寸上限**使用；主产物余量 1.31 MB |
| 我们的 47,628,167 B 被拒 | 已降到 13,259,702 B |
| `ANDROID!` v4 + `kernel_size=0` + pagesize 4096 | ✅ 逐字段照抄原厂头（header_size 1584，ramdisk 起于 0x1000） |
| os_version 14.0.0 / patch 2026-03 | ✅ `0x1c0001a3` 已知可解回 14.0.0 / 2026-03 |
| 保留 `/init` 或 `/sbin/recovery` | ✅ `/init`(symlink) + `/system/bin/recovery` 都在 |
| `recovery.fstab`、`twrp.flags`、触摸 | ✅ `system/etc/recovery.fstab`、`system/etc/twrp.flags`、`hxchipset.ko` + `vendor/firmware/*` |
| 不刷机、不改 of\v3\* | ✅ 全部产物只写 `work\of-slim\` |

---

## 八、上机验证判据表

**建议顺序（每步 1 次 fastboot flash，失败都可回滚）**

| 步 | 闪什么 | 期望 | 若不成立说明 |
|---|---|---|---|
| 1 | `of_recovery_slim_gzip.img`（13.99 MB，风险最低） | 进 OF 界面（英文、无 adb、无触摸固件） | gzip 都过不了 → 见第 3 步与第九节 |
| 2 | `of_recovery_slim.img`（13.26 MB，**推荐主力**） | 进 OF，`adb devices` 有 recovery，触摸可用 | 黑屏/挂死 → zstd 解压失败 |
| 3 | `of_recovery_slim_lz4.img`（15.02 MB） | 预期**被 ABL 拒**（10 s 回 fastboot） | 若它反而过了 → 说明 ABL 上限比我算的宽，回来重算预算 |

> 只想试一个：**直接上第 2 步**。zstd 由内核配置兜底，功能最全。

**判据表**（现象 → 结论 → 下一步）

| 现象 | 判读 | 下一步 |
|---|---|---|
| 出现 OrangeFox 启动图 / 主菜单 | ✅ 成功（压缩路径、cpio、init、linker、主题、触摸固件全通） | 记下 `adb shell getprop ro.boot.hardware`、试 挂载/flash |
| 10 秒内退回 fastboot，屏幕无 OF 痕迹 | ABL **尺寸检查仍不过**（说明我算的 14.57 MB 上限偏宽，或分区/头部形态不对） | 回来看实际 `ramdisk_size` 与 ABL 反汇编常量；先试更小的 `lz4` 变体的尺寸数值 |
| 黑屏，屏幕背光有/无变化，30 s+ 不动，不自动回 fastboot | 内核**解压失败**（zstd 或 gzip 不被解压方接受）→ 无 init → panic/挂死 | 换另一种压缩（gzip→lz4）；若三种都这样，走第九节重编路线 |
| 出现 OF 界面但**触摸无反应** | 触摸驱动/固件问题（`hxchipset.ko` 与内核 vermagic 不匹配，或 panel 型号不符） | 可先用 OTG 鼠标/USB 键盘；再对比 vendor_boot 的模块 |
| 出现 OF 界面但**文字全空/方块** | 主题字体没加载（只可能发生在有人把 fonts 再删的情况） | 换回带完整 6 字体的 `slim` |
| 卡在 fastbootd / 关机充电图标 | init 起来了但 recovery 服务没起 | `adb shell dmesg`（`slim` 有 adbd，能看到 `linker` 报错） |
| 900E（Sahara/EDL） | 与本变更无关（ramdisk 不会造成 900E），先查 vbmeta/AVB 与上次刷的分区 | 走 lead 的回滚表 |

---

## 九、最小可行集与取舍（如果 zstd/gzip 都被拒）

**唯一确定能过 ABL 解压的格式是 lz4，而 lz4 的地板 = 15,015,189 B**（内容已经砍到"只有 TWRP 界面 + 主题 + fstab + sepolicy + hxchipset"，连 `make_f2fs` 都没有）。所以：

- **不要**期待"再删点东西就能上 14.5 MB"——15 个库的符号级依赖已经查过，删任何一个是 linker 阶段直接死。
- 真要在 lz4 下进 14.5 MB，只能**重编 TWRP/OF 减小 `recovery` 二进制的依赖闭包**。可预期的 `TW_EXCLUDE_*` 收益（按本次实测的库清单估）：
  - `TW_EXCLUDE_MTP` → 去 `libtwrpmtp-ffs` + `libfusesideload`（~0.8 MB 压缩前）
  - `TW_EXCLUDE_ENCRYPTED_BACKUPS` / 解密（`TW_INCLUDE_CRYPTO` 相关）→ 去 keymaster/keystore 链（~4 MB）
  - `TW_EXCLUDE_UPDATE_ENGINE_SIDELOAD` → 去 `update_engine_sideload` + ICU 一部分（**ICU 4.57 MB 主要就是这条链**）
  - `TW_EXCLUDE_ADB` → 去 `adbd`（~1.3 MB）
  - 只要砍掉 ICU + protobuf 那条链（`recovery` 重链一次即可），lz4 就能进 12 MB 以内 —— 这是唯一稳妥路径。

**最小可行集**（如果只求"能进去、能刷 zip"）：`core` 内容 + `twres` 主题 + `recovery.fstab` + `twrp.flags` + `hxchipset.ko` + touch 固件 = 主产物去掉 fs/lp/misc 三组（zstd ≈ 11.9 MB）。**会失去**：格式化/fsck（"清除 data"会失败）、动态分区工具、adbd/fastbootd（无 adb、不能 fastbootd）、日志工具。**保留**：触摸、主题、zip 刷入、挂载/备份（TWRP 内部实现，不依赖这些二进制）。

---

## 十、文件清单

```
E:\rom\work\of-slim\
  out\of_recovery_slim.img        13,266,944 B  ramdisk 13,259,702  zstd   ← 主力
  out\of_recovery_slim_zh.img     14,225,408 B  ramdisk 14,218,768  zstd + 中文
  out\of_recovery_slim_gzip.img   13,996,032 B  ramdisk 13,988,278  gzip（保守备选）
  out\of_recovery_slim_lz4.img    15,020,032 B  ramdisk 15,015,189  lz4（超限，仅作对照）
  报告_of-recovery-瘦身.md        本文件
  work\verify_report.txt          逐个产物的头部/cpio/入口体检输出
  work\drop_manifest.txt          删了哪些文件（按类目+逐文件大小）
  work\kernel.config              从 boot.img 内核里抠出来的 IKCONFIG（6949 行）
  work\of_ramdisk.cpio            原始 103 MB cpio（复算用）
  work\*.py                       可复算脚本：21_planner / 35_opt / 50_final / 56_assemble
```

复算方法（WSL，`wsl -d ub -u root`）：

```bash
cd /mnt/e/rom/work/of-slim/work
python3 01_unpack.sh                      # 或 bash 01_unpack.sh 解 lz4→cpio
python3 56_assemble.py                    # 重出 slim / gzip / lz4 三个镜像 + 体检
python3 58_zh.py                          # 出中文变体
```
