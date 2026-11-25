# ZUI 16.0.544 ⟷ ZUI 17（17.0.460 / ZUXOS 1.1.10.460）逐项镜像对比

> 目的：搞清联想在 ZUI17 里改了什么；并判定本机现有分区到底更接近哪一版。
> 全程只读：只读包内文件 + 既有 dump（`work\device-profile\03_fp.tsv`、`work\rescue-matrix\reads\`、`work\boot-backup-20261024\`），未接触设备。
> 生成时间：2026-11-25 02:2x +08:00　工作目录：`E:\rom\work\img-zui-diff\`

---

## 0. 一句话结论

| 问题 | 答案 |
|---|---|
| 这两个包是什么 | ZUI16.0.544 = **Android 14 / SDK34**，构建 2024-11-15，安全补丁 **2024-10-05**，内核 **5.15.123**；ZUI17 = ZUI **17.0.460**（对外叫 **ZUXOS 1.1.10.460**）= **Android 15 / SDK35**，构建 2025-06-08，安全补丁 system 侧 **2025-05-05** / vendor 侧 **2025-01-05**，内核 **5.15.149** |
| 联想改了啥 | 一次 **A14→A15 平台换代**：内核上跳 26 个 LTS 版本、全部 240 个内核模块重建、新增 3 个 USB 网卡模块并写进 recovery 的加载表、SELinux 策略与 init 换新、dtbo 17 个 overlay 加节点、Dolby/SurfaceFlinger/默认刷新率等形态参数调整。**recovery 的流程逻辑没有任何改动**，固件 blob（xbl/tz/hyp/keymaster…）**版本号一个都没变**却换了二进制，属于联想用同一 Qualcomm BSP 重新整合出包（看不出具体改了什么 → 未知） |
| 本机更像哪一版 | **固件基线 = ZUI16.0.544**。49 个可比分区槽位里 37 个精确等于 ZUI16、6 个两版本来就相同、只有 **3 个等于 ZUI17**（`init_boot_b`、`vendor_boot_b`、`recovery_b`），另有 3 个两版都不是（被改过：`boot_a`/`boot_b`/`vbmeta_system_a`） |
| 与题面"recovery 更像 ZUI17"的关系 | 题面读的是 **`recovery_b`**，正确；但 **`recovery_a` = 14,572,954 = ZUI16**。所以不是"整机像 ZUI17"，而是 **B 槽被 ZUI17 内容污染了三个 boot 链分区**，A 槽才是 544 原厂 |
| 兜底包该用哪版 | 用 **ZUI16.0.544 EDL 全量包**（`TB331FC\刷机包\TB331FC_ZUI_16.0.544`），它一次性写 a/b 双槽，能顺手清掉 B 槽那三个 ZUI17 残留。**不要**拿 ZUI17 集去补 —— 它是 A15 平台件，跟现役 544 的 system/super 对不上 |

---

## 1. 两个包的"身份证"

所有版本事实都来自包内二进制自身，不靠文件名猜。

| 项 | ZUI 16.0.544 | ZUI 17（17.0.460） | 证据来源 |
|---|---|---|---|
| 指纹 | `Lenovo/TB331FC_PRC/TB331FC:14/UKQ1.230917.001/ZUI_16.0.544_241115_PRC:user/release-keys` | `Lenovo/TB331FC_PRC/TB331FC:15/AQ3A.240912.001/ZUXOS_1.1.10.460_250608_PRC:user/release-keys` | `vbmeta.img` 的 avb Prop 描述符；recovery ramdisk 的 `prop.default` |
| Android / SDK | 14 / 34 | **15 / 35** | `vbmeta_system.img` 的 `com.android.build.system.os_version`（14 / 15） |
| 构建时间 | 2024-11-15 06:04 CST（`1731621858`） | 2025-06-08 03:08 CST（`1749323311`） | `prop.default` 的 `ro.*.build.date.utc` |
| 安全补丁 | 2024-10-05 | system/product/system_ext **2025-05-05**；boot/vendor/odm **2025-01-05** | avb Prop 描述符 |
| 内核 | `Linux version 5.15.123-android13-8-00044-g5682afbff3e0-ab11501453` | `Linux version 5.15.149-android13-8-00014-gb219e2d2bfe5-ab12114171` | `boot.img` 内核段内嵌串 |
| 构建机 | `ro.build.host=lqsl004` | `ro.build.host=lqsl002` | `prop.default`；xbl / modem 里的 `OEM_IMAGE_VERSION_STRING` 同步 lqsl004→lqsl002 |
| 增量号 | `TB331FC_CN_OPEN_USER_Q00003.0_U_ZUI_16.0.544_ST_241115` | `100`（Lenovo 在 A15 上改用另一套编号） | `prop.default` |
| ZUI 版本 | `ro.com.zui.version=16.0`、`ro.config.lgsi.ui.version=16.0` | `17.0` | `prop.default` |
| 底层代号 | `ro.config.lgsi.code.version_fp=Lgsi:14:34/AOSP/UP1A.231005.007/rel-16.0/20240105_188` | `Lssi:15:35/QCOM/AQ3A.240912.001/qssi_dev/20241202_236`，并新增 `ro.config.lgsi.os.name=ZUXOS` / `os.version=1.1` | `prop.default` |
| avbtool | 1.2.0 | 1.3.0 | vbmeta `Release String` |
| 签名钥匙 | `2597c218aae470a130f61162feaae70afd97f011`（SHA256_RSA4096） | **同一把** `2597c218…` | vbmeta `Public key (sha1)` |
| Rollback Index | 0（location 0） | **仍是 0** | vbmeta / vbmeta_system —— 说明**没有**做防回滚升级，ZUI17→ZUI16 不会被 AVB 拦 |
| 链式签名 | vbmeta → vbmeta_system，key `cdbb7717…`（RSA2048） | 同 | 两版一致 |

> 说明：`prop.default` 里 `ro.system.build.version.release=13` 这类字段两个包都是 13（Lenovo 没维护），**不可用来判定 Android 版本**；判定以指纹里的 `:14` / `:15` 和 avb Prop 为准。

---

## 2. 清单对比：两边各有什么

两个包**不是同一类东西**，这是"哪些只在一边有"的主因：

| | ZUI16 包 | ZUI17 集 |
|---|---|---|
| 形态 | **Qualcomm EDL/QFIL 全量烧写包**（`image\` + `tool\`，`运行我，刷机.bat`） | **raw 分区镜像集**（只有 29 个裸镜像） |
| 文件数 | 106（含 30+ 个 GPT / rawprogram / patch / provision / firehose 文件） | 29 |
| 覆盖 | 全盘（含 GPT、单槽分区、persist、metadata、userdata、super 的 8 个分片） | 只有 A/B 双槽固件 + boot 链 + 三个 super 内逻辑分区镜像 + 两个 vendor_boot 组件 |
| 体积 | zip 4,770,905,665 B（4.44 GiB）；解压目录 7.21 GiB | 7.75 GiB |

### 2.1 只在 ZUI16 侧有（或只有 ZUI16 才有对应物）

- **烧写框架类**：`rawprogram0..5.xml`、`patch0..5.xml`、`provision_*.xml`、`erase_UFS-*.xml`、`FHLoaderErase.xml`、`partition.xml`、`NvDefinition.xml`、`prog_firehose_sm6225_{ddr,lite}.elf`、`gpt_*` 全套、`super_empty.img`、`tool\`（fh_loader / QSaharaServer / GobiConnectionMgmt.dll / QC.QMSLPhone.dll）
- **单槽分区**：`persist.img`（32 MiB）、`storsec.mbn`、`apdp.mbn`、`logfs_ufs_8mb.bin`、`sec.elf`、`oemowninfo.img`、`multi_image.mbn`（→multiimgoem）、`metadata_1..5.img`、`userdata_1..10.img`
- **super 分片**：`super_1..8.img`（EDL 把 12 GiB 的 super 拆成 8 段写）
- **调试变体**：`vendor_boot-debug.img`（13,164,544 B，只有 ZUI16 包里有）

### 2.2 只在 ZUI17 侧有

| 文件 | 大小 | 是什么 |
|---|---:|---|
| `odm.img` | 1,495,040 | odm 逻辑分区镜像（ZUI16 的 odm 在 `super_*.img` 里，没有单独文件） |
| `system_dlkm.img` | 438,272 | system_dlkm 逻辑分区镜像（ZUI16 里对应 `super_5.img`，两者**大小相同但内容不同**） |
| `vendor_dlkm.img` | 59,342,848 | vendor_dlkm 逻辑分区镜像（ZUI16 里最接近的是 `super_8.img` 58,933,248，**不同物**） |
| `vb_dtb.dtb` | 1,290,690 | 从 `vendor_boot.img` 里剥出来的 dtb（已核对：与 vendor_boot 内 dtb 区逐字节一致） |
| `vb_ramdisk.cpio` | 11,779,605 | 从 `vendor_boot.img` 里剥出来的（**未解压的 LZ4 流**，与 header 的 `vendor_ramdisk_size` 完全相等） |
| `abl_inner.bin` | 274,432 | 与 `abl.img` **sha256 完全相同**，是把 ELF 再剥一层的冗余副本 |

### 2.3 文件名映射（同一个分区，两边叫法不同）

联想在 EDL 包里沿用 Qualcomm 传统名（`.elf`/`.mbn`/`NON-HLOS.bin`/`BTFM.bin`/`dspso.bin`/`keymint.mbn`/`uefi_sec.mbn`/`qupv3fw.elf`/`multi_image.mbn`），在 raw 镜像集里改成拼好的分区名（`xbl.img`/`tz.img`/`modem.img`/`bluetooth.img`/`dsp.img`/`keymaster.img`/`uefisecapp.img`/`qupfw.img`/`multiimgoem.img`）。**名字不同不代表不是同一个东西**，本报告一律按分区对齐后再比。

清单明细（名字/大小/sha256）见 **附录 A / 附录 B**。

---

## 3. 同名文件逐项对比

判定口径：
- **文件 sha** = 两个包内镜像文件本身的 sha256 是否相同
- **内容判定** = 差异是"真实内容改动"还是"仅 4K 对齐补零"（`a6_align.py`，流式逐块比）
- **机上** = 用 `03_fp.tsv` 的实测指纹（分区大小 + FULL/HEAD64M 模式 + 零填充后复算）能否精确命中

### 3.1 必查的 12 项

| 分区 | ZUI16 文件 | 大小 (B) | ZUI17 文件 | 大小 (B) | Δ | 文件 sha | 内容判定 | 机上 |
|---|---|---:|---|---:|---:|---|---|---|
| **xbl** | `xbl.elf` | 3,226,752 | `xbl.img` | 3,227,648 | **+896** | 不同 | **真实不同**（首个差异 `0x11C8`，60% 的 512B 块不同） | a、b **都 = ZUI16** |
| **abl** | `abl.elf` | 274,432 | `abl.img` | 274,432 | 0 | **相同** | **逐字节完全一致** | a、b **两版相同** |
| **tz** | `tz.mbn` | 3,514,087 | `tz.img` | 3,514,368 | **+281** | 不同 | **真实不同**（`0x2F60`） | a、b **都 = ZUI16** |
| **keymaster** | `keymint.mbn` | 342,462 | `keymaster.img` | 344,064 | **+1,602** | 不同 | **真实不同**（`0x1228`） | a、b **都 = ZUI16** |
| **hyp** | `hyp.mbn` | 393,224 | `hyp.img` | 397,312 | **+4,088** | 不同 | **真实不同**（`0x1168`） | a、b **都 = ZUI16** |
| **boot** | `boot.img` | 100,663,296 | `boot.img` | 100,663,296 | 0 | 不同 | **真实不同**：`kernel_size` 46,819,840 → 47,172,096（+352,256），内核 **5.15.123 → 5.15.149** | a、b **两版都不是**（被改过） |
| **dtbo** | `dtbo.img` | 8,388,608 | `dtbo.img` | 8,388,608 | 0 | 不同 | **真实不同**：都是 45 个 overlay，17 个尺寸变（+2,704 / +2,936）、4 个换序、28 个逐字节相同 | a、b **都 = ZUI16** |
| **vbmeta** | `vbmeta.img` | 8,192 | `vbmeta.img` | 8,192 | 0 | 不同 | **重建**：同钥匙、RI 仍 0、Aux 6,080→6,144、boot 描述符 Image Size 46,841,856→47,194,112 | a、b **都 = ZUI16** |
| **recovery** | `recovery.img` | 100,663,296 | `recovery.img` | 100,663,296 | 0 | 不同 | **ramdisk 14,572,954 → 14,581,386（+8,432）**；解开的 472 个文件里**只有 5 个变**（见 §4.3） | **a = ZUI16，b = ZUI17** |
| **modem** | `NON-HLOS.bin` | 40,980,480 | `modem.img` | 40,980,480 | 0 | 不同 | **真实不同**（首个差异 `0x1104E`，27% 的块不同）；但 MPSS/ADSP/CDSP/WLAN **版本串两边完全一致** | a、b **都 = ZUI16** |
| **adsp** | — | — | — | — | — | — | **两边都没有 adsp 镜像；本机也没有 adsp 分区**（见 §3.3） | 不适用 |
| **dsp** | `dspso.bin` | 33,554,432 | `dsp.img` | 33,554,432 | 0 | **相同** | **逐字节完全一致** | a、b **两版相同** |

### 3.2 扩展的 11 项（同样做了逐项比对）

| 分区 | ZUI16 | ZUI17 | Δ | 内容判定 | 机上 |
|---|---:|---:|---:|---|---|
| `init_boot` | 8,388,608 | 8,388,608 | 0 | 真实不同（ramdisk 2,005,893 → 2,005,872，仅 `build.prop` 一个文件变） | **a = 被改过，b = ZUI17** |
| `vendor_boot` | 100,663,296 | 100,663,296 | 0 | 真实不同（ramdisk 11,628,676 → 11,779,605；dtb 同尺寸但内容不同） | **a = ZUI16，b = ZUI17** |
| `xbl_config` | 43,056 | 45,056 | +2,000 | 真实不同（`0x1198`） | a、b = ZUI16 |
| `devcfg` | 42,748 | 45,056 | +2,308 | 真实不同（`0x1108`） | a、b = ZUI16 |
| `rpm` | 225,512 | 229,376 | +3,864 | 真实不同（`0x1108`） | a、b = ZUI16 |
| `featenabler` | 90,673 | 94,208 | +3,535 | **ZUI17 = ZUI16 + 尾部补零**（内容相同，只是补到 4K 对齐） | a、b 两版相同 |
| `uefisecapp` | `uefi_sec.mbn` 168,661 | 172,032 | +3,371 | 真实不同（`0x1228`） | a、b = ZUI16 |
| `imagefv` | `imagefv.elf` 36,864 | 36,864 | 0 | **同尺寸但真实不同**（`0x1138`） | a、b = ZUI16 |
| `multiimgoem` | `multi_image.mbn` 13,512 | 16,384 | +2,872 | 真实不同（`0x1108`） | a、b = ZUI16 |
| `qupfw` | `qupv3fw.elf` 57,269 | 57,344 | +75 | 真实不同（`0x2C30`） | a、b = ZUI16 |
| `bluetooth` | `BTFM.bin` 1,028,096 | 1,028,096 | 0 | **同尺寸但真实不同**（`0xB04E`） | a、b = ZUI16 |
| `vbmeta_system` | 4,096 | 4,096 | 0 | 真实不同（`0x1B`；os_version 14→15、SPL 2024-10-05→2025-05-05） | **a = 两版都不是，b = ZUI16** |
| `storsec` / `apdp` / `logfs` | 36,076 / 13,508 / 16,384 | — | — | 只有 ZUI16 侧有 | 均 = ZUI16 |

**注意一个反直觉现象**：`xbl`/`tz`/`hyp`/`keymaster`/`devcfg`/`rpm`/`uefisecapp`/`multiimgoem`/`qupfw`/`xbl_config` 的 ZUI17 文件大小全部是 4096 的整数倍，ZUI16 的都不是。这不是"多了几千字节内容"，而是**打包方式不同**（重签/重排后补到 4K 边界）。但除了 `featenabler` 之外它们**都不是纯补零**——首个差异都落在 ELF 的代码段入口附近（`0x1108`~`0x2F60`），说明是真的重编过或重签过。

### 3.3 关于 `adsp`（必须写清楚的一项）

- 本机 **GPT / by-name 里没有 `adsp` 分区**：`work\device-profile\11_byname.tsv` 全表 97 行、`10_stats.txt`"by-name 分区数 88"里都没有 adsp；
- 两个包里也都没有 adsp 镜像；
- 本机的 ADSP / CDSP / WLAN 固件是**打进 modem 镜像**里的，实测串为：
  `ADSP.VT.5.4.3.c1-00042-DIVAR-1.43007.7`、`CDSP.VT.2.4.1-00268-KAMORTA-1`、`WLAN.HL.3.2.4-01138-QCAHLSWMTPLZ-1.54098.3`、`MPSS.HA.1.1-00356-KD_ALL_PACK-1`，
  **ZUI16 与 ZUI17 这四串完全一致**（`a5_strings.py`，两边都命中 `[BOTH]`）。
- 结论：`adsp` 这一项在本机**不是分区维度可比的对象**；按镜像内固件维度比，**版本没变**（但 modem 二进制本身有 27% 的块变了）。

---

## 4. 差异归因：联想在 ZUI17 里改了什么

### 4.1 能看出意图的（有证据）

| # | 改动 | 证据 |
|---|---|---|
| 1 | **A14 → A15 平台换代**（SDK34→35，底层从 `Lgsi:14:34/AOSP/UP1A…` 换成 `Lssi:15:35/QCOM/AQ3A.240912.001/qssi_dev`） | `prop.default`、`vbmeta_system` 的 `os_version` |
| 2 | **安全补丁上跳**：vendor 侧 2024-10-05 → 2025-01-05（+3 个月）；system 侧 2024-10-05 → **2025-05-05**（+7 个月） | avb Prop `security_patch` |
| 3 | **内核 LTS 上跳**：5.15.123 → **5.15.149**（ab 号 11501453 → 12114171），240 个 `.ko` 全部重建（同名同功能，大小 ±64B 级别） | `boot.img` 内嵌内核串；`vendor_boot` ramdisk 逐模块 sha 比对 |
| 4 | **新增 USB 以太网（SMSC）支持，并且是给 recovery 用的**：新增 `smsc.ko` / `smsc75xx.ko` / `smsc95xx.ko`（83KB/152KB/149KB），并**追加进 `modules.load.recovery`**（`modules.load` 正常启动表**没变**，两版逐字节相同） | `vendor_boot` ramdisk：`lib/modules/modules.load.recovery` 3889→3921 B，diff 正好是这 3 行 |
| 5 | **recovery 的流程一行没改**：解开后 472 个文件里 467 个逐字节相同，只有 `system/bin/init`(+4,496)、`sepolicy`(+4,159)、`prop.default`(+2,526)、`vendor_file_contexts`(-891)、`vendor_service_contexts`(+484) 变了 —— 全是平台件/策略，没有任何 recovery 专有脚本、UI 或分区逻辑变化 | `a8_cpio.py` + `a9_extract.py` |
| 6 | **dtbo 加节点**：overlay 数不变（45），17 个变大（+2,704 / +2,936 字节，规律性增量 = 新增 DT 属性/子节点），4 个换了顺序（0↔1、2↔3 这类，等于面板/DVT 变体排序调整），28 个一动没动 | `a10_dtbo.py` |
| 7 | **默认刷新率 0 → 120**：`ro.config.lgsi.default_refreshrate=0` → `120`，并新增 `available_refreshrates` / `widen_range_*`；SurfaceFlinger 的 phase-offset 一整套（`debug.sf.*.duration`）替换为 A15 新调度 | `prop.default` |
| 8 | **Dolby 升级**：`DAX3_3.8.5.20_r1` → `DAX3_3.13.0.9_r1` | `prop.default` |
| 9 | **外设/形态配置补全**：新增 olympia 无线键盘名（`Lenovo Wireless KB` / `联想小新无线键盘Air` / `联想昭阳蓝牙键盘`）、触控笔名、`ro.odm.lenovo.lcdsize=10.95`、`bqb=pass`、`wificert=pass`、`audioparaver` DVT-2023-07-7→PVT-2023-09-27、`ro.config.zui.education=true`、`ro.vendor.config.lgsi.project=bengal` | `prop.default` |
| 10 | **关掉 VABC**：新增 `ro.vendor.build.dont_use_vabc=true` | `prop.default` |
| 11 | **avbtool 1.3.0 重新出包**，签名钥匙/链式关系/rollback index 全部保持原样（RI 仍 0） | `avbtool info_image` |
| 12 | 打包习惯变化：ZUI17 侧固件统一补到 4096 边界（`featenabler` 甚至是纯补零），EDL 包里的 `.mbn/.elf` 则不补 | `a6_align.py` |

### 4.2 看不出意图的（如实标"未知"）

- **固件 blob 的实质改动未知**：`xbl`/`tz`/`hyp`/`keymaster`/`devcfg`/`rpm`/`uefisecapp`/`multiimgoem`/`qupfw`/`xbl_config`/`imagefv`/`bluetooth`/`modem` 里，**Qualcomm 版本串一个都没变**（`QC_IMAGE_VERSION_STRING=BOOT.XF.4.1-00374-KAMORTALAZ-1`、`TZ.XF.5.1.6-54971-3`、`MPSS.HA.1.1-00356-KD_ALL_PACK-1` 等两边完全相同），但二进制有 4%~60% 的块不同。说明**不是 Qualcomm BSP 升级**，而是联想用同一 BSP 重新编译/重新签名/重新整合。具体改了哪段代码，二进制无符号信息，**未知**。
- **ABL（`abl.elf`/`abl.img`）两版逐字节相同** —— 所以 ABL 的白名单逻辑、`fastboot oem edl`、slot 校验策略**在 ZUI17 里没有任何变化**（这对"ABL 不放行 vbmeta"那类结论是个有用的边界：换成 ZUI17 的 abl 不会有任何区别）。
- **`dspso.bin`/`dsp.img` 两版逐字节相同** —— dsp 分区在两版之间没动。
- **modem 的 27% 差异具体是什么未知**（版本串不变，可能是运营商配置/校准表/NV 默认值差异，但没证据不下结论）。

### 4.3 recovery ramdisk 的 5 个差异（完整清单）

| 文件 | ZUI16 | ZUI17 | Δ |
|---|---:|---:|---:|
| `system/bin/init` | 2,164,264 | 2,168,760 | +4,496 |
| `sepolicy` | 1,095,896 | 1,100,055 | +4,159 |
| `prop.default` | 29,349 | 31,875 | +2,526 |
| `vendor_file_contexts` | 92,814 | 91,923 | **-891** |
| `vendor_service_contexts` | 10,007 | 10,491 | +484 |

⇒ 这 5 个全是"A14 init/sepolicy/属性"换成"A15 init/sepolicy/属性"的连带结果，**不是 recovery 功能改动**。

---

## 5. 本机基线判定

### 5.1 方法（可复现，不靠猜）

`work\device-profile\03_fp.tsv` 是早前从设备上真读的指纹，语义由 `fingerprint.sh` 定义：
- `sz` = 分区大小；`mode` = `FULL`（sz ≤ 64 MiB，对**整分区含零填充**求 sha256）/ `HEAD64M`（sz > 64 MiB，只取**前 64 MiB**）
- `sha` = 上述 sha256；`h4k` = 前 4096 字节 sha256

所以把包内镜像**按分区大小零填充后算同样的摘要**，就能和机上值做**逐字节精确**比对（不是"大小像"或"头几个字节像"）。脚本：`a3_slots.py`。

### 5.2 结果：49 个可比槽位

| 判定 | 数量 | 明细 |
|---|---:|---|
| **= ZUI16** | **37** | `xbl`/`xbl_config`/`tz`/`keymaster`/`hyp`/`devcfg`/`rpm`/`uefisecapp`/`imagefv`/`multiimgoem`/`qupfw`/`bluetooth`/`dtbo`/`vbmeta` 的 a+b 共 28 个；加 `init_boot_a`、`vendor_boot_a`、`recovery_a`、`modem_a`、`modem_b`、`storsec`、`apdp`、`logfs`、`vbmeta_system_b` 共 9 个 |
| **= ZUI17** | **3** | `init_boot_b`、`vendor_boot_b`、`recovery_b` |
| 两版本来相同 | 6 | `abl` a+b、`dsp` a+b、`featenabler` a+b |
| **两版都不是**（被改过） | 3 | `boot_a`、`boot_b`（两者哈希相同）、`vbmeta_system_a` |

### 5.3 「分区 → 更像哪版 → 证据」判定表

| 分区 | 更像哪版 | 证据（机上 sha256 vs 复算值） |
|---|---|---|
| `xbl_a`/`xbl_b` | **ZUI16** | 机上 `d3d65fab…`；`xbl.elf`+零填充到 3,670,016 = `d3d65fab…` ✓；ZUI17 `xbl.img` ✗ |
| `xbl_config_a/b` | **ZUI16** | 机上 `5ba4946c…` = ZUI16 复算 ✓ |
| `abl_a`/`abl_b` | **两版相同** | 机上 `22eaf506…`；两版文件本身逐字节相同，都 ✓ |
| `tz_a`/`tz_b` | **ZUI16** | 机上 `43de2f0c…` = ZUI16 ✓ |
| `keymaster_a/b` | **ZUI16** | 机上 `b71c4171…` = ZUI16 ✓ |
| `hyp_a`/`hyp_b` | **ZUI16** | 机上 `c52db25e…` = ZUI16 ✓ |
| `devcfg_a/b` | **ZUI16** | 机上 `4af9275c…` = ZUI16 ✓ |
| `rpm_a`/`rpm_b` | **ZUI16** | 机上 `45dabac5…` = ZUI16 ✓ |
| `featenabler_a/b` | **两版相同** | 机上 `9ddea24f…`；两版补零后同值 |
| `uefisecapp_a/b` | **ZUI16** | 机上 `7241d28a…` = ZUI16 ✓ |
| `imagefv_a/b` | **ZUI16** | 机上 `646baf6c…` = ZUI16 ✓ |
| `multiimgoem_a/b` | **ZUI16** | 机上 `786caaee…` = ZUI16 ✓ |
| `qupfw_a`/`qupfw_b` | **ZUI16** | 机上 `888d3e1d…` = ZUI16 ✓ |
| `bluetooth_a/b` | **ZUI16** | 机上 `730560ac…` = ZUI16 ✓ |
| `boot_a`/`boot_b` | **都不是**（被改过，a=b 同哈希 `667e1723…`） | 两版复算都不命中；`boot-backup-20261024\boot_a.img` 的 head64M 是 `c7495ab9…`，也不是它 —— 说明当前 boot 是更晚的一次改写（补丁/实验镜像），**不是**任何一版原厂 |
| `init_boot_a` | **ZUI16** | 机上 `2d090fb5…`（8,388,608 B 全量）= ZUI16 包内 `init_boot.img` 的整文件 sha256 **完全相等** ✓（注：2026-10-24 备份里的 `init_boot_a` 是另一个值 `f18dc14a…`，说明当时是补丁版、后来被恢复成原厂） |
| `init_boot_b` | **ZUI17** | 机上 `f0c8380d…` = `zui17_images\init_boot.img` 的整文件 sha256（8,388,608 B 全量命中）✓ |
| `vendor_boot_a` | **ZUI16** | 机上 `27832b98…` = ZUI16 复算 ✓（`boot-backup-20261024\vendor_boot_a.img` 整文件 sha256 = `d526c77b…`，与 ZUI16 `vendor_boot.img` **完全相等**） |
| `vendor_boot_b` | **ZUI17** | 机上 `f09d04d4…` = ZUI17 复算 ✓（其 dtb/ramdisk 与 `vb_dtb.dtb`/`vb_ramdisk.cpio` 同源） |
| `dtbo_a`/`dtbo_b` | **ZUI16** | 机上 `ac8fc83d…` = ZUI16 复算 ✓ |
| `vbmeta_a`/`vbmeta_b` | **ZUI16** | 机上 `9466f0e8…` = ZUI16 `vbmeta.img`+零填充 ✓（与 `rescue-matrix\reads\vbmeta_a_now.bin` 一致） |
| `vbmeta_system_b` | **ZUI16** | 机上 `df407da5…` = ZUI16 复算 ✓ |
| `vbmeta_system_a` | **都不是**（被重签/改过） | 机上 `cea948ea…`；ZUI16/ZUI17 都不命中；`rescue-matrix\reads\vbmeta_system_a_now.bin` 同值 ⇒ 这是 A17/hashtree 实验留在 a 槽的签名版 |
| `recovery_a` | **ZUI16** | 机上 head64M `264aec55…` = ZUI16 复算 ✓（ramdisk 14,572,954） |
| `recovery_b` | **ZUI17** | 机上 head64M `e5353d2a…` = ZUI17 复算 ✓（ramdisk 14,581,386 —— 与题面读到的头值一致） |
| `modem_a`/`modem_b` | **ZUI16** | 机上 head64M `bbe4cbd5…` = ZUI16 复算 ✓（modem 镜像 40.98 MB < 64 MiB，所以整个镜像都在指纹覆盖范围内） |
| `dsp_a`/`dsp_b` | **两版相同** | 机上 `e6dff50c…` = 两版共同的 sha256 ✓ |
| `storsec`/`apdp`/`logfs` | **ZUI16** | 均在位且精确命中 ✓ |

### 5.4 结论 + 怎么变成这个局面的

**本机的固件基线是 ZUI16.0.544；ZUI17 只在 B 槽的三个 boot 链分区上留了脚印。**

为什么恰好是这三个？有一条**可验证的**强线索：

1. `rawprogram4.xml` 里 a/b 双槽是**用同一份文件写的**（`xbl_a` 与 `xbl_b` 都指向 `xbl.elf`……`recovery_a` 与 `recovery_b` 都指向 `recovery.img`），所以**任何一次完整的 9008 全量回刷都会让 a、b 两槽完全一致**；
2. b 槽 23 个 A/B 分区里，**19 个可证明被 544 写过**（16 个精确 = ZUI16：`xbl`/`xbl_config`/`tz`/`keymaster`/`hyp`/`devcfg`/`rpm`/`uefisecapp`/`imagefv`/`multiimgoem`/`qupfw`/`bluetooth`/`dtbo`/`vbmeta`/`vbmeta_system`/`modem`；3 个两版同值：`abl`/`dsp`/`featenabler`），只有 `boot_b` 是事后又改过的；
3. 而 `init_boot_b`、`recovery_b`、`vendor_boot_b` 恰好是 `rawprogram4.xml` 里 **b 槽 24 个 A/B 分区的最后三个**（顺序：`rpm_b → tz_b → … → init_boot_b → recovery_b → vendor_boot_b`），紧接着才是 `devinfo`/`dip`/…/`PrimaryGPT`；
4. ⇒ **最可能的解释**：那次 9008 回刷在 b 槽 boot 链末尾中断/跳过，于是这三个分区保留了设备上一版（ZUI17）的内容。

> 这一条标为**"最可能解释"**而非定论：也可能有人事后单独往 b 槽刷过 `init_boot/vendor_boot/recovery`（例如试 ZUI17 的 recovery）。两种解释在数据上等价，区别只在于"谁写的"。

**另一个与现有文档不符、需要更正的点**：`work\docs\STATE.md` 写着"a 槽已由 9008 全量恢复为 544 原厂（含 vbmeta_a / vbmeta_system_a 原厂）"。实测：`vbmeta_a` 确实是原厂，但 **`vbmeta_system_a` 不是**（两版都不是，被重签过），且 **`boot_a`/`boot_b` 都不是任何一版原厂**（两者哈希相同，说明是成对写进去的同一份补丁/实验镜像）。当前"能开机"的状态里这两项是带改动的，做任何"回到原厂"的动作前必须先认清这一点。
（`init_boot_a` 已核对是**原厂 544**：`2d090fb5…` 与 ZUI16 `init_boot.img` 整文件 sha256 相等；只是 2026-10-24 备份里当时还是补丁版 `f18dc14a…`，之后被恢复了。）

### 5.5 这条判定带来的实际后果（重要）

`vbmeta.img` 里对 `boot`、`init_boot`、`vendor_boot`、`recovery`、`dtbo` 都有 **hash 描述符**，而机上 `vbmeta_a` = `vbmeta_b` = **ZUI16 原厂**。也就是说：

- B 槽的 `init_boot_b`/`vendor_boot_b`/`recovery_b` 是 ZUI17 内容，**与 vbmeta_b 里记录的摘要对不上**；
- 一旦把 active slot 切到 **b**，ABL 对这三个分区的 AVB 校验会失败 ⇒ **b 槽的 recovery / vendor_boot 不可用**，甚至可能判 slot 不可启动（本机已实测过"vbmeta 描述符对不上 → 直接卡 bootloader"这类行为，见 STATE.md 10-25 18:26 条）；
- 现在默认 `misc` 里没有 `_a`/`_b` 后缀（`rescue-matrix\reads\misc.bin` 只有 `-bootloader` 命令字），实际跑的是 **a 槽**，所以日常开机不受影响。

⇒ 实操含义：**B 槽现在是个"坑"**。要么按 §6 用 ZUI16 全量包把 b 槽刷干净，要么永远不要 `set_active b`。

---

## 6. 刷机包选型建议：「回到原厂」兜底包

### 6.1 结论

| 场景 | 用哪版 | 用哪些分区 |
|---|---|---|
| **常规回原厂 / 救砖兜底** | **ZUI16.0.544 EDL 全量包**（`E:\rom\TB331FC\刷机包\TB331FC_ZUI_16.0.544`，`运行我，刷机.bat` + `tool\`） | **全量**（`rawprogram0..5` + `patch0..5`），一次写 a/b 双槽 + GPT + super 8 段 |
| 只想修 B 槽那三个残留 | 同上，全量刷 | 必须全量 —— 单刷 `recovery_b`/`vendor_boot_b`/`init_boot_b` 还得同步修 `vbmeta_b`，得不偿失 |
| 想要 ZUI17 的**内核/驱动**（如 5.15.149 + USB 网卡）但留在 544 | **不建议** | ZUI17 是 A15 平台件，`init_boot`/`vendor_boot`/`boot` 与 544 的 system/super 是跨代组合，且会立刻打破 `vbmeta_a` 的 hash 描述符 ⇒ AVB 不过 |
| 用 ZUI17 集做兜底 | **不要** | 它只有 29 个文件：没有 GPT、没有 rawprogram/patch XML、没有 `persist`/`devinfo`/`modemst`/`splash`/单槽固件，**不可独立成包**；而且它是 A15，与本文档记录的现役 544 系统不匹配 |

### 6.2 为什么强烈建议 ZUI16 而不是 ZUI17

1. **一致性**：37/49 个槽位已经是 ZUI16，全量 544 是唯一能让 a/b 两槽 + super + GPT + 单槽分区**同时回到同一基线**的操作；
2. **签名链自洽**：544 的 `vbmeta`/`vbmeta_system` 与 544 的 boot 链是配套的（原厂 rsa4096 + rsa2048 链），刷完 AVB 全部自洽；
3. **无回滚壁垒**：ZUI17 的 rollback index 仍是 0 ⇒ 从 ZUI17 回 ZUI16 **不会被 AVB 拦**（但仍以实测为准）；
4. **ZUI17 包不完整**：见上表，它没有烧写框架，且缺 `persist`——而 `persist` 全零会直接导致**声音+录音同时失效**（历史事故，`fh_loader` 单写 `persist.img` 修好过）。EDL 包里 `rawprogram0.xml` 的 persist 行是 `filename=""`（官方故意不写），所以**刷完 544 后要单独确认 persist 非全零**，必要时手工写 `persist.img`；
5. **ZUI17 拿到手也补不齐**：`odm`/`system_dlkm`/`vendor_dlkm` 只有逻辑分区镜像，要自己 `fastbootd` 建分区写，且会连带打破 `vbmeta_system` 的 hashtree 描述符。

### 6.3 如果确实想要 ZUI17（A15）的完整兜底

必须用**完整包**而不是 `zui17_images` 这 29 个文件：
`E:\rom\release\TB331FC-rollback-zui17\TB331FC_ZUI_17.0.460_250608_full.zip`（4,742,067,910 B，解出 30 分区 / 7.74 GiB）。
注意历史记录指出它"**实为 ZUXOS 1.1.10.460（A15/SDK35），非设备原 ZUI16**" —— 与本报告 §1 完全吻合（指纹 `ZUXOS_1.1.10.460_250608_PRC`、SDK 35），这条历史结论现在有了硬证据支持。

### 6.4 刷完之后的验收清单（建议）

| 检查 | 期望（= ZUI16 原厂） |
|---|---|
| `xbl_a..vendor_boot_a` 的 head/FULL sha | 与 §5.3 表里的 `…` 值逐项相等（可用 `a3_slots.py` 复算比对） |
| `recovery_a` head64M | `264aec55…` |
| `recovery_b` head64M | **必须变成** `264aec55…`（若还是 `e5353d2a…` 说明 b 槽没写进去） |
| `vendor_boot_b` head64M | **必须变成** `27832b98…` |
| `init_boot_b` sha | **必须变成** `2d090fb5…`（= ZUI16 `init_boot.img` 整文件 sha256，与 a 槽一致） |
| `persist` 非零字节 | > 0（历史事故判据） |
| `vbmeta_a`/`vbmeta_b` | `9466f0e8…` |
| `vbmeta_system_a` | 必须回到 `df407da5…`（与 b 槽同值 = ZUI16 零填充后的分区摘要；对应包内文件 sha `1e0688b4…`）。当前 a 槽是被重签版 `cea948ea…`，全量刷应当覆盖它 |
| `boot` 链 | 若刷完仍是补丁版，说明引导链被后续步骤改过，需单独确认 |

---

## 7. 复现方法

全部脚本在 `E:\rom\work\img-zui-diff\`，WSL 用 `wsl -d ub -u root`：

| 脚本 | 作用 | 产物 |
|---|---|---|
| `a1_headers.py` | 解析 boot/init_boot/recovery/vendor_boot 头（magic、header_version、kernel/ramdisk 大小、ramdisk 偏移） | `a1_headers.txt/.json` |
| `a2_compare.py` | 同名镜像逐项比：文件 sha、零填充后是否命中机上指纹 | `a2_compare.tsv/.json` |
| **`a3_slots.py`** | **按 a/b 槽位判"= ZUI16 / = ZUI17 / 都不是"**（核心判定） | `a3_slots.tsv/.json` |
| `a5_strings.py` | 抽版本串（内核、MPSS/ADSP/CDSP/WLAN、QC_IMAGE_VERSION、ZUI/TB331FC 标签） | `a5_strings.txt` |
| `a6_align.py` | 流式判定"真实内容改动"vs"仅 4K 对齐补零" | `a6_align.txt` |
| `a7_ramdisk.py` | 解 LZ4 legacy 帧（magic 只出现一次，之后是 `[size:4][data]` 重复）→ 输出 cpio | `work/*.cpio` |
| `a8_cpio.py` | 解析 newc cpio，逐文件 sha 比对（recovery / vendor_boot / init_boot） | `a8_cpio.txt/.json` |
| `a9_extract.py` | 抽出 `prop.default`/`build.prop`/`modules.load*` 供文本 diff | `work/x/*` |
| `a10_dtbo.py` | dtbo 45 个 overlay 的数量/尺寸/顺序/内容对比 | `a10_dtbo.txt` |
| `a11_vbpairs.py` | 从 avbtool 输出精确配对 (分区, Image Size) | stdout |
| `a12_tables.py` | 生成清单/判定 markdown 表 | `tables.md` |

关键命令：

```bash
# 核心：本机更像哪一版
wsl -d ub -u root -- bash -c "cd /mnt/e/rom/work/img-zui-diff && python3 a3_slots.py"

# 大文件 hash（增量输出，别用 xargs -P8 一次怼 5.5 GB 的 super_4，会长时间无进度）
wsl -d ub -u root -- bash /mnt/e/rom/work/img-zui-diff/t_hash.sh \
  '/mnt/e/rom/TB331FC/刷机包/TB331FC_ZUI_16.0.544/image' \
  /mnt/e/rom/work/img-zui-diff/zui16.sha256
```

**LZ4 坑记一笔**：recovery/vendor_boot/init_boot 的 ramdisk 都是 **LZ4 legacy 帧**，`magic 0x184C2102 在整个流里只出现一次**，之后是 `[size:4][data]` 反复。按"每块都带 magic"去解析会在第一块之后失步（`a7_ramdisk.py` 最初就踩了这个），而且每个块解出来正好 8 MiB，块大小不能省略 `uncompressed_size`。

---

## 8. 存疑 / 未解决

1. **B 槽三件到底是谁写进去的**：全量回刷中断（最可能，因为这三个正好是 b 槽最后三个）vs 事后手动单刷 ZUI17 boot 链。数据上等价，**未定**。
2. **固件 blob 内部改了什么**：版本串全不变、二进制 4%~60% 块不同。没有符号表，**未知**。
3. **modem 的 27% 差异**具体内容：**未知**（版本串一致，不能推出"没改功能"）。
4. **`imagefv` / `bluetooth` 同尺寸却内容不同**：改动点无法定位，**未知**。
5. `boot_a`/`boot_b` 当前到底是哪种补丁版（permissive？ramoops？KSU/APatch？）——需要把现机 `boot` 读回来跟 `boot-backup-*` 与几份实验镜像逐个比才能定，本轮**没做**（只确认了它不是两版原厂）。
6. `03_fp.tsv` 的采集时刻未记录，只能通过与 `rescue-matrix\reads\*_now.bin`、`boot-backup-20261024\*` 交叉对齐来间接确定（`vbmeta_a`/`vbmeta_system_a` 与 reads 一致，`dtbo_a`/`vendor_boot_a` 与 10-24 备份一致，`boot_a`/`init_boot_a` 与 10-24 备份**不一致**）⇒ 该指纹表至少晚于 2026-10-24 之后的那次 boot 改写。

---

*本报告所有数值均来自一次实跑；脚本与中间产物都在 `E:\rom\work\img-zui-diff\`，可直接重跑复核。*

---

---

---

## 附录 · 完整清单与判定表

> 由 `a12_tables.py` 自动生成，hash 全部为流式 sha256；ZUI16 侧 106 个文件、ZUI17 侧 29 个文件**全覆盖**。
> 表 B 只列能映射到分区的镜像；表 C 是 ZUI16 包剩下的烧写框架 + super 分片 + 单槽分区。
> `super_1..8.img` 是 EDL 把 12 GiB 的 super 分区拆成的 8 段裸写切片，不是镜像。

## 表 A · ZUI17 镜像集清单（29 个文件）

| 文件 | 大小 (B) | sha256 | 对应分区 |
|---|---:|---|---|
| `abl.img` | 274,432 | `fb5f9c18372711e5cc984c1fa7d4003e84194ae7060dd1fdf7504a2f9279a654` | abl |
| `abl_inner.bin` | 274,432 | `fb5f9c18372711e5cc984c1fa7d4003e84194ae7060dd1fdf7504a2f9279a654` | (abl 内部 ELF 副本) |
| `bluetooth.img` | 1,028,096 | `f6d28e08dedea00837ec7c67bc6139bd73f537b9e2084831ab1faaae59c1c6db` | bluetooth |
| `boot.img` | 100,663,296 | `490bc720a8bceaaae6fc18b444bbbb29c432adadb97ee563c3a2fd16950fac9f` | boot |
| `devcfg.img` | 45,056 | `8461d3b93f77a513d8a49e4719824de2ac79f94227ce2ab26c7c7a22ab558e7b` | devcfg |
| `dsp.img` | 33,554,432 | `e6dff50c4becc20edf98810a97c00784757de7554ac6bba0d58445abd42dea16` | dsp |
| `dtbo.img` | 8,388,608 | `cb5255bbd4369f36a7d9585d6d6b877c628b8bb4c14de48edaaad88331edd7f9` | dtbo |
| `featenabler.img` | 94,208 | `ed8b93bb6dd3cf06a927ef754274fc395050f870ef3d16a18ff73871f4f7c67c` | featenabler |
| `hyp.img` | 397,312 | `b9ff047225480827a98cbd0d4c806a45a30f84a141d048a08ea8c188d02b9197` | hyp |
| `imagefv.img` | 36,864 | `3e5732b912ba2bbec7c2b86a73ca2d72a4f4ba9e9659a9de75c19bf2c131713d` | imagefv |
| `init_boot.img` | 8,388,608 | `f0c8380df7fbb3b15a248e0b92f7b85bd05f1461a7eee4e5f7f5c808c7cc20d4` | init_boot |
| `keymaster.img` | 344,064 | `123c02e83db2458b8b20677afecf414d95b9872ba4ca56fb7455d3ab84ded493` | keymaster |
| `modem.img` | 40,980,480 | `3963e98a0a4702e909fe59238c76bc005f844f252666c1a004d962029fa2b8dc` | modem |
| `multiimgoem.img` | 16,384 | `26390e47ae4ed4604ee9415bc8d3aec27d79326ea21cf90a2d555abddc4b5904` | multiimgoem |
| `odm.img` | 1,495,040 | `8adb9ab10c14c61b71c7da1c6246d8ef4c37f2f0a6e04d088cbd9885972b3a46` | odm(逻辑) |
| `qupfw.img` | 57,344 | `bfe7c76c08f4cb96575880e43f6b8b6ae194a6cb109ff781dd9a4e226c7a69cb` | qupfw |
| `recovery.img` | 100,663,296 | `e08d35a061abd0f2a8989541740cdc5e301da7ea39c42a964ef467031db01e2a` | recovery |
| `rpm.img` | 229,376 | `829fe0874dbd7e1a32a99adfa6e3995b007e5d6e950697d1695e16ecb099add0` | rpm |
| `system_dlkm.img` | 438,272 | `4f8dabb00f6e7eb396ce4027d3b8bc7db34c75f24efdca806b4d2d941594d18b` | system_dlkm(逻辑) |
| `tz.img` | 3,514,368 | `2b5c11a339dbf60c13c91590a1bc6eeb805c32f8160ac9057e236969cb34fb0b` | tz |
| `uefisecapp.img` | 172,032 | `1d20b3abb517a385b22ab239ea5dcc6630ef4b6619ddfa99612d27b22d9fbf1c` | uefisecapp |
| `vb_dtb.dtb` | 1,290,690 | `b0ec0d53ff921d866cedc43f883506c14a116f603a9a5f1d1037a0a69234f704` | vendor_boot 内嵌 dtb |
| `vb_ramdisk.cpio` | 11,779,605 | `e587a39d5e53dcc409e2d8ab4f314e22400715b37ae21d32fc3a029e987e7f9b` | vendor_boot ramdisk(解压前) |
| `vbmeta.img` | 8,192 | `5c1f80901158695b0eafd004de0fbfea226ee615fb9b89ab5e2e043a9cb7ef9e` | vbmeta |
| `vbmeta_system.img` | 4,096 | `8582d030eb723749c3785287b739bd606a3c02c831d9493fc092a9d04d10bf17` | vbmeta_system |
| `vendor_boot.img` | 100,663,296 | `cdc982c8a62a1c3c4a0f688665e7b6de748eec91e5b6f56de9abc85db865153c` | vendor_boot |
| `vendor_dlkm.img` | 59,342,848 | `67b3e89a0e806081e99b80448598257575816e1a44c25be321ba9242c4e46acd` | vendor_dlkm(逻辑) |
| `xbl.img` | 3,227,648 | `99ca4203b653e97b9ac87ca55c4aeba69bcaa130a1876b691afc704990147aa3` | xbl |
| `xbl_config.img` | 45,056 | `429155385d55fb9b2fbe09f0cbca534528060dc2cb0689dffd58579802efa9d6` | xbl_config |

## 表 B · ZUI16 包内关键镜像清单（105 个文件里有 sha256 的）

| 文件 | 大小 (B) | sha256 | 对应分区 |
|---|---:|---|---|
| `BTFM.bin` | 1,028,096 | `f25020ecd08eba93d01bbf85d80cecbdf1a6f109910d962973c18e2d3a1bc697` | bluetooth |
| `NON-HLOS.bin` | 40,980,480 | `321f2795ade68987f9ffb00c512307940d7892dd6bc04cb33476e60c2bc9d667` | modem |
| `abl.elf` | 274,432 | `fb5f9c18372711e5cc984c1fa7d4003e84194ae7060dd1fdf7504a2f9279a654` | abl |
| `apdp.mbn` | 13,508 | `702157e0b50263dfb73fdb2a6eb07bc81dd9520102c95bba0ebe3a414309b4fb` | apdp |
| `boot.img` | 100,663,296 | `09daedb9313e2e14d857f5232b0f7443954ea35da7c52db415a88d05f8718d5b` | boot |
| `devcfg.mbn` | 42,748 | `8867d282e5e200f7e05fafb61939a5cbd55c01cbbe400b2bd59073aa4363d9a0` | devcfg |
| `dspso.bin` | 33,554,432 | `e6dff50c4becc20edf98810a97c00784757de7554ac6bba0d58445abd42dea16` | dsp |
| `dtbo.img` | 8,388,608 | `d8219b9a43c1a49417a3525adea2aa0ded4587ac8f9d811054718f893f88810f` | dtbo |
| `featenabler.mbn` | 90,673 | `e3f3b9a7ab1840c9d784d263b107b9acff73748b3dfb2b9cb5d11215935c4409` | featenabler |
| `hyp.mbn` | 393,224 | `ac546c69cd6d86541e75a24cbfad84006f37f098111104e8b8869128d4020039` | hyp |
| `imagefv.elf` | 36,864 | `2b5add782ed46c5d94e61142693b334c1d079bf70250381ccfee5254d28fa1fd` | imagefv |
| `init_boot.img` | 8,388,608 | `2d090fb59244cf3cf55b95478b98234f4a27615fd1c63220e685f76ae79bb01b` | init_boot |
| `keymint.mbn` | 342,462 | `96466864bd5946b56b799ff92cd1708012582f0559add7ad6b3a3b887c858aee` | keymaster |
| `logfs_ufs_8mb.bin` | 16,384 | `cadf6d7179d79ad39cbead824e2aa5394dd6447058d7990a2e37a94bb22e9e55` | logfs |
| `multi_image.mbn` | 13,512 | `e22470d3db9bab684bf608eb4e06f5158b3a7b999bf4cbc5de8a2ddff7c75796` | multiimgoem |
| `qupv3fw.elf` | 57,269 | `cffcc528c45a89838e8fcf9224ca65088ac9150fc2d2bd30c56b39d79ca0ae1b` | qupfw |
| `recovery.img` | 100,663,296 | `ea89e4c32e490b5eacd6323d577467ec76d2b7943a18bd0df8e31c310e93bd08` | recovery |
| `rpm.mbn` | 225,512 | `1bf3c662b82fbc2bc0202eec0b1e5225f881330675dad75aa9671625a762c369` | rpm |
| `storsec.mbn` | 36,076 | `d7b53f94054f9c3663c1dc469441820cf74394b0ffedb1ebc0713943ab35c5ff` | storsec |
| `tz.mbn` | 3,514,087 | `9587c4defb2f69503e0596ea3b8ccf634acd0d1f9b704cc24e4d043979a8b5a9` | tz |
| `uefi_sec.mbn` | 168,661 | `e24f3d6b5e4a4f748dbe3e7c35c958512bf798c67e0e9fc8a1e8c2e0b09a2585` | uefisecapp |
| `vbmeta.img` | 8,192 | `52ecb456ef3e5d82a05c8473cb90414ba90496ef7b41e155c1f9928389de8f66` | vbmeta |
| `vbmeta_system.img` | 4,096 | `1e0688b4778d23f74b78b5007bdf99129949fefa72471363d6d79d7f7defb9fb` | vbmeta_system |
| `vendor_boot-debug.img` | 13,164,544 | `4ee8d6873d4058f7cfe19be14172668e520f70d43f973532823978d61fb844ee` | (debug 变体) |
| `vendor_boot.img` | 100,663,296 | `d526c77b243c5277fd6fb715c9108f9bdc6f7728359ee19a383bc0442ed7a8a1` | vendor_boot |
| `xbl.elf` | 3,226,752 | `dc440eb971c07de6aa969e9791d63013effa0960ac724a04d1c5606f65a27db7` | xbl |
| `xbl_config.elf` | 43,056 | `9ab40e877fe82fe12c74525f31410914aa16a06d2a592d0bbecec4e96691cd1c` | xbl_config |

## 表 C · ZUI16 包内其余文件（烧写框架 / super 分片 / 单槽分区，共 78 个）

| 文件 | 大小 (B) | sha256 |
|---|---:|---|
| `FHLoaderErase.xml` | 1,006 | `b1ebcf94b0f42375737bb916d2b269605707320e5e4c0329e84c4c5b8f7dd580` |
| `NvDefinition.xml` | 3,342,928 | `cdf8c64f52c75b36922a993551ef77329d882ccb9f13b6915a2af0438407a81e` |
| `erase_UFS-128G.xml` | 988 | `991f97ba8ef1fc9baed7dd579939554a25445bac31b1eeb645d2e85bb5245eb3` |
| `erase_UFS-64G.xml` | 987 | `7433b0ded8452ab34c3b4eb905ac973b38477933536eefcc259c4829acab1609` |
| `gpt_backup0.bin` | 20,480 | `8fcb32c9282c8be5ab0bf68d73b445f5624ceed335f0472b8ae7e5e727e6e7a8` |
| `gpt_backup1.bin` | 20,480 | `6ab4aacef0cd8fdad465bc0161b62d58cc01ea5aef2405aba4932272069f20fd` |
| `gpt_backup2.bin` | 20,480 | `2f4a97b5ede3b8dd987c22403fc0ee0c1c442f9645e5fb98315a0c14d354532d` |
| `gpt_backup3.bin` | 20,480 | `3a91e20c0476c5ef65107b3ec32c5582d786d6dc5e35b1ffbfcc391920814c29` |
| `gpt_backup4.bin` | 20,480 | `e2cf08fc11844acea696c350b74d30fd53ea358196870426ee80976d8a833487` |
| `gpt_backup5.bin` | 20,480 | `0108b03103ce00e461f122782c3031735e858f3fa1168d93f8eab7ec956c6946` |
| `gpt_both0.bin` | 45,056 | `e68fe71b9fba6ac8c171d89df4d7904ecbc9112a3447aa210bb804f0eab14547` |
| `gpt_both1.bin` | 45,056 | `ce774fdb532f8383946f2074715abd64bf2059724df7880addfbc76fd4fda276` |
| `gpt_both2.bin` | 45,056 | `9ebadc4a628a21e9826f6e83ad1e15432a4c54fde375ebb4c0ebe80445fb570a` |
| `gpt_both3.bin` | 45,056 | `71734397b31df5fce722b79610705b76861bc2ab2df0675e20ca831c7f4c7e85` |
| `gpt_both4.bin` | 45,056 | `45757899a82668f258bc30c457cdfc05219accd3a7d6659ef9c0cdc29b3dd123` |
| `gpt_both5.bin` | 45,056 | `a5753fe0e7598369aa43a9794d80bb1166fcd18b576b2abb672ac60cb76bf92d` |
| `gpt_empty0.bin` | 24,576 | `296ad8f9dac8ae490e27fc296e68de9183a83efd638e4f05404c3de700e4cc05` |
| `gpt_empty1.bin` | 24,576 | `296ad8f9dac8ae490e27fc296e68de9183a83efd638e4f05404c3de700e4cc05` |
| `gpt_empty3.bin` | 24,576 | `296ad8f9dac8ae490e27fc296e68de9183a83efd638e4f05404c3de700e4cc05` |
| `gpt_empty4.bin` | 24,576 | `296ad8f9dac8ae490e27fc296e68de9183a83efd638e4f05404c3de700e4cc05` |
| `gpt_empty5.bin` | 24,576 | `296ad8f9dac8ae490e27fc296e68de9183a83efd638e4f05404c3de700e4cc05` |
| `gpt_main0.bin` | 24,576 | `41f439aea8d9333c241408c58da07dc95448ad8f9c040790826c3fbb191ce9ea` |
| `gpt_main1.bin` | 24,576 | `35678c14d384672aa68192dce9e4852c720011edc4468b771ab8d7fb7e4e0f69` |
| `gpt_main2.bin` | 24,576 | `71116f7ac866df11b6afa88088843834ad178ac97af01332932a4ca7fb9ab0f7` |
| `gpt_main3.bin` | 24,576 | `a711d2c18ffa6ff9b4bc5f473f3c8dfcc25795dcf4e5d4bad0fa555835d5f709` |
| `gpt_main4.bin` | 24,576 | `525a65a787be1546227d380ffdc7c1f245d4c48b70fd1eacacd2b3c76c47c34f` |
| `gpt_main5.bin` | 24,576 | `969a4b1cec1588a22ea4b66a91817c9caf61075d21b0c72b3f9a6b0902af0a85` |
| `metadata_1.img` | 8,192 | `02fe57ffe74d49dfddd4980a4e8adc136e6edea863516f3ec1874ef7234cb14e` |
| `metadata_2.img` | 32,768 | `a0bf10a74fd174b58700ad561daefba25d1fb43f9a78b7f7153779fa0a575f7e` |
| `metadata_3.img` | 10,539,008 | `b7879a8f4dfb4c2a655b6c8221e7df634b84ee8e3d5c384095d013b777d761a9` |
| `metadata_4.img` | 16,384 | `11d3e657a45035be48dcce2c4de46870c679652d46d6c5b1ec3bbf8b919e6edd` |
| `metadata_5.img` | 28,672 | `8fc3675f27f8ec64dff18edfbe5dacda54d14acc802f84e38575c71088e10d48` |
| `oemowninfo.img` | 1,048,576 | `30e14955ebf1352266dc2ff8067e68104607e750abb9d3b36582b8af909fcb58` |
| `partition.xml` | 16,496 | `420bb96b8916563c7455bc3fdca1727aa5d12c2c5933a6a2a4a8b6d7fa5c28bf` |
| `patch0.xml` | 6,263 | `64563bf5d0aaa2c41b3772ccc218cb258e9d2cd154442f4418657540e26dbc6a` |
| `patch1.xml` | 6,263 | `ddd1543f63ec11da6620cc20fdb68d904823defde9240b62e36bc1b7f2f792eb` |
| `patch2.xml` | 6,263 | `2c0a2125b2706e3c1b079fca4f3e80aa60eece64259b51ce9d70838d5fd9edde` |
| `patch3.xml` | 6,263 | `b5987d9616d44d4af421ffe00ee485afa98ddf402596f944f602cacb1db9022a` |
| `patch4.xml` | 6,271 | `7fd98352a8498bee3c2b3e216636a4af2970f378fe6adbc88751efe99249ba43` |
| `patch5.xml` | 6,263 | `6827f463fd448a963af569b1af8a47005048cbb04028796b49cff1c0f8cad1a1` |
| `persist.img` | 33,554,432 | `c98f42604397a1a71565fd27e0ae8cd44071368bdedd6203381be36391e50304` |
| `prog_firehose_sm6225_ddr.elf` | 670,608 | `26fba9b7e64ead8346ca387fe06f2d77bad8104b5c0deaa0fa9b249cd36f0930` |
| `prog_firehose_sm6225_lite.elf` | 670,480 | `a297d285626a7c8588aa3865671ff4da8e6927865d1c453238fa20d4a8e2d2c7` |
| `provision_default.xml` | 2,768 | `905fb066d8f9f0c71b167611e35829b86b8c455115de233cc4de5a314b1cd807` |
| `provision_hynix.xml` | 2,759 | `7646e1602d6bc58e35b282497909607fb40a41d381e46344c451160170370d39` |
| `provision_samsung.xml` | 2,759 | `7646e1602d6bc58e35b282497909607fb40a41d381e46344c451160170370d39` |
| `provision_toshiba.xml` | 2,759 | `fdfbd7edb808b880625f77abec17a350625cd09673513cc3697719cbf6807776` |
| `provision_ufs22.xml` | 2,488 | `c3d9626e6a4e9df118ace7137247060d0f77d12fe56dba2ac2a12686c41a4ce9` |
| `rawprogram0.xml` | 9,307 | `f68562f3b636cf5cc3faa5653a709735c389ac754f3c04e55599a69d64a26823` |
| `rawprogram0.xml.bak` | 4,793 | `f5fe0f28b0cba5fe6a414a4a036fb43c69b9ac4483eb0b54a32ab9d9dfbe2849` |
| `rawprogram1.xml` | 1,592 | `7e50c2bc9fcd249cf2354f44fbe1d44c9b9d68169699e580b4aa54225a5ce386` |
| `rawprogram2.xml` | 1,592 | `e59a65717f75f81d82f8f67b488954378385ce767b49454a644b4413933c2a5f` |
| `rawprogram3.xml` | 1,841 | `bb85dba1bbe4b905b881166e32d2e9d308b31f8ec5afcdac461d4447dea66f5d` |
| `rawprogram4.xml` | 19,916 | `5f4ce401ce3d4abf4a54d7bfacc981d3d0b2f04df86a34f8a93d6b23689e7240` |
| `rawprogram5.xml` | 2,406 | `3587eac493fc5f5dd6a88e46baa1fdd34cc73809d923674066e1dd50a225f7e1` |
| `restore_min.xml` | 2,799 | `ee1d5a087dff42df9942205e0a2c78a0e6fbbab43597e316dfe99a1717a00de0` |
| `sec.elf` | 12,764 | `7ae61f04098ae82527873371a4829f6d494060c3f44941c2f8cec3a918dc916d` |
| `super_1.img` | 405,504 | `3186e13c3165bf5473662a3aa360e0da70fefb0c3721968e1a62cd22395c8419` |
| `super_2.img` | 1,417,216 | `272aab39d7f6eac82c2c8365752cfe9b5da0313b1f3a5755314774abfca463b7` |
| `super_3.img` | 594,411,520 | `2ca3583312d0481af8ce712371c9ffb12ec2c597c25a1fbda7e9c827b470ecfb` |
| `super_4.img` | 5,493,624,832 | `0b059696ed140b3927b62af14a8b5b1e5fb602822ceac21d26e51011ce0d6001` |
| `super_5.img` | 438,272 | `63ccab07f6e31081636a26479015c8b58053adfd26ae7288445f7c7dc66c5307` |
| `super_6.img` | 460,103,680 | `a29984498917b6a33dfb273e7107540cce239a7058f5e36d32f37660dbc03291` |
| `super_7.img` | 681,275,392 | `c12155e98ca78580cecf41f8db0199804371e9a4aaa43becfeaba3c081b00932` |
| `super_8.img` | 58,933,248 | `b687b1821af17103fc3317f501301b9af909fa0128649f727c61cc5901796933` |
| `super_empty.img` | 5,288 | `28ae614bf9711cf33d3ecf2033fab5eb8713967241748fabb8be3b15ef838cd7` |
| `userdata_1.img` | 8,192 | `6b42d072d8fd6773e2be0dc796b2b721869b9638ecd6bf83eb54bcc45f79ceaa` |
| `userdata_10.img` | 5,054,464 | `b40bbb0131bd5a5492b622d5df971f3942b4f03013da544aa3abbaf33aca5782` |
| `userdata_2.img` | 32,768 | `2fbc9f2c74554c5ad367b8999a016814b24f873b9e64f908d578efbcbd05ffe1` |
| `userdata_3.img` | 69,255,168 | `6cd46166fbcc34286d18581957e2afc3bf1d654b732a4213607eff274ce18fd9` |
| `userdata_4.img` | 4,096 | `2761d7b7c9632493169cfd6b65cca14d14af30bce5dd389db695262e53a34bd4` |
| `userdata_5.img` | 4,096 | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` |
| `userdata_6.img` | 16,384 | `81917950b873d9876dd30565dbed6af4e3693c57d7fd0beaf58409cbdd1a0a70` |
| `userdata_7.img` | 28,672 | `1ef17787192d198c385c140e740568c67d07786f8b630b003a8d5f5e1d36fb8b` |
| `userdata_8.img` | 49,152 | `29d34c57b08da73c97a8fd7b26b3a72e1c9e333d65dadacdf5b49393b31812b9` |
| `userdata_9.img` | 90,112 | `05e37708cdc3f0ed9c485b1e828f5c4e3576137f529b45520178c717ee6ad5a6` |
| `vb_dtb.dtb` | 1,290,690 | `ef51cc7c27f7b83fc41ab6714efedb576531cb24ebacc6c0938ce8417398b940` |
| `vb_ramdisk.cpio` | 11,628,676 | `778db4af053c6cdb538a9f20f0093db9c1ec089ceb1124e9faa6fea05e845ecf` |

## 表 D · 机上 49 个分区槽位 vs 两版的精确判定

| 分区 | 大小 (B) | 模式 | = ZUI16? | = ZUI17? | 判定 |
|---|---:|---|---|---|---|
| `abl_a` | 1,048,576 | FULL | YES | YES | **两版相同** |
| `abl_b` | 1,048,576 | FULL | YES | YES | **两版相同** |
| `apdp` | 262,144 | FULL | YES | no | **= ZUI16** |
| `bluetooth_a` | 1,048,576 | FULL | YES | no | **= ZUI16** |
| `bluetooth_b` | 1,048,576 | FULL | YES | no | **= ZUI16** |
| `boot_a` | 100,663,296 | HEAD64M | no | no | **都不是（被改过/第三来源）** |
| `boot_b` | 100,663,296 | HEAD64M | no | no | **都不是（被改过/第三来源）** |
| `devcfg_a` | 131,072 | FULL | YES | no | **= ZUI16** |
| `devcfg_b` | 131,072 | FULL | YES | no | **= ZUI16** |
| `dsp_a` | 33,554,432 | FULL | YES | YES | **两版相同** |
| `dsp_b` | 33,554,432 | FULL | YES | YES | **两版相同** |
| `dtbo_a` | 25,165,824 | FULL | YES | no | **= ZUI16** |
| `dtbo_b` | 25,165,824 | FULL | YES | no | **= ZUI16** |
| `featenabler_a` | 131,072 | FULL | YES | YES | **两版相同** |
| `featenabler_b` | 131,072 | FULL | YES | YES | **两版相同** |
| `hyp_a` | 524,288 | FULL | YES | no | **= ZUI16** |
| `hyp_b` | 524,288 | FULL | YES | no | **= ZUI16** |
| `imagefv_a` | 2,097,152 | FULL | YES | no | **= ZUI16** |
| `imagefv_b` | 2,097,152 | FULL | YES | no | **= ZUI16** |
| `init_boot_a` | 8,388,608 | FULL | YES | no | **= ZUI16** |
| `init_boot_b` | 8,388,608 | FULL | no | YES | **= ZUI17** |
| `keymaster_a` | 524,288 | FULL | YES | no | **= ZUI16** |
| `keymaster_b` | 524,288 | FULL | YES | no | **= ZUI16** |
| `logfs` | 8,388,608 | FULL | YES | no | **= ZUI16** |
| `modem_a` | 188,743,680 | HEAD64M | YES | no | **= ZUI16** |
| `modem_b` | 188,743,680 | HEAD64M | YES | no | **= ZUI16** |
| `multiimgoem_a` | 32,768 | FULL | YES | no | **= ZUI16** |
| `multiimgoem_b` | 32,768 | FULL | YES | no | **= ZUI16** |
| `qupfw_a` | 65,536 | FULL | YES | no | **= ZUI16** |
| `qupfw_b` | 65,536 | FULL | YES | no | **= ZUI16** |
| `recovery_a` | 104,857,600 | HEAD64M | YES | no | **= ZUI16** |
| `recovery_b` | 104,857,600 | HEAD64M | no | YES | **= ZUI17** |
| `rpm_a` | 524,288 | FULL | YES | no | **= ZUI16** |
| `rpm_b` | 524,288 | FULL | YES | no | **= ZUI16** |
| `storsec` | 131,072 | FULL | YES | no | **= ZUI16** |
| `tz_a` | 4,194,304 | FULL | YES | no | **= ZUI16** |
| `tz_b` | 4,194,304 | FULL | YES | no | **= ZUI16** |
| `uefisecapp_a` | 2,097,152 | FULL | YES | no | **= ZUI16** |
| `uefisecapp_b` | 2,097,152 | FULL | YES | no | **= ZUI16** |
| `vbmeta_a` | 65,536 | FULL | YES | no | **= ZUI16** |
| `vbmeta_b` | 65,536 | FULL | YES | no | **= ZUI16** |
| `vbmeta_system_a` | 65,536 | FULL | no | no | **都不是（被改过/第三来源）** |
| `vbmeta_system_b` | 65,536 | FULL | YES | no | **= ZUI16** |
| `vendor_boot_a` | 100,663,296 | HEAD64M | YES | no | **= ZUI16** |
| `vendor_boot_b` | 100,663,296 | HEAD64M | no | YES | **= ZUI17** |
| `xbl_a` | 3,670,016 | FULL | YES | no | **= ZUI16** |
| `xbl_b` | 3,670,016 | FULL | YES | no | **= ZUI16** |
| `xbl_config_a` | 131,072 | FULL | YES | no | **= ZUI16** |
| `xbl_config_b` | 131,072 | FULL | YES | no | **= ZUI16** |


