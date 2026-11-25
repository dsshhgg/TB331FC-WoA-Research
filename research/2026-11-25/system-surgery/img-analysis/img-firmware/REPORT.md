# modem / dsp / adsp / cdsp / wlan / bt 固件链分析

> 设备：Lenovo 小新 Pad 2024 **TB331FC**（`khaje` / SM6225-AD / 仅 WiFi）
> 参考底包：`TB331FC_ZUI_16.0.544`（`E:\rom\TB331FC\刷机包\TB331FC_ZUI_16.0.544\image\`）
> 日期：2026-11-25 · 全程只读（loop-mount ro / debugfs / 自写 FAT 解析），未刷机
> 在线设备是另一台（Galaxy Watch4 `SM-R880`），**TB331FC 当时离线** → 全部结论来自原厂包 + 既有 dump

---

## 0. 一句话结论

**`modem_a` 那个 180 MiB 的 FAT16 不是"基带分区"，而是整套 ADSP + CDSP + MODEM + WLAN 固件的唯一载体**
（`ADSP.MDT`+35 分片、`CDSP.MDT`+10 分片、`MODEM.MDT`+21 分片、`WLANMDSP.MBN`、39 个 `BDWLAN*`）；
`dsp_a` 是 **ext4**，只装 DSP 的 32/64 位用户态 `.so`（`/vendor/dsp/{adsp,cdsp}`）；
`bluetooth_a` 是 FAT16 但**只有 1 MiB**（不是 64 MiB）。
三块都**运行时 ro 挂载**、**都不在 AVB 描述符里**、**官方 erase 流程都不擦它们**（尾部是否被 `<program>` 零填充未实测）。

**modem_a 当 EFI 探针载体：物理上安全（不在 critical 白名单 / 不进 AVB / 不受 verity），但有两个硬条件要先过 —— ① 它的 FAT 逻辑扇区是 4096 B（UEFI 侧能否挂载待验）；② 只能离线改镜像 + 9008 回刷，Android 侧 ro 挂不进去。写坏的代价不是"丢基带"（本机无蜂窝），而是丢 WiFi + 音频 + CDSP。**

---

## 1. 三处对既有认知的更正（先看这个）

| 既有说法 | 实测 | 证据 |
|---|---|---|
| `bluetooth_a` = FAT16 **64 MB** | 分区**只有 1 MiB**（1,048,576 B）；是**文件系统自称 64 MiB**（BPB `tot32=16384`），`df` 看到的 63 MB 空闲是**幻影** | GPT `gpt_main4.bin`：`bluetooth_a lba=47366..47621 256 sect`；`rawprogram4.xml`：`BTFM.bin num_partition_sectors="256" size_in_KB="1024.0"`；BPB 实测 `bytes_per_sector=4096 tot32=16384` |
| 原厂固件平铺在 `/vendor/firmware/`：`a610_zap.mdt/b00..b20`、`adsp.mdt`、`modem.mbn` | `/vendor/firmware/` 里**没有 adsp.\*、没有 modem.mbn**；`a610_zap` 只有 `mdt/b00/b01/b02`（3 片）。adsp/cdsp/modem **只在 modem_a 的 FAT 里**（大写 8.3 名） | `/vendor/firmware` 全量清单见 §2.4；`fatls.py` 输出见 `ls_modem.txt` |
| 触摸固件"可能在 bt 分区" | **不在**。`novatek_ts_fw.bin`(196,608 B) 在 `/vendor/firmware/`；驱动是 `nvt36523_spi.ko`（在 **vendor_dlkm**，不在 boot/vendor_boot 内核里）；`bt_firmware` 里只有 BT 芯片 patchram/NV | §3.2 三条证据 |
| （任务前提）写坏 modem 会"丢基带" | 本机 `ro.vendor.config.lgsi.device.nettype=wifi` —— **无蜂窝**。真实爆炸半径 = **WiFi + 音频(ADSP) + CDSP(相机/传感器) + BT 走 WLAN 共同体** | `vendor/build.prop` |

---

## 2. 固件链清单

### 2.1 分区真身（LUN4 GPT，**用 `gpt_main4.bin` 实测，不是猜**）

| # | 分区 | LBA | 大小 | 文件系统 | 挂载点 | 内容角色 |
|---|---|---|---|---|---|---|
| 3 | **`modem_a`**（`sde4`） | 1286..47365 | **180.00 MiB** | FAT16 (bps=4096, 簇 16 KiB) | `/vendor/firmware_mnt` | **ADSP/CDSP/MODEM/WLAN 固件 + WLAN 板级数据** |
| 4 | **`bluetooth_a`**（`sde5`） | 47366..47621 | **1.00 MiB** | FAT16（自称 64 MiB） | `/vendor/bt_firmware` | BT 芯片 patchram + NV（AP/CR/CM 三系列共 23 文件） |
| 5 | `mdtpsecapp_a` | 47622..48645 | 4.00 MiB | — | 无 | 原厂包**不写**（rawprogram4 无此行） |
| 6 | `mdtp_a` | 48646..56837 | 32.00 MiB | — | 无 | 原厂包**不写** |
| 8 | **`dsp_a`**（`sde9`） | 57094..65285 | **32.00 MiB** | **ext4**（label `dsp`） | `/vendor/dsp` | DSP 用户态 `.so`（`adsp/` 9.1 M + `cdsp/` 7.3 M） |
| — | `mdtp_b` / `mdtpsecapp_b` | — | 32 / 4 MiB | — | 无 | 同上，原厂包不写 |

**关键结构事实**：GPT 里**根本没有 `adsp_a`、`cdsp_a`、`wlan_a` 这三个分区**。
任务里说的"9 个主固件分区"在本机实际是 **3 个真实分区**（modem/bluetooth/dsp）+ 3 个**逻辑角色**（ADSP/CDSP/MODEM 全部挤在 `modem_a` 的 FAT 里）。WLAN 没有独立分区 —— 它的固件也在 `modem_a`，由 **MSS(调制解调器子系统) 通过 `legacy-wlan` 顺带加载**（见 §3.1）。

> **设备侧实证**（2026-11-16 A17 诊断 dump，`E:\rom\logs\a17_diag_20261116\mounts.txt`）——
> 分区↔节点映射与 `ro` 全部对上，不是推断：
> ```text
> /dev/block/sde4  /vendor/firmware_mnt  vfat   ro,context=…:firmware_file:s0,uid=1000,gid=1000,…,shortname=lower,errors=remount-ro
> /dev/block/sde5  /vendor/bt_firmware   vfat   ro,context=…:bt_firmware_file:s0,uid=1002,gid=3002,…,shortname=lower,errors=remount-ro
> /dev/block/sde9  /vendor/dsp           ext4   ro,seclabel,nosuid,nodev
> /dev/block/sda2  /mnt/vendor/persist   ext4   rw
> ```

### 2.2 `modem_a`（FAT16）内容 —— 194 个条目 / 38,784,219 B

| 家族 | 片数 | 字节 | 说明 |
|---|---|---|---|
| `ADSP.MDT` + `ADSP.B00..B35` | 36 | 16,087,035 | ADSP 固件（**缺 B11**，正常） |
| `CDSP.MDT` + `CDSP.B00..B11` | 11 | 3,208,096 | CDSP 固件（缺 B07/B10） |
| `MODEM.MDT` + `MODEM.B00..B23` | 22 | 8,694,088 | 调制解调器固件（缺 B11/B13/B17） |
| `WLANMDSP.MBN` | 1 | 3,815,792 | WLAN MAC 固件（IPQ/WCN 侧） |
| `BDWLAN.*`（`BIN/S/T/U` + 30+ 个 `Bxx` 板级变体） | 39 | 1,026,792 | 每片 26,328 B，按板型选一片 |
| `QDSP6M.QDB` | 1 | 499,025 | DSP 数据库 |
| `WIDEVINE.MBN` / `RTIC.MBN` | 2 | 491,700 | DRM / Rtic |
| `FEATENAB.*` / `HDCPSRM.*` / `IC4.*` / `LOADALGO.*` / `SMPLAP32.*` / `SMPLAP64.*` / `SOTER64.*` / `GPTEST.*` | 各 9 | 合计 4.30 M | 各类 TZ 侧可信应用 |
| `DATA.MSC` | 1 | 639,654 | 调制解调器文件系统镜像 |
| `ADSPR/ADSPS/ADSPUA/CDSPR/MODEMR/MODEMUW.JSN` | 6 | 2.9 K | **每个子系统一份"权限/资源"描述**（PIL 校验时读） |
| `MODEM_PR/MCFG/CONFIGS/MCFG_SW/OEM_SW_A.TXT` | 2 | 12.6 K | 运营商配置模板 |
| `VERINFO/VER_INFO.TXT` | 1 | 1,124 | 版本信息（`init.qcom.sh:438` 读它判断是否刷新 mcfg） |

**空间账（FAT 表逐簇统计，非估算）**：

```
簇大小 16,384 B · 总簇 11,515 · 已用簇 2,497 · 空闲簇 9,018
空闲 = 147,750,912 B = 140.9 MiB   ← 与既有记录的"剩 141 MB"完全吻合
```

文件本体 `NON-HLOS.bin` 只有 40,980,480 B（= 10,005 个 4096 B 扇区）；分区是 46,080 扇区 →
**原厂刷机只覆盖前 40 MB，后 140.9 MiB 从来不碰**（§4 的核心）。

### 2.3 `dsp_a`（ext4, 32 MiB, label=`dsp`）

`/vendor/dsp/adsp/` = 音频/传感器 DSP 侧的 FastRPC 动态库（`aac_dec_module.so.1`、`fluence_*_module_fvxi.so.1`、
`lc3_enc_module.so.1`、`lsm6dso*.so`、`fastrpc_shell_0` …）；
`/vendor/dsp/cdsp/` = 计算 DSP 侧（`libc++.so.1`、`libsysmon*_skel.so`、`fastrpc_shell_3` …）。
**这里没有 `.mdt/.mbn`** —— 固件本体在 `modem_a`，这里只是"跑在 DSP 上的用户代码"。
空闲 11,714,560 B（11.2 MiB）。

### 2.4 `bluetooth_a`（FAT16）内容 —— 23 文件 / 716,929 B

`APBTFW10/11.TLV`、`APNV10/11/11s.BIN`、`CRBTFW11/20/21.TLV`、`CRNV11/20/21.BIN`、
`CMBTFW10/11/12/13.TLV`(+`.VER`)、`CMNV10/11/12/13(/13s/13t).BIN`。

**本机实际用的是 CR 系列**：`persist.vendor.qcom.bluetooth.soc=cherokee` → Cherokee = **`crbtfw21.tlv` + `crnv21.bin`**
（`AP*` 是另一颗芯片的；主线移植文档同样选 `crbtfw21/crnv21`，见 §3.3 D 行）。
→ 既有记录里"有 `apbtfw11.tlv`/`apnv11.bin`"是对的，但**那不是本机生效的那一对**。

### 2.5 `/vendor/firmware/`（vendor 分区内平铺，共 12 MiB）

GPU：`a610_zap.mdt/b00/b01/b02/elf`（Adreno 610 的 zap shader）、`a630_sqe.fw`、`a660_sqe.fw`、`a662_gmu.bin`、
`gmu_gen70000.bin`；视频：`venus*.mbn`(1.85 M ×7)、`vpu20_*.mbn`；IPA：`ipa_fws.mdt/b00..b04`；
触控：`novatek_ts_fw.bin`、`novatek_ts_fw_csot.bin`、`novatek_ts_mp.bin`、`novatek_ts_mp_csot.bin`（各 196,608 B）、
`Himax_firmware.bin`、`Himax_mpfw.bin`（各 261,120 B）；音频功放：`aw883xx_acf.bin`；
WLAN 配置：`wlan/qca_cld/WCNSS_qcom_cfg.ini → /vendor/etc/wifi/WCNSS_qcom_cfg.ini`、
`wlan/qca_cld/wlan_mac.bin → /mnt/vendor/persist/wlan_mac.bin`（**WLAN MAC 来自 persist**，与 persist 事故同源）、
`wlanmdsp.otaupdate → /data/vendor/firmware/wlanmdsp.mbn`（OTA 覆盖入口）。

---

## 3. 加载路径：谁加载、从哪个路径

### 3.1 挂载与符号链接（逐行证据）

`/vendor/etc/fstab.default`（64 行；`fstab.emmc` 61 行，两份**只差 userdata 的 `emmc_optimized` 加密参数与 zram swap 两行**，
**下面三条固件挂载在两者里同文同位置 59/60/61**；vendor_boot ramdisk 里 `/first_stage_ramdisk/fstab.default` 同为这份）：

```text
:59 /dev/block/bootdevice/by-name/modem      /vendor/firmware_mnt  vfat  ro,shortname=lower,uid=1000,gid=1000,dmask=227,fmask=337,context=u:object_r:firmware_file:s0  wait,slotselect
:60 /dev/block/bootdevice/by-name/dsp        /vendor/dsp           ext4  ro,nosuid,nodev,barrier=1                                                               wait,slotselect
:61 /dev/block/bootdevice/by-name/bluetooth  /vendor/bt_firmware   vfat  ro,shortname=lower,uid=1002,gid=3002,dmask=227,fmask=337,context=u:object_r:bt_firmware_file:s0  wait,slotselect
```

三块**全部 `ro`**；`slotselect` ⇒ `by-name/modem` 按当前槽解析成 `modem_a`/`modem_b`。

`/vendor/etc/init/hw/init.qcom.rc`（`on early-init` 段）：

```text
:72   # create symlink for vendor mount points
:73     symlink /vendor/firmware_mnt /firmware
:74     symlink /vendor/bt_firmware  /bt_firmware
:75     symlink /vendor/dsp         /dsp
```

→ 根下 `/firmware/image/ADSP.MDT` 就是这么来的（`shortname=lower` 让 `adsp.mdt` 能匹配大写 8.3 名）。

`/vendor/etc/init/hw/init.target.rc`：`:61 mount_all --early` ← **真正执行上面三条挂载的触发点**；
`:76 mount_all --late`。

### 3.2 ADSP / CDSP：remoteproc(PAS) + mdt_loader，**由 init 在 early-boot 主动踹一脚**

DT 节点（实测自 `vb_dtb.dtb`）：

| 节点 | compatible | 备注 |
|---|---|---|
| `remoteproc-adsp@ab00000` | `qcom,khaje-adsp-pas` | `memory-region=<&pil_adsp_region>`（`pil_adsp_region@53800000`，30 MiB nomap） |
| `remoteproc-cdsp@b300000` | `qcom,khaje-cdsp-pas` | `cdsp_sec_regions@46200000` |
| `remoteproc-mss@6080000` | `qcom,khaje-modem-pas` | **`legacy-wlan;`** ← WLAN 固件由 MSS 顺带加载 |
| `qcom,msm-adsp-loader` | `qcom,adsp-loader` | `qcom,rproc-handle = <adsp phandle>`（音频侧只负责"踢"） |
| `qcom,msm-adsp-notify` | `qcom,adsp-notify` | 同上 |

加载器本体 = **模块 `qcom_q6v5_pas.ko`**（在 vendor_boot ramdisk 的 `lib/modules/`，`qcom_mdt_load` 由 `mdt_loader.ko` 提供），
其字符串里写死了一整套固件名：

```text
adsp.mdt   adsp_dtb.mdt   cdsp.mdt   cdsp0.mdt  cdsp1.mdt  cdsp_dtb.mdt
modem.mdt  modem_dtb.mdt  slpi.mdt   wcnss.mdt  gpdsp0.mdt gpdsp1.mdt
Failed to request DSP firmware / request_firmware failed for %s: %d
depends=rproc_qcom_common,qcom_sysmon,secure_buffer,qcom_q6v5,qcom-scm,qcom_aoss,mdt_loader,qcom_pil_info,qcom_ramdump
```

**触发时机**（`/vendor/etc/init/hw/init.qti.kernel.rc`）：

```text
:52  write /proc/sys/kernel/firmware_config/force_sysfs_fallback 1     # 固件请求可走用户态兜底
:80  on early-boot
:82    exec_background ... /vendor/bin/init.qti.write.sh /sys/kernel/boot_adsp/boot 1
:83    exec_background ... /vendor/bin/init.qti.write.sh /sys/kernel/boot_cdsp/boot 1
:84    exec_background ... /vendor/bin/init.qti.write.sh /sys/devices/virtual/cvp/cvp/boot 1
```

⇒ **ADSP/CDSP 不是内核一上电就加载**，是 init 走到 `early-boot`（此时 `mount_all --early` 已完成 → FAT 已挂）才被"踹"起来。
这就是"先挂 modem_a 再 boot DSP"的顺序保证。MSS(modem) 更早，由内核 probe 触发。

`adsprpcd` 等用户态守护（`vendor.qti.adsprpc-guestos-service.rc:34`、`vendor.qti.audio-adsprpc-service.rc:30+37`、
`vendor.qti.cdsprpc-service.rc:34`）只做 FastRPC 通道，**不碰固件文件**——所以 persist 全零那次事故里它们是"受害者"（反复重启），不是元凶。

### 3.3 WLAN / BT / GPU / 触控 谁加载

| 目标 | 加载者 | 固件来源 | 关键证据 |
|---|---|---|---|
| WLAN MAC 固件 | **MSS**（`legacy-wlan`） | `modem_a:/image/WLANMDSP.MBN` + `BDWLAN.*` | DT `legacy-wlan;`；`WLANMDSP.MBN` 3,815,792 B 只在 FAT 里 |
| WLAN 配置 / MAC | `cnss-daemon`、qcacld | `/vendor/firmware/wlan/qca_cld/*`（两个 symlink 指到 `/vendor/etc/wifi` 与 **persist**） | 见 §2.5 |
| BT 芯片固件 | `android.hardware.bluetooth@1.0-service-qti` + libbt-vendor | `bluetooth_a:/image/CRBTFW21.TLV` + `CRNV21.BIN` | `persist.vendor.qcom.bluetooth.soc=cherokee` |
| GPU zap shader | msm-kgsl/drm | `/vendor/firmware/a610_zap.mdt` | DT `zap-shader { firmware-name = "qcom/sm6225/LENOVO/TB128FU/a610_zap.mdt" }`（主线 `CANONICAL.dts:2133`） |
| 触控 | **`nvt36523_spi.ko`**（在 **vendor_dlkm**，`super_8.img`） | `/vendor/firmware/novatek_ts_fw.bin` | 该 `.ko` 内含字符串 `novatek_ts_fw.bin`；boot.img 内核里 `novatek/nt36523/ts_fw` **0 命中** |

### 3.4 一处未闭合（诚实标注）

stock `boot.img` 的 GKI 内核（`5.15.123-android13-8-00044-g5682afbff3e0-ab11501453`）里，
**没有** `/vendor/firmware_mnt/image` 也没有 `/firmware/image` 字面量（raw byte 命中 0），
只有 `/lib/firmware/updates/…` 与 `/lib/firmware/`，以及 `firmware_class.path` 这个 sysfs 参数名。
按理 `adsp.mdt` 只能靠 `/firmware → /vendor/firmware_mnt` 这条 symlink 才找得到，但内核侧字符串缺失。
两种可能：(a) 实际运行的加载路径由 `firmware_class.path` 或内核私有 patch 在运行时补齐；(b) 走 §3.2 的 `force_sysfs_fallback` 用户态兜底。
**下次设备在线，跑这 3 条即可定案**（1 分钟）：

```sh
adb shell 'cat /sys/module/firmware_class/parameters/path'
adb shell 'ls -l /firmware/image/adsp.mdt /vendor/firmware_mnt/image/ADSP.MDT'
adb shell 'dmesg | grep -iE "firmware load|q6v5|adsp.*mdt|Direct firmware"'
```

不影响本文其余结论（文件在哪、谁请求、三块分区怎么用是硬证据）。

---

## 4. 对三条线的影响

### 4.1 刷机包：**必须带，且官方已经带全了**

`rawprogram4.xml`（LUN4）里与本链相关的就 3 行，**没有 adsp/cdsp/wlan 行（分区本身不存在）**：

```xml
<program filename="NON-HLOS.bin" label="modem_a"     num_partition_sectors="46080" start_sector="1286"   size_in_KB="184320.0"/>
<program filename="BTFM.bin"     label="bluetooth_a" num_partition_sectors="256"   start_sector="47366"  size_in_KB="1024.0"/>
<program filename="dspso.bin"    label="dsp_a"       num_partition_sectors="8192"  start_sector="57094"  size_in_KB="32768.0"/>
```
（`modem_b/bluetooth_b/dsp_b` 同文件同镜像再写一遍，`start_sector` 分别为 151022 / 197102 / 206830。）

要点：
1. **声明 46,080 扇区但文件只有 10,005 扇区**（40,980,480 B ÷ 4096）→ 按 firehose `<program>` 语义只写文件覆盖的那 40 MB。
   ⚠️ **"尾部不被零填充"是推断、未实测**；验证很便宜：镜像尾部写一条标记 → 官方 QFIL 只刷 modem → 回读尾部看标记是否还在。
2. **`erase_UFS-128G.xml` / `FHLoaderErase.xml` 都不含 modem/bluetooth/dsp**（两个 XML 全文只有 5 个 `<erase>`：misc/metadata/userdata/multiimgoem_a/apdp）。
   ⇒ 官方"擦除"流程**绝不会**碰这三块（这是硬证据）。
3. 自建包的规矩：只换 system/product/system_ext **不需要**带这三块；但只要动 vendor（换 HyperOS/A17 的 vendor 侧），
   `modem_a` 里的 ADSP/CDSP 与 `/vendor/dsp/*.so` **必须同版本**，否则 fastrpc 起不来（症状：音频无声 + `adsprpcd` 重启）。
   保守做法：**成套替换 modem/dsp/bluetooth 三件套**（原厂 544 的 `NON-HLOS.bin`/`dspso.bin`/`BTFM.bin` 已备）。
4. `mdtp_a`/`mdtpsecapp_a`（36 MiB ×2 槽）原厂包**完全不写**，是"永久未格式化"的空地（见 §5 备选）。

### 4.2 Recovery（OF/TWRP）：**这三块基本用不上，触摸不在 bt 分区**

实测原厂 recovery：
- `recovery.img` ramdisk 的 `/system/etc/recovery.fstab` 只挂 `system/system_ext/vendor/odm/product`(logical,avb,first_stage_mount)
  + `userdata`/`metadata`/`sdcard`/`boot`/`misc` —— **没有 modem/dsp/bluetooth/persist 任何一行**。
- `init.recovery.qcom.rc` 全文只有：背光 200、`sys.usb.configfs`、`on fs` 里给 `bootdevice` 建 symlink。**不加载任何固件**。
- recovery 用的模块集是 vendor_boot ramdisk 的 `modules.load.recovery`（236 项），含 `msm_drm.ko`、`panel_event_notifier.ko`，
  **但不含 `nvt36523_spi.ko`**（触控驱动在 vendor_dlkm 的 `lib/modules/` 里，该目录共 222 个条目含元数据文件）；recovery ramdisk 里也**没有任何 novatek/himax 固件**。

⇒ 结论：
| 能力 | stock recovery | 第三方 rec 要做到需要什么 |
|---|---|---|
| 触摸 | ❌（没有触控驱动模块，也没固件） | ① `nvt36523_spi.ko`（+ 对应面板 `hx83102j` 变体）放进 rec ramdisk `/lib/modules/` 并加进 modules.load ② `novatek_ts_fw.bin` 放进 rec ramdisk **`/lib/firmware/`**（因为固件请求发生在 `/vendor` 挂上之前的驱动器 probe 阶段，别指望 `/vendor/firmware`） |
| 音频 | 不需要，也别指望 | ADSP 固件在 `modem_a`，recovery 不挂它 → 无音频 |
| WiFi/BT | 不需要 | 同上 |
| **`modem_a`/`bt` 分区** | **完全不参与** | 不要在 recovery 里挂它们（ro + vfat + 4 KiB 扇区，多一事不如少一事） |

⚠️ 提醒：第三方 recovery 在本机是**已知死路**（ABL 独立于 AVB 的 recovery 白名单，见 `09-ABL白名单静态逆向.md`）。
上面这张表只在"换个思路/换台机器"时有意义——**别为它继续投工时**。

### 4.3 Linux（mainline / WoA）：**路径要从"平铺大写"改成"目录化小写"，且 `.mbn` 要符号链接骗**

现成资产：`E:\rom\work\tb331fc-linux\TB331FC-Linux-main\`
- `docs\FIRMWARE.md`（提取与摆放说明）
- `dtb\CANONICAL.dts`（真机 DTS，含全部 `firmware-name`）
- `docs\PORTING-NOTES.zh-CN.md` §第二十三轮（**ADSP 已实测启动成功**）

**映射表（DTS 里写的 → 实际该放哪 → 从哪来）**：

| DTS `firmware-name` | 放到 | 源 | 实测状态 |
|---|---|---|---|
| `qcom/sm6225/LENOVO/TB128FU/adsp.mbn` | 同路径，**并 `ln -sf adsp.mdt adsp.mbn`** | `NON-HLOS.bin:/image/ADSP.MDT` + `ADSP.B00..B35`（改小写） | ✅ **成功**：`Booting fw image …/adsp.mbn, size 9580` → `remote processor adsp is now up`，fastrpc `compute-cb@3..7` 建齐；可热启动 `echo start > /sys/class/remoteproc/remoteproc1/state` |
| `…/cdsp.mbn` | 同上，`ln -sf cdsp.mdt cdsp.mbn` | `CDSP.MDT` + `CDSP.B00..B11` | ❌ `qcom_q6v5_pas b300000.remoteproc: error -22 reading firmware …/cdsp.mbn metadata`（mdt 元数据不被接受，未解） |
| `…/modem.mbn` | 同上 | `MODEM.MDT` + `MODEM.B00..B23` | ⬜ 未见尝试验证；本机无蜂窝，**但 WiFi 的 `legacy-wlan` 挂在 MSS 上 → 真要让 WiFi 起来可能绕不开 MSS** |
| `lenovo-tb128fu`（wcn3990-wifi，被当 **board name** 拼 BDF 路径） | `/lib/firmware/lenovo-tb128fu/bdwlan.*` | `BDWLAN.*`（选本机板型那片） | 🟡 `ath10k_snoc` 绑定成功、ADSP running，probe 仍卡在 iommu group（无固件请求、无 wiphy） |
| `wlanmdsp.mbn`（→ `/lib/firmware/qcom/`） | `qcom/wlanmdsp.mbn` | `WLANMDSP.MBN` | 已就位（同上卡在更前面） |
| `qcom/sm6225/LENOVO/TB128FU/a610_zap.mdt`(+b00..b02) | 同路径 | `/vendor/firmware/` | 已就位 |
| `qcom/a630_sqe.fw` | `qcom/a630_sqe.fw` | `/vendor/firmware/` | 早期报过 `Direct firmware load for qcom/a630_sqe.fw failed`，补齐后解决 |
| `/lib/firmware/qca/crbtfw21.tlv` + `crnv21.bin`（`btqca.c` 写死） | 同路径 | `BTFM.bin:/image/` | 🟡 UART/serdev/hci0/pinctrl/4 路稳压器全对，芯片仍 `command 0xfc00 tx timeout` |
| `/lib/firmware/novatek_ts_fw.bin` | 同路径 | `/vendor/firmware/` | ❌ DLM 写入 CRC 不符 |

**两个必须记住的坑**：
1. **`.mbn` vs `.mdt`**：主线 `qcom_q6v5_pas` 严格按 DT 名字请求，**不会自动回退找 `.mdt`**。
   而 `adsp.mdt` 本身就是 ELF 头 + 分片索引，**改名/软链成 `.mbn` 能被 `qcom_mdt_load` 正确解析并加载全部分片**（ADSP 已实证）。
   cdsp 同一手法失败 → cdsp 的 mdt 元数据格式/偏移与 adsp 不同，需要单独处理（不是路径问题）。
2. **大小写与目录**：Android 侧是 FAT 里的 `ADSP.MDT` 平铺；主线要 `qcom/sm6225/LENOVO/TB128FU/adsp.mdt` 小写。
   不想复制也行：`mount --bind`（或符号链接的父目录）把 `/lib/firmware/qcom/sm6225/LENOVO/TB128FU` 指到
   `/vendor/firmware_mnt/image`，再在里头补 `adsp.mbn/adsp.bNN` 小写软链。**不用重新提取固件**。

---

## 5. `modem_a` 那 140.9 MiB 空闲能当载体吗？（BDS/EFI 探针）

### 5.1 有利条件（都已核实）

| 条件 | 实测 | 证据 |
|---|---|---|
| 空间够 | **140.9 MiB** 空闲（9,018 簇 × 16 KiB） | FAT 表逐簇统计 |
| 不是 fastboot/ABL 的 critical 分区 | ✅ critical 只有 `abl`/`xbl`（`0x100000`/`0x380000`，禁刷只能 9008） | `tb331fc-flash-porting` KB:132/273；`09-ABL白名单静态逆向.md` |
| **不进 AVB** | ✅ vbmeta 描述符只有 `boot dtbo init_boot odm recovery system_dlkm vbmeta_system vendor vendor_boot vendor_dlkm` + `system/product/system_ext`；**modem/dsp/bluetooth 一个字都没有** | `avbtool info_image`（两把钥：`2597c218…`/`cdbb7717…`） |
| 无 dm-verity / 无哈希树 | ✅ 同上（不是 verity 目标） | 同上 |
| 官方"擦除"流程碰不到它 | ✅ 两个 erase XML 只擦 misc/metadata/userdata/multiimgoem_a/apdp | §4.1 要点 2 |
| 官方 `<program>` 是否零填尾部 | ⚠️ **未实测**（文件只覆盖前 40 MB，按 firehose 语义尾部应保留原值） | §4.1 要点 1 的标记实验 |
| ABL 能读 FAT | 结构上是 FAT16，ABL 的 UEFI FAT 驱动理论可读 | 见 5.3 风险① |

### 5.2 两个前置条件（先过这两关再谈载体）

**① FAT 逻辑扇区是 4096 B —— UEFI 侧不一定认**
BPB：`bytes_per_sector=4096, sectors_per_cluster=4`（簇 16 KiB）。这是高通固件分区的惯例，
但 **EDK2 FatPkg 传统上只接受 512 B 逻辑扇区**（ABL 的 BDS/FAT 栈就是 EDK2 血统）。
→ 必须在 ABL 侧实测"能不能给它挂上"；不能的话这条路要么改 BPB（危险：Linux vfat 能读但可能改变全盘簇链解释）、
要么放弃 `modem_a`，改用别的载体。**这是本方案唯一的"可能直接废掉整条路"的风险点。**

**② 只能离线改 + EDL 回刷**
运行时 `/vendor/firmware_mnt` 是 **`ro`**（`fstab.default:59`）+ `context=u:file…:firmware_file` + `uid=1000`，
Android 侧（即使 root）写不进去，也不该去写。可行做法：**在 PC 上改 `NON-HLOS.bin` 的副本（往 FAT 空闲区加文件），
再用 `fh_loader --sendxml` 只刷 40 MB 这一块**。官方原版 `NON-HLOS.bin` 必须留底（现在就在原厂包里）。

### 5.3 风险清单（按"真出事"的严重度排）

| # | 风险 | 后果 | 兜底 |
|---|---|---|---|
| 1 | **写坏 FAT 引导扇区/FAT 表/根目录** | `/vendor/firmware_mnt` 挂不上 → **ADSP + CDSP + MODEM + WLAN 固件全丢**：音频无声、相机/CDSP 挂、WiFi 起不来、`adsprpcd` 每秒重启（persist 全零那次的同一套症状） | 回刷 40 MB `NON-HLOS.bin` 即可（**不需要整包**）。EDL：`fh_loader --sendxml=write_modem.xml --memoryname=ufs`；若 `modem` 非 critical，理论上 `fastboot flash modem_a NON-HLOS.bin` 也行（**未实测**） |
| 2 | 本机**无蜂窝** → 丢的不是"基带通话"，是 **WiFi/音频/CDSP** | 同上，但**不会变成砖**：ABL→boot→system 全在别的分区 | 同上 |
| 3 | 文件放进 `image/` 目录、或占用了 `MDT` 会引用的簇 | PIL 按名找 `ADSP.Bnn`，被挤掉/改名 → 该子系统加载失败 | 一律放进**新建子目录**（如 `/probe/`），**绝不碰 `image/` 下任何名字** |
| 4 | 簇链碎片化（16 KiB 簇） | 大文件跨簇、写工具没按 16 KiB 对齐 → 校验读回来是垃圾 | 用 `mtools`/`mkfs`-级别工具或自写 FAT 追加器；写完**整块读回比对** |
| 5 | 误用 QFIL "全部格式化" / erase 流程 | 三块固件分区一起被清 | 铁律：**永不勾全格式化**（KB 已写死） |
| 6 | 官方后续包把 `NON-HLOS.bin` 做大（现在只占 39/180 MiB） | 我们放在后半段的数据被覆盖 | 探测数据先做**哈希自检**，坏了就当空的 |
| 7 | 探测数据留在盘上没人清 | 换机/送修/以后刷官方也擦不掉（erase XML 不含它） | 用完主动清（重刷原版 `NON-HLOS.bin`） |

### 5.4 更好的备选载体（值得先评估）

| 载体 | 大小 | 优点 | 缺点 |
|---|---|---|---|
| **`mdtp_a` + `mdtp_b`** | 各 32 MiB（共 64） | **原厂包完全不写**（rawprogram4 无此行）、不是 AVB 目标、非 critical | ABL 能不能认它有疑问；等于"造一个 FAT 进去"，比"往已有 FAT 塞文件"更容易被 BDS 忽略 |
| `bluetooth_a` **剩余空间** | 名义 63 MiB，**实际 0** | — | ❌ **陷阱**：分区只有 1 MiB，写超必 I/O 错。别再考虑 |
| `dsp_a` 空闲 11.2 MiB | 11.2 MiB | 原厂包会写（版本齐） | **ext4**，ABL/BDS 读不了；只能 Linux 侧用 |
| `super` 里的空逻辑分区 | 若干 | — | 会被 super metadata 管，动态分区重建时丢 |

**结论**：`modem_a` 是"物理上安全、协议上干净、但 FAT 形态（4 KiB 扇区）可能不被 UEFI 认"的载体；
优先级建议 **① 先验 ABL 能否挂载 4 KiB 扇区的 FAT16（拿 `img-abl` 那条线的 FatPkg 静态结论或写一个 2 KiB 的标记文件实测）
② 不行再评估 `mdtp` 造盘 ③ 都不行就回 WoA 的常规 ESP 路线**。

---

## 6. 证据与可复现脚本（都在 `E:\rom\work\img-firmware\`）

| 文件 | 作用 |
|---|---|
| `gpt_dump.py` | 解析 `gpt_main*.bin`（4096 B 逻辑扇区）→ 分区表真身 → `gpt_lun4.txt` |
| `fatls.py` | 自写 FAT12/16/32 只读列举器（无 mount、无写）→ `ls_modem.txt` / `ls_bt.txt` |
| `fatstat.py` | 逐簇统计空闲（得到 140.9 MiB / 63.0 MiB 幻影两个数） |
| `ext4info.py` | 读 ext4 卷标/挂载点/空闲 → 确认 `super_7=vendor`、`dspso.bin=ext4(label dsp)` |
| `bootparse.py` / `bootextract.py` / `bootscan.py` | boot/vendor_boot/recovery/init_boot 解包（lz4-legacy/gzip/cpio），`rd\` 下有产物 |
| `gpt_lun4.txt` | LUN4 全部 65 个分区（名字/大小/属性） |
| `vendor\` | 从 `super_7.img` 抽出的 `/vendor/etc/init/**`(111 个 rc)、`fstab.default`、`build.prop`、`LISTINGS.txt` |
| `*.sh` | 全部 WSL 只读操作（loop mount ro / debugfs / strings），逐条可回放 |

关键原始输出：`ls_modem.txt`（FAT 全量 194 条）、`LISTINGS.txt`（`/vendor/firmware` 全量）、
`vendor/etc/fstab.default:59-61`、`vendor/etc/init/hw/init.qcom.rc:73-75`、`init.qti.kernel.rc:52,82-83`。

---

## 7. 下次设备在线时的 5 条速查（1 分钟）

```sh
adb shell 'cat /proc/mounts | grep -E "firmware_mnt|/dsp|bt_firmware"'      # 三块是否 ro 挂上
adb shell 'cat /sys/module/firmware_class/parameters/path'                    # §3.4 未闭合点
adb shell 'ls /firmware/image | head; ls /vendor/dsp/adsp | head'            # symlink 是否生效
adb shell 'cat /proc/partitions | grep -E "sde[0-9]+"'                       # sde4/sde5 大小核对（1 MiB？）
adb shell 'df -h /vendor/bt_firmware /vendor/firmware_mnt /vendor/dsp'       # 看 FAT 自称 64 MiB 的幻影
```
