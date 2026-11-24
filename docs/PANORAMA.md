# TB331FC 全景机制文档（PANORAMA）

> 设备：联想小新 Pad 2024 **TB331FC** / 代号 `khaje` / **SM6225-AD（骁龙 685，bengal 平台）**
> 生成日期：2026-11-25 · 性质：**只读整合**。本轮未刷机、未连设备。
> 本文把本轮全部研究报告合并为一份权威机制视图。**每条结论都标了出处**（`→ 报告 §节`），
> 出处格式见 §0.3 的映射表；地址/偏移一律给原始值，不做四舍五入。

---

## 0. 读法

### 0.1 证据分级

【实测】= 本机真机回显 / 归档原始日志 · 【静态】= 对原厂镜像/XML 的字节级解析 ·
【反汇编】= 对 ABL/XBL 的指令级取证 · 【推断】= 多条证据收敛但未直接观测 · 【未证】= 明确没有证据。

### 0.2 一句话总览

```
PBL(ROM) ──验签──> XBL = SBL1 + 完整 QCOM UEFI(102 个 DXE 模块)
                        └─ QcomBds ──LaunchAppFromGuidedFv──> ABL(LinuxLoader)
                              └─ LoadKernel/BootLinux ──blr x8──> Linux(EL1)
                                                                  ▲
                          EL2 已被 QIPL 的 hyp(mbn) 占用（kvm: HYP mode not available）
```

**三条目标线各自的真实阻塞点不同：**
- **刷机包**：技术上已闭环（v4 六项验收通过），阻塞在"真机四项未验"与"A17 起不来的 hashtree 根因已定位但需按批重签"。
- **recovery**：编译已解决（三条路线都有产物），阻塞在 **ABL 对 `recovery` 分区的独立校验/白名单**。
- **Linux/WoA**：mainline 内核已编出可刷件，则**自编 UEFI 跳进即挂死**，且"SEC 栈踩 XBL""FD 基址覆盖致命"两条假设**均已被证伪**，故障点未定位。

### 0.3 出处缩写映射

| 缩写 | 报告 |
|---|---|
| `xbl` | `work\img-xbl\REPORT.md`（+ `table_dxe.md`、`cfg\`） |
| `abl` | `work\img-abl\REPORT.md` |
| `tee` | `work\img-tee\REPORT.md` |
| `900e` | `work\img-900e\REPORT.md`（+ `analyze.py`） |
| `9008` | `work\img-9008\REPORT.md` |
| `small` | `work\img-smallparts\REPORT.md` |
| `bootgrp` | `work\img-boot-group\REPORT.md` |
| `zuidiff` | `work\img-zui-diff\REPORT.md`（+ `tables.md`） |
| `dual` | `work\dual-boot\REPORT.md` / `work\dual-boot\FLASH-PLAN.md` |
| `ofrec` | `work\of-build\GUIDE-RECOVERY.md` |
| `ofkern` | `work\of-build\GUIDE-KERNEL.md` |
| `wdt` | `work\woa\wdt-proof\REPORT.md` |
| `secmem` | `work\woa\sec-memory\REPORT.md` |
| `clean` | `work\disk-cleanup-2026-11-24\REPORT.md` |
| `rl` | `work\research-lenovo-20261124\REPORT.md` |
| `rca` | `work\research-coolapk-20261124\REPORT.md` |
| `rgh` | `work\research-gh-20261124\`（**只有 `MANIFEST-downloads.tsv` + 抓取树，无 REPORT.md，进行中**） |
| `v4` | `work\flashkit-v4\REPORT.md` |
| `super`/`firmware` | `work\img-super\`、`work\img-firmware\`（**目录只有脚本与 raw/ 素材，REPORT.md 尚未生成 ⇒ 本文相关段落标「进行中」**） |

---

## 1. 硬件

### 1.1 SoC 与固件基线

| 项 | 值 | 出处 |
|---|---|---|
| SoC | SM6225-AD（骁龙 685），**bengal** 平台，`soc_id 518`，代号 `khaje`，变体 `DivarLAA` | `xbl` §0.1、`rl` §1 |
| 固件家族 | `BOOT.XF.4.1`（ZUI16 与 ZUI17 两版**版本串完全相同**） | `xbl` §0.1、`zuidiff` §4.2 |
| XBL 构建指纹 | `msm-kernel-bengal-consolidate` / `abl-user` / `DEBUG_CLANG35`（DEBUG 版 ABL ⇒ 日志串丰富） | `abl` 头部 |
| 存储 | **UFS，6 个 LUN，全部 4096 B 逻辑扇区** | `9008` §2.3 |
| 槽位 | **A/B（slot-count=2）+ 独立 `recovery` 分区**（96 MiB / 100,663,296 B） | `9008` §3.3、`ofrec` §0.1 |
| 内存 | 6 GB；`/proc/iomem` 实测 `40000000-456fffff`、`48000000-4aafffff`、`55d17000-5fffffff`、`63900000-7cbfffff`、`80000000-1bfffffff` 为 System RAM，`MemTotal 5,778,924 kB` | `secmem` §1.4 |
| 显示 | **BOE p255 + Himax HX83102J**，1200×1920@90Hz，`orientation=180`（= 横屏 1920×1200） | `bootgrp` §4.4 |
| 触摸 | 同颗 TDDI，SPI `touch@0`（`himax,hxcommon` + `novatek,NVT-ts-spi` 双 compatible），10 MHz，IRQ GPIO80 / RST GPIO86 | `bootgrp` §4.4、`ofrec` §0.1 |
| 解锁态 | `unlocked: yes`、`secure: yes`（硬件 Secure Boot 仍开）、`verifiedbootstate=orange` | `tee` §4.3、`bootgrp` §3.2 |

### 1.2 内存地图（原厂一手证据：`uefiplat.cfg`，已解出 9,098 B 明文）

XBL 内 `uefiplat.cfg` 位于 `FD+0x40000`（RAW 载荷起点 `FD+0x40038`），`Version=3`、`MaxMemoryRegions=74`。
`[MemoryMap]` 共 17 条（DDR 侧），下表是最有用的 12 条（**全部为原厂声明，非二手引用** → `xbl` §3.1）：

| 标签 | 基址 | 大小 | MemoryType / 缓存 |
|---|---|---|---|
| Kernel | `0x40000000` | `0x05700000` | Reserv / WB_XN |
| HYP | `0x45700000` | `0x00600000` | Reserv / WB_XN |
| Boot Info | `0x45D00000` | `0x00020000` | **BsData** / WB_XN |
| SMEM | `0x46000000` | `0x00200000` | Reserv / UC_XN |
| PIL Reserved | `0x4AB00000` | `0x09400000` | Reserv / UC_XN |
| **DXE Heap** | `0x53F00000` | `0x02800000` | Conv / WRITE_BACK |
| **Display Reserved** | `0x5C000000` | `0x01000000` | Reserv / **WRITE_THROUGH_XN** |
| FV Region | `0x5F800000` | `0x00200000` | BsData / WB_XN |
| **ABOOT FV** | `0x5FA00000` | `0x00200000` | **Reserv** / WRITE_BACK |
| **UEFI FD** | `0x5FC00000` | `0x00300000` | **BsData** / WRITE_BACK |
| SEC Heap | `0x5FF00000` | `0x0008C000` | BsData / WB_XN |
| CPU Vectors | `0x5FF8C000` | `0x00001000` | BsData / WRITE_BACK |
| MMU PageTables | `0x5FF8D000` | `0x00003000` | BsData / WB_XN |
| **UEFI Stack** | `0x5FF90000` | `0x00040000` | BsData / WB_XN |
| Log Buffer | `0x5FFF7000` | `0x00008000` | RtData / WB_XN |
| Info Blk | `0x5FFFF000` | `0x00001000` | RtData / WB_XN |

三条最有用的解读（→ `xbl` §3.1）：
1. `UEFI FD 0x5FC00000` 的 MemoryType 是 **`BsData`**（不是 `Reserv`）⇒ 语义上 ExitBootServices 之后可复用。
2. `Display Reserved 0x5C000000 + 16 MB, WRITE_THROUGH` = splash 预留区；khaje DTS 里 `cont_splash_region` 是 **15 MB**（`0xF00000`）——同一块地的两种标定（高通多了 1 MB）。
   想在 UEFI 里画东西，帧缓冲就在这里，且 WT 属性不需要 flush cache。
3. `ABOOT FV 0x5FA00000 + 2 MB` 是 `Reserv` —— 这正是 BDS 从 `abl.img` 解出的 guided FV 的落地点，**ABL 的运行现场，不要碰**。

`[ConfigParameters]` 里与本项目直接相关的键（38 条中的 12 条，→ `xbl` §3.3）：

| 键 | 值 | 含义 |
|---|---|---|
| `DefaultBDSBootApp` | `"LinuxLoader"` | ★ 默认启动 app（按 guided FV 加载，不是路径） |
| `DefaultChargerApp` | `"QcomChargerApp"` | 充电界面（走**文件路径** `fv1:\…`，与上一条机制不同） |
| `SecurityFlag` | **`0xC4`** | bit0 `SecBootEnableFlag`=**0**、bit2 `CommonMbnLoad`=1、bit6 `LoadSecApp`=1、bit7 `LoadKeymaster`=1 |
| `TzAppsRegnAddr` / `Size` | `0x61800000` / `0x02100000` | TZ Apps 区 33 MB（KeyMint TA 落点） |
| `EDL cookie` | `DloadCookieAddr=0x003D3000` / `Value=0x10` | 写 `0x10` 到 IMEM `0x3D3000` 再复位 ⇒ SBL 进 EDL |
| `EnableLogFsSyncInRetail` | `0x0` | 零售版不同步 logfs ⇒ **拿不到运行期 ABL/BDS 日志** |
| `EnableDisplayThread` | `1` | 显示在独立线程并行初始化（解释"有 logo 但很晚才有字"） |
| `EnableShell` | `0x1` | **空转**：DXE 卷里没有 Shell 模块 |
| `AllowNonPersistentVarsInRetail` | `0x1` | UEFI 变量可退化 volatile（写坏变量时的兜底） |
| `PwrBtnShutdownFlag` | `0x0` | 电源键不做软关机判定（长按关机是 PMIC 硬件行为） |

> **更正**：旧报告引用 `SecBootEnableFlag = 0x1` 说"安全启动使能"——那一行在 cfg 里是**注释**（`# SecBootEnableFlag = 0x1 …`）。真值是 `SecurityFlag = 0xC4`，bit0 = **0**。详见 `CORRECTIONS.md` C-03。
> 与 tapas 那份 cfg 的关系：**内容逐条一致，只差 tapas 多一行 `LAST LOG`，所以 19 行之后整体前移 1 行**（`xbl` §3.4）。

### 1.3 三条硬件级硬约束（本轮新增，全部有证据）

| # | 约束 | 证据 | 后果 |
|---|---|---|---|
| 1 | **XBL 的 UEFI 里没有 ACPI** | 整个 DXE 卷里 `DSDT`/`FACP`/`RSDP`/`XSDT`/`FADT`/`ECAM`/`MCFG` **全部 0 命中**（`ACPI` 仅有 2 处断言串）→ `xbl` §4.1 | 这套固件**不可能直接跑 `bootmgfw.efi`**；Windows 必须靠 Mu 自编 FD 生成 ACPI |
| 2 | **没有 USB 主机协议生产者** | DXE 卷里 `UsbKb`/`UsbMouse`/`Xhci` 字符串 0 命中；**没有任何模块含 `EFI_USB_HC_PROTOCOL`(2f707ebb) 或 `EFI_USB2_HC_PROTOCOL`(240a86d8) 的 GUID**；唯一出现 `EFI_USB_IO_PROTOCOL`(2b2f68d6) 的是 **QcomBds（消费者）** → `xbl` §4.1 | "插 U 盘让 BDS 引导"在这份固件里**没有驱动支撑**；BDS 的 30 s USB-first 等待窗**永远等不到设备**，只把开机拖慢（`xbl` §5.5） |
| 3 | **EL2 已被 QHEE hyp 占用** | 5 份 900E 转储的内核日志一致命中 `kvm [1]: HYP mode not available`；cmdline 主动写了 `kvm-arm.mode=protected` 但仍无 EL2 → `tee` §3.2 | KVM/pKVM 用不了；"我到 EL2 做 hypervisor/UEFI 运行环境"的方案必须先让 XBL 不加载 `hyp`，而该开关不在任何可写分区里 |

`hyp.mbn`：393,224 B，ELF64 ET_EXEC，入口 `0x4574a000`，LOAD memsz 2,334,720 B，
签名 **Lenovo Elm 链**（与 `keymint.mbn` 同链），自述串 `HYP Version Info`、`SMC call to qsee from hypervisor failed`。
DT carveout `hyp_region@45700000`，内核实测 `0x45700000..0x45cfffff (6144 KiB) nomap non-reusable` → `tee` §3.1。

---

## 2. 分区全表

### 2.1 LUN 布局

| LUN | 装什么 | 备注 |
|---|---|---|
| 0 | 主表：`persist` `misc` `oemowninfo` `keystore` `frp` `vbmeta_system_*` `lenovo*` … | `PrimaryGPT` 在 sector 0（24 KiB） |
| **1** | **`xbl_a`**（sector 6，896 扇区） | **PBL 的启动 LUN**；写坏 = 只能靠 9008 救 |
| **2** | **`xbl_b`**（sector 6，896 扇区） | 第二个启动 LUN |
| 3 | `cdt`（sector 32，32 扇区） | 平台/panel/DDR 配置，XBL PEI 阶段读 |
| 4 | `abl_*` `tz_*` `hyp_*` `keymaster_*` `devcfg_*` `boot_*` `init_boot_*` `vendor_boot_*` `dtbo_*` `recovery_*` `vbmeta_*` `cmnlib*` `uefivarstore` `logfs` `rawdump` `logdump` `splash` `spunvm` … | 绝大多数可写分区都在这 |
| 5 | `modemst1/2` `fsg` `fsc` | NV / EFS |

→ `9008` §3.3、§2.3；`small` §2.2

> `physical_partition_number` = **LUN 号**，不是"分区序号"。6 个 LUN 全部 `bLogicalBlockSize=0x0c`（= 4096）→ `9008` §2.3。

### 2.2 关键分区几何（起点已用 GPT 逐条核对，91/91 全中）

| 分区 | LUN | start_sector | sectors | 大小 | GPT bit60 | 备注 |
|---|---|---|---|---|---|---|
| `persist` | 0 | 8 | 8192 | 32 MiB | – | 声音/校准/MAC；官方包 **不写** |
| `misc` | 0 | 8200 | 256 | 1 MiB | – | BCB + ABL 私有状态 |
| `oemowninfo` | 0 | 8584 | 256 | 1 MiB | RO | 出厂身份 |
| `vbmeta_system_a` | 0 | 3235720 | 16 | 64 KiB | RO | 锚点已核 |
| `xbl_a` / `xbl_b` | 1 / 2 | 6 | 896 | 3.5 MiB | RO | **PBL 验签** |
| `tz_a` | 4 | 134 | 1024 | 4 MiB | RO | |
| `abl_a` | 4 | 56838 | 256 | 1 MiB | RO | 写坏 = 失去 fastboot |
| `boot_a` | 4 | **65414** | 24576 | 96 MiB | – | 锚点已核 |
| `keymaster_a` | 4 | 65286 | 128 | 512 KiB | RO | |
| `cmnlib_a` | 4 | **89990** | 128 | 512 KiB | RO | 锚点已核；**永远全零**（见 §4.3） |
| `cmnlib64_a` | 4 | 90118 | 128 | 512 KiB | RO | 同上 |
| `vbmeta_a` | 4 | **90294** | 16 | 64 KiB | RO | 锚点已核 |
| `init_boot_a` | 4 | 97518 | 2048 | 8 MiB | – | KSU 修补目标 |
| `recovery_a` | 4 | 99566 | 25600 | 100 MiB | RO | ABL 白名单会拦第三方 rec |
| `vendor_boot_a` | 4 | 125166 | 24576 | 96 MiB | – | cmdline/模块/DTB 全在这 |
| `uefivarstore` | 4 | 362212 | 128 | 512 KiB | RO | `PTBL`+`VAR2` 私有格式 |
| `logdump` | 4 | 345788 | 16384 | **64 MiB** | – | 空分区，可当取证草稿区 |
| `rawdump` | 4 | 313020 | 32768 | **128 MiB** | – | 同上 |
| `modemst1` / `modemst2` | 5 | 32 / 544 | 512 | 2 MiB ×2 | – | 本机非零（74.68%）；`fsg` 金备份**全零** |

→ `9008` §3.3/§3.7、`small` §2.1/§2.2

**三个必须知道的长度陷阱**（→ `9008` §3.4/§3.7）：
1. `label` **不参与寻址**，只认 `start_sector` + `num_partition_sectors`；label 写错会**静默写到别处**。
2. `NUM_DISK_SECTORS-n` 是**设备端支持的表达式**；出厂 `gpt_main*.bin` 的 `AlternateLBA` 是"预打补丁"值，别当真实盘尾。
3. `super`/`metadata` 在扇区表里只是**非零分片**（super 表内 1,779,934 扇区 vs GPT 3,145,728）；`userdata` 在出厂 GPT 里长度写 **0**（靠 `patch0.xml` 按实际容量补）⇒ 要全长必须 `getstorageinfo` 或读活体 GPT。

### 2.3 分区计数与"全零"的分类

| 数字 | 值 | 出处 |
|---|---|---|
| GPT 分区项 | 97 | `9008` §3 |
| `by-name` 可见 | 88 | `zuidiff` §3.3 |
| `rawprogram*.xml` 里 `filename=""` | **47 条**（扣 5 条 `last_parti` 占位 ⇒ **42 个真实分区官方包不写**） | `9008` §3.7 |

**"全零"必须分两类，混起来会得出错误结论**（→ `small` §6）：

| 类别 | 分区 | 判据 |
|---|---|---|
| **本来就应该全零**（正常态，别去"修"） | `cmnlib_a/b`、`cmnlib64_a/b`（黄金 md5 `59071590099d21dd439896592338bf95`）、`fsc`、`apdp`、`limits`、`toolsfv`、`multiimgqti`、`cate*`、`rawdump`/`logdump`、`spunvm`、`frp`、`secdata` | 见 §4.3 的 TEE 机制 |
| **被一次动作清零**（不该全零） | `keystore`（Widevine keybox）、`splash`、`lenovolock`、`lenovocust`(300 MB)、`fsg`（NV 金备份 → 单向损失）、**历史实证的 `persist`** | 共同成因已定位：**QFIL 勾「Erase All Before Download」或重跑 `provision_*.xml`** → `tee` §5.3 红线 2、`small` §6.2 |

**通用判据（按这个顺序，能省很多误判）**（→ `small` §6.4）：
1. 包里 `filename` 非空 ⇒ 官方会写 ⇒ 本该有内容；`filename=""` ⇒ 官方**从不**写，全零可能"出厂如此"也可能"被谁清了"，只能靠同型号机对比区分。
2. 看功能面有没有症状（`persist`→声音/MAC/传感器；`keystore`→DRM/attestation；`cmnlib`→TZ 起不起；`misc`→能否正常重启）。**功能正常就不能判它坏了。**
3. 看"形状"：真空分区整块 0 无残留；被清过的往往有结构残骸。
4. 看时间戳（`persist` 的 ext4 `mtime/wtime = 1970-01-01T00:00:26Z`，是时钟未设置时 mkfs 的）。

### 2.4 `misc` 的结构（1 MiB，实测字节级）

```
0x0000-0x001F  command[32]   实测 = 00×8 + "-bootloader" + 00×13   ← 不是有效命令
0x0020-0x033F  status[32] / recovery[768]
0x0340-0x07FF  stage[32] / reserved     全零
0x0800-0x7FFF  全零（含 AOSP 认为放 bootloader_control 的 +2048）
0x8000        02 B0 0A 74 56     ← ABL 私有状态 #1（5 B）
0x8080        01 0C 11 B5 6A     ← 私有状态 #2
0x80C0        01 "roms"          ← 私有状态 #3
0x80C5-0xFFFFF 全零
```
**非零总计 26 B，只占 4 KiB 块 #0 与 #8。** → `small` §3.1

- ABL 在 `command[32]` 上**只认两个字面量**：`boot-recovery`（串 `0xa42a3`）与 `boot-fastboot`（串 `0xaf0f6`）。首字节是 NUL ⇒ 当前等价于"空命令"，**不会让设备再进 recovery/fastbootd** → `small` §3.2。
- `0x8000` 那 15 B 的语义**未闭合**：不是 AOSP `bootloader_control`（无 `BLLT` magic、CRC 不成立），也不是 QCOM slot 表。ABL 里与 misc 相关的串指向 **FFBM（Fast Factory Boot Mode）** 与 **virtual-A/B 快照消息** 暂存 → `small` §3.1。
- **安全清法**：只写 `[0,4096)` 全零（等价于只清 `command[32]`，因为这块本来就只有 `0x08..0x12` 有内容）。产物 `misc_clear4k_zero.bin` + `write_misc_clear.xml` 已生成 → `small` §3.3。

### 2.5 `devinfo`（4 KiB，只有 14 个非零字节）

```
0x0000-0x000C  "ANDROID-BOOT!"   魔数 13 B
0x000D         0x00   ← is_unlocked
0x000E         0x00   ← is_unlock_critical
0x0090         0x01   ← verity_mode（不是解锁位！）
其余全零
```
**指令级证据**（ABL 写盘函数，→ `small` §4.2）：

| 地址 | 指令 | 含义 |
|---|---|---|
| `0x2dc20` | `strb w8,[x1,#0xd]` | is_unlocked → **+0x0D** |
| `0x2dd90` | `strb w8,[x1,#0xe]` | is_unlock_critical → **+0x0E** |
| `0x2d770` | `strb w8,[x1,#0x90]` | **verity_mode → +0x90** |
| `0x2e648` | `strb w0(=1),[x1,#0x90]` | verity_mode 初始化 = 1（与 dump 完全吻合） |

**为什么"读出 0 却已解锁"**：解锁权威**不在 devinfo**。初始化函数 `0x2e5f4 bl 0x13230` 一步同时决定两个全局，而
`0x13230` 是 `gBS->LocateProtocol(GUID {8E5EFF91-21B6-47D3-AF2B-C15A01E020EC})` —— **向固件/安全侧问状态**，不是读分区字节。
且三个写函数都是**幂等**的（先比当前值，相等就 `ret`），比较发生在"全局 vs 全局"之间，所以"分区里 0、运行时 unlocked"可以长期共存。
`verifiedbootstate=orange` 的权威来源是固件/硬件侧 + TZ 的 `qsee_get_secure_state` → `small` §4.3。

### 2.6 `uefivarstore`（512 KiB，Qualcomm 私有格式）

```
0x000000  "PTBL" 头（0x00..0x37 页/项描述）
0x002000  "VAR2" 记录区 ← 真正的变量
```
现有变量（全量）：`ConIn` `ConOut` `ErrOut` `SetupMode` `SecureBoot` `SignatureSupport` `VolatileTables`
`VarTableInit` `RTCInfo` `RunCycles` `MemoryOverwriteRequestControl` `HwErrRec*` `UefiSecAppLoadAddr` `UefiSecAppVersion`。
**没有 `Boot####` / `BootOrder` / `BootNext` / `AttemptUSBFirst` / `KernelBaseAddr`。** → `small` §5.1

- 权限上：有裸分区节点，需 root；**不在任何 vbmeta 描述符里** ⇒ 不受 AVB 保护；不在 critical 表、不在锁态表 ⇒ **fastboot 也能写**。
- **真正卡点是 `PTBL` 头那 0x38 字节的语义没解出来**，所以"安全追加一条变量"的补丁做不出来。写坏大概率只是变量回默认（`AllowNonPersistentVarsInRetail=0x1` 兜底），但**未验证** → `small` §5.2。

---

## 3. 启动链：PBL → XBL → ABL → Linux

### 3.1 全景

```
PBL (SoC 掩膜 ROM，无文件)
  │ 从 LUN1 xbl_a / LUN2 xbl_b 载入，用熔丝根证书验 xbl.img 的 hash 段
  ▼
XBL = ph6 (SBL1 主体，0x0C225000) + ph16 (完整 FFS2 UEFI 固件卷 @0x5FC00000, 0x220400)
  │ SBL1: DDR 训练 / PMIC / SMEM / DAL / forced-EDL 判定 / 把 ph16 搬到 0x5FC00000
  ▼
SEC (XBLCore，PrePi 型；TE ImageBase 0x5FC01000，entry RVA 0xBD30 → 0x5FC0CD30)
  │ 解析 uefiplat.cfg → 建内存图 → 解 GUIDed gzip 段 → 直接把 DxeCore 装起来并跳进去
  ▼
DXE (102 个 FFS；DxeCore 0x041030 B + 74 DRIVER + 25 FREEFORM + 1 APPLICATION)
  │ 驱动全部装起来；QcomBds 是 BDS
  ▼
QcomBds.efi (110,592 B，ImageBase=0 ⇒ VA==文件偏移)
  │ 0x107DC 读配置 "DefaultBDSBootApp"
  │ 0x10810 LaunchAppFromGuidedFv(FvName 046fae99-cf2e-49ed-a6a8-a1488b7e80d3, "LinuxLoader")
  ▼
ABL = LinuxLoader.efi（970,752 B，PE32+，VA==文件偏移），FV 落在 ABOOT FV 0x5FA00000+2MB
  │ fastboot continue → 0x7f0fc → LoadImageAndAuth 0x1afd4 → BootLinux 0x6a30
  │ 0x8610  x8 = BootInfo+0x40（= 解压目标 = KernelBaseAddr+0x80000）
  │ 0x861c  x0 = BootInfo+0x58（= DTB）
  │ 0x862c  blr x8
  ▼
Linux（EL1；EL2 已被 hyp 占）
```

→ `xbl` §0.1/§2/§5.1/§6.3、`abl` §0、`tee` §3.2

### 3.2 XBL = 无加密 + 一个签名

- **没有任何加密段。** 唯一的高熵带（`0xC0000–0x28FFFF`，逐 64 KB 熵 7.96–7.98）完全落在 ph16 内，是 FFS `9e21fd93-9c72-4c15-8c4b-e77f1db2d792` 的 GUIDed 段（GUID `1d301fe9-be79-4353-91c2-d23bc959ae0c`，`DataOffset=0x18`，`attr=PROCESSING_REQUIRED`），载荷首字节 `1f 8b 08 00` = **gzip**；解出 **6,631,112 B** 的合法 DXE 卷（`FvLength 0x652EC0`、102 个 FFS 全部头校验成立）→ `xbl` §1.1/§1.2。
- **真正不可改的是签名**：`ph1`（`0x1000–0x2CD8`）是 QCOM hash+cert 段，明文可读（DER 链里有 `QUALCOMM` / `Elm Root CA` / `Elm Attestation CA` / `BeiJing0/1`，有效期 `230626014543Z`–`430621014543Z`），但改一个字节 PBL 验签就失败 → `xbl` §1.3。
- FD 头逐字节核对：`ZeroVector` = AArch64 `b +0xCD30` → `0x5FC0CD30`，**逐位等于** SEC TE 的 `ImageBase 0x5FC01000 + 0xBD30`；FV 头校验和按 EDK2 16 位截断累加实算 `0x9857` = 文件里的 `0x9857` → `xbl` §2（更正了旧报告"ZeroVector 是 L3 魔数、校验和不成立"的说法）。
- SEC 是 **PrePi 型、没有 PEI 阶段**，自述串证明：`UefiPlatCfg.c` / `"uefiplat.cfg"` / `"UEFI Memory Map configuration not found"` / `PrePiLib.c` / `"Loading DxeCore at 0x%10p EntryPoint=0x%10p"` → `xbl` §2 末尾。

### 3.3 BDS 的引导逻辑（地址级）

`QcomBds.efi`：`.text 0x1000–0x19000`、`.data 0x19000–0x1A000`。主函数在 `0x105xx–0x10AC0`：

```
106E0 读 "FwVerStr" 变量 → 打印 "UEFI Ver   : %a"
1073C 0x30D0(...)                 ; 充电 / off-mode-charging 判断
10744 logfs 同步（EnableLogFsSyncInRetail=0 ⇒ 打 "BDS: LogFs sync skipped"）
10770 读配置 "DefaultChargerApp" → 10798 AsciiSPrint("fv1:\%a") → 0x1311C 按【路径】LoadImage
107DC 读配置 "DefaultBDSBootApp"
10800 FvName GUID = .data:0x19188 = 046fae99-cf2e-49ed-a6a8-a1488b7e80d3
10810 0x110CC(FvNameGuid, AppName, NULL)  ; = LaunchAppFromGuidedFv  ★ 就这一句启动了 ABL
10814 0xFD70(...)                          ; ← 返回后（见下）
10818 若未配 DefaultBDSBootApp：走标准 BootOrder/Boot####/BootNext 流程 + USB-first
```
→ `xbl` §5.1

**`0xFD70`（本次新发现，很关键）**：
```
FD70  print U:"Press any key to shutdown"
FD88  0x346C(&key,0) ; 内部 0x34D8 用 ConIn + GUID 0x19288(SimpleTextInputEx) → ReadKeyStrokeEx
FD94  if (读键成功) { print U:"Key detected, shutting down"; gRT->ResetSystem(EfiResetShutdown) }
```
⇒ **语义是"默认 app 返回（=失败/退出）后，屏提示按任意键关机，按下就关机"**。
两条用法（→ `xbl` §5.3/§6.4）：
1. 如果我们以 EFI app 形态被 BDS 加载，**我们的 app 绝不能 return**（return 就等于走到"按任意键关机"）。
2. **免费探针**：黑屏后按任意键会关机 ⇒ 说明 BDS 已把 ABL 拉起来且 ABL 返回了（问题在 ABL→我们的 SEC）；按键毫无反应 ⇒ 根本没走到 BDS 返回（问题在 SEC 早期或更前）。

`LaunchAppFromGuidedFv`（`0x110CC`）内部：`LocateHandleBuffer(FV2)` → 逐句柄找 `MEDIA_DEVICE_PATH(4)/MEDIA_PIWGFV(7)` 节点 → `CompareGuid(node->FvName, 046fae99…)` → `CreateFileDevicePath(handle, AppName)` → `LoadImage(BootPolicy=TRUE)` → `StartImage`。
闭环证据：QcomBds 的 `.data:0x19188` 常量与 `abl.img` 里 LZMA guided 段解出的嵌套 FV 的 `FvName` **逐字节相同** → `xbl` §5.1。

**BDS 没有任何按键菜单 / 热键入口**（四条证据，→ `xbl` §5.4）：
1. `BDS Menu` / `Exit BDS Menu` / `MenuHelp` / `Provision RPMB` / `Enter Shell` / `Boot USB First` 这些串**只出现在 `BDS_Menu.cfg`（FFS #79）内部**，102 个可执行模块里一个都没有。
2. `QcomBds.efi` 全文对 `BDS_Menu`（ASCII/UTF-16）与 `BDS_Menu.cfg` 的 FFS GUID `a91d838e-…079e` **均 0 命中**（对比：`DefaultBDSBootApp`@0x13705、`DefaultChargerApp`@0x17BFC、`BootUsbFirstDelayValue`@0x1357E 全都能命中）。
3. 键盘只有两处引用：`SimpleTextInput` 2 处（0xEDF8/0xEFD4，**控制台重建**）、`SimpleTextInputEx` 1 处（0x34D8，**按任意键关机**）。**没有"StartTimer + WaitForEvent → 按键进菜单"的代码。**
4. 没有菜单/Shell 的可执行体：`APPLICATION` 型只有 `QcomChargerApp` 一个；`EnableShell=0x1` 空转。
- **真正会吃按键的是 ABL**，不是 BDS。`bootonce` 类热键入口**不存在**（QcomBds 的 UTF-16 变量表逐条枚举，无 bootonce 语义）。

**BDS 唯一的"等待"是 USB-first 窗口**（`0x1700`）：读 QCOM 变量 `BootUsbFirstDelayValue`（缺省 `0x1E` = 30 秒）→ `LocateHandleBuffer(EFI_USB_IO_PROTOCOL)` → `Stall(200ms)` 循环到窗口结束。因无 HC 生产者，**永远等不到设备** → `xbl` §5.5。

### 3.4 ABL：BootLinux 的完整失败判据

**入口**：`BootLinux` 真入口是 **`0x6a30`**（`stp x29,x30,[sp,#-0x10]!`），`0x6a34` 只是第二条指令（更正旧报告）→ `abl` 头部注。

**通用失败尾 `0x8634`**：先 `bl 0x66ec`，而 `0x66ec` 是 **`CpuDeadLoop()`**（`str xzr,[sp]`/`ldr x8,[sp]`/`cbz x8,自身`）。
⇒ 走到 `0x8634` 的分支表现为**卡死不重启**（后面那条 `return 0x8000000000000013` 不可达）。
同一条尾也接在 `blr` 之后（`0x862c blr x8 → 0x8630 b 0x8634`）：**载荷即使从入口 `ret` 返回，ABL 也是死循环**，不会恢复 fastboot → `abl` §0。

**23 条失败判据（全集，按地址序；→ `abl` §1.3）** —— 摘录决定性的 8 条：

| # | 地址 | 条件 | 打印串 | 返回 |
|---|---|---|---|---|
| 2/3 | `0x6f94`/`0x6fa8` | 取不到 `boot`/`recovery` 镜像，或 size==0 | `BootLinux: Get%aImage failed!` | →19 |
| 8/9 | `0x72e0`/`0x730c` | `header_size`/`ramdisk_size` > 文件大小 | `Wrong size in init boot header!` | →19 |
| **17** | **`0x7fa4` → `0xa520`** | **追加 DTB 不是"恰好一棵"** | **`Not the single appended DTB`** | **`0x800000000000000E`** |
| 18 | `0x7fec` → `0x3b320` | 更新 cmdline 失败（板号/PCBA/国家码） | `Error updating cmdline. Device Error %r` | 其 status |
| **19** | **`0x80d0` → `0xbe10`** | **`LoadRamdisk` 失败** | 见 §3.5 四条 | 2 / 4 |
| **20** | **`0x8144` LocateProtocol** | **kernel-stack protocol 找不到** | `Error getting kernel stack protocol. Error %r` | **→HANG** |
| **22** | **`0x8488` → `0x345d0`** | **memory map / 关 BootServices 准备失败** | `Failed to allocate pages for memory map` + `Can not shutdown UEFI boot services` | **→HANG** |
| 23 | `0x85cc` → `0xca10` | 切 32-bit 模式失败（仅 32 位路径） | `Failed to switch to 32 bit mode` | **→HANG** |

**`0x7fa4 → blr` 主线段（逐条）**：
```
0x7f74  if (strstr(Cmdline,"root=")) g_0xc66c0 = 1;   // 不失败
0x7fa4  bl 0xa520    ← DTB 单树校验                       [17]
0x7fc4  bl 0x5c080
0x7fec  bl 0x3b320   ← cmdline（板号/PCBA/国家码）          [18]
0x80c8  bl 0xbe10    ← LoadRamdisk                         [19]
0x80f0  bl 0x31a20   ← UI/字体（必成功）
0x8144  LocateProtocol(GUID b5062be7-…) 失败 → HANG        [20]
0x82a4  GetVariable(L"KernelSize", GUID 882f8c2b-…)        [21]
0x8488  bl 0x345d0   ← ExitBootServices 准备，失败 → HANG   [22]
0x85b4  if (BootInfo+0xc0 == 0) → 0x8610   // arm64 跳
0x8610  x8 = BootInfo+0x40   ★ 原值，中间没有任何 +offset
0x861c  x0 = BootInfo+0x58   ★ = DTB
0x862c  blr x8
```
**关键点复述**：`+0x80000` 只在 `0x9824` 加过一次（压缩路径），所以"相对解压输出 offset = 0"成立 → `abl` §1.4。

### 3.5 `LoadRamdisk`（`0xbe10`）的 5 段 CopyMem

| 段 | 指令 | dest | src | len | 门控 | 来源 |
|---|---|---|---|---|---|---|
| **A** | `0xc210` | `sp+0xa0`（滚动指针，初值 `bi+0x50`） | `bi+0x20 + bi+0x6c` | `bi+0x94` | `header_version >= 3` | **vendor_boot** 的 vendor_ramdisk |
| **B** | `0xc284` | `sp+0xa0` | `bi+0x30 + bi+0x6c` | `bi+0x98` | `Info+2≠0` **且** `0x89a0()` **且** `bi+0x98≠0` | **recovery** 分区的 ramdisk |
| **C** | `0xc2d0` | `sp+0xa0` | `[sp+0x68] + bi+0x7c` | `bi+0x78` | 恒执行 | `[sp+0x68]` = init_boot（GKI 且 v4）否则 boot/recovery |
| **D** | `0xc508` | `bi+0x40`（紧跟内核） | `bi+0x08 + bi+0x6c` | `bi+0x9c` | `BootInfo+0xc0≠0`（**只有 32 位内核**） | boot 镜像 |
| **E** | `0xc570` | `sp+0xa0` | `bi+0x20 + … + align(0x94)+align(0x88)+align(0x8c)` | `bi+0x90` | `header_version >= 4` | **vendor_boot 的 bootconfig** |

段 E 之后 `0xc5c8`：`AsciiStrnCats(bi+0xb0, …)` —— **把 bootconfig 文本拼进内核 cmdline 缓冲**（不是拼进 ramdisk）。
**最终 initramfs = vendor_ramdisk ‖ recovery_partition_ramdisk ‖ bootconfig**；内核来自 `boot` 分区 → `abl` §2.1、`dual` §1.2。

**失败判据（4 条串 + 返回码）**（→ `abl` §2.2）：

| 地址 | 条件 | 串 | 码 |
|---|---|---|---|
| `0xbea4` | `bi == NULL`（只查第 2 参，**不查 Info**） | `Invalid input parameters` | `0x…02` |
| **`0xbff4`** | **`RamdiskLoadAddr + 总长` 2^64 回绕**；**`RamdiskLoadAddr == 0` 且 total>0 时必然命中（最隐蔽）** | `Error: Ramdisk size is over the limit` | `0x…04` |
| `0xc0d8`→`0xc0f8` | `src + RamdiskOffset` 回绕 | `Integer Overflow: ImageBuffer=%u, RamdiskOffset=%u` | `0x…04` |
| `0xc3f8..0xc410` | 越过 DTB 区顶 | `Integer Overflow: while Kernel image copy` / `Kernel size is over the limit` | 4 / 2 |

### 3.6 「32 位误判」——最隐蔽的一条（无需日志即可分辨）

`0xa270` 拿**解压后**镜像 `+0x38` 的 4 字节与常量 `0x644d5241` 比较，该常量的内存字节序是 **`41 52 4D 64`（ASCII `"ARMd"`，不是 `"ARM64"`）**。
不匹配时：若 `KernelSize > 0x2c` → `0xa368` → `CopyMem(BootInfo+0x84, src+0x2c, 4)` → 落到 `0xa394`（dst==src 自拷贝）→ `0xa3bc` 再判一次仍不匹配 → **置 `BootInfo+0xc0 = 1` 后 `return 0`（放行）**。
⇒ 只要 payload 头 `+0x38` 不是 `41 52 4D 64`，就会**静默地**按 32 位 ABI 跳（`r0=0,r1=0,r2=Dtb`），**完全不产生日志**。64 位 payload 遇到这个会立刻异常，症状与"没跳"极像。
**改 4 个字节即可验证** → `abl` §6.3。

### 3.7 ABL 的槽位记账（重试计数语义）

递减/落盘/打印全在记账例程 `0x276d0`（唯一调用者 `0x1b1ec`），retry 是 slot 元数据 **`+0x34` 字的 bits 19..21**：

```
279d4  ubfx x8,w8,#19,#3   → retry
279c4  ubfx x8,w8,#22,#1   → successful
279b4  ubfx x8,w8,#23,#1   → unbootable
27b2c  and x8,x8,#0xffc7ffffffffffff   ← 清 bits 51..53
27b58  orr x8,x8,x10,lsl #51           ← 把 (旧值-1) 填回   ★ 全镜像唯一递减点
27b70  bl  0x21190                     ← 统一落盘（misc）
27c14  打印 "Active Slot %s is bootable, retry count %ld"（打印递减后的值）
```
递减条件：`unbootable==0` **且** `successful==0` **且** `retry!=0`，另有两个全局 flag 守卫（`0x27adc`/`0x27ae8`/`0x27af8`）。
`SetActiveSlot`（`0x25428`）把 priority 与 tries 一起置满 **7**，并清 unbootable / 条件清 successful。
**递减发生在"决定要启动这个槽"的一刻，早于把控制权交给内核** —— 不是"判定失败之后"才减 → `wdt` §1.1–§1.5。

判据强度（这是本节最有用的产出，→ `wdt` §0/§2.3）：

| 观测（窗口内无人为介入） | 判定 |
|---|---|
| `retry` 减 **≥2** | **EXECUTED**（只有载荷自己造成 SoC 复位才会产生第 2 次尝试） |
| `slot-unbootable:a = yes` 或 `current-slot` 由 a 变 b | **EXECUTED**（只可能由连续 6/7 次自动失败产生） |
| `retry` 减 **1** | **INCONCLUSIVE** —— 我们自己那次 `fastboot reboot` 就会先减 1 |

**前置条件**：`slot-successful:a` 必须为 `no`，否则 ABL **跳过递减**（`0x279e8`/`0x27ac4`）。本机实测 `slot-successful:a=yes` ⇒ 必须先 ARM（`--set-active=a`）再读基线 → `wdt` §1.3/§附录 B。

### 3.8 ABL 的命令面与 critical 白名单

**fastboot 命令 27 条**（静态表 `0xb1e70` 24 项 + 条件追加 3 条；注册器 `0x7bea8`）→ `abl` §3。
其中 `reboot-recovery`(`0x7ffdc`)、`reboot-fastboot`(`0x80070`)、`snapshot-update`(`0x80104`) **只在存在 `super` 分区时注册**（门控 `0x7bbd0 bl 0x8900`，`0x8900`→`0xfd90` 用 `"super"` 查分区）。
**表里没有裸 `oem` / 裸 `flashing`，也没有 `edl` / `reboot-edl`。**

**critical 分区白名单 24 项**（判定函数 `0x8026c`，表在 `0xb2018`，`cmp x21,#0xc0` ⇒ 24 项）→ `abl` §4：

```
abl rpm tz sdi xbl hyp pmic bootloader devinfo partition devcfg ddr frp cdt
cmnlib cmnlib64 keymaster mdtp aop multiimgoem secdata imagefv qupfw uefisecapp
```
命中即：`flash:` 打 `Flashing is not allowed for Critical Partitions`（`0x7c690`）、`erase:` 打 `Erase is not allowed for Critical Partitions`（`0x7dce0`）。

**另一张 3 项表（容易混淆，别当 critical）**：`0xb20d8` = `misc` / `metadata` / `userdata`，由 `0x802d4` 判定，前置条件是 `0x69960()` 的返回值 `(v & 0xfffffffe) == 2`（bootmode ∈ {2,3}）——语义是"某类模式下禁止擦写这三块"，**只在锁态生效** → `abl` §4、`small` §0-C4。

---

## 4. 各镜像职责

### 4.1 启动链镜像

| 镜像 | 大小 | 形态 / 关键字段 | 谁加载 / 谁验 | 职责与风险 |
|---|---|---|---|---|
| `xbl.img` | 3,227,648 B | ELF64 + QCOM MBN，17 phdr | **PBL**，用熔丝根证书 | SBL1 + 完整 UEFI(102 DXE) + 内嵌子 ELF + XBLRamDump。**改一个字节即硬砖**（只剩 9008） |
| `abl.img`/`abl.elf` | 274,432 B | ELF32 ARM 外壳 + 内层 AArch64 `LinuxLoader` PE32+（970,752 B） | XBL 的 UEFI BDS（`DefaultBDSBootApp`） | fastboot 27 条命令、槽位记账、AVB、BootLinux。写坏 = 失去 fastboot/recovery，**只剩 9008**。两版 ZUI 逐字节相同 |
| `boot.img` | 96 MB 分区 | `ANDROID!` **v4**，`kernel_size`（原厂 46,819,840）、`ramdisk_size=0`、`header_size=1584`、**cmdline 全零** | ABL `LoadKernel` `0x9c70` | 只装内核；gzip 支持；入口 = 解压目标 = offset 0 |
| `init_boot.img` | 8,388,608 B | v4，`kernel_size=0`、`ramdisk_size=**2,005,893**` | ABL（GKI 路径 `0x7188` 起） | **GKI 通用 ramdisk，只有 16 条目**：`init`(2,567,024)、`system/bin/snapuserd`、`system/etc/init/snapuserd.rc`、`system/etc/ramdisk/build.prop`(**1,064 B**)、若干空目录。**没有 `/lib`、没有 novatek 固件** |
| `vendor_boot.img` | 96 MB 分区 | `VNDRBOOT` v4：vendor_ramdisk 11,628,676 / dtb 1,290,690 / table 108 / bootconfig 125 | ABL `UpdateBootParamsSizeAndCmdLine` `0x8bb0` | **内核 cmdline 的唯一入口**（`video=vfb:640x400,bpp=32,memsize=3072000 bootconfig`）+ 246 个 GKI 模块 + 6 棵 base FDT + bootconfig |
| `dtbo.img` | 本体 3,500,977 B（分区 24 MB） | `0xD7B7AB1E`，45 棵完整 overlay 树 | ABL 按每棵树自带的 `qcom,msm-id`/`board-id`/`pmic-id` 打分选树 | 屏/触摸/音频/充电/摄像头/splash **全部只在这里** |
| `recovery.img` | 100,663,296 B | v4，`kernel_size=0`、ramdisk ≈14.57 MB | ABL 按 **BCB + 当前活跃槽** 读 | **只装 ramdisk，不装内核**（内核永远来自 `boot`） |
| `vbmeta.img` | 本体 8,192 B（分区 64 KB） | `SHA256_RSA4096`，公钥 sha1 `2597c218…f011`（AOSP testkey_rsa4096），`flags=0`，`rollback_index=0` | ABL 用**内嵌公钥** memcmp 1,032 B | 1 Chain（→`vbmeta_system`, RIL=2）+ 20 Prop + 5 Hash + 4 Hashtree |
| `vbmeta_system.img` | 本体 4,096 B | `SHA256_RSA2048`，公钥 sha1 `cdbb7717…617d`，`release string avbtool 1.3.0`（第三方重签痕迹） | 根 vbmeta 的 chain | 3 条 Hashtree（`system`/`product`/`system_ext`，salt `00…01`，`fec_roots=0`） |

各 `image_size` 与"谁按谁的尺寸算"（→ `bootgrp` §3.3）：
```
vbmeta_a.boot.image_size        = 46,841,856 = 4096 + 46,819,840(原厂 kernel) + 16,384(AVB0 签名区)
vbmeta_a.init_boot.image_size   =  2,011,136 = 4096 + round_up(2,005,893, 4096)
vbmeta_a.vendor_boot.image_size = 12,939,264 = 4096 + ru(11,628,676) + ru(1,290,690) + ru(108) + ru(125)
vbmeta_a.dtbo.image_size        =  3,500,977 = dt_table_header.total_size
vbmeta_system.{product,system,system_ext}.image_size = footer 的 original_image_size
                                   2,909,995,008 / 1,697,497,088 / 1,503,494,144
```

### 4.2 逐分区 hash 复算（本机实测，→ `bootgrp` §3.2）

| 分区 | 声明 digest | 实测 | 结论 |
|---|---|---|---|
| `boot` | `ad970718…` | `89013232fa91fa39bfb722484dec8bf5ce852c550a8fd0bb30e02391ed273990` | **MISMATCH** |
| `dtbo` | `b1858a6b…` | `b1858a6b…ab915a` | MATCH |
| `init_boot` | `ab394ed4…` | `ab394ed4…29ad0c9` | MATCH |
| `vendor_boot` | `a81b4405…` | `a81b4405…0e6ec0e9a` | MATCH |

⇒ **当前机器上只有 `boot` 一个分区破了 boot 链的 AVB**。设备上的 `boot_a`（43,098,112 B）是"仅内核"重打包件（kernel 43,092,480 / ramdisk 0），其后 3,743,744 B 是原厂 boot 的残留字节，而 `vbmeta_a` 按 46,841,856 B 计算哈希。
`verifiedbootstate=orange` 是解锁态的正常取值；boot 这条失配说明 ABL 走的是**"校验失败但放行"**分支（`0x1cdf0`：`State: Unlocked, … continue boot`），不是没校验 → `bootgrp` §0。

**`veritymode=eio` 只跟 hashtree 有关**（与 boot 的 hash 描述符无关）：`vbmeta_a` 有 4 条 hashtree（`odm`/`system_dlkm`/`vendor`/`vendor_dlkm`），`vbmeta_system` 有 3 条（`product`/`system`/`system_ext`）。只要一条 hashtree 的 root 与数据不符，init 就以 eio 模式挂载 → `bootgrp` §3.4。

### 4.3 TEE 链：单体 QSEE（本轮最重要的机制发现之一）

**`cmnlib` / `cmnlib64` / `qwes` 根本不从分区加载，它们被编在 `tz.mbn` 里面。**

`tz.mbn`：3,514,087 B，ELF64 ET_EXEC，入口 `0xc100000`，28 个 phdr、无节头。段布局（→ `tee` §1.3）：

```
0x0C100000..0x10300000   TZ 核心（seg 3..15，含 922,840 B 大代码段）
0x10300000 + 359 B       ★ 清单 blob（seg16）：embed_images 表 @文件偏移 0x205000
0x10301000..0x1036B000   cmnlib      （seg 17,18,19）
0x1036B000..0x103F2000   cmnlib64    （seg 20,21,22）
0x103F2000..0x10455000   qwes        （seg 23..27）
0x10455000               HASH/签名段（文件里在 0x1000）
```
`embed_images = 3`，每项后面都跟一个 `none`（= 无外部来源/无分区名），与 `rawprogram4.xml` 里 `filename=""` 完全对应。
算术校验（`p_assert.py`）：

| 内嵌镜像 | base | 声明 size | 覆盖 phdr | 段 filesz 合计 | 余量 |
|---|---|---|---|---|---|
| `cmnlib` | `0x10301000` | `0x6a000`(434,176) | 17,18,19 | 430,552 | 3,624 |
| `cmnlib64` | `0x1036b000` | `0x87000`(552,960) | 20,21,22 | 546,640 | 6,320 |
| `qwes` | `0x103f2000` | `0x63000`(405,504) | 23..27 | 392,180 | 13,324 |

`0x103f2000 + 0x63000 = 0x10455000` **正好等于 HASH 段的 vaddr** —— 三个镜像首尾相接填满，无缝隙。
**不是"清单指向别处"，是"清单描述自己"。**

**五条独立证据说明"cmnlib 全零是正常态"**（→ `tee` §2.2、`small` §6.1）：
1. 镜像自己带着（上表）。
2. **分区尺寸装不下**：`cmnlib64_a` 只有 128×4096 = **524,288 B**，而内嵌的 cmnlib64 段合计 **546,640 B**（含对齐 552,960）⇒ **物理上不可能承载**。
3. 出厂就没人写它：`rawprogram4.xml` 与 `partition.xml` 里 `filename=""`，GPT attr 带 `bit60 read-only`，ZUI16/17 两版镜像集里都**没有** `cmnlib*.mbn`。
4. 运行时 TZ 是活的：`QSEECOM: qseecom_init_control: qsee_version = 0x1402000`、FBE 已解锁、`IKeyMintDevice/default` 在服务、`/data/misc/keystore/persistent.sqlite` 有 73 个 key。
5. 依赖方向是"TA 依赖 TZ 内嵌库"：`keymint.mbn` 有 `DT_NEEDED libcmnlib.so` 与 15 个 `qsee_*` import；TA 是动态链接的，`libcmnlib.so` 只能由 TZ 提供。

**签名分层**（→ `tee` §1.2）：`tz.mbn` 是 **Qualcomm 签的**（`QSEE Attestation Root CA 2` / `CASS - SBL3`，有效期 `240111183759Z`–`260111183759Z`）；`keymint.mbn` 与 `hyp.mbn` 是 **Lenovo Elm 链**（`Elm Attestation CA` → `Elm Root CA`）。签名由 **XBL 的 PIL** 校验，不是 AVB、不是 dm-verity。

**AVB 完全不覆盖 TZ 链**：`vbmeta.img`（8,192 B）的 13 个分区名与 `vbmeta_system.img`（4,096 B）的 3 个里，`tz`/`hyp`/`keymaster`/`keymint`/`cmnlib` 出现 **0 次**；`tz.mbn` 里 `avb`/`vbmeta`/`dm-verity`/`verity` 也是 **0 次** ⇒ 改 system、重签 vbmeta 与 TEE 无交集 → `tee` §4.1。

### 4.4 `dtbo`：45 棵完整板级 overlay（不是"几片小补丁"）

表头：`total_size=3,500,977`、`dt_entry_count=**45**`、`dt_entry_size=32`、`page_size=4096`、`version=0`。
**45 条的 `id`/`rev`/`custom` 全为 0** —— 选树不靠这两个字段，而靠**每棵树自带的** `qcom,msm-id`/`qcom,board-id`/`qcom,pmic-id` 打分。
本机 SoC = khaje（`msm-id 518`）、board = IDP-nopmi（`65570`）⇒ 生效 **entry 2「KHAJE IDP nopmi」**（182,701 B，315 nodes，115 fixups）。
真机 `ro.boot.dtbo_idx=2`、`ro.boot.dtb_idx=0` 是**引导器写回**的选择结果 → `bootgrp` §4.1/§4.2。

45 棵分组：entry 0–15 = khaje 各板型（ATP/IDP/IDPS/QRD…）、**16–25 = khajeg 全套（msm-id 585）**、**26–34 = khajep（561）**、**35–44 = khajeq（562）**。

**panel / touch 全部只在 dtbo 里**，`vendor_boot` 的 6 棵 base DTB 里 `p255_*` / `hx83102` / `himax,hxcommon` 出现次数**全为 0**。
base DTB 只有 SoC 侧的 `qcom,mdss_mdp`/`dsi_ctrl0`/`dsi_phy0`/`pinctrl`/`thermal` → `bootgrp` §0-5、§4.4。

三个 panel 变体（都在 `/fragment@35/__overlay__/qcom,mdss_mdp/`）：

| 节点 | phandle | panel-name | hfp/hbp/hpw | vfp/vbp/vpw | 绑定 |
|---|---|---|---|---|---|
| `…panel_p255_hx83102j_fhd_video` | **0x35** | `hx83102j video mode dsi boe panel` | 185/40/20 | 118/12/8 | **默认（`qcom,dsi-default-panel = <0x35>`）** |
| `…panel_p255_inx_fhd_video` | 0x36 | `nt36523n … inx panel` | 96/96/4 | 56/248/2 | 备选 |
| `…panel_p255_csot_fhd_video` | 0x37 | `nt36523n … csot panel` | 100/100/4 | 30/134/2 | 备选 |

三者共同：`dsi_video_mode`、`orientation="180"`、`bl-max-level=0xFFF`、`bl-min-level=13`、`status-check-mode=reg_read`（读 `0x0A` 期望 `0x9C`/`0x9D`）。
触摸 `touch@0`：`spi-max-frequency=0x989680`(10 MHz)、`himax,display-coords = <0 0x2EE0 0 0x4B00>`（= 1200×1920 ×10）、`novatek-mp-criteria-6072@0`（646 行自检门限表）。

**`__symbols__` 账本（决定"能不能自建 DTB"）**：base DTB 有 **829** 条 `__symbols__`；45 棵 overlay 合计只用到 **143** 条不同符号，全部能在 base 解析（**0 缺失**），单棵 `__fixups__` 41–129 条（entry 2 = 115）。
⇒ 自建 vendor_boot 的 DTB 必须**原样保留这 143 个符号名**，否则 `ufdt_apply_overlay` 解析 `__fixups__` 失败 → fragment 被丢或整体报错 → "overlay 里明明有 panel，起来却没屏" → `bootgrp` §4.5。

### 4.5 `super` 与逻辑分区（**报告进行中**）

本机 `super` = **12 GiB**（3,145,728 扇区 × 4096 = 12,884,901,888 B），LP 组各 12,876,513,280 B；
LP 元数据 magic 在 **`0x3000`**（不是 `0x2000`）。
逻辑分区 `system_a`/`system_ext_a`/`product_a`/`vendor_a`/`vendor_dlkm_a`/`system_dlkm_a`/`odm_a` 有数据；
**7 个 `*_b` extents = 0** ⇒ b 槽**永远不可能跑第二套 Android** → `ofrec` §0.1/§3.2、`dual` §7。

> `work\img-super\` 与 `work\img-firmware\` 两个目录本轮**只有脚本与 `raw\` 素材，`REPORT.md` 尚未生成**（进行中）。
> 上述数值来自 `ofrec`/`small`/`9008` 的交叉引用，待那两份报告出来后应以其为准复核。

### 4.6 其它小分区（→ `small` §2.2）

| 分区 | 大小 | 用途 | ABL 策略 |
|---|---|---|---|
| `oemowninfo` | 1 MiB | 出厂身份（sn/psn/skuid/btmac/wifimac…33 字段） | **—**（唯一不受锁定/critical 保护的持久写入口：`fastboot oem oemowninfo set`） |
| `keystore` | 512 KiB | QSEE/Widevine keybox | — |
| `lenovolock` | 512 KiB | 联想自己的锁定/工厂标记区（**不是** ABL 的解锁位） | —（ABL 里无此名） |
| `frp` / `cdt` / `secdata` | 512 KiB / 128 KiB / 28 KiB | FRP / 平台配置 / 安全数据 | **C** |
| `splash` | 32.64 MiB | 开机 logo（显示缓冲在 `0x5C000000+0xF00000`，由 **XBL** 的显示线程初始化） | — |
| `spunvm` | 8 MiB | Secure-Processor uNVM | — |
| `logfs` | 8 MiB | ABL 日志（**实测为 FAT12 空文件系统**，`Active Slot`/`retry count`/`BootLinux` 全 0 命中） | — |
| `catefv`/`catecontentfv`/`cateloader` | 512 KiB / 1 MiB / 2 MiB | Qualcomm 工厂测试环境 CATE | — |

> 黑屏/logo 问题**优先怀疑 XBL，不是 ABL**：ABL 有串 `Splash region not found in device tree, powering down the display and controller` → `small` §2.2 注。

---

## 5. 三条目标线：现状与阻塞

### 5.1 目标线一 · 刷机包（A17 / HyperOS 4）

**现状：v4 已出包并通过全部六项验收**（→ `v4` §0/§4）：

| 项 | 值 |
|---|---|
| v4 目录 | 66 文件 / 6,547,715,606 B |
| v4 zip | 3,046,558,012 B，sha256 `8d1cc81d36576eb0addd777b184044cda2624033a87c57907cea396592c24a77` |
| 验收 | `7z t` Everything is Ok；镜像 **6/6** 一致；整包清单 **39/39** 一致；6 个 bat `6/6 clean`；tools 可跑；`selftest.bat` `FAIL:0 WARN:0` |
| v3 状态 | 目录与 zip **一行未动**，可回退 |

**A17 起不来的根因已闭合（2026-11-13）**：`work\tools\verify_hashtree.py` 独立实现 dm-verity 根哈希（block 4096 / sha256 / salt 前缀）——

| 镜像 | 重算 root | 声明 root | 结论 |
|---|---|---|---|
| `system_G.img`（对照，机器挂载成功） | `cc180c18…` | `cc180c18…` | ✅ 算法正确 |
| `product_D.img` | `0bcedeb0…` | `832596f2…` | ❌ **镜像自身不自洽** |

⇒ dm-verity 对 product 必然失败（`dm-13: data block 0 is corrupted`）→ init 读不到 superblock → `Attempted to kill init!` → panic → 900E。
与刷新方式/分区尺寸/sparse/`vbmeta_a` **全部无关**。历史谜团的解释：`vbmeta_system_E/G2/H/J` 声明的 product root 全是 `832596f2…`（对应**旧版** product 数据），10-26 那次成功只刷了 `system_G` + `H`、**没重刷 product**。
修复配方（已验证可复现启动）：`head -c 2909995008` 取数据段 → `avbtool add_hashtree_footer`（**必须显式 `--do_not_generate_fec`**，本机没有 fec 二进制）→ `make_vbmeta_image`（`--algorithm SHA256_RSA2048 --key testkey_rsa2048.pem --padding_size 4096`）→ fastbootd 重建 `product_a` 并刷三件。

**当前阻塞**：`v4` §6 诚实标注的**真机四项未验**——`fastboot getvar` 真实回显格式、fastbootd 实刷三张逻辑分区、`fastboot -w`、9008 的 `fh_loader` 写入分支；900E 判定只验证过"无 900E"一侧。
**包完整 ≠ 刷机链在真机走通。**

**另一个必须先认清的事实（→ `zuidiff` §5.4/§5.5）**：本机固件基线是 **ZUI16.0.544**（49 个可比槽位里 **37 个精确等于 ZUI16**），
`vbmeta_a` 确实是原厂，但 **`vbmeta_system_a` 不是**（是 A17/hashtree 实验留下的重签版 `cea948ea…`），且 **`boot_a`/`boot_b` 都不是任何一版原厂**（两者哈希相同 `667e1723…`，成对写入的补丁/实验镜像）。
`work\docs\STATE.md` 里"a 槽已由 9008 全量恢复为 544 原厂（含 vbmeta_system_a 原厂）"**与实测不符** → 见 `CORRECTIONS.md` C-36。

**B 槽是坑**（→ `zuidiff` §5.5）：`init_boot_b`/`vendor_boot_b`/`recovery_b` 是 **ZUI17 内容**，与 `vbmeta_b`（= ZUI16 原厂）里记录的摘要**对不上** ⇒ 一旦 `set_active=b`，ABL 对这三个分区的 AVB 校验会失败，b 槽的 recovery / vendor_boot 不可用，甚至可能判 slot 不可启动。
最可能的成因：那次 9008 全量回刷在 b 槽 boot 链末尾中断（`init_boot_b → recovery_b → vendor_boot_b` 恰好是 `rawprogram4.xml` 里 b 槽 24 个 A/B 分区的**最后三个**）。

### 5.2 目标线二 · 第三方 recovery（TWRP / OrangeFox）

**编译已解决，设备侧是闸门。**

三条路线（→ `ofrec` §0.3/§1）：

| 路线 | 一句话 | 磁盘 | 首次构建 | 本机可验证性 |
|---|---|---|---|---|
| ③ 纯 ramdisk 拼装（不编译） | 拿现成 donor ramdisk 修 fstab/模块/rc 后与原厂 `vendor_boot` 拼接 | **< 1 GB** | **30 s** | **可离线 82 项验收**（`verify_v3.py`） |
| ② OrangeFox `fox_12.1` | `repo init` OF manifest，编 `fox_TB331FC` | ≥ 110 GB | 2–4 h | 只能验头/大小 |
| ① TWRP minimal manifest | `repo init` `minimal-manifest-twrp/… -b twrp-12.1` | ≥ 90 GB | 2–4 h | 同上 |

**闸门**：本机历史上**已经编译出过可发布的 TWRP/OrangeFox 镜像**（`yxyyds666/TB331FC-TWRP`、`dsshhgg/TB331FC-TWRP` 的 `fox-12.1`），但**设备进不去**——刷入后一律回 `fastboot`（`18D1:D00D`），黑屏无 adb。
已逐一证伪的"解释/修法"（→ `ofrec` §0.2）：
- 对齐 stock 头（空 cmdline、`kernel_size=0`、`os_version=99.0.0`）→ 仍回 fastboot（**头不是阻断点**）
- `avbtool --flags 3` 的 testkey vbmeta（关 AVB）→ 仍回 fastboot
- `flags=0` + 全哈希重算、改 1 bit 配哈希、footer `alg=NONE` 自洽 → 均失败
- 把 OF 塞进 `boot` 分区（含"头部一字不差"的 96 MiB 版 + 匹配 vbmeta）→ 失败
- 9008 降级 ZUI15 `abl`（写入成功、回读一致）→ 第三方 rec 仍被拦

**当前判定**：`recovery` 分区这条路上，**ABL 有一层独立于 AVB 的 recovery 校验/白名单**（自 2026-10-18 未变）。
**注意**：ABL 两版 ZUI **逐字节相同**（→ `zuidiff` §4.2）⇒ 换成 ZUI17 的 abl 不会有任何区别。

**唯一还没被判死的通道 —— BCB + ramdisk-only 形态（本轮最重要的可执行新发现）**（→ `dual` §0/§1.4、`dual` FLASH-PLAN §3）：

| 镜像 | header | kernel_size | ramdisk_size |
|---|---|---|---|
| 原厂 `recovery.img`（ZUI16） | v4 | **0** | 14,572,954 |
| `zui17_images\recovery.img` | v4 | **0** | 14,581,386 |
| `of\v3\recovery_of_tb331fc_v3.img`（MODE=1 存档） | v4 | 43,092,480 | 47,627,143 |

本机 ABL 的 recovery 语义是「**内核永远来自 `boot`，`recovery` 只提供 ramdisk**」。
历史上往 `recovery_a/b` 刷的是 **TWRP/OF 的完整 boot 镜像**（`kernel≠0`）——**那是另一种形态**，ABL 的分派/拼装路径完全不同。
⇒ **"OF 进不去"的历史结论，并不能推出"recovery 分区这条路死了"，因为从没按本机要求的形态（`kernel_size=0`、只有 ramdisk）试过。**

**BCB 是活代码**（四跳全部有指令地址，→ `dual` §1.1/§1.2）：
```
GetBootCommand 0x6a710（misc GUID 82acc91f-357c-4a68-9c8f-689e1b1a23a1，强制 cmd[31]=0，
                        strncmp "boot-recovery"/"boot-fastboot"）→ 全局 flag 0xea83c
  → 0x98100 唯一调用点 → 0x97b80 BootInfo+0x2 = flag → 0x1afd4 分派
  → 0x1b248 ldrb [x19,#2] / cbz → 非 0 打 "Booting into Recovery Mode via Boot"(0xa321a)
  → LoadRamdisk 0xbe10 段 B：把 recovery 分区的 ramdisk 插到 vendor_ramdisk 之后
最终 initramfs = vendor_ramdisk ‖ recovery_partition_ramdisk ‖ bootconfig
内核           = boot 分区
```
`SetBootCommand 0x6a300` 尾巴是 `AsciiStrnCpyS(dst, DestMax=32, …)`。
`0x9749c` = `return (BCB flag == 0)` 的布尔门（交叉印证：`wdt` §1.3 里重试计数递减条件含 `0x27af8 bl 0x9749c; cbz` ⇒ "进 recovery 这一次不算启动失败"）。

**ABL 用哪个槽的 recovery**：**当前活跃槽**（`recovery_a` / `recovery_b`），**不是固定 a**。
证据：名字表 `0xafdf0` 起 6 项全是**无后缀基名**（`boot`/`dtbo`/`vbmeta`/**`recovery`**/`vendor_boot`/`init_boot`），槽后缀 `_a`/`_b` 在 `0xafe20` 起 UTF-16 内联 6 份；槽本身由 **UFS boot LUN** 决定，首启默认 `_a`。
⇒ 刷 `recovery_b` 后 `reboot-recovery` **预期仍是原厂 recovery**。要验证 OF 的 ramdisk 必须写 `recovery_a`（或先 `--set-active=b`）→ `dual` FLASH-PLAN §3、`abl` §2.4。
**反证条件**：若刷 `recovery_b` 后进了 OF，则"当前槽"结论被推翻（那是零风险的证伪实验）。

**实测过的 adbd 行为（重要，与常见前提不同）**（→ `dual` FLASH-PLAN §1.1）：原厂 recovery 里非 root adbd **被 SELinux 挡在 `/dev/block` 外**（`adb pull /dev/block/by-name/recovery_b` → `Permission denied`；`adb shell id` → `shell_service.cpp:380 Could not set SELinux context`）；`adb root` 之后 `uid=0(root) … context=u:r:ksu:s0` 可用（**KSU 在 recovery 启动路径下同样生效**），但它的 adbd 很脆，一次 spawn 失败就把 USB gadget 一起带走。

### 5.3 目标线三 · Linux 与 Windows on ARM

**已有成果**：
- mainline **6.14** 内核已编出可刷件（`work\linux-build\out\Image-6.14.0-rc5-tb331fc` 37.155 MB、`Image.gz` 13.43 MB、`boot-v3-linux.img` 13.438 MB、`sm6225-lenovo-tb331fc.dtb`）→ `clean` §1
- GKI 5.15 线：`arch/arm64/boot/Image` 38,959,616 B，`CONFIG_KSU=y` + `MODULES=y` + `MODVERSIONS=y` → `ofkern` §2.1
- 2026-10-24 用 `boot_b` 纯内核 + `vendor_boot_b` + `init_boot_b`(512 B 空 cpio) 起到 **Linux root shell** → `dual` §3.2

**WoA 线的现状与阻塞**：
1. **Mu UEFI 已被 ABL 执行，但随后卡死**：`fastboot continue` 后设备离开 fastboot，屏幕停在 logo、USB 静默、且**永不复位** → 仓库 README §"现在卡在哪"。
   按判据（`wdt` §0）这只是"发生了一次启动尝试"，**不能判执行**（`retry` 减 1 = INCONCLUSIVE）。
2. **两条主要假设均已被证伪**（详见 §6）：
   - 「SEC 栈 `0x5FF90000+0x40000` 踩了 XBL 活跃栈」→ 那块地**就是原厂自己声明的 UEFI Stack**（`secmem` §2）。
   - 「FD 基址 `0x5FC00000` 覆盖致命」→ 同 SoC 的 tapas/tb128fu 都这么覆盖且能开机（`secmem` 理由 C）。
3. **硬件级三条锁死**（§1.3）：无 ACPI、无 USB 主机协议、EL2 被 hyp 占。
   `tee` §4.2 的分层结论：换 ABL ❌（PIL 签名 + GPT 只读）· 9008 强写 ❌（XBL 拒载，无私钥）· 拿 EL2 ❌（hyp 已占，关它要改 XBL ⇒ 闭环锁死）。
   **建议把目标降级为"EL1 下自编内核/DTB/镜像"，别把 EL2 写进验收。**
4. **可复用的横向成果（这是最有价值的发现之一）**（→ `rl` §0/§2.1）：
   `xVanTuring/uefi-tb128fu`（**TB128FU = 小新 Pad 2022 = SM6225 / khaje / bengal，soc_id 518**）已在真机把 Mu UEFI 跑到 **iPadOS 桌面 + 触摸 + Adreno 610 内核驱动**，四个关键地址里**三个与我们现值逐字节相同**：

   | 项 | TB128FU（同 SoC，已上机） | tapas/topaz（同 SoC，小米） | 我们现值 |
   |---|---|---|---|
   | Display / cont_splash | `0x5C000000` + `0xF00000` | `0x5C000000` + `0x1000000` | `0x5C000000`+`0xF00000` ✅ |
   | UEFI FD | `0x5FC00000` + `0x300000` | 同 | 同 ✅ |
   | UEFI Stack | `0x5FF90000` + `0x40000` | 同 | 同 ✅ |
   | DXE Heap | `0x5D000000` + `0x2800000` | `0x63900000` + `0x4500000` | 正改到 tapas 值 |

   它的 `PORTING.md` 把"**为什么没有 vendor 驱动可抽**"写死成结论，这段话对 TB331FC **逐字成立** ⇒ **Mu-only（无 vendor DXE）是唯一可行路线，不是妥协**。
5. **公开情报面**（→ `rca` §一）：酷安上**没有任何人在这台机器上跑起过 UEFI 或 Windows 的证据**（`TB331FC UEFI` / `khaje` 等关键词 0 命中）；第三方 recovery 也没有人为 TB331FC 做出来。但有主线 Linux 的口风（weiPluto 2026-10-22「小新pad2024，主线有戏」）。
   评论区是硬缺口（`/v6/feed/replyList` 全部 403、`/v6/feed/reply` 401），**需登录，未尝试绕过**。
6. **`research-gh-20261124\REPORT.md` 尚未生成**（目录里只有 `MANIFEST-downloads.tsv` 与抓取树），本节的 GitHub 横向量化结论**待补**。

**下一手（按 `secmem` §3 的排序）**：先把"哪一段死了"变成 framebuffer 上的 2–3 个哨兵色（`BootShim.S` 里加 6 条 `movz/movk`，不依赖栈、不依赖缓存刷新：`_Start` 第一条指令前一个颜色、`br x5` 之前换一种），**在把"哪一段死了"变成两三个像素之前，不要再改地址。**

---

## 6. 已证伪清单

> 详细"旧说法 → 现证据 → 正确结论"三段式见 [`CORRECTIONS.md`](CORRECTIONS.md)。此处只列一句话结论。

| # | 已证伪的假设 | 一句话 |
|---|---|---|
| F1 | 改 XBL 需要 OEM 解密 key | **没有加密层**；唯一高熵带是 gzip，无需 key（`xbl` §1.2） |
| F2 | ZeroVector 是 `4c 33 00 14` 魔数 ⇒ FV 校验和不成立 | 那是标准 AArch64 `b +0xCD30`，**逐位等于** SEC 入口；校验和 `0x9857` 成立（`xbl` §0.3） |
| F3 | `SecBootEnableFlag=0x1` ⇒ 安全启动使能 | 那是**注释行**；真值 `SecurityFlag=0xC4`，bit0 = 0（`xbl` §0.3） |
| F4 | 插 U 盘让 BDS 引导是可用备选 | **无 HC 协议生产者**，BDS 的 30 s 窗口永远等不到设备（`xbl` §4.1/§5.5） |
| F5 | BDS 有按键菜单/热键 | 菜单串只在数据文件里，`QcomBds` 对 `BDS_Menu`/其 GUID **0 命中**；`EnableShell=0x1` 空转（`xbl` §5.4） |
| F6 | 改 `DefaultBDSBootApp` 可以换启动目标 | 它在签名固件里的 cfg 里，且解析不到 FAT 上的 `.efi`（`xbl` §5.2） |
| F7 | `BootLinux` 入口是 `0x6a34` | 真入口 **`0x6a30`**；`0x6a34` 只是第二条指令（`abl` 头部注） |
| F8 | 走到 `0x8634` 会"返回错误码" | 它先 `bl 0x66ec` = **`CpuDeadLoop`** ⇒ **卡死不重启**，返回码不可达（`abl` §0） |
| F9 | 载荷从入口 `ret` 返回后 ABL 会恢复 fastboot | 同一条尾也接在 `blr` 之后 ⇒ **死循环**（`abl` §0） |
| F10 | 「ABL 用 `recovery_a`」 | 用**当前活跃槽**；名字表是无后缀基名 + 运行时套 `_a`/`_b`（`dual` FLASH-PLAN §3） |
| F11 | 「recovery 分区这条路死了」（因为 OF 进不去） | 历史上刷的是**带内核的完整镜像**，形态就不对；本机要求 `kernel_size=0` 的 ramdisk-only 形态，**从没按这个形态试过**（`dual` §1.4） |
| F12 | 「开机时按键选 Android / recovery」 | ABL **无按键→菜单逻辑**，也**不支持 `bootonce-*`**（镜像里 0 命中）（`dual` §7） |
| F13 | 「用 `bootctl` 在 Android 侧切槽」 | 原厂 system 镜像里**根本没有 `/bin/bootctl`**（debugfs 已证）（`dual` §1.5） |
| F14 | b 槽可以跑第二套 Android | `super` 里 **7 个 `*_b` extents = 0**（`ofrec` §3.2、`dual` §7） |
| F15 | 「`misc` 在 critical 白名单里，所以 `fastboot erase misc` 被拦」 | `misc` 只在**锁态表**（3 项）里，本机已解锁 ⇒ **会被允许**。不用的真正理由是一次抹 1 MiB 会毁掉 `misc+0x8000` 的厂商状态（`small` §0-C4） |
| F16 | 「槽元数据在 `misc+2048`（AOSP `bootloader_control`）」 | `misc+2048` 起至 `misc+32768` **全零**，无 `BLLT` magic ⇒ 本机 `misc` 里**没有** AOSP 槽元数据（`small` §0-C2/§3.4） |
| F17 | 「`devinfo` 的 `is_unlocked` 在 `0x10`」 | 在 **`+0x0D`**；`+0x0E` = is_unlock_critical；**`+0x90` 是 verity_mode**（`small` §0-C3/§4.2） |
| F18 | 「读出 `devinfo+0x0D=0` 却已解锁」是矛盾 | 解锁权威**不在 devinfo**（`0x13230` 是 `LocateProtocol` 问固件/安全侧 + TZ `qsee_get_secure_state`）（`small` §4.3） |
| F19 | 「`cmnlib` 全零是故障，要修」 | 单体 QSEE：cmnlib/cmnlib64/qwes **内嵌在 `tz.mbn`**；`cmnlib64_a` 槽 524,288 B **装不下** 546,640 B ⇒ 物理上不可能承载（`tee` §1.4/§2.2） |
| F20 | 「`Failure in cmnlib_init()` 说明 TZ 载入 cmnlib 失败」 | 字符串存在只说明代码路径存在；该路径走内嵌镜像、不读分区（`tee` §2.4） |
| F21 | 「900E = 另一个 EDL，可以用 QFIL 修」 | 900E 是 Sahara **MEMORY_DEBUG**，**只能读、不能写**；QFIL/fh_loader/QSaharaServer 全超时是**预期行为**（`900e` §0/§5） |
| F22 | 「进了 900E 只能等/换板」 | 唯一软件出口是 Sahara **`RESET_REQ(0x07)`** ⇒ 落到 fastboot（`900e` §0-3） |
| F23 | 「900E 需要设备先"挂死"」 | 900E 需要 **panic/异常 → dload dump**；死循环只会"安静地卡住"（`9008` §4.1） |
| F24 | 「`fastboot oem edl` 存在，或 `adb reboot edl` 不通」 | ABL **没有注册 EDL**（`edl`/`dload` 串 0 命中）；但 `adb reboot edl` **成功过**（2026-10-25 实测，2 s 后枚举 9008）（`9008` §1.3/§1.5） |
| F25 | firehose 能用 `peek`/`poke` 读内存 | 分派表**无这两个标签**；且 `Peek is disabled on secure boot devices` ⇒ **双重不可用**（`9008` §2.2/§4.1） |
| F26 | 最小 XML 需要 `label`/`size_in_KB` 等属性 | 设备**只解析 5 个属性**；`label` **不参与寻址**，写错会静默写到别处（`9008` §3.2/§3.4） |
| F27 | 「刷官方包能修 persist」 | `rawprogram0.xml` 里 persist 那行 **`filename=""`** ⇒ 官方 9008 全量刷机**从不写它**（`small` §6.2） |
| F28 | 「SEC 栈 `0x5FF90000+0x40000` 踩了 XBL 活跃栈」 | 那就是**原厂 khaje SEC 自己写死的 UEFI Stack**（字面量 @VA `0x5FC0CE48`）；cfg `:26` 同名同址同长；左邻 CPU Vectors/MMU PageTables、右邻 Log Buffer/Info Blk 全是 UEFI 自有数据，SEC 清的 256 KB 与这条逐字节相等且两侧都没碰到（`secmem` §2 理由 A） |
| F29 | 「FD 基址 `0x5FC00000` 覆盖 XBL 驻留 UEFI 是致命操作」 | tapas/tb128fu **都这么覆盖 3 MB**（原厂 FV 只有 `0x220400`）且能开机 ⇒ 无法区分能开机与不能开机的设备（`secmem` 理由 C） |
| F30 | `init_boot` 的 `2,011,136` ≠ vbmeta 声明 ⇒ AVB 已破 | `2,011,136 = 4096 + round_up(2,005,893, 4096)`，是**镜像大小**语义；实测 `ab394ed4…` **MATCH**（`bootgrp` §0-1/§1.2） |
| F31 | 设备 `boot_a` 是原厂 ZUI16 544 内核 | 是**重打包件**（kernel 43,092,480 / ramdisk 0，尾部 3.7 MB 原厂残留）⇒ 真正的 AVB 破点是它（`bootgrp` §0-2/§1.2） |
| F32 | 「ABL 需要 120 条 DT 符号」 | base DTB 有 **829** 条 `__symbols__`；45 棵 overlay 合计用到 **143** 条（单棵 fixups 41–129）（`bootgrp` §0-7/§4.5） |
| F33 | 修补 `init_boot` 必须保留 `novatek_ts_fw.bin`(196,608 B) 与 `build.prop`(1,302 B) | 原厂 544 的 init_boot ramdisk **只有 16 条目**（`build.prop` 是 **1,064 B**），**没有 `lib/`、没有 novatek 固件**（`bootgrp` §1.2） |
| F34 | 「整机更像 ZUI17（因为机上 recovery 是 14,581,386）」 | 那读的是 **`recovery_b`**；`recovery_a` = 14,572,954 = **ZUI16**。37/49 槽位 = ZUI16，只有 3 个 = ZUI17，全在 **b 槽**（`zuidiff` §0/§5.2） |
| F35 | 「a 槽已由 9008 全量恢复为 544 原厂（含 vbmeta_system_a / boot）」 | `vbmeta_a` 是原厂，但 **`vbmeta_system_a` 两版都不是**（重签版），**`boot_a`/`boot_b` 两版都不是**（`zuidiff` §5.4） |
| F36 | 换 ZUI17 的 `abl` 可能改变白名单行为 | 两版 `abl.elf`/`abl.img` **逐字节相同** ⇒ 不会有任何区别（`zuidiff` §4.2） |
| F37 | 「槽重试计数减 1 = 载荷执行了」 | 减 1 = **INCONCLUSIVE**（我们自己那次 `reboot` 就先减 1）；判执行要减 **≥2** 或终态转移（`wdt` §0/§2.3） |
| F38 | 「`logfs` 里有 ABL 运行日志可读」 | 实测 `logfs.bin` 是 **FAT12 空文件系统**，`Active Slot`/`retry count`/`BootLinux` 全 0 命中（`wdt` §3.C） |
| F39 | 「载荷可以自己写 misc 留一个'我来过'标记」 | 载荷是被 `blr x8` 跳进去的 Linux Image，**不是 EFI app**，到那时已无 Boot Services ⇒ 没有块设备句柄（`wdt` §3.B） |
| F40 | 改 `super` 逻辑分区会影响 TEE | AVB 与 `tz.mbn` **双向 0 命中** ⇒ TEE 完全不参与（`tee` §4.1） |
| F41 | 「解锁会弄坏 TEE」 | 不会。KeyMint 密钥在 RPMB，锁状态只影响 attestation 字段（73 个 key 是活证据）；真正会弄坏的是重 provision UFS / 擦整盘（`tee` §4.3） |
| F42 | 「A17 结构性不可行」 | **已撤回**：实测起到过桌面（`release=17`/`sdk=37`/`boot_completed=1`/29/29 传感器）；起不来的直接原因是 product hashtree 不自洽（`v4` §5.1、`900e` §4.4） |
| F43 | 「`v3 目录是 37 文件`」 | 实测 **65 文件 / 6,547,633,424 B**（`v4` §5-1） |

---

## 7. 待验证清单

> 每条都给"具体到命令/实验"的验证方法。**只读项优先。**

### 7.1 零风险 / 只读（一次 adb 或一次 9008 只读就能定）

| # | 问题 | 验证方法 | 判据 |
|---|---|---|---|
| O1 | 是否真的"读全局不读分区"（devinfo） | `fastboot oem device-info` | 打 `Device unlocked: yes` 而 `devinfo+0x0D` 字节是 0 ⇒ 成立（`small` §4.3） |
| O2 | `has-slot:recovery` 是 yes/no | `fastboot getvar has-slot:recovery` | 决定用 `recovery_a` 还是 `_b`（`dual` FLASH-PLAN §9-1） |
| O3 | `partition-size:recovery_a/b` 真实值 | `fastboot getvar partition-size:recovery_a` | 按原厂镜像推 96 MiB（100,663,296 B）（同上 §9-2） |
| O4 | `ro.boot.dtbo_idx` 是否仍为 2 | `adb shell getprop ro.boot.dtbo_idx` | = 2 ⇒ 生效 entry 2「KHAJE IDP nopmi」（`bootgrp` §7-2） |
| O5 | 真正在跑的是哪颗触摸 | `adb shell su -c "dmesg \| grep -iE 'hxchipset\|nt36\|synaptics'"` | himax 线活 ⇒ BOE 屏 TDDI `touch@0`（`bootgrp` §4.4） |
| O6 | `splash` 是否真全零 | `adb shell su -c 'dd if=/dev/block/by-name/splash bs=4096 count=8 \| od -A x -t x1z'` | 有内容 + 有 logo ⇒ 未被清（`small` §7-4） |
| O7 | 900E 为何走 memory-dump 而非 EDL | `python E:\rom\work\tools\auto_900e.py --regions MD_RST_STAT.BIN,MD_PMIC_PON.BIN,MD_PMON_HIS.BIN,MD_SMEMINFO.BIN,MD_SMEM_VER.BIN` | panic 型 ⇒ `MD_RST_STAT` 给 warm reset + WDT/panic 标志（`900e` §2.4） |
| O8 | 内核态 oops 的符号化栈 | 同上 `--regions md_KELF_HDR.BIN,md_KCNTXT.BIN` | 把 PC 变成函数名（10-18 那次 `synchronous external abort` 目前只有一行字）（`900e` §8-2） |
| O9 | TZ / hyp 真实状态 | `adb shell su -c "dmesg \| grep -iE 'QSEECOM\|qsee_version\|kvm\|HYP mode\|hyp_region'"` | 期望 `qsee_version=0x1402000` + `HYP mode not available` + `hyp_region 6144 KiB nomap`（`tee` §6 ①–③） |
| O10 | `cmnlib` 仍是全零 | `adb shell su -c 'dd if=/dev/block/by-name/cmnlib_a bs=4096 count=128 \| md5sum'` | 期望 `59071590099d21dd439896592338bf95`（`tee` §6-⑤） |
| O11 | `peek`/`poke` 是没编进去还是别处有表 | 9008 下发一次 `<poke address64=… size_in_bytes=4>` | 回 `Unsupported` vs secure-boot 拒绝（`9008` §6-1） |
| O12 | 出厂 GPT 的 LUN4 实际容量（GPT 说 1.48 GB / provision 说 4 GB） | `fh_loader --getstorageinfo=1` | 用 `NUM_DISK_SECTORS-5` 绕过（`9008` §6-4） |
| O13 | VIP（签名摘要表）是否强制 | `configure AlwaysValidate=1` 跑一次 `program` | 是否 NAK（`9008` §6-3） |
| O14 | `uefivarstore` 的 `PTBL` 字节结构 | 先只读导出 512 KiB（`make_xml.py --read --lun 4 --start 362212 --sectors 128`） | 找 `PTBL` 头/记录长度/CRC（`small` §5.2、`9008` §6-5） |
| O15 | `misc+0x8000` 那 15 B 是什么 | 先备份 1 MiB，擦掉它，观察能否开机/OTA/进 fastbootd | **有风险**，除非要修某症状（`small` §7-1） |
| O16 | `-bootloader` 残尾的来历 | 9008 回刷后读 misc 前 4 KiB | 仍带这 11 B ⇒ 出厂如此（`small` §7-2） |

### 7.2 单变量实验（有刷写，风险可控，全部可回滚）

| # | 问题 | 实验设计 | 预测 / 反证 |
|---|---|---|---|
| E1 | ABL 是否接受**外来 ramdisk**（recovery 线生死） | 造 `kernel_size=0` + OF ramdisk 的镜像，先刷 **`recovery_b`**（零影响）再 `reboot-recovery` | 出现 OF 界面 ⇒ 成；仍是原厂 ⇒ 说明"当前槽"结论成立（**零风险证伪实验**）。再刷 `recovery_a`（`dual` FLASH-PLAN §3.4 选项 A、`dual` §5-4/B1） |
| E2 | b 槽四件为什么被拒（20:10 那次 22 s 回 fastboot） | 只改 `boot_b`（保留原厂 `vendor_boot_b`/`init_boot_b`）看是否仍 22 s 回 fastboot；再逐个替换定位 | 22 s 量级 = ABL 侧拒绝，不是内核 panic（panic → 900E）（`dual` §2.2、`dual` §10-5） |
| E3 | payload 的 appended DTB 是否"恰好一棵" | payload 的 appended DTB 数改成 **1 / 0 / 2** 各试一次 | 出现 `Not the single appended DTB` ⇒ 命中 `0x7fa4`→`0xa520` 返回 `0xE`（`abl` §6.3-a） |
| E4 | 是否走了 32 位误判分支（最隐蔽、零日志） | 把 payload 头 `+0x38` 的 4 字节改成 `41 52 4D 64`（或反过来） | 行为变化即命中；**改 4 个字节即可验证**（`abl` §6.3-b） |
| E5 | 卡在 ABL 还是卡在 SEC | 拿到 ABL 日志（UART 或 `logfs`）看有没有 `Shutting Down UEFI Boot Services: %lu ms` | 有 ⇒ L1~L5 全排除，问题在 L6~L9（`abl` §6.3-c）。⚠️ 本机 `logfs` 为空（F38），只能靠 UART |
| E6 | Mu UEFI 到底死在哪一段 | 在 `BootShim.S` 的 `_Start` **第一条指令前** + `br x5` 之前各写一个哨兵色到 `0x5C000000`（`movz/movk` 三条，不依赖栈/缓存刷新） | 三色 = 三段定位；**在把"哪一段死了"变成两三个像素之前，不要再改地址**（`secmem` §3-1） |
| E7 | ABL 交接的 MMU/缓存状态 | 在 shim 里读 `SCTLR_EL1`/`TTBR0_EL1` 并把值写进 framebuffer 像素（或 SMEM） | 若该段不是 normal-cacheable identity，`stp` 写栈就 abort（`secmem` §3-2） |
| E8 | `kernel_size` 是否等于真实 gzip 流长度 | 解包镜像，取 boot header `+0x08`，与 `0x800..0x800+size` 的 gzip 流实际长度比 | 写小了 ⇒ zlib 半途失败、ABL 打印错误、**根本不跳**（`secmem` §3-3） |
| E9 | `md_KLOGBUF` 能否与控制台做差集分析 | 先确定记录结构与 `log_buf` 的 `LOG_*` 位宽 | 目前只能做子串命中（环形覆盖会截断记录）（`900e` §8-4） |
| E10 | 自己造一份"已知死因"的 900E 对照样本 | 用 avbtool 重建 **root 故意写错** 的 `vbmeta_system`（只 4 KB），单刷 | 预测：≤5 s 见 900E 且转储里有 `data block 0 is corrupted` + `exitcode=0x00007f00`；反证：正常起桌面 ⇒ 解锁态 ABL 忽略坏描述符（`900e` §5.1-方案B） |

### 7.3 需要设备在线 + 写操作的（先做 §7.1 再排）

| # | 问题 | 方法 | 备注 |
|---|---|---|---|
| W1 | 机上 `recovery_a` 与原厂 `recovery.img` 是否逐字节相同 | 进 Android 用 root `dd` 回读比对（100 MB） | `dual` §10-3；`recovery_b` 已确认是 ZUI17（`zuidiff` §5.3） |
| W2 | `misc` 在不在 fastboot 白名单里 | `fastboot flash misc misc_full.bin`（**写回同一份字节**，零状态变化） | 报 critical ⇒ 受保护（`dual` §S2） |
| W3 | BCB 通道是否活的 | `fastboot reboot-recovery`（ABL 自己写 BCB 再重启，**零刷机**） | **分水岭**：通了才值得做 E1（`dual` §S3） |
| W4 | A17 单变量收尾（可选） | 按 `product_FIX.img` + `vbmeta_system_fix.img` 配方重刷三件，重启复现性 | 重启≥2 次都起桌面 ⇒ 闭合（`v4` §5.1） |
| W5 | b 槽三件到底是谁写进去的 | 全量 544 刷完后复读 `recovery_b` head64M | 必须变成 `264aec55…`，若仍是 `e5353d2a…` ⇒ b 槽没写进去（`zuidiff` §6.4） |
| W6 | 蓝本对比：另一台**同型号未解锁机** | 逐分区 sha 对比 | 这是区分"出厂就空"与"被清过"的**唯一干净黄金参照**（`small` §6.3） |

### 7.4 报告缺口（进行中，出来后需回填本文）

| # | 缺什么 | 现状 |
|---|---|---|
| G1 | `work\img-super\REPORT.md` | 目录有 17 个脚本 + `raw\` 素材（`00_features.txt`、`10_vendor_vintf.txt`、`13_vendor_tree.txt` 等），**无 REPORT.md**。§4.5 的 super 章节需以其为准复核 |
| G2 | `work\img-firmware\REPORT.md` | 目录有 `bootextract.py`/`fatls.py`/`gpt_dump.txt`/`ls_modem.txt` 等，**无 REPORT.md**。固件链（modem/dsp/adsp 内部）章节待补 |
| G3 | `work\research-gh-20261124\REPORT.md` | 只有 `MANIFEST-downloads.tsv`（9143 B）+ `issues\`/`Mu-Silicium-main\`/`sapphiren\`/`topaz-woa\` 等抓取树。§5.3-6 的 GitHub 横向结论待补 |
| G4 | 900E `analyze.py` 的批量 `--summary` 覆盖面 | 现有 6 份转储（4×11-13、1×11-23、1×race no_log），`race_20261113_113918` 未抢到日志 |

---

## 8. 附：本轮工作盘的资产状态

| 项 | 状态 | 出处 |
|---|---|---|
| E: 空闲空间 | **43.14 GiB**（两批清理共释放 **32.13 GiB**） | `clean` §0/§2 |
| WSL `ub` vhdx | 实体 38.479 GiB / 内部已用 30 GiB ⇒ **虚胖约 8.4 GiB**（需 `wsl --shutdown` 才能回收） | `clean` §2 |
| 救砖底牌 | ZUI16.544 EDL 全量包（`rawprogram0..5` + `patch0..5` + `prog_firehose_sm6225_ddr.elf`）· `recovery_stock_ZUI16/ZUI17.img` · `misc_full.bin` · `boot_a.img`(sha256 `2510b098…`) | `v4`、`dual` FLASH-PLAN §2.3 |
| 回滚成本序 | `vbmeta`(8 K) < `vbmeta_system`(4 K) < `dtbo`(3.5 M) < `init_boot`(2 M) < `boot`(43 M) < `vendor_boot`(12.9 M) —— **全部可 fastboot 完成，不需要 9008** | `bootgrp` §5.1 |
| 三个最危险操作 | ① `provision_*.xml` / QFIL 勾"全部格式化" ② `fh_loader --firmwarewrite` ③ `benchmark` 写测试 | `9008` §5.2 |

---

*本文由本轮全部研究报告整合而成。凡与单份报告冲突处，以报告内标注的原始地址/字节证据为准；本文只做汇总与交叉引用，不新增未标注来源的结论。*
