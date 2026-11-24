# TB331FC / 澎湃4（A17, SDK 37）系统运行机制档案

> **用途**：给后续移植 / 改包 / 刷机提供「这套系统到底怎么跑起来的」的事实底本。
> **取证方式**：只读。全程 `adb -s 5e367954 shell`（KSU root，`context=u:r:ksu:s0`），未刷机、未改系统文件、未 reboot。
> **采集时间**：分两段完成。
> - **第一段 13:12–13:15 CST**（当时开机 uptime ≈ 315 s，约 13:09 开机）：getprop / mounts / lpdump / dmesg / logcat / config.gz。
> - **13:15 设备从 USB 完全消失**（`pnputil` 里已无任何 USB 设备，非 adb 问题），**13:26 自行回来，但 uptime 只有 113 s → 中间又重启了一次**。
> - **第二段 13:26–13:28 CST**：bootconfig / `/proc/modules` / dm 映射 / boot·init_boot·vendor_boot 头部 / SELinux 目录 / thermal sysfs。
> **⚠️ 设备会自发重启**：`persist.sys.boot.reason.history` = `bootloader,57`（累计 57 次 bootloader 重启；13:13 采样时还是 54，到 13:26 已变 57）。本次会话期间**至少重启 1 次**（uptime 315 s → 113 s → 194 s）。第 5 节有详细记录。
> **设备身份**：`5e367954`，`TB331FC`，槽位 `_a`，HyperOS `OS4.0.5.0.XPZCNXM`，A17/sdk37。

---

## 0. 一句话结论

**这是一套「A17 系统 + A13/A14 vendor」跨四代拼装的系统，跑在一颗社区自建的 5.15.167 GKI 内核上（内建 KernelSU+SUSFS），内核把模块 vermagic 校验 patch 掉了，硬凑 5.15.74 的 vendor 模块；7 个逻辑分区上 dm-verity 真实开启（eio 模式）；SELinux Enforcing、policy 版本 331，且每次开机都现场编译 sepolicy（plat 与 odm 预编译哈希不一致）。**

三个「一眼就能定调」的数字：

| 项 | 值 | 含义 |
|---|---|---|
| `ro.build.version.sdk` | **37** | 系统侧 Android 17 |
| `ro.vendor.build.version.sdk` / `ro.llndk.api_level` | **33** / **33** | vendor 侧 Android 13（ZUI 16.0.544） |
| 内核 `uname -r` | `5.15.167-...-dirty` | 而模块 vermagic 是 `5.15.74-ga0aa332d6eec-*` |

再补四个「结构位」的事实（都在后面有实证）：

| 项 | 值 |
|---|---|
| 模块来源 | **三处**：vendor_dlkm 152 个（in-tree）+ vendor_dlkm 63 个（out-of-tree）+ **vendor_boot ramdisk 78 个**（含 UFS/SMMU/WLAN 核心驱动） |
| `boot_a` / `init_boot_a` | `ANDROID!` v4，**kernel 43,092,480 B + ramdisk 0** / **kernel 0 + ramdisk 2,005,893 B** |
| 逻辑分区 | 每个都是 `X_a`(dm-linear) → `X-verity`(dm-verity) 两层，**挂载用的是 verity 层**；`_b` 槽全空 |
| 重启倾向 | `persist.sys.boot.reason.history = bootloader,57`，取证期间自发重启 ≥1 次 |

---

## 1. 内核层

### 1.1 版本与编译

```
Linux version 5.15.167-android13-5.15.167_r00-dirty (runner@runnervmliwqe)
  (clang version 17.0.4 (https://github.com/llvm/llvm-project 309d55140c46384b6de7a7573206cbeba3f7077f),
   LLD 17.0.4) #1 SMP PREEMPT Sun Aug 9 16:49:46 UTC 2026
```

| 事实 | 证据 |
|---|---|
| 内核 **5.15.167**，GKI `android13-5.15.167_r00` 基线，`-dirty` | `/proc/version`、dmesg `[0.000000]` |
| 由 **clang 17.0.4 + LLD 17.0.4** 编译 | 同上 |
| 构建主机 `runner@runnervmliwqe` → **GitHub Actions runner 命名**，即社区 CI 自建内核，非联想出厂 | 同上 |
| 构建时间 `Sun Aug 9 16:49:46 UTC 2026`，比 system 镜像（`ro.build.date: Sun Sep 13 21:05:44 CST 2026`）早一个月 | getprop |
| `Machine model: Qualcomm Technologies, Inc. KHAJE IDP nopmi` — **DT model 串还是 IDP（内部开发平台）**，没改成量产机型名 | dmesg `[0.000000]` |
| 内核命令行含 `kpti=off`、`cpufreq.default_governor=performance`、`log_buf_len=2048k`、`console=ttyMSM0,115200n8`、`video=vfb:640x400,bpp=32,memsize=3072000`（**虚拟 framebuffer 当 console**） | dmesg 里的 `Kernel command line:` |
| 面板由 cmdline 指定：`msm_drm.dsi_display0=qcom,mdss_dsi_panel_p255_hx83102j_fhd_video:` | 同上；dmesg 6.07s `Successfully bind display panel 'qcom,mdss_dsi_panel_p255_hx83102j_fhd_video'` |
| `log_buf_len=2048k` → dmesg 环形缓冲 2 MB，本次开机 **未回卷**，所以 `dmesg_head.txt` 实际是**完整开机日志**（5645 行，0.00s → 315.27s） | dmesg 首尾时间戳 |

### 1.2 `/proc/config.gz` 关键项（6975 行，已解压到同目录 `config`）

| 选项 | 值 | 影响 |
|---|---|---|
| `CONFIG_MODULES` | `=y` | 支持模块 |
| `CONFIG_MODVERSIONS` | `=y`（`CONFIG_ASM_MODVERSIONS=y`） | 有符号 CRC 校验 |
| `CONFIG_MODULE_FORCE_LOAD` | **`is not set`** | 内核层禁止 `--force` 加载 |
| `CONFIG_MODULE_SIG` | `=y`、`SIG_ALL=y`、`SIG_PROTECT=y`、`SIG_SHA1`、`KEY="certs/signing_key.pem"` | 有签名机制 |
| `CONFIG_MODULE_SIG_FORCE` | **`is not set`** | **签名不强制** → 未签名模块只告警 |
| `CONFIG_FB` | **`is not set`**（只有 `CONFIG_FB_CMDLINE=y`） | **无 framebuffer 控制台**，显示纯 DRM |
| `CONFIG_DRM` | `=y`（`DRM_MIPI_DSI`/`DRM_KMS_HELPER`/`DRM_PANEL`/`DRM_BRIDGE` 全 y） | |
| `CONFIG_DRM_MSM` | **`is not set`** | QCOM 显示驱动是**外部模块** `msm_drm.ko`（在 `/vendor_dlkm`） |
| `CONFIG_SCSI_UFSHCD` | `=y`（`UFSHCD_PLATFORM=y`、`UFS_DWC_TC_PLATFORM=y`、`UFS_BSG=y`、`UFS_CRYPTO=y`、`UFS_HPB=y`） | UFS 控制器**内建**，不是模块 |
| `CONFIG_SCSI_UFS_QCOM` | **`is not set`** | QCOM  glue 走 DWC_TC 平台驱动，非 QCOM 专用驱动 |
| `CONFIG_UFS_FS` | `is not set` | 不认 UFS 文件系统（正常） |
| `CONFIG_KSU` | **`=y`** | **KernelSU 编进内核** |
| `CONFIG_KSU_SUSFS` | `=y` + `SUS_PATH`/`SUS_MOUNT`/`SUS_KSTAT`/`SPOOF_UNAME`/`ENABLE_LOG`/`HIDE_KSU_SUSFS_SYMBOLS`/`SPOOF_CMDLINE_OR_BOOTCONFIG`/`OPEN_REDIRECT`/`SUS_MAP` 全开 | 隐藏套件全套启用 |
| `CONFIG_DM_VERITY` | `=y`、`DM_VERITY_FEC=y` | |
| `CONFIG_DM_CRYPT`/`DM_DEFAULT_KEY`/`DM_SNAPSHOT`/`DM_INIT` | `=y` | 支持 FBE + 快照（OTA 回滚） |
| `CONFIG_SECURITY_SELINUX` | `=y`（`DEVELOP=y`、`AVC_STATS=y`、`CHECKREQPROT_VALUE=0`） | |
| `CONFIG_LSM` | `landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,smack,tomoyo,apparmor,bpf` | 全 LSM 编入，运行时只激活 selinux |
| `CONFIG_CFI_CLANG` | `=y`、`CFI_CLANG_SHADOW=y`、`CFI_PERMISSIVE` 未开 | **CFI 强制**——自己编模块必须带 CFI 信息，否则调用即崩 |
| `CONFIG_KALLSYMS_ALL` | `=y` | 符号全开（KSU 需要） |
| `CONFIG_EXT4_FS` / `F2FS_FS` / `OVERLAY_FS` | 全 `=y` | ext4/f2fs/overlayfs 内建 |
| `CONFIG_ARM64_VA_BITS` | `39` | 39 位 VA |
| `CONFIG_RANDOMIZE_BASE` | `=y` | KASLR |

### 1.3 模块加载机制

**目录结构**

```
/vendor/lib/modules -> /vendor_dlkm/lib/modules      (软链，24 字节，lrw-r--r--)
```

- `vendor_dlkm` 是**独立逻辑分区**（`/dev/block/dm-10`，56.2 MiB），模块实际落在 `/vendor_dlkm/lib/modules`。
- **216 个 `.ko`**；`modules.load` 216 行（**清单与文件数 1:1，无遗漏、无多余**）。
- `modules.load.recovery` **不存在** —— 该机是 A/B + virtual_ab，**没有 recovery 分区**，所以不需要 recovery 变体清单。
- 另有 `modules.dep`（17 KB）、`modules.alias`（27 KB）、`modules.softdep`（535 B）。
- `modules.softdep` 里有几条对本机很关键的依赖：
  ```
  softdep msm_kgsl   pre: arm_smmu nvmem_qfprom socinfo
  softdep hxchipset  pre: msm_drm        # 触屏依赖显示
  softdep nvt36523_spi pre: msm_drm
  softdep msm_video  pre: subsys-pil-tz msm-mmrm
  softdep nopmi_chg  pre: sc8960x_charger mm8013c10_battery
  softdep dwc3_msm   pre: phy-generic phy-msm-snps-hs phy-msm-ssusb-qmp eud
  ```

**★ 模块有「三处来源」，不是一个目录**（这是改包最容易漏的一点）

运行态 293 个模块（`/proc/modules` 293 行）的构成，已用 vermagic + Flags 逐条对账：

| 来源 | 数量 | Flags | vermagic | 说明 |
|---|---|---|---|---|
| `/vendor_dlkm/lib/modules`（in-tree 构建） | **152** | `E` | `5.15.74-ga0aa332d6eec-ab44` | 磁盘 152 个 `-ab44` **全部加载**，1:1 |
| `/vendor_dlkm/lib/modules`（out-of-tree 构建） | **63** | `OE` | `5.15.74-ga0aa332d6eec-dirty` | 磁盘有 64 个 `-dirty`，`mmrm_test_module.ko` 未加载（测试模块） |
| **`vendor_boot` 的 ramdisk**（first-stage） | **78** | `E` | 磁盘无对应 `.ko` | 见下 |
| 合计 | **293** | | | |

`qca_cld3_wlan.ko` 的坑：文件 14.29 MB，但**内部模块名是 `wlan`**（`modinfo name=wlan`），所以在 `/proc/modules` 里叫 `wlan`（core 10.12 MB），按名字找不到。

**78 个来自 vendor_boot ramdisk 的模块 —— 全是核心驱动**

```
ufs_qcom, ufshcd_crypto_qti, arm_smmu, sdhci_msm, wlan(qca_cld3_wlan), zsmalloc,
bam_dma, slimbus, slim_qcom_ngd_ctrl, pdr_interface, qmi_helpers, usbpd,
simtray, mem_offline, qcom_pmu_lib ...
```

- 它们由 init first stage 从 ramdisk 的 `/lib/modules` 加载（dmesg `[0.955571] init: Loading module /lib/modules/qcom_hwspinlock.ko` …）。
- **运行期 `/lib/modules` 已不存在**（`ls: /lib/modules/: No such file or directory`）—— ramdisk 在 second stage 前就卸掉了，模块留在内核里。
- `vendor_boot_a` 的 `vendor_ramdisk_size = 11,628,676 B`（11.09 MiB），这 78 个就在里面。

> **结论**：**改 `vendor_boot` 不只是"改个 ramdisk"，会连带换掉 UFS / SMMU / SDHCI / WLAN 这层核心驱动。** 而改 `vendor_dlkm` 只影响显示、触屏、音频、充电、摄像头这些外设模块。

**vermagic 实测值（216 个 .ko 全测，逐文件见 `modules.txt`）**

| vermagic | 模块数 | 已加载 |
|---|---|---|
| `5.15.74-ga0aa332d6eec-ab44` | 152 | 152 |
| `5.15.74-ga0aa332d6eec-dirty` | 64 | 63 |
| 与内核 `5.15.167-android13-5.15.167_r00-dirty` 相同 | **0** | — |

> 两种后缀（`-dirty` / `-ab44`）说明这批模块来自**两个不同的构建**，都被塞进同一个目录；`-dirty` 那 64 个正是 out-of-tree（`OE`）的那批。

**★ 内核 patch 掉了 vermagic 校验 —— 四条独立证据**

1. **293 个 vermagic 全不匹配的模块全部加载成功**，而 dmesg 里**零条** `version magic ... should be` / `disagrees about version of symbol`。dmesg 全文 `grep -i magic` 只有 1 条命中，是 KSU 的 `search_manager: dir: /data/app got magic! 0xf2f52010`，与模块无关。
2. **不是靠 force load 绕过的**：`/proc/sys/kernel/tainted = 12288` = `0x3000` = bit12(`OOT_MODULE`)+bit13(`UNSIGNED_MODULE`)，即 taint 串 **`OE`**，**没有 `F`（forced module load，bit1）**；且 `CONFIG_MODULE_FORCE_LOAD is not set`，内核层根本不给这个口子。`/proc/modules` 每行尾部标志也是 `(OE)` / `(E)`。
3. **不是靠签名绕过**：`CONFIG_MODULE_SIG_FORCE` 未开，签名失败只是告警——dmesg 唯一一条：
   ```
   [0.956065] qcom_hwspinlock: module verification failed: signature and/or required key missing - tainting kernel
   ```
   加载照旧成功。另有 `[2.094794] qrng_dlkm: loading out-of-tree module taints kernel.`
4. **CRC 校验也放宽了**：`[5.858018] btpower: no symbol version for cnss_utils_update_device_type` —— MODVERSIONS 缺 CRC 本该是硬错误，这里只打印警告。

> **结论（改包必须知道）**：这套「5.15.167 内核 + 5.15.74 模块」是**故意做的不匹配对**，靠内核侧 patch 撑着。
> - 把内核换回官方/别家 5.15.167 编译版 → 模块可能全部拒载，开机即死。
> - 反过来单独替换 `/vendor_dlkm` 里的 `.ko`（哪怕版本号写对）也会因为 `CONFIG_CFI_CLANG=y` 且缺 CFI 信息而崩。
> - **改显示/触屏/充电/音频驱动，只能改源码重编整套内核+模块，不能单换 `.ko`。**

### 1.4 KernelSU 是怎么进的

**结论：KSU 编在 boot 分区的 kernel 里（`CONFIG_KSU=y`），不是 init_boot ramdisk patch，也不是 GKI LKM 模式。**

证据链：

| # | 证据 | 说明 |
|---|---|---|
| 1 | `/proc/config.gz` 有 `CONFIG_KSU=y` | 内核**编译期**就带 KSU，不是运行时注入 |
| 2 | `[0.828506] KernelSU: feature: feature management initialized` | 时间点 **0.83 s**，早于 `[0.921396] init: init first stage started!` —— 用户态还没起来 KSU 已就位 |
| 3 | `[4.090094] KernelSU: /system/bin/init second_stage executed` | KSU 在 **init 第二阶段**做 hook（劫持 init 是 KSU 的 GKI 打法） |
| 4 | `KernelSU: backup sepolicy success!` / `adding POLICYDB_CONFIG_ANDROID_NETLINK_ROUTE` | 内核态直接改 SELinux policy，用户态做不到 |
| 5 | `KernelSU: sid '70' is set for secctx_name 'u:r:ksu:s0'`、`Cached su SID: 70` | 内核自建 `ksu` 域 |
| 6 | 内核版本 `-dirty` + `runner@runnervmliwqe` + 构建于 2026-08-09 | **社区 CI 自建的 KSU 内核**，不是联想原厂内核 |
| 7 | 用户态 `/data/adb/ksud` 4.89 MB（`ksud 3.3.0 (uapi: 2)`），`/data/adb/ksu/bin/{ksud,resetprop,busybox,bootctl}` | 用户态只是客户端 |

**分区布局（`/dev/block/by-name/`）**

| 分区 | 设备节点 |
|---|---|
| `boot_a` | `/dev/block/sde11` |
| `boot_b` | `/dev/block/sde35` |
| `init_boot_a` | `/dev/block/sde22` |
| `init_boot_b` | `/dev/block/sde48` |
| `vendor_boot_a` | `/dev/block/sde24` |
| `vbmeta_a` | `/dev/block/sde16` |
| `vbmeta_system_a` | `/dev/block/sda11` |
| `super` | `/dev/block/sda10` |
| `userdata` | `/dev/block/sda14` |

> **推论**：刷 root 只需动 `boot_a`；动 `init_boot` 不影响 root（反之亦然）。**但**本机 `boot_a` 里的 kernel 同时承载 KSU 与 5.15.167 内核本体，所以「换内核」和「保 root」是同一件事。

**★ 已用镜像头部实证（不再是推断）** —— 各读 4096 字节头部解析：

| 分区 | magic | header_version | kernel_size | ramdisk_size | 其它 |
|---|---|---|---|---|---|
| **`boot_a`** (`sde11`) | `ANDROID!` | 4 | **43,092,480 B（41.1 MiB）** | **0** | cmdline 空，header_size 1584 |
| **`init_boot_a`** (`sde22`) | `ANDROID!` | 4 | **0** | **2,005,893 B（1.9 MiB）** | 即 generic ramdisk 在这里 |
| **`vendor_boot_a`** (`sde24`) | `VNDRBOOT` | 4 | — | `vendor_ramdisk_size` = **11,628,676 B（11.09 MiB）** | page_size 4096，dtb_size 1,290,690 B，cmdline = `video=vfb:640x400,bpp=32,memsize=3072000 bootconfig` |

**三条硬结论**：

1. **内核（41.1 MiB）在 `boot_a`，且 `boot_a` 的 ramdisk 为 0** → KSU（`CONFIG_KSU=y`）+ 内核本体都在 `boot_a` 的 kernel 段里。**刷 `boot_a` = 换内核 + 换 KSU，两者不可分离。**
2. **`init_boot_a` 只装 1.9 MiB 的 generic ramdisk**，`kernel_size=0` → 这里**没有内核**，改它不会影响 root，也不会影响内核版本。Magisk 那种「patch init_boot」的路子在这台机器上作用对象是这 1.9 MiB。
3. **`vendor_boot_a` 承载 11.09 MiB vendor ramdisk + 1.29 MB DTB + 全部 cmdline**，`boot_a` 的 cmdline 是空的 → **想改内核命令行（`msm_drm.dsi_display0=` 面板选择、`video=vfb`、`log_buf_len`）必须改 `vendor_boot`**，改 `boot` 没用。bootconfig（1176 B / 66 nodes）也由 `vendor_boot` 的 `bootconfig` 标记带出。

**`/proc/bootconfig`（32 行，全文见 `bootconfig.txt`）**

```
androidboot.hardware = "qcom"                    androidboot.hwlevel = "MP"
androidboot.memcg = "1"                          androidboot.bootload_sn = "9D4042665BF187C0..."
androidboot.load_modules_parallel = "false"      androidboot.secboot = "yes"
androidboot.usbcontroller = "4e00000.dwc3"       androidboot.baseband = "apq"
androidboot.bootdevice = "4804000.ufshc"         androidboot.dtbo_idx = "2"
androidboot.boot_devices = "soc/4804000.ufshc"   androidboot.dtb_idx = "0"
androidboot.serialno = "5e367954"                androidboot.force_normal_boot = "0"
androidboot.psn = "androidboot.gsn=5e367954"     androidboot.fstab_suffix = "default"
androidboot.mirrorflag = "disable"               androidboot.verifiedbootstate = "orange"
androidboot.countrycode = "CN"                   androidboot.keymaster = "1"
androidboot.btaddr = "androidboot.wifiaddr="     androidboot.vbmeta.device = "PARTUUID=3bd0ac22-..."
androidboot.usbdebugflag = "disable"             androidboot.vbmeta.avb_version = "1.2"
androidboot.hwboardid = "SM6225_6+128_801"       androidboot.vbmeta.device_state = "unlocked"
                                                 androidboot.vbmeta.hash_alg = "sha256"
                                                 androidboot.vbmeta.size = "8832"
                                                 androidboot.vbmeta.digest = "847fce35...cde9"
                                                 androidboot.veritymode = "eio"
                                                 androidboot.veritymode.managed = "yes"
                                                 androidboot.slot_suffix = "_a"
```

注意：`/proc/bootconfig` **只有 androidboot.* 项**，内核自己的 `msm_drm.dsi_display0=`、`video=vfb` 等在 cmdline 里（dmesg 的 `Kernel command line:` 可看到完整拼接结果）。

**KSU 运行时状态**：`su` → `uid=0(root) context=u:r:ksu:s0`；已装模块 3 个（`xbt_continuity_fix`、`xbt_recents_proxy`、`zz_density320`）；`/data/adb/service.d/` 存在（开机自修复脚本所在）。

---

## 2. init 与启动顺序

### 2.1 `/system/etc/init/hw/init.rc` 结构（1710+ 行）

**import 链（文件头）**

```
 7: import /init.environ.rc
 8: import /system/etc/init/hw/init.usb.rc
 9: import /init.${ro.hardware}.rc
10: import /vendor/etc/init/hw/init.${ro.hardware}.rc
11: import /system/etc/init/hw/init.usb.configfs.rc
12: import /system/etc/init/hw/init.${ro.zygote}.rc
611: import /system/etc/init/hw/init.boringssl.${ro.zygote}.rc
1669: import /system/etc/init/init-perfetto.rc
```

**关键阶段（行号）**

| 行 | 段 | 备注 |
|---|---|---|
| 15 | `on early-init` | 含 MIUI 的 `write /proc/bootprof "INIT:early-init"` 打点 |
| 144 | `on early-init && property:ro.boot.bootchart.enabled=""` | bootchart 分支 |
| 159 | `on init` | `sysclktz 0`、把 `/proc/cmdline`+`/proc/bootconfig` 混进熵池 |
| 714 | `on early-fs` | |
| 721 | `on post-fs` | |
| 839/860/869 | `on late-fs`（三段） | 850 行 `class_start early_hal` |
| 891 | `on late-fs && property:ro.virtual_ab.enabled=true` | **virtual A/B 专有分支** |
| 903 | `on post-fs-data` | 最长的一段（903→1372，约 470 行） |
| 1382 | `on zygote-start` | |
| 1409 | `on boot` | 含 1600 `class_start hal` / 1602 `class_start core` |
| 1604 | `on boot && property:ro.debuggable=1` | 本机 `ro.debuggable=1`，**这段会执行** |
| 1608 | `on nonencrypted` | `class_start main` + `class_start late_start` |
| 1622 | `on property:sys.boot_completed=1` | |
| 148 | `on property:sys.boot_completed=1` | MIUI 内存增强：写 `/dev/memcg/{freeze-app,protected-app}/memory.anno_writeback_*` |

**`on boot` 实际内容（很短，其余都被 MIUI 拆成条件段）**

```
on boot
    # basic network init
    ifup lo
    hostname localhost
    domainname localdomain
```

**MIUI 加的启动期特殊项（改包容易踩）**

| 行 | 内容 |
|---|---|
| 155 | `on property:persist.sys.stability.lz4asm=off` → `exec u:r:modprobe:s0 -- /system/bin/modprobe -r -d /system/lib/modules lz4asm` |
| 643 | `on property:sys.boot_from_charger_mode=1` → `class_stop charger` |
| 697 | `on perf_pin_init && property:persist.sys.systemui.compress=on` |
| 699 | `on perf_pin_overlay` |
| 880 | `on property:ro.product.cpu.abilist64=* && property:bootreceiver.enable=1` |
| 1372 | `on property:vold.checkpoint_committed=1` |
| 1376 | `on property:ro.miui.pm.install.speedinstall=*` |
| 1399 | `on property:sys.boot_completed=1 && property:ro.config.batteryless=true` → 更激进的 dirty 回写（`cp_interval 2`） |
| 1656 | `on property:persist.sys.stability.SmartCacheEnable=true` |

**dmesg 里 init 的真实启动里程碑（本次开机）**

```
 0.921396  init: init first stage started!
 0.955571  init: Loading module /lib/modules/qcom_hwspinlock.ko     ← first-stage 模块来自 ramdisk
 1.218621  init: Loaded kernel module /lib/modules/qcom_hwspinlock.ko
 1.218837  init: Loading module /lib/modules/smem.ko
 1.224446  init: Loading module /lib/modules/minidump.ko
 1.264825  init: Loading module /lib/modules/qcom_ipc_logging.ko
 1.271818  init: Loading module /lib/modules/smp2p.ko
 2.191339  printk: init: 205 output lines suppressed due to ratelimiting   ← 约 205 行模块加载日志被限流吞掉
 2.295064  init: [libfstab] Using Android DT directory /proc/device-tree/firmware/android/
 2.295675  init: EarlySetupOverlays check: debug_build: 0, force_debuggable: 0, unlocked: 1, enable_overlay: 0
 2.295685  init: EarlySetupOverlays is disabled non-debuggable build
 2.297772  init: [libfstab] ReadDefaultFstab(): target default fstab path=/vendor/etc/fstab.default
 2.302556  init: [libfstab] InjectMiProductMountEntries: injecting 3 entries    ← MIUI 运行时改 fstab
 2.302602  init: [libfstab] ModifyOverlayLowerdirsForMiProduct: /mnt/vendor/mi_product not mounted, skipping
 2.302770  init: Opening SELinux policy
 2.306878  init: /system/etc/selinux/plat_sepolicy_and_mapping.sha256
                and /odm/etc/selinux/precompiled_sepolicy.plat_sepolicy_and_mapping.sha256 differ
 2.306888  init: Compiling SELinux policy            ← ★ 每次开机现场编译，约 1.8 s
 4.090094  KernelSU: /system/bin/init second_stage executed
 4.198132  init: init second stage started!
 4.219453  selinux: Loaded file context from: plat / system_ext / product / vendor 四份
 6.273908  init: wait for '/dev/block/platform/soc/4804000.ufshc' took 0ms
26.487620  init: [libfs_mgr] Skipping '/mnt/vendor/mi_product' during mount_all
```

### 2.2 设备专有 rc

**`/vendor/etc/init/`：132 项**（完整清单见同目录 `vendor-init-rc-list.txt`），分类：

| 类别 | 数量 | 代表 |
|---|---|---|
| `android.hardware.*` 平台 HAL | 22 | `audio.service_64`、`thermal@2.0-service.qti-v2`、`usb@1.2-service-qti`、`wifi@1.0-service` |
| `vendor.qti.*` | 35 | `hardware.display.composer-service`、`hardware.perf-hal-service`、`media.c2`、`hardware.sensorscalibrate` |
| **联想 / longcheer 专有** | **8** | `init.lenovo.rc`、`vendor.lenovo.hardware.{battery,display,factory,misc,performance,touchscreen}-service.rc`、`vendor.longcheer.hardware.flag@1.0-service.rc` |
| 其它守护进程 | 60+ | `qseecomd`、`netmgrd`、`ipacm`、`imsdaemon`、`cnd`、`vendor.dolby.*`、`vndservicemanager` |
| 子目录 | — | `hw/`（按 `ro.hardware` 导入） |

**`/odm/etc/init/`：不存在**（`No such file or directory`）。`/odm` 虽然挂上了（`/dev/block/dm-12`，1.4 MiB），但里面没有 init 目录，`/odm/etc/fstab*` 也不存在 —— **ODM 是空的**，所有 vendor 定制都压在 `/vendor` 里。

**关键 rc 摘要（按重要性）**

- `init.lenovo.rc` —— 联想自己的入口，`ro.vendor.config.lgsi.*` 一整套（`device.type=pad`、`screen_size=11`、`platform=qcom`、`hw.version=TB331FC`）就是这里读的。
- `vendor.qti.hardware.perf-hal-service.rc` —— 起 `perf-hal-2-3`。**注意：服务在跑，但 sepolicy 不让系统侧 `find` 它**（见 §3.4，35 次/开机被拒）。
- `imsdaemon.rc` —— 起 `vendor.imsdaemon`，实测 `init.svc.vendor.imsdaemon=stopped`（WiFi-only 无 modem，崩溃循环后已被 KSU `service.d` 停掉）。
- `init.qti.display_boot.rc` —— `qti_display_boot` 服务，实测 `stopped`（跑完即退，正常）。
- `vendor.lenovo.hardware.touchscreen-service.rc` —— `touchscreen_hal_service`，实测 `running`。

**init 服务总览（214 个 `init.svc.*` 属性）**：`running` 134 / `stopped` 80。关键 HAL 状态：

```
running:  android.thermal-hal, perf-hal-2-3, performance, vendor.perfservice,
          display_aidl_service, display-color-hal-1-0, vendor.qti.hardware.display.{allocator,composer},
          audioserver, vendor.audio-hal, vendor.audioadsprpcd_audiopd,
          vendor.sensors-hal-2-1-multihal, sensorscal-hal-1-0, touchscreen_hal_service,
          gnss_service, thermal-engine, wifidisplayhalservice, vendor.wifi_hal_legacy,
          vendor-dolby-media-c2-hal-1-0, vendor-qti-media-c2audio-hal-1-0, battery_aidl_service
stopped:  vendor.imsdaemon, qti_display_boot, system_perf_init, apexd, bootanim,
          audioshell_system, bpfloader, traced_perf
```

### 2.3 分区挂载

**fstab：`/vendor/etc/fstab.default`**（`ro.boot.fstab_suffix=default`）。另有 `fstab.emmc`（5954 B）、`fstab.zram_wb`（180 B）。**`/odm/etc/fstab*` 不存在。**

| 挂载点 | 源 | 类型 | fs_mgr flags | verity? | logical? |
|---|---|---|---|---|---|
| `/system` | `system` | ext4 | `wait,slotselect,avb=vbmeta_system,logical,first_stage_mount,avb_keys=/avb/{q,r,s}-gsi.avbpubkey` | ✅ | ✅ |
| `/system_ext` | `system_ext` | ext4 | `wait,slotselect,avb=vbmeta_system,logical,first_stage_mount` | ✅ | ✅ |
| `/product` | `product` | ext4 | 同上 | ✅ | ✅ |
| `/vendor` | `vendor` | ext4 | `wait,slotselect,avb,logical,first_stage_mount` | ✅（`avb` 无参=vbmeta_a） | ✅ |
| `/vendor_dlkm` | `vendor_dlkm` | ext4 | 同上 | ✅ | ✅ |
| `/system_dlkm` | `system_dlkm` | ext4 | 同上 | ✅ | ✅ |
| `/odm` | `odm` | ext4 | 同上 | ✅ | ✅ |
| `/metadata` | `/dev/block/by-name/metadata` | **f2fs** | `wait,check,formattable,first_stage_mount` | ❌ | ❌ |
| `/data` | `userdata` | **f2fs** | `latemount,wait,check,formattable,quota,reservedsize=128M,fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0,metadata_encryption=...,keydirectory=/metadata/vold/metadata_encryption,checkpoint=fs` | ❌ | ❌ |
| `/mnt/vendor/persist` | `persist` | ext4 | `wait` | ❌ | ❌ |
| `/misc` | `misc` | emmc | `defaults` | ❌ | ❌ |
| `/vendor/firmware_mnt` | `modem` | vfat | `ro,...,context=u:object_r:firmware_file:s0` | ❌ | ❌ |
| `/vendor/dsp` | `dsp` | ext4 | `ro` | ❌ | ❌ |
| `/vendor/bt_firmware` | `bluetooth` | vfat | `ro,context=u:object_r:bt_firmware_file:s0` | ❌ | ❌ |
| swap | `/dev/block/zram0` | swap | `zramsize=65%,zram_backingdev_size=prop` | ❌ | ❌ |

**★ dm-verity 是真的开着 —— 每个逻辑分区都是「linear + verity」两层，挂的是 verity 那一层**

`/dev/block/mapper/` 的符号链接把两层结构暴露得很清楚（`dmsetup` 命令本机没有，用 sysfs 侧的 mapper 链接等价取证）：

| 逻辑分区（dm-linear over super） | 上层的 verity 设备 | 实际挂载点 |
|---|---|---|
| `odm_a` → `dm-0` | **`odm-verity` → `dm-12`** | `/odm` |
| `system_dlkm_a` → `dm-1` | **`system_dlkm-verity` → `dm-11`** | `/system_dlkm` |
| `vendor_a` → `dm-2` | **`vendor-verity` → `dm-9`** | `/vendor` |
| `vendor_dlkm_a` → `dm-3` | **`vendor_dlkm-verity` → `dm-10`** | `/vendor_dlkm` |
| `system_a` → `dm-4` | **`system-verity` → `dm-7`** | `/` |
| `system_ext_a` → `dm-5` | **`system_ext-verity` → `dm-8`** | `/system_ext` |
| `product_a` → `dm-6` | **`product-verity` → `dm-13`** | `/product` |
| （无） | `userdata` → `dm-56` | `/data`（FBE，非 verity） |
| （无） | `dm-swapfile` → `dm-57` | zram backing |

dmesg 侧完全对得上（每次挂载前建 verity 表，7 组，**零条校验失败**）：

```
[2.137146] device-mapper: verity: sha256 using implementation "sha256-ce"
[2.142154] EXT4-fs (dm-7):  mounted ...   ← /system      (system-verity)
[2.146666] device-mapper: verity: sha256 using implementation "sha256-ce"
[2.152217] EXT4-fs (dm-8):  mounted ...   ← /system_ext  (system_ext-verity)
[2.157559] ... (dm-9  /vendor      = vendor-verity)
[2.161818] ... (dm-10 /vendor_dlkm = vendor_dlkm-verity)
[2.165499] ... (dm-11 /system_dlkm = system_dlkm-verity)
[2.168836] ... (dm-12 /odm         = odm-verity)
[2.173922] ... (dm-13 /product     = product-verity)
```

> **改包硬约束**：动 `/system`、`/system_ext`、`/product` 任何一个字节，都必须**重算 hashtree + 重签对应 vbmeta**（`system/system_ext/product` → `vbmeta_system`；`vendor*`/`odm` → `vbmeta`）。
> 但本机 `veritymode=eio`（不是 `restart`），所以校验失败**表现为读 EIO 而不是重启** —— 出错时可能只是某文件读失败、系统诡异但能开机，**不会给你明显的"verity fail"提示**。这也是为什么本机两处修复都选了 bind-mount 而不是改镜像。

**实际挂载（`/proc/mounts` 158 条，全表见 `mounts.txt`）**

| fstype | 条数 | 说明 |
|---|---|---|
| ext4 | 93 | 7 个 dm 逻辑分区 + apex 挂载 |
| f2fs | 14 | `/data`、`/metadata`、`/data_mirror/*`、`/data/user/0` |
| tmpfs | 12 | |
| **erofs** | 10 | **apex 用 erofs**（`/bootstrap-apex/com.android.{runtime,virt}`） |
| functionfs | 6 | USB gadget |
| cgroup/cgroup2 | 5 | |
| fuse / fuse.miuserfsd | 5 | MIUI 自己的 FUSE 守护 |
| vfat | 2 | firmware_mnt / bt_firmware |

**★ 两个 bind-mount 痕迹 = 本机两处 KSU 修复的落地方式**

```
/dev/block/dm-56  /system/framework/framework-res.apk                 f2fs
/dev/block/dm-56  /system_ext/etc/permissions/continuity_sdk_app.xml  f2fs
```

`dm-56` = `/data`（userdata）。即：
- **全面屏手势修复**：`framework-res.apk` 由 `/data` 里的文件 bind-mount 覆盖（对应 KSU 模块 `xbt_recents_proxy`）；
- **continuity SDK 修复**：`continuity_sdk_app.xml` 同样 bind-mount 覆盖（对应 `xbt_continuity_fix`）。

> 这说明本机改系统文件**不需要动分区镜像**——`/data` + `post-fs-data.sh` bind-mount 就够了，且天然可回滚。

**其它关键挂载事实**

- `/dev/block/sda2` → `/mnt/vendor/persist`，**ext4 且已挂上**（`rw`）—— 与历史记忆里「persist 全零导致声音+录音消失」那次事故形成对照：现在 persist 是好的。
- `/bootstrap-apex/*` 用 **erofs + loop 设备**（`loop0/loop1`），而 `/apex/*@370399999` 用 ext4 + dm 设备 —— A17 的 bootstrap apex 机制。
- `/vendor`、`/vendor_dlkm`、`/system_dlkm`、`/odm` 都挂成 **`without journal`**（`EXT4-fs (dm-9): mounted filesystem without journal`）；`/` 和 `/product` 是 `ordered data mode`。
- 所有 ext4 挂载都带 `discard`，而 dmesg 明确警告：`EXT4-fs (dm-7): mounting with "discard" option, but the device does not support discard` —— 逻辑分区（dm-linear）不支持 discard，`discard` 是空转。

### 2.4 动态分区（`lpdump`，全表见 `lpdump.txt`）

```
Metadata version: 10.2      Metadata size: 1384 B   max 65536 B   3 个 metadata slot
Header flags: virtual_ab_device        Current slot: _a
super: First sector 2048, 12,884,901,888 B = 12.00 GiB   (即 /dev/block/sda10)
Snapshot state: Update state: none, Using snapuserd: 0, Using userspace snapshots: 0
Boot indicator: booting from unknown slot
```

**逻辑分区（slot `_a` 有实体，`_b` 全是空 extent —— 虚拟 A/B）**

| 分区 | 组 | 属性 | 扇区 | 大小 | super 起始扇区 |
|---|---|---|---|---|---|
| `system_a` | **default** | none | 3,417,968 | **1,668.9 MiB** | 5120 |
| `product_a` | **default** | none | 5,859,368 | **2,861.0 MiB** | 3,423,232 |
| `system_ext_a` | **default** | none | 3,027,336（**两段**：2,615,296 + 412,040） | **1,478.2 MiB** | 9,283,584 和 11,899,904 |
| `odm_a` | qti_dynamic_partitions_a | readonly | 2,768 | 1.4 MiB | 2048 |
| `system_dlkm_a` | qti_dynamic_partitions_a | readonly | 856 | 0.4 MiB | 11,898,880 |
| `vendor_a` | qti_dynamic_partitions_a | readonly | 1,330,616 | 649.7 MiB | 12,800,000 |
| `vendor_dlkm_a` | qti_dynamic_partitions_a | readonly | 115,104 | 56.2 MiB | 14,131,200 |
| `system_b`/`system_ext_b`/`product_b`/`odm_b`/`vendor_b`/`vendor_dlkm_b`/`system_dlkm_b` | `*_b` | readonly | — | **空（0 extent）** | — |

**要点（改包必看）**

1. **`system_a` / `system_ext_a` / `product_a` 属于 `default` 组且 `Attributes: none`** —— 不是 `readonly`，理论上可 resize；而 `vendor*`/`odm`/`system_dlkm` 属 `qti_dynamic_partitions_a` 且 `readonly`。
2. **`system_ext_a` 是两段不连续的 extent**（2,615,296 + 412,040 扇区，中间被 `system_dlkm_a` 和别的东西隔开）—— 用 `fastboot flash system_ext` 刷整块时靠 lp 元数据拼，别指望线性偏移。
3. **`_b` 槽全空** —— 虚拟 A/B，没有真正的 B 系统。`lpdump` 明说 `booting from unknown slot`，`Source build fingerprint` 空。所以**「切槽回滚」在本机不成立**，回滚只能重刷 `_a`。
4. `super` 共 12 GiB，已用约 6.7 GiB（system+product+system_ext+vendor+dlkm+odm），余量约 5.3 GiB。

---

## 3. SELinux 与权限

### 3.1 状态

| 项 | 值 |
|---|---|
| `getenforce` | **`Enforcing`** |
| `/sys/fs/selinux/enforce` | `1` |
| `ro.boot.selinux` | **空**（未设 → 默认 enforcing） |
| `ro.build.selinux` | 空 |
| `/sys/fs/selinux/policyvers` | **`331`** |
| audit 记录 | `type=1404 ... enforcing=1 old_enforcing=0 ... enabled=1`（4.079 s） |

`/sys/fs/selinux/` 节点齐全（`access avc booleans checkreqprot class commit_pending_bools context create deny_unknown disable enforce initial_contexts load member mls policy policy_capabilities policyvers reject_unknown ...`）。

### 3.2 ★ 每次开机现场编译 sepolicy（关键机制）

```
[2.306878] init: /system/etc/selinux/plat_sepolicy_and_mapping.sha256
              and /odm/etc/selinux/precompiled_sepolicy.plat_sepolicy_and_mapping.sha256 differ
[2.306888] init: Compiling SELinux policy
[4.090094] KernelSU: /system/bin/init second_stage executed     ← 1.8 s 后才进第二阶段
```

**含义**：
- `/odm/etc/selinux/precompiled_sepolicy` 是按 **A13 vendor 的 plat sepolicy** 预编译的，与现在 A17 的 `/system/etc/selinux/plat_sepolicy_and_mapping.sha256` 对不上 → init 走 `selinux_android_restorecon` 的**现场编译**路径（`secilc` 逻辑），**每次开机多花约 1.8 秒**。
- 这条是「跨代拼装」的直接体检报告：**policy 不是官方配好的一对，而是每次开机临时拼的**。
- 改包提醒：如果往 `/system/etc/selinux/` 或 `/vendor/etc/selinux/` 塞自定义 `.cil`，走的是同一条现场编译路径 —— 语法错会让 **init 直接死**（不是降级），因为编译失败没有兜底。

**policy 输入文件清单（实测各目录内容）**

| 目录 | 内容 |
|---|---|
| `/system/etc/selinux/` | `plat_sepolicy.cil`、`plat_sepolicy_and_mapping.sha256`、`plat_file_contexts`、`plat_property_contexts`、`plat_service_contexts`、`plat_hwservice_contexts`、`plat_seapp_contexts`、`plat_keystore2_key_contexts`、`plat_tee_service_contexts`、`plat_mac_permissions.xml`、`mapping/`、`bug_map/`，**以及三个 genfs 版本**：`plat_sepolicy_genfs_202504.cil`、`plat_sepolicy_genfs_202604.cil`、`plat_sepolicy_genfs_202704.cil` |
| `/system_ext/etc/selinux/` | `system_ext_sepolicy.cil` + 对应 contexts/sha256，**以及 `userdebug_plat_sepolicy.cil`**（本机 `ro.debuggable=1`，所以 userdebug 变体生效） |
| `/product/etc/selinux/` | `product_sepolicy.cil` + contexts/sha256 |
| `/vendor/etc/selinux/` | `vendor_sepolicy.cil`、**`plat_pub_versioned.cil`**、**`plat_sepolicy_vers.txt`**、`vndservice_contexts`、`selinux_denial_metadata/` |
| `/odm/etc/selinux/` | **只有 4 个文件**：`precompiled_sepolicy` + `precompiled_sepolicy.{plat,product,system_ext}_sepolicy_and_mapping.sha256` |

> **三个 `plat_sepolicy_genfs_*` 版本（202504 / 202604 / 202704）是个有意思的细节**：A17 的 plat 侧按**vendor API level** 准备了多套 genfs 规则，运行期按 `ro.board.api_level` 挑。本机 vendor 是 api 33（远低于 202504），所以这些新 genfs 规则全部不匹配 —— 这也是「历史记忆里 `ro.llndk.api_level=202604` 说法」的来源（那是某个版本的**要求值**，不是本机的值；本机实际 `ro.llndk.api_level=33`）。
> `plat_pub_versioned.cil` + `plat_policy_vers.txt` 是「vendor 侧只公开一个版本化子集」的机制，用于跨版本 vendor 兼容 —— 本机能开机靠的就是这条通道。

### 3.3 KSU 的 SELinux 处理

| 动作 | dmesg 原文 |
|---|---|
| 备份原 policy | `KernelSU: backup sepolicy success! latest_granting=1` |
| 改 netlink 配置 | `adding POLICYDB_CONFIG_ANDROID_NETLINK_ROUTE` / `..._GETNEIGH` → `new config: 3221225473` |
| 自建 su 域并缓存 SID | `sid '70' is set for secctx_name 'u:r:ksu:s0'`、`Cached su SID: 70`、`Cached zygote SID: 69`、`Cached init SID: 71`、`Cached ksu_file SID: 73` |
| **selinux_hide（反检测）** | `feature: registered handler for selinux_hide (id=4)`、`initialize_fake_status: status_page not exist`、`selinux_hide: fake status need late initialization`、`initialize_fake_status initialized: sequence=0, policyload=0, enforcing=1` |
| SUSFS 逐进程打标 | `KernelSU: susfs: mark no sucompat checks for pid: '1280', exec: '/vendor/bin/hw/android.hardware.thermal@2.0-service.qti-v2'`（同类多条，针对 thermal-engine、cnss_diag 等） |

> **`/sys/kernel/ksu`、`/sys/kernel/susfs*` 都不存在**（`find /sys -iname '*ksu*'` 空、`ls /sys/kernel/susfs*` → No such file）。KSU 3.x 已改为 **prctl + ioctl 通道**（dmesg 里那张 IOCTL 命令表：`GRANT_ROOT=0x4b01`、`GET_INFO=0x80104b02`、`SET_SEPOLICY=0xc0004b04`、`GET_SULOG_FD=0x40044b14`、`DISABLE_ESCAPE_TO_ROOT=0x4b15` 等），**没有 sysfs 节点可读**。想验证 root 只能用 `su -c id`，别去翻 `/sys/kernel/ksu`。

### 3.4 运行期 AVC 统计（本次开机 315 s 内 **632 条**，`permissive=0` 占 **631** 条）

> `permissive=0` 意味着**真的被拒**，不是宽松模式下的记录。

| 次数 | 源域 | 权限 | 目标 | 类 | 影响 |
|---|---|---|---|---|---|
| **368** | `u:r:graphicsengine:s0` | read | `hwservicemanager_prop` | file | 图形引擎反复读不到属性文件，噪声，**不影响使用**（每 ~0.85 s 一次） |
| **134** | `u:r:platform_app_36:s0` | write | `vendor_dpmtcm_socket` (`tcm`) | sock_file | 小米账号/网络定位/推送/商店/云同步/小爱 共 6 个 app 反复写失败，**降级但不崩** |
| **35** | 多域（system_app / platform_app / priv_app） | **find** | `vendor.qti.hardware.perf2.IPerf/default` | service_manager | **性能 HAL 不可达** → `WLC-Service: Waiting For perf mpctl Init Completion` 45 次/开机 |
| 15+14+12+4+2+2 | `platform_app_36`/`system_server`/`system_app`/`priv_app`/`radio`/`shell` | **find** | `default_android_service` | service_manager | 见下表 |
| 7 | 多域 | find | `HyperOSCustFeatureResolve` | service_manager | **`miui.os.HyperOSCustFeatureResolve` NPE**（见 §5） |
| 7 | `system_server` | find | `vendor.xiaomi.hw.touchfeature.ITouchFeature/default` | service_manager | 触控增强特性不可用（触屏本身正常） |
| 6+6 | `system_server` / `bpfloader` | read | `vendor_default_prop` | file | 属性读不到 |
| 6 | `vendor_qti_embmssl_app` | read | `default_prop` | file | |
| 4 | `priv_app` | search | `mcd_data_file` | dir | |
| 3 | `vendor_init` | **set** | `default_prop` | property_service | **vendor/build.prop 的属性被丢弃**（见 §3.5） |
| 2+2 | `vendor_init` | set | `build_prop` / `audio_prop` | property_service | 同上 |
| 2 | `fsck` | write | `tmpfs` | dir | |
| 3 | `hypsys_ssi_default` | read | `tmpfs` | dir | 小米 HyperOS SSI 服务 |

**被拒的 `find` 服务清单（跨代 sepolicy 缺 type 的直接后果）**

| 服务名 | 次数 |
|---|---|
| `vendor.qti.hardware.perf2.IPerf/default` | 35 |
| `HyperOSCustFeatureResolve` | 7 |
| `vendor.xiaomi.hw.touchfeature.ITouchFeature/default` | 7 |
| `vendor.xiaomi.aidl.mipowerhal.IMiPowerHalAIDLService/default` | 3 |
| `vendor.qti.sla.service.ISlaAIDLService/default` | 2 |
| `vendor.xiaomi.hardware.display.mihwcextension.IMiHwcExtension/default` | 1 |
| `vendor.xiaomi.hardware.displayfeature_aidl.IDisplayFeature/default` | 1 |
| `vendor.xiaomi.hardware.display.mihwcextension` / `misys` / `cld` / `minet` / `videoservice` / `servicetracker` / `mediaeventgather` / `extphone` | 各 1 |

> **机制解释**：这些服务的 `tcontext` 全是 `u:object_r:default_android_service:s0` —— 说明 **A13 vendor 的 sepolicy 里根本没有这些服务的专用 type**（`perf2`、`touchfeature`、`mipowerhal` 都是 A15+ 才进 AOSP/小米 sepolicy 的）。服务注册时被标成兜底 type，而 A17 的 plat sepolicy 不允许 app 域 `find` 兜底 type → 全部被拒。**这是「服务在跑但用不了」的典型形态**，光看 `init.svc.*=running` 会误判。
>
> ⚠️ **一个容易搞混的点**：servicemanager 在做 `checkService(name)` 时，**先按名字查 sepolicy、再查服务是否存在** —— 所以即使服务压根没注册，也会先产出一条 `find` 拒绝的 AVC。因此**「看到 AVC 被拒」≠「服务存在但被挡」**。本机 `perf2` 和 `HyperOSCustFeatureResolve` 实测是**服务根本不在 `service list`（371 条）里**（见 §3.6），AVC 只是次生现象。**判定顺序应该是：先 `service list | grep <名字>`，再看 AVC。**

### 3.5 vendor 属性被 SELinux 丢弃（隐蔽但真实）

```
[4.246715] init: Do not have permissions to set 'ro.adb.secure' to '1' in property file '/vendor/build.prop':
              SELinux permission check failed (source_context=u:r:vendor_init:s0, target_context=u:object_r:build_prop:s0)
[4.246991] init: Do not have permissions to set 'persist.backup.ntpServer' to '0.pool.ntp.org' ... (default_prop)
[4.247311] init: Do not have permissions to set 'vendor.mm.enable.qcom_parser' ... (vendor_mm_parser_prop)
[4.247432] init: Do not have permissions to set 'ro.qc.sdk.audio.ssr' ... (default_prop)
[4.247465] init: Do not have permissions to set 'ro.qc.sdk.audio.fluencetype' ... (default_prop)
[4.247518] init: Do not have permissions to set 'persist.audio.fluence.voicecall' ... (audio_prop)
[4.247553] init: Do not have permissions to set 'persist.audio.fluence.voicerec' ... (audio_prop)
[4.243802] init: Overriding previous property 'ro.control_privapp_permissions':'disable' with new value 'enforce'
```

**含义**：A17 的 plat sepolicy 收紧了 `build_prop` / `default_prop` / `audio_prop` 的写入权限，而 vendor 侧 `build.prop` 还按 A13 的规则写这些 —— **静默丢弃，不报错到上层**。
- 直接后果：`persist.audio.fluence.*`（双麦降噪）没生效；`vendor.mm.enable.qcom_parser` 没设；`ro.adb.secure` 被系统侧强制为 `0`（本机 `ro.adb.secure=0`）。
- 排查音频/WiFi 问题时**先查这个**，别以为是驱动问题。

### 3.6 「开发者选项闪退」——**已实测：不闪退，但确实踩到 sepolicy + 缺服务**

**实测方法**（只拉 Activity，未改任何东西，结束后已把前台恢复为 `com.miui.home` 桌面）：
```
adb shell am start -W -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS
```
返回 `Status: ok`，`Activity: com.android.settings/.Settings$DevelopmentSettingsActivity`（**注意 MIUI 把类名从 AOSP 的 `DevelopmentSettingsDashboardActivity` 改成了 `DevelopmentSettingsActivity`**）。

**结果：没有闪退。**
- `pidof com.android.settings` = `16681`，进程存活；
- `logcat -b crash` = **0 行**，全程无 `FATAL EXCEPTION`、无 `ANR in`；
- `mFocusedApp` 正常落在 `Settings$DevelopmentSettingsActivity`。

**但打开的一瞬间确实产生了两类错误**：

**(1) `HyperOSCustFeatureResolve` NPE —— 完整堆栈（本次抓到根因）**
```
E HyperOSCustFeatureResolve: java.lang.NullPointerException: Attempt to invoke interface method
    'boolean miui.os.IHyperOSCustFeatureResolve.getCustResolveBooleanFeature(java.lang.String, boolean)'
    on a null object reference
  at miui.os.HyperOSCustFeatureResolve.getBoolean(HyperOSCustFeatureResolve.java:43)
  at miui.securityspace.ConfigUtils.isSupportSecuritySpace(ConfigUtils.java:30)
  at com.android.settings.development.SecondSpaceDeleteController.isAvailable(SourceFile:75)
  at com.android.settings.development.SecondSpaceDeleteController.updateState(SourceFile:70)
  at com.android.settings.development.SecondSpaceDeleteController.onResume(SourceFile:66)
  ...
  at com.android.settings.development.DevelopmentSettingsDashboardFragment.onResume(SourceFile:405)
E HyperOSCustFeatureResolve: at com.android.settings.development.DevelopmentSettingsDashboardFragment.enableDeveloperOptions(SourceFile:1161)
```
即：**打开开发者选项 → `SecondSpaceDeleteController`（"删除第二空间"这一项）在 `onResume` 里问"支不支持第二空间" → `miui.securityspace.ConfigUtils.isSupportSecuritySpace` → `HyperOSCustFeatureResolve.getBoolean` → 服务是 null → NPE**。异常被 Settings 自己 catch 掉（只打 E 日志），所以**只降级不崩**。

**(2) 同一时刻 4 条 `permissive=0` 的 AVC**
```
avc: denied { read } for name="u:object_r:vendor_display_prop:s0"
     scontext=u:r:system_app:s0 tcontext=u:object_r:vendor_display_prop:s0 tclass=file permissive=0
avc: denied { call } scontext=u:r:system_app:s0 tcontext=u:r:vendor_hal_gnss_qti:s0      tclass=binder permissive=0
avc: denied { call } scontext=u:r:system_app:s0 tcontext=u:r:hal_health_default:s0       tclass=binder permissive=0
avc: denied { call } scontext=u:r:system_app:s0 tcontext=u:r:hal_memtrack_default:s0     tclass=binder permissive=0
```
**`system_app` 无权通过 binder `call` 三个 HAL（gnss / health / memtrack）** —— 这是 A13 vendor sepolicy 没有给 A17 的 `system_app` 开放这些 `call` 权限。开发者选项里"后台进程限制/GPU 呈现/电量统计"类页面会因此拿到空数据。

**★ 根因升级：不是 sepolicy 挡的，是服务根本不存在**

```
$ service list | wc -l          →  371
$ service list | grep -i HyperOSCust  →  0 条
$ service list | grep -i perf2        →  0 条   （但 vendor.lenovo.hardware.performance.IPerformance 在、vendor.perfservice 在）
```

- **`HyperOSCustFeatureResolve` 服务未注册**（371 个服务里没有）→ `getBoolean` 拿到 null 是必然的，与 sepolicy 无关。
- **`vendor.qti.hardware.perf2.IPerf` 也未注册** → 尽管 `init.svc.perf-hal-2-3` 是 `running`，它注册的是旧版 **HIDL** `vendor.qti.hardware.perf@2.3`，A17 要的 **AIDL `perf2`** 不存在。这才是 `WLC-Service: Waiting For perf mpctl Init Completion` 45 次/开机永远等不到的真正原因。
- §3.4 里那些 `find ... default_android_service` 的 AVC，是 framework **尝试查找一个本就不存在的服务**时被 sepolicy 再挡一道的次生现象。

> **结论**：`开发者选项闪退` **在本 build 上未复现**（能正常打开）。历史上若真崩过，最可能就是 `HyperOSCustFeatureResolve` 这条链 —— 某些子页面如果没 catch 这个 NPE 就会崩。**修的方向不是改 sepolicy，而是补服务**（`HyperOSCustFeatureResolve` 属于小米 framework/vendor 配套件；`perf2` 属于 QCOM A15+ HAL，A13 vendor 根本没有，只能靠 framework 侧兼容或换 vendor）。

**历史痕迹（旁证，说明这条线确实被追过）**

设备上还留着上一轮排查的产物：

```
/data/local/tmp/devopt.rule:
    allow system_app logpersistd_logging_prop property_service set
    allow system_app logpersistd_logging_prop file { read getattr map open }
/data/local/tmp/dev_crash.sh:   # 清 logcat → 拉起开发者选项 → 等 5 s → 抓 FATAL / AndroidRuntime / Settings_CRASH
/data/local/tmp/devprof/        # 另有目录
```

`devopt.rule` 针对的是 `logpersistd_logging_prop` —— 即开发者选项里「**日志记录器缓冲区大小 / 启用日志持久化**」那一项。这条 sepolicy 规则如果当时是手工 `apply_se.sh` 临时加进去的，**重启就失效**（本机 sepolicy 每次开机现场编译，不会持久化），所以「开发者选项一打开就闪退」的现象可能在不同 boot 之间表现不一致 —— 这也解释了为什么本次复现不了。

---

## 4. 属性与身份

> 全量 2195 条见同目录 `getprop.txt`。以下只列与「平板形态 / 性能 / 显示 / 身份」相关的。

### 4.1 身份总表

| 属性 | 值 |
|---|---|
| `ro.build.fingerprint` | `Lenovo/miproduct_yupei/TB331FC:17/CP2A.260605.016/OS4.0.5.0.XPZCNXM:user/release-keys` |
| `ro.build.description` | `yupei-user 17 CP2A.260605.016 OS4.0.5.0.XPZCNXM release-keys` |
| `ro.build.id` | `CP2A.260605.016` |
| **`ro.build.display.id`** | **`CP2A.260605.016 by dsshhgg`** ← 打包者签名串 |
| **`ro.mi.os.version.incremental`** | **`OS4.0.5.0 by dsshhgg`** ← 同上 |
| `ro.build.version.release` / `sdk` / `sdk_full` | `17` / `37` / `37.0` |
| `ro.build.version.incremental` | `OS4.0.5.0.XPZCNXM` |
| `ro.build.version.security_patch` | `2026-08-01` |
| `ro.build.date` | `Sun Sep 13 21:05:44 CST 2026` |
| `ro.build.type` / `tags` | `user` / `release-keys` |
| `ro.mi.os.version.{code,name,release}` | `4` / `OS4.0.5.0` / `17` |
| `ro.miui.ui.version.{code,name}` | `816` / `V816` |
| `ro.product.device` / `model` / `name` | `TB331FC` / `TB331FC` / **`miproduct_yupei`** |
| `ro.product.brand` / `manufacturer` | `Lenovo` / `LENOVO` |
| `ro.product.board` | `bengal` |
| `ro.product.name_for_attestation` | `TB331FC_PRC` |
| `ro.product.property_source_order` | `odm,vendor,product,system_ext,system` |
| `ro.build.characteristics` | **`tablet`** |
| `ro.product.cpu.abilist` | `arm64-v8a,armeabi-v7a,armeabi` |
| `ro.zygote` | `zygote64_32` |
| `ro.treble.enabled` | `true` |

### 4.2 ★ 跨代证据（vendor 侧）

| 属性 | 值 |
|---|---|
| **`ro.vendor.build.fingerprint`** | **`Lenovo/TB331FC_PRC/TB331FC:14/UKQ1.230917.001/ZUI_16.0.544_241115_PRC:user/release-keys`** |
| **`ro.vendor.build.version.sdk`** | **`33`** |
| `ro.vendor.build.version.release` / `release_or_codename` | `13` / `13` |
| `ro.vendor.build.version.incremental` | `TB331FC_CN_OPEN_USER_Q00003.0_U_ZUI_16.0.544_ST_241115` |
| `ro.vendor.build.date` | `Fri Nov 15 06:04:18 CST 2024` |
| `ro.vendor.build.security_patch` | **`2024-10-05`**（比 system 侧旧 22 个月） |
| **`ro.llndk.api_level`** / `ro.vendor.api_level` / `ro.board.api_level` / `ro.board.first_api_level` / `ro.product.first_api_level` | **全 `33`** |
| `ro.vendor.com.zui.version` | `16.0` |
| `ro.vendor.qti.soc_model` / `soc_id` | `SM6225` / `518` |
| `ro.vendor.perf-hal.ver` | `2.3` |

> **系统侧 sdk37 / vendor 侧 sdk33 = 跨 4 代**。所有 §3.4 的 sepolicy 缺 type、§5 的 VINTF 缺 HAL，根子都在这一行。

### 4.3 平板形态 / 显示 / 性能

| 属性 | 值 | 说明 |
|---|---|---|
| `ro.sf.lcd_density` | **`320`** | 关键：1200px ÷ 320 × 160 = **600 dp**，刚好卡到 `sw600dp` 平板门槛 |
| `persist.miui.density_v2` | **`320`** | 与上一行同值，无 override |
| `ro.build.characteristics` | `tablet` | |
| `ro.vendor.config.lgsi.device.type` | `pad` | 联想侧也认平板 |
| `ro.vendor.config.lgsi.screen_size` | `11` | 11 寸 |
| `ro.opengles.version` | `196610` = 3.2 | |
| `ro.surface_flinger.has_HDR_display` | `true` | |
| `ro.surface_flinger.has_wide_color_display` | `true` | |
| `ro.surface_flinger.use_color_management` | `true` | |
| `ro.surface_flinger.supports_background_blur` | `1` | 但 `persist.sys.background_blur_supported=false`（overlay 是 true）→ **模糊实际关闭**（性能考虑） |
| `ro.surface_flinger.game_default_frame_rate_override` | `60` | |
| `ro.surface_flinger.max_virtual_display_dimension` | `4096` | |
| `ro.hwui.texture_cache_size` / `max_texture_allocation_size` | `72` / `209715200` | |
| `persist.sys.computility.{cpu,gpu}level` | `5` / `5`（V2: cpu `4`, gpu `3`, device `3`） | 小米算力分级：**低端机** |
| `ro.vendor.gpu.available_frequencies` | `1260/1114.8/1025/785/600/465/320 MHz` | Adreno 610 |
| `ro.vendor.dolby.dax.version` | `DAX3_3.8.5.20_r1` | |
| `ro.vendor.perf.scroll_opt` | `false` | |
| `debug.hwui.*` skia tracing | 全 `false` | |

### 4.4 boot / 安全状态

| 属性 | 值 | 含义 |
|---|---|---|
| `ro.boot.slot_suffix` | **`_a`** | A 槽 |
| `ro.boot.verifiedbootstate` | **`orange`** | **已解锁 + 自签 vbmeta**（橙灯） |
| `ro.boot.veritymode` | **`eio`** | verity 开启，但**校验失败只返 EIO 不重启** |
| `ro.boot.veritymode.managed` | `yes` | 用户态（fastboot `--disable-verity`）可管 |
| `ro.boot.flash.locked` | `0` | 未锁 |
| `ro.boot.vbmeta.device_state` | `unlocked` | |
| `ro.boot.vbmeta.size` / `digest` / `hash_alg` | `8832` / `847fce35…cde9` / `sha256` | |
| `ro.boot.avb_version` / `vbmeta.avb_version` | `1.2` / `1.2` | |
| `ro.boot.secboot` | `yes` | |
| `ro.secureboot.lockstate` / `devicelock` | `unlocked` / `1` | |
| `ro.boot.bootreason` / `sys.boot.reason` | `bootloader` / `bootloader` | |
| `persist.sys.boot.reason.history` | `bootloader,54` | **累计 54 次 bootloader 重启** |
| `ro.boot.hwboardid` | `SM6225_6+128_801` | 6+128 版本 |
| `ro.boot.hwlevel` / `baseband` | `MP` / `apq` | **WiFi-only 无 modem** |
| `ro.boot.dtbo_idx` / `dtb_idx` | `2` / `0` | |
| `ro.boot.fstab_suffix` | `default` | |
| `ro.boot.memcg` | `1` | |
| `ro.boot.load_modules_parallel` | `false` | **模块串行加载**（改模块清单会影响开机时间） |
| `ro.boot.mirrorflag` | `disable` | |
| `ro.debuggable` / `ro.secure` / `ro.adb.secure` | **`1` / `0` / `0`** | **userdebug 性质：adb root 免授权** |
| `ro.control_privapp_permissions` | `enforce` | 被 system 侧覆盖（vendor 写的 `disable` 被顶掉） |
| `ro.crypto.state` / `type` | `encrypted` / `file` | FBE 已开 |
| `sys.boot_completed` | `1` | |
| `ro.vendor.radio.noril` | `true` | **确认无 RIL**（WiFi-only） |

---

## 5. 已知问题与运行期证据

> 全部取自**本次开机**（13:09 起，dmesg 315 s / logcat 4 min）。dmesg 未回卷（`log_buf_len=2048k`，实际 5645 行），因此是「从开机第一秒到现在」的完整记录。

### 5.1 按频率排序（logcat 侧，11-24 当次开机）

| 次数 | tag | 内容 | 影响使用？ |
|---|---|---|---|
| **572** | `E ThermalResourceMonitor` | `FileNotFoundException: /sys/class/thermal/thermal_message/board_sensor_temp` | ⚠️ **是（轻度）**：MIUI `mirim` 温控红线读不到温度，降级保护失效 |
| **529** | `E HyperOSCustFeatureResolve` | `NullPointerException: ... IHyperOSCustFeatureResolve ... on a null object reference`（`getBoolean` L43） | ⚠️ **是**：MIUI 特性开关全走空指针兜底；**根因是该 binder 服务未注册**，详见 §3.6 |
| **257**（dmesg）/ 248（logcat） | `E init` | `Control message: Could not find 'aidl/vendor.qti.data.nwmgr.INwMgr' for ctl.interface_start` | ❌ 否（A17 期望的 nwmgr 服务 A13 vendor 没有，每 1 s 刷一条） |
| **141** | `E JobScheduler.JobStatus` | — | ❌ 否 |
| **84** | `E audit` | AVC 拒绝（见 §3.4） | 部分 |
| **71** | `E ProcessManager` | `error write exception log` | ❌ 否 |
| **67** | `E AurogonImmobulusMode` | `can not found the app for com.xiaomi.gamecenter.sdk.service` / `com.aios.osbot` / `com.xiaomi.macro` / `com.baidu.carlife.xiaomi` | ❌ 否（冻结名单里有未安装的包） |
| **46** | `E WLC-Service` | **`Waiting For perf mpctl Init Completion`**（45 次）+ `Perf Hal Init Incomplete` | ⚠️ **是**：`vendor.qti.hardware.perf2.IPerf`（AIDL）**服务未注册**（`service list` 无此项，running 的 `perf-hal-2-3` 是旧 HIDL）→ 充电/性能联动永远等不到 |
| **46** | `E JNI_GREEZE` | — | ❌ 否 |
| **45** | `E CloudTelephonyManager` / `E NotificationVibratorHelper` | — | ❌ 否（无 modem 的必然结果） |
| **43** | `E SELinux` | AVC（同 §3.4） | 部分 |
| **32** | `E Diag-Router` | — | ❌ 否 |
| **30** | `E IMiCharge` | — | ⚠️ 轻度 |
| **25 / 25** | `E sc8960x_monitor_workfunc` / `E mm8013c10_battery_poll` | 内核充电/电量驱动往 logcat 打日志 | ❌ 否（噪声） |
| **17** | `E WifiHealthMonitor` | — | ⚠️ 轻度 |
| **16** | `E Zygote` | `SetMemoryProtected process_name_ptr:...`（`com.android.settings`、`com.miui.passwords:sync`） | ❌ 否 |
| **15** | `E ActivityThread` | `Failed to find provider info for com.xiaomi.cloud.cloudidprovider` / `aiasst.vision` / `aicr.action.provider` / `personalassistant.servicedeliver.system.provider` | ⚠️ **是**：AI 识屏 / 负一屏 provider 缺失（与历史记忆「未合入组件」一致） |
| **12** | `E lpdumpd` | — | ❌ 否 |

### 5.2 dmesg 侧（内核/底层）

| 次数 | 内容 | 影响 |
|---|---|---|
| 632 | AVC 拒绝（permissive=0 占 631） | 见 §3.4 |
| 64 | `BPF:[N] Invalid name_offset:` | ❌ 否（bpfloader 解析 A17 的 bpf map 定义失败，A13 vendor 的 bpfloader 不认识新格式） |
| 22 | `qcom-spmi-adc-tm5 ...: get dt data failed: -N` | ❌ 否（ADC 热敏通道 DT 缺项，但 thermal-engine 另有路径） |
| 47 | `i2c_geni 4a94000.i2c / 4a84000.i2c: i2c error :-N` | ⚠️ 需关注（见下） |
| 10 | `libbinder.BackendUnifiedServiceManager: ... Cannot cache binder as linkToDeath cannot be implemented. serviceName: vold` | ❌ 否 |
| 7 | `msm_vidc: err : ... heice: msm_vidc_query_ctrl: get_ctrl failed for id ...` | ⚠️ 轻度（视频编码器，HEIC 路径） |
| 6 | `init: failed write pid N to memcg` | ❌ 否 |
| 6 | `aw35615 4-0022: aw_IsDeviceValid - I2C error reading chip id Return: '-N'` | ⚠️ **是（轻度）**：USB PD 协议芯片读不到 ID → PD 快充协商可能退化 |
| 6 | `msg DeviceRead i2c read error: -N` | ⚠️ 同上族 |
| 5 | `sc8960x-charger 1-006b: tcpc device not ready, probe defer!` | ⚠️ **是（轻度）**：主充电 IC 探测时 TCPC 未就绪，靠 defer 重试成功 |
| 5 | `BpfMonitor: Collect pinned obj info failed! No such file or directory` | ❌ 否 |
| 5 | `zram: Cannot change disksize for initialized device` | ❌ 否 |
| 4 | `[Awinic] aw883xx_parse_*_dt: read ... failed, use default`（4 组） | ❌ 否（4 颗智能功放的 DT 参数缺，走默认值） |

### 5.3 分类详述

#### UFS —— **无错误，健康**

44 条 UFS 相关日志**全是信息级**，无一条 error/timeout/reset：

```
[1.958683] ufshcd-qcom 4804000.ufshc: boot_config val = 49 is_bootdevice_ufs = 4
[1.961839] ufshcd-qcom 4804000.ufshc: Found QC Inline Crypto Engine (ICE) v3.1.0
[1.964774] scsi host0: ufshcd
[2.045277] ufshcd-qcom 4804000.ufshc: No HPB LU supported
[2.068205] sd 0:0:0:0: [sda] 30169088 4096-byte logical blocks: (124 GB/115 GiB)
[2.073222] sd 0:0:0:4: [sde] 1048576 4096-byte logical blocks: (4.29 GB/4.00 GiB)
[6.273908] init: wait for '/dev/block/platform/soc/4804000.ufshc' took 0ms
```

- 只有 3 条 vreg 缺失告警（`unable to find vdd-hba-max-microamp`、`vccq-supply`、`qcom,vccq-parent-supply`）—— DT 简化，不影响。
- `No HPB LU supported` → 无 HPB（Host Performance Booster），随机读性能一般。
- 中断计数健康：`GICv3:ufshcd(40)` 在 315 s 内从 2254 涨到 51936，无 stalled。

> **历史对照**：`5.15.74` 模块 + `5.15.167` 内核在 UFS 上是能跑的，`ufshcd` 是内建（`CONFIG_SCSI_UFSHCD=y`），不受模块版本错配影响。

#### thermal —— **有功能性缺陷（不是硬件问题）**

```
[0.145488] thermal_sys: Registered thermal governor 'step_wise' / 'user_space' / 'power_allocator'
[1.800622] thermal thermal_zone0: binding zone pm6125-tz with cdev cpufreq-cpu0 failed:-22
[43.897534] servicemanager: Could not find android.hardware.thermal.IThermal/default in the VINTF manifest
```

- **`-EINVAL` 绑 CPU 降温设备失败**：`pm6125-tz` 想绑 `cpufreq-cpu0`，A17 内核的 cpufreq 设备名已变（`cpufreq-cpu0` 是老的）→ 这一条温控链断了。
- **`android.hardware.thermal.IThermal`（AIDL）在 VINTF 里找不到**：vendor 只有 `android.hardware.thermal@2.0-service.qti-v2`（HIDL）。A17 framework 要 AIDL 版。
- **MIUI 侧 `ThermalResourceMonitor` 读 `/sys/class/thermal/thermal_message/board_sensor_temp` 直接 ENOENT**（572 条）—— `thermal_message` 是小米内核特性节点，**这颗内核没编这个节点**。实测 `/sys/class/thermal/` 只有 `thermal_zone0`–`thermal_zone24`（25 个 zone）和 `cooling_device0`–`cooling_device35`（36 个），**没有 `thermal_message` 目录**。
- `android.thermal-hal` 与 `thermal-engine` 两个服务都在 running，说明**底层温控还能工作**，缺的是「上层精细读温度」的通道。

> **风险**：`persist.sys.computility.*=5` 是低端机档，性能本来就保守；温控红线读不到 → MIUI 的「温度过高降频/停充」保护可能不触发。**长期高负载有隐患，但不影响日常使用。**

#### watchdog —— **正常**

```
[1.571816] msm_watchdog f017000.qcom,wdt: QCOM Apps Watchdog Initialized
```
全程 315 s **无 watchdog bite / 无 softlockup / 无 hung task**。`CONFIG_KSU` 编译时带的 `hung_task_enh.ko` 也在 `modules.load` 里且已加载。

#### display / DSI —— **初始化完全正常，有 2 个良性告警**

```
[6.034888] [drm:dsi_pll_init [msm_drm]] DSI_PLL_0: DSI pll label = dsi_pll_5nm
[6.036368] [drm:dsi_phy_driver_probe [msm_drm]] DSI_0: Probe successful
[6.038170] [drm:dsi_ctrl_dev_probe [msm_drm]] dsi-ctrl-0: Probe successful
[6.040417] [drm] [msm-dsi-warn]: [hx83102j video mode dsi boe panel] fallback to default te-pin-select
[6.073064] [drm:dsi_display_bind [msm_drm]] Successfully bind display panel 'qcom,mdss_dsi_panel_p255_hx83102j_fhd_video'
[6.073808] msm_drm 5e00000.qcom,mdss_mdp: bound soc:qcom,dsi-display-primary
[6.076842] [drm:sde_backlight_setup:268] Failed to register backlight cdev: -19
```

| 告警 | 判定 |
|---|---|
| `fallback to default te-pin-select` | 良性：TE 引脚选择用默认值（BOE HX83102J 面板），不影响显示 |
| `Failed to register backlight cdev: -19`（-ENODEV） | 良性：背光由独立模块 `ktz8866_leds.ko` 管（`bkl_probe 482: probe success`），SDE 想注册 cdev 失败但背光正常 |
| `OF: graph: no port node found in /soc/qcom,dsi-display-primary` | 良性：用了老的 bind 方式（`dsi_display_bind` 成功） |
| `sde_mdp_parse_dt_prop_len: prop qcom,mdss-{rot-vbif-memtype,inline-rot-qos-lut,...} doesn't exist in device tree` | 良性：DT 精简，旋转/内联旋转参数缺 → **旋转走 GPU 而非 MDP**（性能略差） |

> 背光链完整：`ktz8866_leds.ko` → `hwen_gpio = 425`（内核编号，pin 27 + 398）→ `bkl_backlight_enable` → `probe success`。

#### audio —— **服务全起，但有 3 层隐患**

- 服务层健康：`audioserver`、`vendor.audio-hal`、`vendor.audioadsprpcd_audiopd`、`vendor-qti-media-c2audio-hal-1-0`、`vendor-dolby-media-c2-hal-1-0` 全 `running`。
- 驱动层：`aw883xx_dlkm.ko` 4 颗功放 probe 成功，但**4 组 DT 参数缺失走默认值**：
  ```
  [Awinic] aw883xx_parse_fade_enable_dt: read fade-enable failed, close fade_in_out
  [Awinic] aw883xx_parse_sync_flag_dt: read sync flag failed, default phase sync off
  [Awinic] aw_parse_port_id_dt: read aw-rx-port-id failed, use default
  [Awinic] aw_monitor_parse_dt: read hw-monitor-delay failed, set default value
  ```
  → 淡入淡出关闭、相位同步关闭。**听感层面可能有爆音/相位差，但不出错。**
- 属性层：`persist.audio.fluence.voicecall` / `voicerec` 被 SELinux 拒（§3.5）→ **双麦降噪没开**。
- 无 `audioadsprpcd` 崩溃循环（历史事故已修）。

#### WiFi —— **能连，但 3 个底层告警**

```
[5.858018] btpower: no symbol version for cnss_utils_update_device_type
[5.981722] cfg80211: Problem loading in-kernel X.509 certificate (-13)
[6.017154] icnss2 c800000.qcom,icnss: Adding to iommu group 30
[6.022630] icnss2: Platform driver probed successfully
[33.337492] cfg80211: failed to load regulatory.db
[40.088224] wlan: [10:E:fwol] ucfg_fwol_send_get_thermal_stats_cmd: Command Disabled in Ini
[40.088239] wlan: [10:E:OSIF] os_if_fwol_get_thermal_stats_req: Failed to send thermal stats cmd to FW, 4
```

| 告警 | 判定 |
|---|---|
| `Problem loading in-kernel X.509 certificate (-13 = EACCES)` → `failed to load regulatory.db` | ⚠️ **是（轻度）**：**无监管域数据库** → 5 GHz/信道/发射功率按世界默认值，可能信道受限。`regulatory.db` 在 `/vendor/firmware` 里可能缺，或 SELinux 拒读 |
| `btpower: no symbol version for ...` | 模块 CRC 缺版本，加载成功但脆弱 |
| `fwol ... thermal stats cmd: Command Disabled in Ini` | 固件 INI 关了 WLAN 热统计 → 上层读不到 WiFi 芯片温度（与 thermal 缺陷叠加） |
| `icnss2 ... probe successfully` + `wifi_hal_legacy` running | ✅ WiFi 主链路正常 |

- 另：`[2.069127] sd 0:0:0:1: [sdb] ... 8.00 MiB`、`sd 0:0:0:3: [sdd] 32.0 MiB` —— WiFi/BT 的 `bluetooth`、`modem` 等小分区都在 UFS 上，已正常挂载。

#### VINTF manifest 缺项（A17 framework ↔ A13 vendor manifest）

`servicemanager` 明确报「`Could not find X in the VINTF manifest. No alternative instances declared in VINTF.`」的 HAL：

| HAL | 后果 |
|---|---|
| `android.hardware.boot.IBootControl/default` | ⚠️ **是**：`bootctl` / `fastbootd` 槽位与「重启到 bootloader」控制受影响（出现 2 次，`vold` 与 `system_server` 都问过） |
| `android.hardware.thermal.IThermal/default` | ⚠️ 见 thermal 段 |
| `android.hardware.power.stats.IPowerStats/default` | ⚠️ 轻度：电量统计粒度下降 |
| `android.hardware.usb.IUsb/default`、`android.hardware.usb.gadget.IUsbGadget/default` | ⚠️ **是**：USB 模式切换（MTP/ADB/tethering）走兜底路径 —— 与「USB 极不稳定」的既有观察**可能相关** |
| `android.hardware.graphics.allocator.IAllocator/default` | ⚠️ 轻度：图形缓冲分配走 HIDL 兼容层 |
| `android.hardware.soundtrigger3.ISoundTriggerHw/default` | ❌ 否（语音唤醒，本机小爱走别的路） |
| `android.hardware.bluetooth.ranging.IBluetoothChannelSounding/default` | ❌ 否（A17 新特性，硬件本就没有） |
| `vendor.qti.hardware.bttpi.IBtTpi/default` | ❌ 否 |

> **机制**：`VintfObject.verifyBuildAtBoot()` 就是历史记忆里「设备内部出现问题」弹窗的触发点 —— **这套 manifest 不匹配是那类弹窗的结构性根因**，靠 `hide_error_dialogs=1` 屏蔽，未根治。

#### ★ 崩溃与重启（本次会话实证）

**A. 设备会自发重启 —— 累计 57 次**

```
sys.boot.reason                 = bootloader
sys.boot.reason.last            = bootloader
ro.boot.bootreason              = bootloader
persist.sys.boot.reason.history = bootloader,57      （13:13 采样时是 bootloader,54）
```

- `bootreason = bootloader` 意味着**每次都是「从 bootloader 正常启动」，不是 kernel panic / watchdog / 硬复位**。即：要么有人 `reboot`，要么 ABL/XBL 侧主动回 bootloader（历史记忆里 XBL `VBVerifyImage failed → 回 fastboot` 就是这种形态）。
- 本次会话期间 **13:15 → 13:26 之间设备重启过一次**（uptime 315 s → 113 s），13:27 时 uptime 194 s。**不是取证造成的**（全程只读，未 reboot）。
- **改包含义**：刷完镜像后若设备反复回 bootloader/fastboot，先看 `sys.boot.reason.history` 的增量与 `ro.boot.bootreason`，别急着怀疑系统崩了。

**B. `imsdaemon` 每次开机仍崩一次（已知问题的现状）**

```
01-01 08:00:58.455  KernelSU: susfs: mark no sucompat checks for pid: '1773', exec: '/vendor/bin/imsdaemon'
01-01 08:00:58.768  auditd: avc: denied { read } for comm="imsdaemon" name="vendor_persist_rcs_prop" ... permissive=0
01-01 08:00:58.940  auditd: avc: denied { read } for comm="imsdaemon" name="persist_debug_prop" / "default_prop"
01-01 08:00:58.947  libc: Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0 in tid 1938 (imsdaemon), pid 1773
```

- 域 `u:r:vendor_ims_service:s0`，崩溃形态 `SEGV_MAPERR addr 0x0` —— 与历史记录的 `ImsMain::registerImsFactoryHal()` 空指针完全一致。
- 现在靠 `/data/adb/service.d/_boot_fix.sh` 在启动后停掉（`init.svc.vendor.imsdaemon=stopped`），所以**只崩一次、不循环**。属「已止血未根治」。

**C. 每次开机有一个 `init` 子进程 abort（未定论）**

```
01-01 08:00:29.167  771  771 F libc: Fatal signal 6 (SIGABRT), code -1 (SI_QUEUE) in tid 771 (init), pid 771 (init)
01-01 08:00:29.209  771  771 F libc: Crash due to signal: crash_dump helper failed to exec, or was killed
```

- 真 init 是 pid 1，而 **pid 771 的 comm 也是 `init`** —— 典型的「init fork 出子进程、在 `execve` 之前就 abort」形态（子进程在 exec 前继承父进程 comm）。上一 boot 同位置也有一次（pid 3848）。
- `crash_dump helper failed to exec` → 早期启动阶段 tombstone 也抓不到，所以 `/data/system/dropbox/` **是空的**（`total 0`），没有 crash 落盘可查。
- **影响**：无（系统照常起到桌面）。**判定：观察到了、未定位到是哪个 service。**

#### 其它结构性缺失（MIUI 分区期望落空）

```
[2.302602] init: [libfstab] ModifyOverlayLowerdirsForMiProduct: /mnt/vendor/mi_product not mounted, skipping
[4.255101] init_hook_E: Could not find /cust/cust_variant and /data/miui/cust_variant
[6.473892] vold: DM_DEV_STATUS failed for mi_product_a: No such device or address
[26.487620] init: [libfs_mgr] Skipping '/mnt/vendor/mi_product' during mount_all
[28.327333] init_hook_E: Could not find /cust/cust_variant and /data/miui/cust_variant
```

- **`mi_product` 逻辑分区不存在** —— 小米平板的「小米产品定制分区」，`lpdump` 里确实没有。`init` 每次开机尝试两次（early + late）都失败。
- **`/cust/cust_variant` 不存在** —— 小米的运营商定制分区，联想机器没有。`init_hook` 读不到就跳过（`cust prop white key` 那一串白名单属性全部不生效：`ro.miui.cust_variant`、`ro.miui.mcc/mnc`、`ro.carrier.name` 等）。
- 这些是**良性失败**（有兜底），但会让人误以为「属性没设对」。

---

## 6. 缺口与复取命令

**13:15 设备曾从 USB 完全消失**（`pnputil` 里无任何 `VID_05C6` / 联想 VID 设备，物理链路问题），13:26 自行回来。**回来后已把下列项全部补齐**：

| 项 | 状态 |
|---|---|
| `/proc/bootconfig` | ✅ 已取，见 `bootconfig.txt` 与 §1.4 |
| `boot_a` / `init_boot_a` / `vendor_boot_a` 头部结构 | ✅ 已取 4096 B 头部解析，见 §1.4（结论升级为实证） |
| dm 两层结构（linear vs verity） | ✅ 已取 `/dev/block/mapper/`，见 §2.3 |
| `/proc/modules` 带 Flags 完整清单 | ✅ 293 行，见 `modules.txt` |
| `/sys/class/thermal/` 是否缺 `thermal_message` | ✅ 已确认缺，见 §5.3 |
| SELinux 各目录 `.cil` 清单 | ✅ 已取，见 §3.2 |
| KSU 模块 / `service.d` 内容 | ✅ 3 个模块 + 2 个脚本（`_boot_fix.sh`、`mi_os_ver.sh`） |
| `/data/system/dropbox/` 崩溃落盘 | ✅ 空（`total 0`），见 §5.3-C |
| **开发者选项闪退** | ✅ 已实测：**不闪退**，但抓到 NPE 完整堆栈 + 4 条 AVC + 服务未注册的根因，见 §3.6 |
| `service list`（371 个服务） | ✅ 已用于判定「服务未注册 vs 被 sepolicy 拒」 |

**仍未取到的项（需重启或有风险，本次未做）**：

| 未取到 | 原因 | 复取命令 |
|---|---|---|
| 完整 `modules.load` 216 行 | 已读但未落盘 | `adb pull /vendor_dlkm/lib/modules/modules.load` |
| `/vendor/etc/init/init.lenovo.rc` 等正文 | 只取了文件名清单 | `adb shell cat /vendor/etc/init/init.lenovo.rc` |
| KSU `su` 的完整 sepolicy 增量规则 | 需 `ksud` 内部接口，非只读 | — |
| `/proc/config.gz` 之外的 dmesg 早期被限流吞掉的 205 行模块加载日志 | `printk: init: 205 output lines suppressed due to ratelimiting` | 只能改 `ignore_loglevel` 重启复现 |
| `init` 子进程 SIGABRT 是哪个 service | 需 strace/重启 | — |

---

## 7. 交付物清单（同目录）

| 文件 | 内容 | 大小 |
|---|---|---|
| `REPORT.md` | 本文件 | ~62 KB |
| `getprop.txt` | `getprop` 全量，2195 行 | 94,942 B |
| `mounts.txt` | `/proc/mounts` 全表 158 条 + fstype 统计 + 关键挂载摘要 | 19,330 B |
| `lpdump.txt` | `lpdump` 原始输出（super 布局/逻辑分区/组表/快照态） | 7,234 B |
| `modules.txt` | 293 个运行态模块（Flags/vermagic/来源）+ 216 个 `.ko` 的 vermagic 全表 | 45,416 B |
| `dmesg_head.txt` | 本次开机**完整** dmesg（0.00 s → 315.27 s，5645 行；因 `log_buf_len=2048k` 未回卷，是"全量"不是"头部"） | 631,587 B |
| `bootconfig.txt` | `/proc/bootconfig` 全文（32 行 androidboot.*） | — |
| `config` / `config.gz` | 解压后的内核配置 6975 行 / 原始 gzip（40,901 B） | 188,624 B |
| `vendor-init-rc-list.txt` | `/vendor/etc/init/` 132 项分类清单 | 3,981 B |
| `_logcat_full.txt` | `logcat -d -b all` 全量 25,473 行（供二次分析） | 3,869,761 B |
| `_boot_a.head` / `_iboot_a.head` / `_vboot_a.head` | boot / init_boot / vendor_boot 各 4096 B 头部原始字节 | 各 4 KB |

---

## 8. 三个「移植/改包时必须知道的机制」（浓缩版）

1. **内核与模块是「故意不匹配」的一对，靠内核 patch 撑着；而且模块有三处来源，不是只改 `vendor_dlkm` 就够。** 内核 `5.15.167-android13-...-dirty`（社区 CI 自建，`CONFIG_KSU=y`），磁盘 216 个 vendor 模块是 `5.15.74-ga0aa332d6eec-{ab44(152),dirty(64)}`，vermagic 校验被 patch 掉（293 个模块全载、taint 只有 `OE` 没有 `F`、`CONFIG_MODULE_FORCE_LOAD` 未开、`MODULE_SIG_FORCE` 未开）。运行态 293 个模块 = **152 (vendor_dlkm/in-tree) + 63 (vendor_dlkm/out-of-tree) + 78（来自 `vendor_boot` 的 11.09 MiB ramdisk，含 `ufs_qcom`/`arm_smmu`/`sdhci_msm`/`wlan` 这些核心驱动）**。**换内核 = 模块全废；单换 `.ko` = CFI 崩；改 `vendor_boot` 会连带换掉 UFS/SMMU/WLAN 驱动。**

2. **dm-verity 是「linear + verity」两层、7 个逻辑分区全覆盖（eio 模式），改 system 分区必须重算 hashtree + 重签 `vbmeta_system`；但改单个文件有免刷机的旁路。** 实测映射：`system_a(dm-4)→system-verity(dm-7)`、`system_ext_a(dm-5)→system_ext-verity(dm-8)`、`product_a(dm-6)→product-verity(dm-13)`、`vendor_a(dm-2)→vendor-verity(dm-9)`、`vendor_dlkm_a(dm-3)→vendor_dlkm-verity(dm-10)`、`system_dlkm_a(dm-1)→system_dlkm-verity(dm-11)`、`odm_a(dm-0)→odm-verity(dm-12)`，**挂载点用的都是 `-verity` 那层**。本机两处修复就是旁路证据：`framework-res.apk` 与 `continuity_sdk_app.xml` 都是 `/data`(dm-56) → 系统路径的 **bind-mount**，走 KSU `post-fs-data.sh`，不碰分区、天然可回滚。另注意：`_b` 槽全空（virtual A/B 单槽），**「切槽回滚」在本机不存在**；`boot_a` 是 `kernel 41.1 MiB + ramdisk 0`，`init_boot_a` 只有 1.9 MiB ramdisk，`vendor_boot_a` 才有 cmdline + DTB + 11.09 MiB ramdisk —— **改内核命令行必须改 `vendor_boot`，改 root 才动 `boot`**。

3. **SELinux 是「每次开机现场编译」的跨代拼装，不是一对配好的 policy；而且很多「服务在跑但用不了」其实是「服务压根没注册」。** `plat_sepolicy_and_mapping.sha256` 与 `/odm/etc/selinux/precompiled_sepolicy` 的哈希不一致 → init 每次开机编译 1.8 s；A13 vendor 的 sepolicy 里没有 `perf2` / `touchfeature` / `mipowerhal` 等服务的 type，导致注册成 `default_android_service` 后被 A17 的 plat policy 拒绝 `find`（35 次/开机）。**但更根本的一层是：`service list`（371 条）里根本没有 `vendor.qti.hardware.perf2.IPerf` 和 `HyperOSCustFeatureResolve`** —— A17 framework 期望的 AIDL 服务 A13 vendor 没有，`init.svc.perf-hal-2-3=running` 注册的是旧 HIDL 版本。**排这类问题时先 `service list | grep <名字>`，别一上来就改 sepolicy。** 同时 `/vendor/build.prop` 里 `persist.audio.fluence.*`、`ro.qc.sdk.audio.*` 等因 `vendor_init` 无权限被静默丢弃 —— 排音频/WiFi 问题先看 `dmesg | grep "Do not have permissions"`。
