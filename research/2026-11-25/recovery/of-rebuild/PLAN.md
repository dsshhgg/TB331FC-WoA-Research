# 用源码重编一个「能进 14.5 MB」的 TWRP / OrangeFox

> 设备：联想小新 Pad 2024 **TB331FC**（`khaje` / SM6225-AD / A/B + **独立 recovery 分区** / Himax HX83102J 1200×1920 / **无 `CONFIG_FB`**）
> 硬约束（ABL 反汇编 `0xbff4`）：`(上限 − RamdiskLoadAddr) − (init_boot + vendor_boot + recovery 三段 ramdisk 之和) ≥ 0`；
> 现役能启动的原厂 `recovery.img` 给出 **`ramdisk_size = 14,572,954 B`** 这条可用上限。
> 现状：现成 OF ramdisk 已到拼装极限 —— lz4 地板 15,015,189 B（超 442,235），zstd 13,259,702 B（尺寸过、init 卡住）。
> 本文只出方案，**不执行 repo sync**。2026-11-25。
> 证据标注：**【实测】**= 本轮在本机字节级/在盘上真机镜像上实测 ·**【源码】**= TWRP 12.1 上游构建文件原文（本轮经 GitHub API 取回，存 `ref/`）·**【估算】**= 公式外推且已标出。

---

## 0. 一页结论

### 0.1 数字

| 问题 | 答案 |
|---|---|
| 重编后 ramdisk 能到多少？ | **lz4：11.8 MB（极简）～ 14.40 MB（全功能，余 0.17 MB）；推荐档 13.67 MB（余 0.91 MB）**。gzip 同一配置 **11.70 MB**。zstd **8.26 MB**。全部 13 档实测见 §3 |
| 达标要开哪些开关 | ① `TW_INCLUDE_CRYPTO := false` ② `TW_EXCLUDE_MTP := true` ③ 不装 fastbootd / update_engine\* / Python / AROMAFM / 多余字体与语言；④ lp_tools 里**去掉 `lpdumpd`**（它一个人拖 2.41 MB） |
| 最关键的 3 个开关 | ① **`TW_INCLUDE_CRYPTO := false` → −4,485,464 B lz4（占总收益 85 %）** ② **`TW_INCLUDE_FASTBOOTD := false` + device.mk 删 `fastbootd`（−739,520）** ③ **`TW_EXCLUDE_MTP := true`（−124,141）** |
| 最反直觉的一条 | **ICU 4.60 MB 与 libchrome 1.31 MB 不是「删不掉」，而是「由 `TW_INCLUDE_CRYPTO` 引进来的」。** `of-slim` 报告 §三 的「删不掉」只在「不重编、直接删文件」前提下成立（§1.3） |
| 最容易白扔的 2.41 MB | 动态分区工具里的 **`lpdumpd`（本体仅 31,424 B）→ `liblpdump.so` → `libprotobuf-cpp-full.so` 2,252,984 B**。砍它一个等于白送 0.93 MB lz4（§2.2） |

### 0.2 先做这两件「零编译」的事（比重编便宜 100 倍）

| 顺序 | 动作 | 依据 | 预期 |
|---|---|---|---|
| **1** | 刷盘上已有的 **`of-slim/out/of_recovery_slim_gzip.img`（13,996,032 B，ramdisk 13,988,278）** | gzip 由内核兜底（`CONFIG_RD_GZIP=y`，IKCONFIG 6949 行实测）；ABL 只查尺寸、解压方是内核，与 zstd 是**两条独立路径** | 尺寸已在限内，**直接回答「卡住是不是压缩格式问题」** |
| **2** | 若还是卡住：把 `init_boot_a/b` 刷成**空 cpio（8,192 B）** 再试同一个镜像 | 原厂 `init_boot` ramdisk = **2,005,893 B**（【实测】`work/40_bootimg_sizes.py`）。若 `0xbff4` 的三段求和成立，recovery 额度 1:1 增加 | recovery 上限抬到 **≈16.58 MB**，连现在的 15,015,189 B lz4 也能过尺寸检查 |

只有这两步都失败，才值得投入 §4/§5 的重编。

---

## 1. 体积从哪来：ramdisk 内容 = `recovery` 的 `DT_NEEDED` 闭包

### 1.1 方法与可复算资产

`work/of-slim/work/root/`（现成 OF ramdisk 原样解包，4,263 条目，331 个 ELF）是本轮全部分析的输入。

| 脚本 | 作用 | 产出 |
|---|---|---|
| `work/10_needed_graph.py` | 解析 331 个 ELF 的 `PT_DYNAMIC`/`DT_NEEDED`，建正反向依赖图；已用 `readelf -d` 抽查（`libtar.so` / `recovery` 逐条对齐） | `needed_graph.txt`、`reverse_deps.txt` |
| `work/30_price.py` | 「边际闭包」定价：去掉某二进制/库组后 ramdisk 少多少字节（共享库不重复计） | `price_table.md` |
| `work/20_scenarios.py` | 真打 newc cpio（含非 ALLOC section 清零）+ `lz4 -l -12` / `gzip -9` / `zstd -19` 压缩，逐档实测 | `scenarios.json` |
| `work/31_delta.py` `34_fs_tools.py` `35_diff_groups.py` `36_forced.py` | 开关表与实测 Δ 的对账、工具组逐二进制定价、强制模块定价 | 控制台 |
| `work/33_check_pack.py` | 打包器自检（`sum(成员 size) == sum(data) == 期望`） | 通过 |

复算一条命令：`wsl -d ub -u root -- bash -lc "cd /mnt/e/rom/work/of-rebuild/work && python3 10_needed_graph.py && python3 30_price.py && python3 20_scenarios.py"`

### 1.2 现成 ramdisk 的依赖账（【实测】）

`recovery` 直接 `NEEDED` 55 个库，闭包 109 个 ELF / 24,481,688 B；`init` 33 个 / 8,644,344 B。最大的几块及**谁把它们拖进来**：

| 库 | 字节 | 实际引入者（反向图实测） | 由哪个开关控制 |
|---|---:|---|---|
| `libicui18n`+`libicuuc`+`libandroidicu` | **4,599,488** | `recovery`→`libandroidicu`；`libsqlite`→`libandroidicu` | `TW_INCLUDE_CRYPTO`（Android.mk L344） |
| `libchrome` | **1,309,920** | `libtar`→`libchrome`、`keystore_cli_v2` | `TW_INCLUDE_CRYPTO_FBE`（`libtar/Android.mk` L54） |
| `libsqlite` | 1,155,704 | `recovery`（crypto 块的 `libsqlite.recovery`） | `TW_INCLUDE_CRYPTO`（L352） |
| `libcrypto`(BoringSSL) | 1,228,216 | init/toybox/recovery 都有 | **必留** |
| `libhidlbase` | 753,904 | `recovery`（L83 无条件） | **必留** |
| `libbinder`+`_ndk`+`libhwbinder` | 706,272 | `recovery`/`libtar`/`libminuitwrp` | `TW_INCLUDE_CRYPTO`（L343）+FBE 块 |
| keymaster/keystore2 20 个 AIDL+HIDL 库 | 2,004,024 | `recovery`/`libtar`/`keystore2` | `TW_INCLUDE_CRYPTO`+FBE 块 |
| `libprotobuf-cpp-lite` | 486,536 | `recovery`（L83 无条件） | **必留** |
| **`libprotobuf-cpp-full`** | **2,252,984** | **只有 `lpdumpd`→`liblpdump.so`→它** | **只要不装 `lpdumpd` 就没有** |
| `libft2`+`libpng` | 841,888 | `libminuitwrp`（主题字体渲染） | 只能砍主题（不建议） |
| `libevent` | 312,512 | `libchrome` | 随 libchrome 走 |
| `libunwindstack` | 534,656 | `libbacktrace`←`init` | **必留** |
| `libtwrpmtp-ffs` | 265,080 | `recovery` | `TW_EXCLUDE_MTP` |
| `libtwadbbu` | 62,136 | `recovery`/`bu` | 见 §2.4 反向坑 |

### 1.3 关键更正：ICU / libchrome 是「开关问题」，不是「删不掉」

`of-slim` 报告 §三 用符号级分析证明「ICU 每份都有符号被真实引用，删任何一个 linker 直接死」——**结论对，但只在「不重编」的前提下成立**。【源码】原文：

```make
# bootable/recovery/Android.mk（twrp-12.1，L335-356）
ifeq ($(TW_INCLUDE_CRYPTO), true)
    LOCAL_SHARED_LIBRARIES += libgpt_twrp android.frameworks.stats@1.0 \
        android.hardware.authsecret@1.0 android.security.authorization-ndk_platform \
        android.hardware.oemlock@1.0 libf2fs_sparseblock libbinder libbinder_ndk \
        libandroidicu.recovery \            # ← ICU 三件（4.60 MB）从这里进来
        android.hardware.gatekeeper@1.0 android.hardware.weaver@1.0 \
        android.security.maintenance-ndk_platform \
        android.system.keystore2-V1-ndk_platform libkeyutils liblog \
        libsqlite.recovery \                # ← libsqlite
        libkeystoreinfo.recovery libgatekeeper_aidl
    LOCAL_STATIC_LIBRARIES += libkeymint_support
    TW_INCLUDE_CRYPTO_FBE := true           # ← 顺手把 FBE 也打开
endif

# bootable/recovery/libtar/Android.mk（L16-56）
ifeq ($(TW_INCLUDE_CRYPTO_FBE), true)
    LOCAL_SHARED_LIBRARIES += android.hardware.keymaster@3.0/@4.0/@4.1 ... \
        libkeymaster4support libkeymaster4_1support libkeymint_support \
        libkeystoreinfo libkeystore-attestation-application-id \
        libhwbinder libchrome               # ← libchrome（1.31 MB）从这一行进来
endif
```

反向图还显示：**`libtar` 的 FBE 块把 40 个库全列成了 NEEDED**（连 `libchrome` 都在）。所以任何「在 libtar 之外做手术」的瘦身对 libchrome 都无效——**必须从 `TW_INCLUDE_CRYPTO_FBE` 这个开关下手**，而它由 `TW_INCLUDE_CRYPTO` 自动打开。

一次关掉的净成本（【实测】闭包差分）：**未压缩 10,436,696 B / lz4 4,485,464 B**。

---

## 2. 开关收益表（字节）

口径：「未压缩」= 解开 ramdisk 后 `.so`/二进制的字节和；「lz4 Δ」= §3 harness 里关掉该开关后 `ramdisk_size` 的实测变化。
> 压缩比不是一个常数：**库类 ≈ 0.37–0.45，工具类二进制 ≈ 0.5–0.83**（e2fsprogs/f2fs-tools/ntfs-3g 几乎压不动）。表里能用实测就用实测。

### 2.1 三个决定性开关

| 开关 | 源码位置 | 砍掉什么 | 未压缩 | **lz4 Δ（实测）** | 代价 |
|---|---|---|---:|---:|---|
| **`TW_INCLUDE_CRYPTO := false`** | Android.mk L335-369 · libtar L16-65 · L554-571 | ICU 三件、libchrome+libevent、libsqlite、binder 三件、keymaster/keystore2 20 库、`keystore2` 二进制(闭包 3.48 MB)、`qseecomd`、`fscryptpolicyget`、keymint/gatekeeper/tui_comm 三个 vendor service、`libgpt_twrp`、`libf2fs_sparseblock` | **10,436,696** | **−4,485,464** | 读不到已加密 `/data`（**格式化仍可**）；本机 ZUI 的 keymaster 与 TWRP 绑定版本不匹配，解密本来就没成功过（GUIDE §6.4 #17） |
| **`TW_INCLUDE_FASTBOOTD := false`** + `PRODUCT_PACKAGES` 删 `fastbootd`、`android.hardware.fastboot@1.1-impl-mock` | Android.mk L456-458 只加 CFLAG；二进制来自 `PRODUCT_PACKAGES` | `fastbootd` 1,244,448 + `android.hardware.fastboot@1.0/1.1` 205,072 + `libasyncio` | 1,459,936 | **−739,520**（P7↔P6 实测） | 不能在 recovery 里进 fastbootd（系统侧 `adb reboot fastboot` 仍在） |
| **`TW_EXCLUDE_MTP := true`** | Android.mk L224-226、L236-238 | `libtwrpmtp-ffs`，去掉 `-DTW_HAS_MTP` | 265,080 | **−124,141** | 无 USB 存储挂载；`adb push/pull` 仍可用 |

### 2.2 「白送」的一刀：`lpdumpd`

| 动作 | 砍掉什么 | 未压缩 | lz4 Δ（实测） | 代价 |
|---|---|---:|---:|---|
| 不装 `lpdumpd`（和 `dmuserd`） | `lpdumpd` 31,424 → `liblpdump.so` 161,440 → **`libprotobuf-cpp-full.so` 2,252,984** | **2,414,424** | **−916,397**（N5→P2 实测） | 少一个「动态分区元数据守护进程」，`lpdump`/`lpmake`/`lpunpack`/`lpadd`/`lpflash` 全都还在 |

> 这是全表**性价比最高**的一条：删 31 KB 的守护进程，换回 2.41 MB。

### 2.3 中等收益（合计还能再挤 3～6 MB）

| 开关 / 动作 | 源码位置 | 砍掉什么 | 未压缩 | lz4 Δ | 代价 |
|---|---|---|---:|---:|---|
| **不装 `TW_INCLUDE_PYTHON`** | Android.mk L635-637 | `python3_twrp` + `system/etc/python` | 6,594,000【of-slim 实测】 | −~2,860,000【估算 ×0.43】 | OF 里没有 python 脚本在用（of-slim 已逐处确认 0 引用）。**从 topaz 抄 BoardConfig 会默认继承，是本机最贵的单行** |
| 不装 `nano`/`bash`/`tzdata`/`vim`/`htop`/`lsof`/`openvpn`/`powertop` | Android.mk L515-531；**`vendor/twrp/config/packages.mk`（默认就带）** | nano 全家、bash、tzdata、vim 等 | 2,940,000【of-slim】 | −~1,270,000【估算 ×0.43】 | 终端只剩 mksh/toybox |
| `FOX_DELETE_AROMAFM := 1` / `FOX_DISABLE_APP_MANAGER := 1` | OrangeFox 变量（GUIDE §3.4） | AromaFM、OF 应用管理器 | ~1,500,000 | −~650,000【估算】 | 两个 GUI 工具没了，刷 zip 不受影响 |
| 字体只留主题引用的 6 个、语言只留 `en.xml` | `twres/fonts`、`twres/languages` | 13 个未引用字体 + 14 套语言 | 3,900,000【of-slim】 | −~1,690,000【估算 ×0.43】 | 英文界面；中文见 §3.4 |
| `file_contexts` 用文本版（56 KB）替代 `file_contexts.bin`（1.04 MB） | 构建产物 | context 二进制表 | 983,000【of-slim】 | −~426,000【估算】 | 无（TWRP 读文本版） |
| `TW_INCLUDE_REPACKTOOLS := false` | Android.mk L533-536 | `magiskboot` | 1,250,000【of-slim】 | −~540,000【估算】 | 「安装 Magisk / 重打包 boot」菜单项失效 |
| device.mk 删 `update_engine` `update_engine_sideload` `update_verifier` | 本机 `device.mk` L36-39 | OTA 侧载三件 | 2,203,208（`update_engine_sideload` 边际） | −~950,000【估算】 | 不能侧载官方 A/B OTA；`flashable zip`/`fastboot flash` 不受影响 |
| `TWRP_INCLUDE_LOGCAT := false` + `TARGET_USES_LOGD := false` | Android.mk L609-614 | `logcat`+`event-log-tags`+`logd`+`libsysutils`+`libnl` | 977,104 | −~420,000【估算】 | 没有 `logcat` 命令；`/tmp/recovery.log` 仍在 |
| 只装 `make_f2fs`+`fsck.f2fs` 而不是整组 fs 工具 | `PRODUCT_PACKAGES` | 相比整组省 `e2fsck/mke2fs/resize2fs/sload_f2fs/exfat/ntfs/fat` | 1,500,000 量级 | −1,145,808（P1 11.99 vs N4 13.13 实测） | 只能格式化 f2fs 的 /data；不能 format ext4/修 ext4 |

### 2.4 两个**反向**坑（照抄会变大）

1. **`TW_EXCLUDE_ENCRYPTED_BACKUPS` 的判断是反的**（Android.mk L400-404）：
   ```make
   ifneq ($(TW_EXCLUDE_ENCRYPTED_BACKUPS),)   # 非空
       LOCAL_SHARED_LIBRARIES += libopenaes     #   → 反而"加上"库
   else
       LOCAL_CFLAGS += -DTW_EXCLUDE_ENCRYPTED_BACKUPS   # ← 空才真的排除
   endif
   ```
   **要排除加密备份，就不要写这个变量**（或写空）。写 `:= true` 会引入 `libopenaes` 并保留代码。
2. **`TW_EXCLUDE_TWRPAPP` 不出现在 Android.mk**：`me.twrp.twrpapp.apk` 在 L502 是**无条件** `TWRP_REQUIRED_MODULES`。真要删得改 `vendor/twrp/config/*` 或构建后从 ramdisk 里删（只有几百 KB，优先级低）。

### 2.5 必须显式「不设」的东西

| 项 | 后果 | 说明 |
|---|---|---|
| `TW_FORCE_USE_BUSYBOX` | 切到 busybox，`sbin/busybox` 1.50 MB | Android.mk L219-223 强制 `TW_USE_TOOLBOX := true` |
| `TW_INCLUDE_PYTHON` | +6.59 MB | 见 §2.3 |
| `TW_OEM_BUILD := true` | 顺带排除 MTP/TZDATA/NANO/BASH/ZIP | 体积友好但改一堆行为（`BOARD_HAS_NO_REAL_SDCARD` 等），不建议 |
| `TW_LOAD_VENDOR_MODULES` | +`kernel_module_loader.cpp`+`libmodprobe`（静态） | 本机**必须留**（`hxchipset.ko`） |

---

## 3. 目标体积推算（13 档，逐档实测）

上限 **14,572,954**。所有数字由 `20_scenarios.py` 实际打包 + 压缩得到（B0 与瘦身报告的 15,015,189 / 9,622,929 分别差 1,101 B / 783 B，harness 与既有报告一致）。

### 3.1 逐档结果

| 档 | 配置 | cpio | **lz4** | gzip | zstd | 距上限(lz4) |
|---|---|---:|---:|---:|---:|---:|
| B0 | `core`（瘦身报告的地板；无 adbd、无触摸固件） | 34,612,457 | 15,014,088 | 12,830,911 | 9,623,712 | 超 441,134 |
| B1 | core+`adbd`+触摸固件 = **今天能用的最小集（仍带 crypto）** | 37,915,649 | **16,416,181** | **14,013,167** ✓ | 10,204,853 | 超 1,843,227 |
| N1 | B1 + `TW_INCLUDE_CRYPTO:=false` | 27,473,617 | **11,930,717** | 10,208,108 | 7,202,303 | 余 2,642,237 |
| N2 | + `TW_EXCLUDE_MTP` | 27,178,465 | 11,806,576 | 10,104,155 | 7,125,351 | 余 2,766,378 |
| N3 | + 不装 adb-backup / logcat | 27,116,189 | **11,782,590** | 10,083,333 | 7,111,426 | 余 2,790,364 |
| P1 | N3 + 只加 `make_f2fs`+`fsck.f2fs` | 27,505,605 | **11,987,608** | 10,254,240 | 7,232,996 | 余 2,585,346 |
| N4 | N3 + 整组 `fs_tools` | 29,872,565 | 13,133,416 | 11,236,996 | 7,945,953 | 余 1,439,538 |
| P2 | N4 + `lp_tools`（**去 lpdumpd/dmuserd**） | 30,227,937 | **13,274,653** | 11,354,114 | 8,019,503 | 余 1,298,301 |
| P3 | P2 + 精简 `misc`（去 sgdisk/lzma/zip/awk/bc/pigz/charger/avbctl） | 30,488,529 | 13,333,464 | 11,415,128 | 8,054,309 | 余 1,239,490 |
| **P7** | **P3 + TWRP 强制模块（minadbd/hwservicemanager/vndservicemanager/twrp），无 fastbootd** | 31,337,081 | **13,665,292** | **11,702,987** | 8,263,633 | **余 907,662 ← 推荐** |
| P6 | P7 + `fastbootd`（lz4 下功能最全） | 32,797,601 | **14,404,812** | 12,313,392 | 8,372,205 | 余 168,142（太薄） |
| N6 | 全 `misc`（含 lzma/zip/awk/bc/pigz/sgdisk/avbctl）+ 全 `lp_tools`（含 lpdumpd） | 34,162,377 | 14,839,048 | 12,701,291 | 9,003,282 | 超 266,094 |
| N8 | N7 + health/boot HAL service | 37,083,405 | 16,148,570 | 13,806,151 | 9,443,525 | 超 1,575,616 |

（P4 14,009,596 / P5 14,069,884 / P8 13,529,310 等中间档在 `scenarios.json`。）

### 3.2 三档可选配置

| 档 | 内容 | lz4 | 余量 | gzip | 取舍 |
|---|---|---:|---:|---:|---|
| **极简**（先打通调试通道） | P1：crypto off + MTP off + adbd + 触摸 + `make_f2fs` | **11.99 MB** | **2.59 MB** | 10.25 MB | 有 TWRP 界面/主题、adb shell、触摸、刷 zip、备份恢复、格式化 f2fs；无解密、MTP、fastbootd、lp 工具、ext4 格式化 |
| **推荐**（主产物） | **P7**：极简 + 整组 fs 工具 + lp 工具（去 lpdumpd）+ 精简 misc + TWRP 强制模块 | **13.67 MB** | **0.91 MB** | 11.70 MB | 上面全部 + `e2fsck/mke2fs/resize2fs`（格式化与修 ext4/f2fs）+ 动态分区工具（`lpmake/lpdump/lpunpack/lpadd/lpflash/dmctl`）+ `simg2img/zip/resetprop/bootctl`；无 fastbootd、无解密、无 MTP、无 OTA |
| **全功能 lz4** | P6：P7 + `fastbootd` | **14.40 MB** | 0.17 MB | 12.31 MB | 加回 fastbootd。**余量只有 168 KB，不建议**——重编后 `recovery` 二进制大小会有 ±100~300 KB 抖动 |
| **全功能 gzip** | B1 的内容 + gzip：**连 crypto 都不用关** | 16.42 MB ✗ | — | **14.01 MB ✓** | gzip 是唯一能「既保 crypto 又达标」的格式（余 559,787）。前提是 gzip 这条路本身能启动 |

### 3.3 结论

- **lz4 + 全功能不可能**：即使关掉 crypto，全 misc + 全 lp + fastbootd + HAL 也到 15.5 MB 以上。
- **lz4 + 推荐档（P7）13.67 MB 达标，余 0.91 MB** —— 这是本机「功能/体积」的最优点。
- **gzip 是隐藏的更优解**：同一份 P7 只有 11.70 MB（余 2.87 MB），连 fastbootd 加上也才 12.31 MB。**如果 gzip 能启动，一切都轻松**。
- **容差声明**：本 harness 的内容集合与真实构建有 ±差异（真实构建会多 `sbin/*.sh`、`init.recovery.usb.rc`、`permissive.sh`、`twrp_ramdisk` 里的 `ramdisk-files.*` 等，但少了部分我未建模的 twres 资源）。按 P7 的 0.91 MB 余量给结论，实际应在 **13.3–14.0 MB**。**构建后必须用 §5.5 的第 2 条自检实际 `ramdisk_size`。**

### 3.4 若必须留中文界面

`DroidSansFallback.ttf` 3.94 MB，TTF 压缩比约 0.48 → **lz4 +1.9 MB**：

| 组合 | lz4 | 结论 |
|---|---:|---|
| P1（11.99）+ 中文 | **13.89 MB** | ✓ 余 0.68 MB |
| P7（13.67）+ 中文 | 15.57 MB | ✗ |
| P7 + `pyftsubset` 裁到 GB2312 常用 3,500 字（约 0.9 MB，+0.43 MB） | **14.10 MB** | ✓ 余 0.47 MB |

P7 + 用 `pyftsubset` 把字体裁到 GB2312 常用 3,500 字（约 0.9 MB，+0.43 MB）是「要中文又要功能」的唯一路：
`pyftsubset DroidSansFallback.ttf --text-file=常用字表.txt --output-file=out.ttf`

### 3.5 需要写进 device tree 的最小开关集

```make
# ---- 体积：按收益排序（§2）----
TW_INCLUDE_CRYPTO := false            # −4,485,464 lz4（ICU/libchrome/sqlite/binder/keystore2 全链）
TW_INCLUDE_FASTBOOTD := false         # 只关 CFLAG；二进制在 device.mk 去掉（−739,520）
TW_EXCLUDE_MTP := true                # −124,141
TW_INCLUDE_PYTHON := false            # 别抄 topaz（−~2.86 MB）
TW_INCLUDE_REPACKTOOLS := false       # 去 magiskboot
TWRP_INCLUDE_LOGCAT := false          # 去 logcat/logd
TARGET_USES_LOGD := false
TW_EXTRA_LANGUAGES := false           # 只留 en.xml
TW_EXCLUDE_APEX := true
# TW_EXCLUDE_ENCRYPTED_BACKUPS        # ← 故意不写：写了反而加 libopenaes（Android.mk L400 判断反了）
TW_DEVICE_VERSION := TB331FC-slim
```

内容侧（不是 make 变量）：`file_contexts` 用文本版、`twres` 只留 6 个字体 + `en.xml`、不装 nano/bash/tzdata/vim/htop/lsof/openvpn/powertop、lp 工具不装 `lpdumpd`/`dmuserd`。

---

## 4. 最小 device tree（本机专用）

依据：`_ref/ofox_topaz_BoardConfig.mk`（OF `fox_12.1`，同 SM6225）+ `_ref/pbrp_tapas_BoardConfig.mk`（PBRP）+ 本盘 `port_tools/TB331FC-OrangeFox/device/lenovo/TB331FC/`，按 §3 结论裁剪。**8 个必需文件**见 GUIDE-RECOVERY §2.1；本节只写与体积/显示/打包有关的行。

### 4.1 `BoardConfig.mk`

```make
DEVICE_PATH := device/lenovo/TB331FC
ALLOW_MISSING_DEPENDENCIES := true

# ---- 架构（bengal / SM6225-AD / khaje）----
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_VARIANT := cortex-a73
TARGET_CPU_VARIANT_RUNTIME := cortex-a73
TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := cortex-a53
TARGET_2ND_CPU_VARIANT_RUNTIME := cortex-a53
TARGET_BOARD_PLATFORM := bengal
TARGET_BOARD_PLATFORM_GPU := qcom-adreno610
BOARD_USES_QCOM_HARDWARE := true

# ---- 内核与打包头：本机三条铁律 ----
BOARD_KERNEL_PAGESIZE := 4096
BOARD_BOOT_HEADER_VERSION := 4
TARGET_PREBUILT_KERNEL := /dev/null                 # 满足 kernel.mk 的 NO-KERNEL 检查
BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE := true    # → kernel_size=0，且不追加 buildvariant=eng
BOARD_MKBOOTIMG_ARGS += --header_version 4 --pagesize 4096
#   ↑ 本机 ABL 对非空 cmdline 有缺陷（GUIDE §6.4 #19），产物 cmdline 必须为空

# ---- ramdisk 压缩：一个变量管所有 ramdisk ----
# 【源码】build/make/core/Makefile L805-820 定义 COMPRESSION_COMMAND，
#         L2276-2278 把它用在 recovery_ramdisk 上；LZ4 分支 = `lz4 -l -12 --favor-decSpeed`
#         （`-l` = legacy 格式，正是原厂 02 21 4c 18）。不设任何 *_USE_* 时落到 MINIGZIP（gzip）。
BOARD_RAMDISK_USE_LZ4 := true
#   要 gzip：把上面一行注释掉即可（不要用 BOARD_RAMDISK_USE_XZ/LZMA —— 本机内核
#   CONFIG_RD_XZ / RD_LZMA 都不存在，IKCONFIG 实测）

# ---- A/B + 独立 recovery 分区 ----
AB_OTA_UPDATER := true
BOARD_USES_RECOVERY_AS_BOOT :=                      # 必须留空！
BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT :=     # 同上
BOARD_USES_GENERIC_KERNEL_IMAGE := true

# ---- 分区尺寸（本机实测）----
BOARD_FLASH_BLOCK_SIZE := 262144
BOARD_BOOTIMAGE_PARTITION_SIZE := 100663296         # 96 MiB
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 100663296
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE := 8388608
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_DTBOIMG_PARTITION_SIZE := 25165824

# ---- super = 12 GiB（不是 topaz 的 9.65 GB；本盘两棵旧树都写错过）----
BOARD_SUPER_PARTITION_SIZE := 12884901888
BOARD_SUPER_PARTITION_GROUPS := qti_dynamic_partitions
BOARD_QTI_DYNAMIC_PARTITIONS_PARTITION_LIST := \
    system system_ext product vendor vendor_dlkm odm system_dlkm
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE := 12876513280

# ---- 文件系统 ----
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
TARGET_USES_MKE2FS := true
BOARD_USES_METADATA_PARTITION := true
BOARD_USES_SYSTEM_EXTIMAGE := true
BOARD_HAS_LARGE_FILESYSTEM := true
TARGET_COPY_OUT_VENDOR := vendor                    # 不设会 board_config:682 报错
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4

# ---- 显示：无 CONFIG_FB ⇒ 只能 DRM；1200×1920 ----
TARGET_RECOVERY_PIXEL_FORMAT := "RGBX_8888"
TW_THEME := portrait_hdpi
TW_SCREEN_BLANK_ON_BOOT := true                     # 原厂 recovery 会先点亮屏；本机必须先亮
TW_MAX_BRIGHTNESS := 255
TW_DEFAULT_BRIGHTNESS := 200                        # 与原厂 `on init` 写的 200 对齐
TW_BRIGHTNESS_PATH := "/sys/class/backlight/panel0-backlight/brightness"
TW_FRAMERATE := 90                                  # 面板 1200x1920x90vid（不设只是默认 60fps）

# ---- 触摸：只要 hxchipset.ko ----
TW_LOAD_VENDOR_MODULES += "hxchipset.ko"
TW_LOAD_VENDOR_MODULES_EXCLUDE_GKI := true

# ---- 体积开关：见 §3.5（建议单独放 size.mk 便于对比构建）----
include $(DEVICE_PATH)/size.mk

# ---- AVB：只求产物自洽，别指望它解决闸门 ----
BOARD_AVB_ENABLE := true
BOARD_AVB_RECOVERY_KEY_PATH := external/avb/test/data/testkey_rsa4096.pem
BOARD_AVB_RECOVERY_ALGORITHM := SHA256_RSA4096
BOARD_AVB_RECOVERY_ROLLBACK_INDEX := 1
BOARD_AVB_RECOVERY_ROLLBACK_INDEX_LOCATION := 1
```

### 4.2 `device.mk`

```make
DEVICE_PATH := device/lenovo/TB331FC
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += boot dtbo init_boot system vendor odm product system_ext

# 要（边际很小）：boot HAL（A/B 槽位，11 KB）+ health HAL（电量，74 KB）
PRODUCT_PACKAGES += \
    android.hardware.boot@1.2-impl-qti.recovery \
    android.hardware.health@2.0-service

# 不要（各 0.7～2.2 MB）：验证阶段全关
#   fastbootd / android.hardware.fastboot@1.1-impl-mock      −739,520 lz4
#   update_engine / update_engine_sideload / update_verifier −~950,000 lz4
#   otapreopt_script / cppreopts.sh
#   qcom_decrypt / qcom_decrypt_fbe / android.hardware.keymaster@4.1   （crypto 关掉后无意义）

PRODUCT_PACKAGES += lenovo_prebuilt_modules        # 只放 hxchipset.ko（见 §5.3）
PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_BUILD_SUPER_PARTITION := false
PRODUCT_SOONG_NAMESPACES += $(DEVICE_PATH)
TW_DEVICE_VERSION := TB331FC-slim
```

### 4.3 `fox_TB331FC.mk`（TWRP 树改名为 `twrp_TB331FC.mk`）

```make
$(call inherit-product, device/lenovo/TB331FC/device.mk)
$(call inherit-product, vendor/twrp/config/common.mk)
TARGET_SUPPORTS_32_BIT_APPS := false        # 64-bit-only 产品必写，否则 lunch abort
TARGET_SUPPORTS_64_BIT_APPS := true
PRODUCT_NAME := fox_TB331FC
PRODUCT_DEVICE := TB331FC
PRODUCT_BRAND := Lenovo
PRODUCT_MODEL := Xiaoxin Pad 2024
PRODUCT_MANUFACTURER := Lenovo

# OF 侧（屏幕 + 体积）
OF_SCREEN_H := 1920                         # 本机竖屏 1920（topaz 是 2400）
OF_STATUS_H := 80
OF_AB_DEVICE_WITH_RECOVERY_PARTITION := 1
OF_DELETE_AROMAFM := 1
FOX_DISABLE_APP_MANAGER := 1
OF_ENABLE_ALL_PARTITION_TOOLS := 1          # 要 lp 工具就留；更激进的瘦身可设 0
OF_NO_TREBLE_COMPATIBILITY_CHECK := 1
OF_USE_LEGACY_TIME_FIXUP := 1
# OF_DEFAULT_KEYMASTER_VERSION 不设（crypto 关闭后无意义）
```

### 4.4 `recovery.fstab`

照 GUIDE §2.5 的 14 行 `_a` 版。唯一硬要求：**逻辑分区写 `_a`、不带 `slotselect`、不带 `avb=`** —— `super` 里 7 个 `*_b` 的 extents 全是 0，`slotselect` 会让 `fs_mgr` 静默跳过（`of/v3` FIX-1 已验证）。

### 4.5 `recovery/root/init.recovery.qcom.rc`

```rc
on early-init
    write /sys/fs/selinux/enforce 0
    write /proc/sys/kernel/firmware_config/force_sysfs_fallback 1   # Himax 固件被 ueventd 找到的前提

on init
    write /sys/class/backlight/panel0-backlight/brightness 200      # 缺这行 = 有画面也全黑
```

判读一行：`grep -aE 'Using (drm|fbdev) graphics' /tmp/recovery.log`。`Using drm graphics.` + `card0-DSI-1 connected` + `brightness=200` 三者齐了还黑 ⇒ 问题在面板上电，不在 TWRP。

---

## 5. 构建环境与命令

### 5.1 本机 WSL 现状（【实测】，`work/env_survey.sh`）

| 项 | 现状 | 要补 | 理由 |
|---|---|---|---|
| 发行版 | **Ubuntu 24.04.5 LTS** | 建议另装 **Ubuntu 22.04**（`wsl --install -d Ubuntu-22.04`） | 12.1 的 prebuilt clang 依赖 `libncurses5`，24.04 已移除；OF CI 用的就是 `ubuntu-22.04` |
| JDK | 只有 **21.0.13** | `openjdk-11-jdk`（AOSP 12 对齐版，CI 同款） | 21 会让 soong 的部分 jlink 参数不认 |
| `repo` | **未安装** | `curl -s https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo && chmod a+x ~/bin/repo` | |
| ccache | **未安装** | `apt install ccache`；`export USE_CCACHE=1` | 首次 2–4 h → 之后增量 5–20 min |
| swap | **只有 2 GiB** | 加 **12 GiB** swapfile（`fallocate -l 12G /swapfile && mkswap && swapon`） | 7.7 GiB 内存 + Soong 全树分析 = OOM 一号杀手（16 GB runner 也中过） |
| CPU/内存 | 8 vCPU / 7.7 GiB | `mka recoveryimage -j2` | 16 GB 才 `-j8` |
| 磁盘 | `/` 939 GiB 可用 | 够 | 源码 30–45 + out 25–35 + ccache 10–20 GB |
| lz4 / cpio / gcc | 有（1.9.4 / 有 / 13.3） | `zstd` 缺（只本地试压缩才要，构建不需要） | |

依赖清单取自 OF CI 的真实成功配置（`port_tools/TB331FC-OrangeFox/.github/workflows/build-fox.yml`）：

```bash
sudo apt update && sudo apt install -y --no-install-recommends \
  bc bison build-essential ccache curl flex g++-multilib gcc-multilib git gnupg \
  gperf imagemagick lib32ncurses5-dev lib32readline-dev lib32z1-dev libc6-dev-i386 \
  libelf-dev libgl1-mesa-dev libxml2-utils libssl-dev libx11-dev libncurses5 \
  libncurses5-dev libsdl1.2-dev libwxgtk3.0-gtk3-dev lzop pngcrush python3 rsync \
  schedtool squashfs-tools xsltproc zip zlib1g-dev unzip python-is-python3 \
  openjdk-11-jdk lz4
# lib32gcc-1 不存在，正确是 lib32gcc-s1（GUIDE §6.4 #2）
```

### 5.2 `repo` 与分支（**本方案不执行**）

```bash
# 路线② OrangeFox fox_12.1（推荐：自带 A/B + recovery 分区开关，比 TWRP minimal 少 3–4 个坑）
mkdir -p ~/fox && cd ~/fox
repo init --depth=1 -u https://gitlab.com/OrangeFox/Manifest.git -b fox_12.1
repo sync -c -j4 --force-sync --no-clone-bundle --no-tags

# 路线① TWRP minimal（只在要 TWRP 上游最新特性时）
#   repo init --depth=1 -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp -b twrp-12.1
#   twrp-default.xml 已内置 remove-project 覆盖，不要再写 local manifest（GUIDE §6.4 #5）
```

成本【估算】：源码 30–45 GB + `out/` 25–35 GB + ccache 10–20 GB = **≥ 90–110 GB，建议留 180 GB**；首次 2–4 h，增量 5–20 min。**建在 WSL 的 `/`（939 GB）上，不要放 `E:`。**

### 5.3 device tree 与 prebuilt

```bash
cp -r /path/TB331FC-OrangeFox/device/lenovo/TB331FC ~/fox/device/lenovo/TB331FC
chmod +x ~/fox/device/lenovo/TB331FC/vendorsetup.sh
# prebuilt 只要两样：
#   prebuilt/kernel                                ← 原厂 boot.img 里的 46,819,840 B Image（或 KSU 内核）
#   prebuilt/vendor/lib/modules/1.1/hxchipset.ko   (607,560 B) + modules.load/.load.twrp/.dep（各 13 B 单行）
```

### 5.4 构建

```bash
cd ~/fox
source build/envsetup.sh
export ALLOW_MISSING_DEPENDENCIES=true
export FOX_USE_TWRP_RECOVERY_IMAGE_BUILDER=1
export LC_ALL=C
lunch fox_TB331FC-eng          # 报 Invalid lunch combo → 试 -ap2a-eng / -ap3a-eng / -trunk_staging-eng
mka recoveryimage -j2
```

### 5.5 构建后必跑的三条自检

```bash
# 1) 头：header_version=4、kernel_size=0、cmdline=''
python3 work/of/tools/hdr4.py out/target/product/TB331FC/recovery.img
# 2) 尺寸：看 ramdisk_size，必须 ≤ 14,572,954（分区大小 96 MiB 不是闸门）
python3 -c "import struct;d=open('out/target/product/TB331FC/recovery.img','rb').read(4096);print('kernel,ramdisk=',struct.unpack_from('<II',d,8))"
# 3) 需要 vbmeta（minimal manifest 没有 vbmeta target）
python3 external/avb/avbtool make_vbmeta_image --flags 3 --algorithm SHA256_RSA4096 \
  --key external/avb/test/data/testkey_rsa4096.pem --padding_size 65536 --output vbmeta.img
```

---

## 6. 风险与替代

### 6.1 零重编的两档杠杆（**先做**）

| 杠杆 | 做法 | 收益 | 风险 |
|---|---|---|---|
| **A. 换压缩格式** | 刷 `of-slim/out/of_recovery_slim_gzip.img`（**13,996,032 B**，ramdisk 13,988,278，含 core+fs 工具） | 立刻进入限内；且 gzip 与 zstd 是**两条独立路径**（`CONFIG_RD_GZIP=y` 是内核最老的 initramfs 格式） | 低。失败 = 10 s 回 fastboot |
| **B. 让 `init_boot` 腾额度** | 把 `init_boot_a/b` 刷成空 cpio（8,192 B 镜像 / 512 B cpio） | 若三段求和成立：额度 **+2,005,381 B**（原厂 init_boot ramdisk = 2,005,893，【实测】）→ recovery 上限 ≈ **16.58 MB**，连 15,015,189 B 的 lz4 都能过尺寸检查 | 要确认 ABL 在 recovery 启动路径上也加载 init_boot；不加载则无收益，可回滚 |

### 6.2 如果重编也压不进

按代价从低到高：

1. **只装 `make_f2fs`+`fsck.f2fs`** 而不是整组 fs 工具 → P1 = 11.99 MB（−1.15 MB vs 整组）。
2. **不装 lp 工具** → P8 = 13.53 MB（只在 P7 上再省 0.14 MB，因为 lpdumpd 已砍）。
3. **去掉 fastbootd** → 从 P6 的 14.40 降到 P7 的 13.67（−0.74 MB）。
4. **换 gzip**：同一 P7 只有 11.70 MB。
5. **换 zstd**：8.26 MB（但已有「init 卡住」的实测）。

### 6.3 替代路径：极简自研 init/adbd ramdisk（先打通调试通道）

本机最值得留的兜底，因为它把「recovery 分区能不能装第三方 ramdisk」和「TWRP 的显示/主题/init 依赖齐不齐」彻底解耦。

| 项 | 做法 |
|---|---|
| 起点 | AOSP 12.1 的 `system/core/init` + 静态 `adbd`，或 mksh + busybox + 自写 init（无 TWRP、无 minui、无主题） |
| 体积 | 目标 **≤ 3 MB lz4**：`init` 1.98 MB + `adbd` 2.10 MB 是主成本；换静态 busybox + 极简 `init` 可到 **1.5 MB** 以内 |
| 显示 | **不初始化 DRM**，不黑屏也不白屏，只靠 `adb` 判成败 |
| 判据 | `adb devices` 出现 `recovery`；`uname -a` / `cat /proc/cmdline` / `ls /dev/dri` / `cat /proc/modules` |
| 材料 | 全部在盘上：原厂 `recovery.img` 当容器模板、`work/of/tools/mkv4.py` 拼 v4 头、`of/v3/build_v3.py` 打 lz4 cpio。**30 分钟能出镜像** |
| 判读 | 极简能进 + TWRP 不能进 ⇒ 瓶颈在 TWRP 侧（显示/init 依赖）→ 按 §3 推荐档重编；极简也进不去 ⇒ recovery 分区这条路可判死 |

### 6.4 走 `vendor_boot` 而非 recovery 分区（§6.3 判死后的路）

`of/v3` 的 MODE=2：`boot_b` 只放内核、`vendor_boot_b` = 原厂 vendor ramdisk + OF 段、`init_boot_b` = 空 cpio。**不碰 recovery 分区**，绕开 recovery 段的白名单/尺寸闸门；本盘已有 82 项离线验收通过的产物与一键回滚 bat（`刷入OF_v3.bat` / `rollback`）。维护语义不同，但「打通调试通道」这个目标它更短。

### 6.5 关掉 crypto 的代价（必须让 lead 知道）

| 失去 | 影响 | 缓解 |
|---|---|---|
| `/data` 解密（FBE） | 读不到已加密 /data，不能备份 data、不能从 /data 刷 zip | 本机 keymaster 版本与 TWRP 绑定不匹配，**解密本来就没成功过**（GUIDE §6.4 #17）；格式化 data 仍可 |
| MTP | 不能 USB 挂载存储 | `adb push/pull` 可用（adbd 保留） |
| fastbootd | 不能在 recovery 里进 fastbootd | 系统侧 `adb reboot fastboot` 仍可用 |
| OTA 侧载 | 不能刷官方 A/B OTA 包 | `flashable zip`、`flash_image`、`fastboot flash` 不受影响 |

### 6.6 重编的失败面

已知 20 条在 GUIDE-RECOVERY §6.4（`vold` fscrypt 回补、AIDL `-ndk_platform` 空 stub、`kernel.mk:594` 上游 tab bug、`TARGET_COPY_OUT_VENDOR`、三段式 lunch、OOM…）。本轮**新增/强调** 3 条：

1. `TW_INCLUDE_PYTHON := true`（topaz 默认带）→ +6.59 MB，最贵的单行。
2. `TW_EXCLUDE_ENCRYPTED_BACKUPS` 判断反向（§2.4）→ 写了反而变大。
3. `vendor/twrp/config/packages.mk` 默认就装 bash/nano/vim/htop/lsof/openvpn/powertop（2.94 MB）→ 要显式不装。

### 6.7 决策树

```
① 刷 of_recovery_slim_gzip.img (13,996,032 B)
├─ 进 recovery → 体积问题解决。再用本方案关 crypto 把 lz4 也压到 13.7 MB（双保险）
└─ 不进
   ├─ ② init_boot 换空 cpio（额度 +2.0 MB）再刷同一个镜像
   │  ├─ 进 → ABL 额度是瓶颈 → 重算三段预算，现有镜像就够
   │  └─ 不进
   │     ├─ ③ 极简自研 ramdisk（≤1.5 MB）能进 → 瓶颈在 TWRP 侧 → 按 §3 推荐档(P7) 重编
   │     └─ ④ 极简也进不去 → recovery 分区判死 → 走 of/v3 的 vendor_boot 路线（§6.4）
```

---

## 7. 本轮新增资产（全部可复算）

```
E:\rom\work\of-rebuild\
  PLAN.md                          本文件
  work\10_needed_graph.py          331 个 ELF 的 DT_NEEDED 图  → needed_graph.txt / reverse_deps.txt
  work\20_scenarios.py             13 档配置真打包 + 三种压缩    → scenarios.json
  work\30_price.py                 边际闭包定价                 → price_table.md
  work\31_delta.py                 开关表 ↔ 实测 Δ 的对账
  work\33_check_pack.py            打包器自检（sum(size)==sum(data)）
  work\34_fs_tools.py / 35_diff_groups.py / 36_forced.py   工具组与强制模块逐项定价
  work\40_bootimg_sizes.py         原厂三件 ramdisk 尺寸实测
  work\env_survey.sh               WSL 构建环境体检
  ref\twrp12_Android.mk            ★ TWRP 12.1 构建规则原文（所有开关结论的来源）
  ref\twrp12_libtar_Android.mk     ★ libtar 的 FBE 库清单（libchrome 的来源）
  ref\twrp12_build_core_Makefile.mk  build/make Makefile（压缩变量、BOARD_EXCLUDE_KERNEL…）
  ref\twrp12_Android.bp / twrp12_variables.h / twrp12_vendor_{common,packages}.mk
```

一键复算：`wsl -d ub -u root -- bash -lc "cd /mnt/e/rom/work/of-rebuild/work && python3 10_needed_graph.py && python3 30_price.py && python3 20_scenarios.py"`
