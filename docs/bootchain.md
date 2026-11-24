# TB331FC（khaje / SM6225-AD）启动链与固件层档案 —— 地址级

- 日期：2026-11-24
- 对象：联想小新 Pad 2024 / TB331FC / `khaje` / 骁龙 685（SM6225-AD），A/B + 独立 recovery
- 性质：**只读**。全程未刷机、未写分区、未 reboot、未改任何镜像。设备侧只做了 `getprop` 与 `dd ... | od`（管道到 stdout，不落盘）
- 素材：本轮新做的静态分析（XBL / ABL / GPT / AVB）+ 已有六份报告（`abl-hang-analysis`、`abl-jump-analysis`、`abl-avb-semantics`、`abl-cmd-surface`、`uefi-part`、`fd-audit`）
- 产物：`E:\rom\work\bootchain-profile\`（本文件 + `_scripts\` 12 个新脚本 + `_d\` 反汇编落盘）

**反汇编基址约定**：ABL 是 PE32+/ImageBase=0，三节 `rawsz==vsz` 且 `rawoff==va` ⇒ **VA == 文件偏移**（`.text 0x1000..0xc0000`）。本文所有 `0x…` 地址都是这个约定下的文件偏移/VA。

---

## 0. 一页纸

| 级 | 载体 | 大小 | 谁验签 | 验不过怎么办 |
|---|---|---|---|---|
| **PBL** | SoC 内部 ROM（无分区） | — | 自己（熔丝里的 OEM PK hash） | 掉 EDL(9008)，无任何输出 |
| **XBL** | `xbl_a`（0x380000 = 3.5 MiB） | 镜像 3,227,648 B | PBL 用 XBL 自带的 X.509 链（Elm Root CA）验 hash segment | 掉 EDL / 卡 9008 |
| **UEFI(SEC+DXE)** | **内嵌在 XBL 里**（PT_LOAD @ `0x5FC00000`，FvLength `0x220400`） | 2.13 MiB | 随 XBL 一起被验 | 同上 |
| **ABL(LinuxLoader)** | `abl_a`（0x100000 = 1 MiB） | 镜像 274,432 B → 解出 PE 970,752 B | XBL 的 UEFI 安全启动链 | 掉 EDL；ABL 起不来就没有 fastboot |
| **boot 链** | `vbmeta_a` → `boot_a` / `init_boot_a` / `vendor_boot_a` / `dtbo_a` / `recovery_a` + `vbmeta_system_a` → system/product/system_ext | 见 §2 | **ABL 内 libavb**（钉 testkey_rsa4096，1032 B memcmp） | **解锁态下不拦**（`0x1cdf0` 打印 `State: Unlocked, … continue boot`） |
| **Linux** | 内核在 `boot_a`，ramdisk 在 `init_boot_a`，DTB 在 `vendor_boot_a` | 内核 46.8 MB | 内核 + dm-verity（由 vbmeta 描述符驱动） | verity 失败 → init 退出 127 → panic → **900E** |

三条本轮新增/夯实的硬结论：

1. **UEFI 固件不在 `abl` 里，在 `xbl` 里。** `xbl.img` 的第 16 个 PT_LOAD 就是一份完整 FFS2 固件卷（`vaddr=0x5FC00000`、`FvLength=0x220400`、含 SEC `8af09f13` + `uefiplat.cfg` + LZMA 压缩的 DXE 卷 `9e21fd93`）。ABL 只是 BDS 按名字加载的一个 UEFI 应用 —— 证据是 XBL 里可读的配置文本写着 **`DefaultBDSBootApp = "LinuxLoader"`**（`0xbf4c3`）。
2. **槽位元数据不在 `misc`，在 GPT 分区属性里。** 位域已从反汇编逐位解出（§2.5）：`bits48-49=priority`、`bit50=active`、`bits51-53=retry`、`bit54=successful`、`bit55=unbootable`。`misc` 只放启动命令（`boot-recovery` / `boot-fastboot`）。
3. **整条 AVB 链用的是 AOSP 公开 testkey。** 实测：`testkey_rsa4096.pem` → avbpubkey sha1 `2597c218…f011` = `vbmeta_a` 公钥；`testkey_rsa2048.pem` → `cdbb7717…617d` = `vbmeta_system_a` 公钥。**AVB 不是障碍，可以随意重签。**

---

## 1. 启动链全图

### 1.1 五级链（按实际执行顺序，带地址）

```
┌──────────────────────────────────────────────────────────────────────────┐
│ ① PBL  (SoC mask ROM，不在任何分区里；不可读、不可改)                      │
│    读 GPT → 找 xbl_a → 校验 XBL 的 QCOM hash segment                       │
│    信任根 = 熔丝里的 OEM PK hash（Lenovo 公钥的 sha256）                    │
│    失败 → 进 EDL(Sahara 9008)；无显示、无日志                              │
└───────────────────────────┬──────────────────────────────────────────────┘
                            │ xbl_a（0x380000，镜像 3,227,648 B，ELF64）
┌───────────────────────────▼──────────────────────────────────────────────┐
│ ② XBL = SBL1 + UEFI（一体）                                               │
│   ├─ SBL1 段（可读，字符串 0x4a88 起）：DDR 训练 / PMIC / clock / RPMh /    │
│   │   dload 判定。证据：`SBL1 BUILD @ 05:35:33 on Jun  8 2025`、           │
│   │   `sbl1_load_ddr_training_data`、`do_ddr_training, Start` …            │
│   └─ UEFI 段（PT_LOAD @ vaddr 0x5FC00000，FvLength 0x220400）              │
│        ├─ FFS PAD 0xFA0                                                   │
│        ├─ FFS SECURITY_CORE 8af09f13… size 0x3F018（未压缩 TE，原地执行）   │
│        ├─ FFS FREEFORM dde58710… = uefiplat.cfg（0x23C6，明文！见 §1.4）    │
│        └─ FFS 9e21fd93… size 0x1D7A30 = GUIDed LZMA 压缩的 DXE 卷          │
│   由 BDS 按名字加载下一个 app：DefaultBDSBootApp = "LinuxLoader"            │
└───────────────────────────┬──────────────────────────────────────────────┘
                            │ abl_a（0x100000，镜像 274,432 B，ELF32）
┌───────────────────────────▼──────────────────────────────────────────────┐
│ ③ ABL / LinuxLoader（UEFI 应用，PE32+ AArch64，970,752 B，ImageBase=0）     │
│   BootLinux = 0x6a30                                                      │
│    0x783c UpdateBootImageParams(判 gzip → BootInfo+0xc2)                   │
│    0x7860 QueryBootParams  → KernelLoadAddr = UEFI变量 KernelBaseAddr+0x80000│
│    0x7894 LoadKernel       → zlib inflate 到同一地址（dst==src 自拷贝）      │
│    0x7fa4 appended-DTB 校验（单棵才放行，见 §3）                            │
│    0x8488 → 0x8610 ldr x8,[BootInfo+0x40] → 0x862c blr x8                  │
│              x0 = BootInfo+0x58 = DtbLoadAddr（arm64 FDT 指针）             │
└───────────────────────────┬──────────────────────────────────────────────┘
                            │ 跳进 boot_a 解压后的镜像（物理 ≈ 0x40080000）
┌───────────────────────────▼──────────────────────────────────────────────┐
│ ④ Linux 内核（boot_a，v4 头，kernel_size 0x2CA6A00）                       │
│   + init_boot_a 的 ramdisk（2,004,357 B）+ vendor_boot_a 的 DTB            │
│     （0x13B1C2 = 1,290,690 B 六棵 FDT，装载地址 0x1F00000）                 │
│   内核起 dm-verity 校验 system/product/system_ext/vendor/…                 │
└───────────────────────────┬──────────────────────────────────────────────┘
                            ▼
                  ⑤ Android init（first stage 在 init_boot 的 ramdisk 里）
```

### 1.2 逐级细目

| 项 | PBL | XBL | ABL | Linux |
|---|---|---|---|---|
| 分区 | 无（ROM） | `xbl_a` / `xbl_b` | `abl_a` / `abl_b` | `boot_a` / `init_boot_a` / `vendor_boot_a` |
| 分区大小（getvar） | — | `0x380000` = 3.5 MiB | `0x100000` = 1 MiB | `0x6000000` / `0x800000` / `0x6000000` |
| 镜像大小 | — | 3,227,648 B | 274,432 B（ELF32 壳） | 100,663,296 B（含 AVB footer） |
| 封装 | — | ELF64（machine `0xB7`），17 个 phdr | **ELF32**（`EM_ARM 0x28`，entry `0x9fa00000`）→ FV → FFS → LZMA → PE32+ | Android boot header v4 |
| 压缩/加密 | — | **部分加密**：`0xC0000–0x28FFFF`（≈1.7 MiB）熵 7.98 | 载荷 LZMA（`ee4e5898…`）→ 970,952 B | 内核未压缩（首 8 B = `ccmp`+`b entry`） |
| 谁验签 | 熔丝 OEM PK hash | PBL（用 XBL 自带的 Elm 证书链） | XBL 的 UEFI 安全启动 | ABL 的 libavb + 内核 dm-verity |
| 验不过 | 静默进 9008 | 静默进 9008 | ABL 不启动（无 fastboot，掉 EDL） | 解锁态放行；否则 `18D1:D00D` fastboot |
| 关键证据 | 不可读 | `xbl.img` ph16 → FV 头（§1.3） | `abl.img` 解包链（§1.2.1） | `boot.img` 头 + `vbmeta` 描述符（§2） |

#### 1.2.1 ABL 的解包链（复述并核对，字节级）

```
abl.img 274,432 B  ELF32 / EM_ARM / e_entry=0x9fa00000
  ph0 type=0  off=0x0     filesz=0x94
  ph1 type=0  off=0x1000  vaddr=0x9fa40000 filesz=0x1a38   ← QCOM hash segment + 证书
  ph2 type=1  off=0x3000  vaddr=0x9fa00000 filesz=0x40000  ← 载荷
0x3000 : FV(8c8ce578…) len=0x40000 attr=0x0003feff hdrlen=0x48
0x3048 :   FFS(9e21fd93…) type=FIRMWARE_VOLUME_IMAGE size=239,297
0x3060 :     SECTION GUIDED ee4e5898-3914-4259-9d6e-dc7bd79403cf  LZMA → 970,952 B
0x0008 :       内层 FV(8c8ce578…) len=0xed0c0
0x0050 :         FFS(ffffffff) FFS_PAD 44 B
0x0080 :         FFS(f536d559) APPLICATION size=970,808  UI="LinuxLoade…"
0x0098 :           SECTION UI
0x00b4 :           SECTION PE32  970,756 B → 970,752 B PE32+ AArch64
```
解出的 PE `sha256 = 33CA0240027D83CB930B4C263CEB54C5B9884442FE5EB84D20E23E18B9D25123`，
**ZUI15 / ZUI16 / ZUI17 三版 `abl.img` 解出的 PE 逐字节相同**（ZUI15 除外：966,656 B / `68d14109…`）。

### 1.3 ★ XBL 解剖：UEFI 固件就藏在 XBL 里（本轮新证据）

`E:\rom\work\zui17_images\xbl.img`，3,227,648 B：

```
ELF64  machine=0xB7(AArch64)  e_entry=0xC225908  phnum=17
  ph0  type=0  off=0x0      filesz=0x3f8      ← QCOM hash segment 头
  ph1  type=0  off=0x1000   vaddr=0x5FE21000 filesz=0x1cd8   ← hash 表 + X.509 链
  ph2..ph15    type=1  多个 PT_LOAD（0xC119000 / 0xC225000 / 0x45E00000 …）
  ph16 type=1  off=0x7d4b0  vaddr=0x5FC00000 filesz=0x220400  ★ UEFI 固件卷
```

对 `ph16` 按 FV 解析（`_scripts\fvlist.py`）：

| 字段 | 值 | 判定 |
|---|---|---|
| ZeroVector[0] | `0x1400334C` = `b +0xCD30` | 跳板指向 FV+0xCD30 |
| ZeroVector[1] | `0` | **无 PEI 入口 ⇒ PrePi 架构** |
| FileSystemGuid | `8c8ce578-8a3d-4f1c-9935-896185c32dd3` | FFS2 ✓ |
| FvLength | `0x220400`（2,229,248）= 段长 | ✓ |
| BlockMap | `0x1102 × 0x200 = 0x220400` | ✓ |
| HeaderLength / Checksum | `0x48` / `0x9857`，16 位截断累加 = `0x0000` | **VALID** |
| FFS 文件 | 4 个（见下） | ✓ |

| # | 偏移 | 类型 | GUID | 大小 | 内容 |
|---|---|---|---|---|---|
| 0 | `0x000048` | `0xF0` PAD | `ffffffff…` | `0xFA0` | 对齐垫片 |
| 1 | `0x000FE8` | `0x03` SECURITY_CORE | `8af09f13-44c5-96ec-1437-dd899cb5ee5d` | `0x3F018` | UEFI SEC（未压缩，原地执行） |
| 2 | `0x040000` | `0x02` FREEFORM | `dde58710-41cd-4306-dbfb-3fa90bb1d2dd` | `0x23C6` | **`uefiplat.cfg`（明文）** |
| 3 | `0x0423C8` | `0x0B` COMBINED_PEIM | `9e21fd93-9c72-4c15-8c4b-e77f1db2d792` | `0x1D7A30` | GUIDed LZMA 压缩的 DXE 卷 |

**⇒ 结构结论**：XBL 内的这份 FV 与源机 `uefi.img` 里的 FV（`uefi-part\REPORT.md` §2.2）**同构**（PAD / SEC `8af09f13` / `uefiplat.cfg` / LZMA FV `9e21fd93`）。
也就是说：**"edk2/UEFI 直启" 与 "ABL 启动" 在这台机器上共用同一份 UEFI 固件，只是前者由 XBL 直接进 BDS，后者由 BDS 再加载 LinuxLoader。**
这也解释了 `uefi` 分区为什么在本机不存在且 ABL 里零引用（`uefi-part\REPORT.md` §1/§3）——**它不需要存在，UEFI 在 XBL 里**。

### 1.4 XBL 里可读的 `uefiplat.cfg`（明文，`0xbe900–0xbf500`）

这是本次最有信息量的一块可读数据（节选，全部原文）：

```
[ConfigParameters]
ConfigParameterCount = 64
PlatConfigFileName = "uefiplatLA.cfg"
OsTypeString = "LA"
NumCpusFuseAddr = 0x5C04C
SharedIMEMBaseAddr    = 0x0C125000
DloadCookieAddr = 0x003D3000     DloadCookieValue = 0x10
NumCpus = 8   NumActiveCores = 8
SpecialLogPartition = "LOGFS:\"    MaxLogFileSize = 0x400000
SecurityFlag = 0xC4
TzAppsRegnAddr = 0x61800000      TzAppsRegnSize = 0x02100000
DefaultChargerApp = "QcomChargerApp"
DefaultBDSBootApp = "LinuxLoader"        ★★ ABL 的入口
EnableLogFsSyncInRetail = 0x0            ★ retail 下不同步日志到 logfs
ShmBridgememSize = 0xA00000
EnableMultiThreading = 1   MaxCoreCnt = 8   EarlyInitCoreCnt = 1
EnableDisplayThread = 1                  ← 显示初始化在独立线程，与启动并行
EnableUefiSecAppDebugLogDump = 0x1
AllowNonPersistentVarsInRetail = 0x1
```
（`0xbf4a6` 一带即 `DefaultBDSBootApp = "LinuxLoader"`，`LinuxLoader` 字面量在 `0xbf4c3`；`0xbe900–0xbf310` 是 `SecurityFlag` 的位定义注释。）

三条可直接用的推论：

| 推论 | 依据 | 用途 |
|---|---|---|
| **ABL 是 XBL 的一个 UEFI 应用，不是独立的第二阶段** | `DefaultBDSBootApp = "LinuxLoader"`（`0xbf4c3`） | 想换引导器 = 换 `abl` 分区即可，不必碰 XBL |
| **retail 下 XBL 不同步日志到 logfs** | `EnableLogFsSyncInRetail = 0x0`（明文段 `0xbe900–0xbf310`） | 别指望从 `logfs` 分区读 ABL 日志（见 §4） |
| **显示由 XBL 的 UEFI 线程初始化** | `EnableDisplayThread = 1` | splash/黑屏问题要先怀疑 XBL→ABL 交接，不是 ABL 的显示代码 |

### 1.5 XBL 的"可读占比"与加密段（实测）

| 指标 | 值 |
|---|---|
| 文件大小 | 3,227,648 B（`0x314000`） |
| **长度 ≥8 的可打印串总字节** | **80,792 B = 2.50%**（2,797 段） |
| 全文件可打印字节比 | 32.56%（随机数据的理论值 ≈37.1%，说明大部分是代码/加密） |
| 全文件熵 | 7.5099 |
| **高熵段（≥7.96）** | `0xC0000 – 0x28FFFF`，**≈1.70 MiB = 53%**，逐 64 KiB 熵 7.96–7.98 |

可读部分全部集中在三块，且**都是"外壳/配置/证书"，没有算法主体**：

| 区间 | 内容 | 证据 |
|---|---|---|
| `0x1500 – 0x1e2c` | X.509 证书链：`Elm Root CA` / `Elm Attestation CA` / `QUALCOMM` / `BeiJing`（Lenovo），有效期 `230626014543Z–430621014543Z` | 直接字符串 |
| `0x39b8` | `*XBLLoader*boot_images/Build/DivarLAA/Dll/RELEASE/XBLLoader.dll` | 构建路径泄漏（工程名 `Divar`） |
| `0x4a88 – 0x50xx` | SBL1 段：`SBL1, Start (MPM timestamp = %d)`、`SBL1 BUILD @ 05:35:33 on Jun  8 2025`、`do_ddr_training, Start`、`sbl1_load_ddr_training_data`、`boot_clock_init_rpm`、`sbl1_efs_handle_cookies`、`EDL: sbl1_dload_entry: …` | 直接字符串 |
| `0xbe900 – 0xbf500` | `uefiplat.cfg` 全文（§1.4） | 直接字符串 |
| `0xab408 / 0xacad2` | UEFI 日志串：`UEFI DXE`、`UEFI Start [%5d]`、`Sec.efi`、`Scheduler up on Core %d` | 直接字符串 |

**不可读/不可用的部分（明确结论）**：XBL 的算法主体在 `0xC0000–0x28FFFF` 高熵段内，静态拿不到；
`KernelBaseAddr` / `KernelSize` 这两个 UEFI 变量名在 XBL 可读区**零命中**（`_scripts\xbl2.py` 实测 `0 hits`），
所以「谁写 `KernelBaseAddr`」这条链**静态不可闭合**（见 §4）。

### 1.6 ABL 的职责边界

#### 做了（全部有地址）

| 职责 | 证据 |
|---|---|
| 读 `boot` 分区 + 解析 boot header（v0/1/2 与 v3/v4 两条独立分支） | `0x8bb0 GetBootImageInfo`；v0/1/2 → `0x8be8`，v3 → `0x8cb4`，v4 → `0x8ffc` |
| 判 gzip 并解压 | `0x6b950 IsGzip`（嗅 `1f 8b 08`）→ `0x6b0a0 DecompressImage` → 调用点 `0x9e98` |
| 算装载地址 | `0x9824 add x8,x8,#0x80,lsl#12`（`base+0x80000`）；未压缩时 `0x9818` 改加 `text_offset` |
| 校验 appended DTB 唯一性 | `0x7fa4 bl 0xa520` → `0xaab4 fdt_check_header(p2)` → `0xab58 "Not the single appended DTB"` |
| AVB 校验（libavb） | `0x1afd4 LoadImageAndAuth` → `0x1c394 LoadImageAndAuthVB2` → `0x1cd78 bl 0x608dc`（`avb_slot_verify`） |
| 槽位管理（GPT 属性读写） | `0x21190`（写回 GPT）；读/解析 `0x202d0/0x202e4`；retry 递减 `0x27b10`；标 unbootable `0x2714c` |
| 启动命令（misc BCB） | `0x6a300 SetBootCommand`（thunk `0x81458`）；`0x6a710 GetBootCommand`（memcmp `boot-recovery`@`0x6aa8` / `boot-fastboot`@`0x6b10`） |
| fastboot 命令面（27 条） | 表 `0xb1e60`/`0xb1e70`（24 条）+ 3 条条件注册 `0x7bbd0`；分发器 `0x7a338` |
| splash / 屏参 | 字符串族：`Splash region not found in device tree…`、`Selecting Panel: `、`oem select-display-panel`（`0x7ea80`） |
| 起跳前最后一件事 | `0x8594 bl 0x60510(w0=1)` 写 Shared IMEM（变量名 `L"Shared_IMEM_Base"`@`0xaf984`）；`0x8610–0x862c` 跳转 |
| 跳转寄存器约定 | `x0 = DtbLoadAddr`（`0x861c`），`x1=x2=x3=0`（`0x8620–0x8628`），`blr x8`（`0x862c`） |

#### 没做（"不做什么"同样重要）

| 没做 | 证据（ABL 字符串全表统计） | 谁做 |
|---|---|---|
| DDR 训练 / DDR 参数 | 无 `ddr_training` 类串（`sbl1_*` 全在 XBL） | XBL 的 SBL1 段 |
| PMIC / 时钟 / RPMh | `RPMh` 0 命中、`clock` 0 命中；`PMIC` 24 条**全是充电屏/关机充电文案**（`oem enable-charger-screen` 一族） | XBL + AOP/RPM |
| UFS / 块设备驱动 | 只有 BlockIo **协议消费者**：`Failed to get the BlockIo for the device`、`BlockIo for %s is corrupted`、`%x.ufshc`；无 `UfsDxe`/初始化代码 | XBL 的 DXE |
| USB 栈 | 只调 `gBS` 的 `UsbTransfer`（`0x7f6ec blr x19`），无控制器驱动 | XBL 的 DXE |
| 显示驱动 / framebuffer | `DxeCore` 0 命中、`SimpleFb` 0 命中、`GraphicsConsole` 0 命中、`DisplayDxe` 0 命中 | XBL 的 DXE（`SimpleFbDxe` / `GraphicsConsoleDxe`） |
| PEI 阶段 | ABL 里无 `PEIM`；XBL 的 FV 里 `ZeroVector[1]`（PEI 入口）= 0 | 不存在（PrePi 架构） |
| 真正的异常兜底 | 全 `.text` **零条 `msr vbar_el*`**；只有 fastboot 路径碰 WDT（唯一串 `0xa1812 "Fastboot: Couldn't disable watchdog timer: %r"`） | 没有 —— 见 §3 第 3 条 |

### 1.7 内存地址地图（本机，实测/推导混合，逐条标注）

| 地址 | 用途 | 来源强度 |
|---|---|---|
| `0x40000000` | DDR 物理基址（`PHYS_OFFSET`） | 实测：`forensics_900e\auto_20261113_114831\ramdump_scan.md:380` |
| **`0x40080000`** | **内核装载地址 = KernelBaseAddr + 0x80000** | 推导（强）：`0x9824` + DDR 基址 |
| `0x43C00000` | base+0x3C00000（常量页 `0xbefe0` = `0x03c00000`，内核区大小的典型值 60 MB） | 静态 |
| `0x45600000` | 内核可用区上界（base+0x5600000，常量页 `0xbefdc`） | 静态 |
| `0x45700000` | HYP 区（MemoryMapLib 与 DTS 一致） | 静态：`hyp_region@45700000` |
| `0x5C000000 + 0xF00000` | **splash / framebuffer**（dtbo overlay `cont_splash_region` 逐字节证实） | 实测：`zui17_images\dtbo.img` fragment@30 |
| `0x5CF00000 + 0x100000` | DFPS data region | 静态：`fdt0.dts:676` |
| **`0x5FC00000 + 0x220400`** | **XBL 内嵌 UEFI 固件卷（本轮新增）** | 实测：`xbl.img` ph16 |
| `0x5FC00000 + 0x300000` | ABL MemoryMapLib 里的 "UEFI FD" 保留区（与上一条重叠） | 静态：`MemoryMapLib.c:47` 一族 |
| `0x5FF90000 + 0x40000` | SEC 栈（`PcdCPUCoresStackBase`） | 静态：`tb331fc.dsc:47-48` + SEC 入口反汇编 |
| `0x0C125000` | Shared IMEM（ABL 起跳前写一次） | 实测：XBL `uefiplat.cfg` + ABL `0x8594` |
| `0x1F00000` | vendor_boot 的 DTB 装载地址（`dtb_addr`） | 实测：`vendor_boot.img` 头 |
| `0x61800000 + 0x2100000` | TZ apps 区 | 实测：XBL `uefiplat.cfg` |

> ⚠️ **给 WOA 线的一条高价值线索（未验证，别据此动手）**：`0x5FC00000` 是 **XBL 自己那份 UEFI FV 的装载地址**。
> 而 BootShim 的做法正是把 3 MiB 自编 FD 拷到 `0x5FC00000` 再跳。若 ABL 运行时这块内存仍是活着的 XBL-UEFI 代码/数据，
> 这一步就是"把自己的运行时踩掉"。这条能解释 `abl-hang-analysis` 里"三版构建全黑、无 USB、不复位"的 Top1，
> 且与"tapas 能跑"不矛盾（tapas 的 UEFI FD 基址未必是 0x5FC00000）。**验证办法**：换一个空闲基址（如 `0x5F800000` 之上的空窗）重编 FD，或先在 9008 下 dump `0x5FC00000` 看是否非零。

### 1.8 boot 链头部结构（原厂 544 实测，逐字段）

**`boot.img`（100,663,296 B，AVB footer 里 Original size = 46,841,856）**

| 字段 | 值 |
|---|---|
| magic / header_version | `ANDROID!` / **4** |
| kernel_size | `0x2CA6A00` = 46,841,856 |
| ramdisk_size | `0`（ramdisk 已移到 init_boot） |
| page_size | 4096 |
| cmdline | **空**（v4 的 cmdline 在 vendor_boot 里） |
| 内核头（kernel+0） | `MZ`（PE/COFF，EFI stub 布局）；`+0x38 = "ARMd"` ✓；`text_offset=0`、`image_size=0x2D50000`、`flags=0xA` |
| **入口（关键）** | 前 8 字节反汇编 = `ccmp x18,#0,0xd,pl` + **`b #0x27E0000`** ⇒ **从偏移 0 进入即可**（与 BootShim 依赖的契约一致） |
| PE 头 | `e_lfanew=0x40`、machine `0xAA64`、2 节、`SizeOfHeaders=0x10000`、`.text` raw 0x10000 / 0x2A00000、entry RVA `0x27E0404` |

**`init_boot.img`（8,388,608 B）**：`ANDROID!` / v4 / kernel_size `0` / ramdisk_size `0x1E9B85`（2,004,357）。

**`vendor_boot.img`（100,663,296 B）**

| 字段 | 值 |
|---|---|
| magic / header_version / page | `VNDRBOOT` / 4 / 4096 |
| kernel_addr / ramdisk_addr | `0x8000`（**ABL 不读**）/ `0x1000000` |
| vendor_ramdisk_size | `0xB17084` = 11,628,164 |
| **cmdline** | `video=vfb:640x400,bpp=32,memsize=3072000 bootconfig`（51 B） |
| tags_addr / header_size | `0x100` / `0x850` |
| **dtb_size / dtb_addr** | **`0x13B1C2` = 1,290,690** / `0x1F00000` |
| vendor_ramdisk_table | size `0x6C`，1 条，entry 108 B |
| bootconfig_size | `0x7D` |

> 注：`dtb_size = 1,290,690` 与 `Resources\DTBs\tb331fc.dtb`、ZUI17 `vb_dtb.dtb` **同尺寸**，即**原厂 DTBO/DTB 本身就是 6 棵 FDT 的 blob**。
> 这一点很关键：**"多棵 FDT" 在 vendor_boot 里是合法的**，ABL 的 `Not the single appended DTB` 只针对**追加在 boot.img 内核后面的** DTB（§3）。

---

## 2. 关键结构表

### 2.1 `vbmeta_a` 完整描述符清单（`avbtool info_image`，原厂 544 `image\vbmeta.img`，8192 B）

```
Minimum libavb version:   1.0
Header Block: 256 B   Authentication Block: 576 B   Auxiliary Block: 6080 B
Public key (sha1):        2597c218aae470a130f61162feaae70afd97f011
Algorithm:                SHA256_RSA4096
Rollback Index: 0     Flags: 0     Rollback Index Location: 0
Release String:           'avbtool 1.2.0'
```

| # | 描述符 | 分区 | Image Size | 算法/树参数 | Salt | 摘要 / Root Digest | 覆盖方式 |
|---|---|---|---|---|---|---|---|
| 1 | **Chain** | `vbmeta_system` | — | RIL=2 | — | pubkey sha1 **`cdbb771777f731920bbe0a0f94f84d9038ae0617d`**，Flags=0 | 链式 |
| 2 | Hash | `boot` | 46,841,856 | sha256 | `0b8f7e2fd96e1922090e393672502d6f0578446e15451c092721c68863957689` | `ad970718ab11fdbf7331b8a084809ab71d90da233d577ee7024079e43f21e3e5` | **hash** |
| 3 | Hash | `dtbo` | 3,500,977 | sha256 | 同上 | `b1858a6b5975a0f6dff25462b64daff50ac58459dfc38b60dfdb783849ab915a` | **hash** |
| 4 | Hash | `init_boot` | 2,011,136 | sha256 | `6cb9fac082a02cf1f55350c88443cc5d7c858e041e60c73311658ea77045f42b` | `ab394ed4e359ce444fd64cba717f982d038f30fb696b46f054044fe6329ad0c9` | **hash** |
| 5 | Hash | `recovery` | 14,577,664 | sha256 | `0b8f7e2f…7689` | `57af39113f73cd6e3f52cd8be460d4a00929fd93a055a563150cc7e58d72aa7b` | **hash** |
| 6 | Hash | `vendor_boot` | 12,939,264 | sha256 | `0b8f7e2f…7689` | `a81b4405a7dd25e8287a0dd83fefdb877f40095dd4f90bb6ee0fd18ce6ec0e9a` | **hash** |
| 7 | Hashtree | `odm` | 1,310,720 | v1 / blk 4096 / sha256 / FEC 2 roots | `2e7e7a71387f00af064094d46007e748370b5293825cb137ad9b7c261fc9f613` | `e5bf7ad658130a3631da959979031ced58c6d4cc21cf230053a536ed70a69785` | **hashtree** |
| 8 | Hashtree | `system_dlkm` | 352,256 | 同上 | `2e7e7a71…f613` | `04114d7d4de3342be143b0cdde7cd7090dc2507b6061b58a529387ce46526031` | **hashtree** |
| 9 | Hashtree | `vendor` | 670,437,376 | tree off 670,437,376 / tree 5,283,840 / FEC 5,349,376 | `2e7e7a71…f613` | `9f28d49cce333e9ce512e59caf1bb3f527d230451fe3ded8f3935c3c775c6800` | **hashtree** |
| 10 | Hashtree | `vendor_dlkm` | 57,925,632 | tree 458,752 / FEC 466,944 | `2e7e7a71…f613` | `ac9cb2bd9b3ae809229e105ca47667b0bded40584a01952b907eafab57dce22c` | **hashtree** |

Prop 描述符 20 条（`com.android.build.{boot,init_boot,vendor_boot,recovery,vendor,odm,vendor_dlkm,system_dlkm,dtbo}.{os_version,fingerprint,security_patch}`），
其中指纹统一为 `Lenovo/TB331FC_PRC/TB331FC:14/UKQ1.230917.001/ZUI_16.0.544_241115_PRC:user/release-keys`，
`security_patch = 2024-10-05`，`os_version = 13`（boot/init_boot/vendor 系）。

### 2.2 `vbmeta_system_a` 完整描述符清单（原厂 544 `image\vbmeta_system.img`，4096 B）

```
Header 256 B   Authentication 320 B   Auxiliary 2432 B
Public key (sha1):  cdbb77177f731920bbe0a0f94f84d9038ae0617d
Algorithm:          SHA256_RSA2048
Rollback Index: 0   Flags: 0   RIL: 0    Release String: 'avbtool 1.2.0'
```

| # | 描述符 | 分区 | Image Size | 树参数 | Salt | Root Digest |
|---|---|---|---|---|---|---|
| 1 | Hashtree | `product` | 584,949,760 | tree 4,612,096 / FEC 4,661,248（2 roots） | `9aa7d2aead0e43f79340994f0d14f11da90f2dcf099ebf19ebb455edc3d31065` | `8c3eed36cbf2e799b92b83597008d2cffe382a08a975ac01b6a4a63ba263e35d` |
| 2 | Hashtree | `system` | 5,406,855,168 | tree 42,577,920 / FEC 43,081,728 | 同上 | `6a1bb7019ab22a5dafcd44b20ee4e112a7d59201776e076a199f7a22918e5de0` |
| 3 | Hashtree | `system_ext` | 452,763,648 | tree 3,571,712 / FEC 3,612,672 | 同上 | `953f7306157f0da22a04741ece4205badc97b70f1c69c5f6c33858b5d831479a` |

Prop 描述符 11 条（`com.android.build.{system,product,system_ext}.{os_version,fingerprint,security_patch}`，`os_version=14`）。

### 2.3 各分区 footer 的 algorithm / salt / 公钥

| 分区 | footer 里的 Algorithm | 公钥 sha1 | Salt | 说明 |
|---|---|---|---|---|
| `boot` | **NONE** | **无**（Authentication Block = 0 B） | `0b8f7e2f…7689` | 未自签，签名只在 `vbmeta_a` 里 |
| `init_boot` | **NONE** | 无 | `6cb9fac0…f42b`（**与其他分区不同**） | 同上 |
| `dtbo` | **NONE** | 无 | `0b8f7e2f…7689` | 同上 |
| `vendor_boot` | **NONE** | 无 | `0b8f7e2f…7689` | 同上 |
| `recovery` | **NONE** | 无 | `0b8f7e2f…7689` | 同上 |
| `vbmeta_a` | **SHA256_RSA4096** | **`2597c218aae470a130f61162feaae70afd97f011`** | — | 根，RIL=0，Flags=0 |
| `vbmeta_system_a` | **SHA256_RSA2048** | **`cdbb77177f731920bbe0a0f94f84d9038ae0617d`** | — | 链子，Flags=0 |
| odm / vendor / vendor_dlkm / system_dlkm / product / system / system_ext | 由 `vbmeta` 的 hashtree 描述符覆盖（分区自身 footer 未逐个跑，`avbtool` 会读整个 5.4 GB 镜像） | 同其父 vbmeta | 见 §2.1/§2.2 | — |

**★ 公钥 = AOSP 公开 testkey（本轮实测证明）**

```
python3 avbtool.py extract_public_key --key testkey_rsa4096.pem --output tk4.avbpubkey
  → len 1032  sha1 2597c218aae470a130f61162feaae70afd97f011   ← 与 vbmeta_a 公钥逐字节同
python3 avbtool.py extract_public_key --key testkey_rsa2048.pem --output tk2.avbpubkey
  → len  520  sha1 cdbb77177f731920bbe0a0f94f84d9038ae0617d   ← 与 vbmeta_system_a 公钥逐字节同
```
（`testkey_*.pem` 在 `E:\rom\work\tools\`；1032 B 也正是技能库记的「ABL 内嵌钉钥 memcmp 1032 字节」的长度。）

### 2.4 AVB 覆盖矩阵（97 个 GPT 分区〔`getvar` 里 raw 型 90 个〕+ 7 个 super 逻辑分区）

| 类别 | 受 AVB 保护 | 完全没有 AVB 保护 |
|---|---|---|
| boot 链 | `boot`(hash) `dtbo`(hash) `init_boot`(hash) `recovery`(hash) `vendor_boot`(hash) | — |
| 系统 | `system` `product` `system_ext`（hashtree via vbmeta_system）<br>`vendor` `odm` `vendor_dlkm` `system_dlkm`（hashtree via vbmeta） | `super` 容器本身、`userdata` |
| **引导固件** | **无** | `xbl_a/b` `xbl_config_a/b` `abl_a/b` `hyp_a/b` `tz_a/b` `rpm_a/b` `devcfg_a/b` `cmnlib_a/b` `cmnlib64_a/b` `keymaster_a/b` `mdtp_a/b` `mdtpsecapp_a/b` `qupfw_a/b` `uefisecapp_a/b` `imagefv_a/b` `featenabler_a/b` `multiimgoem_a/b` `multiimgqti` `catefv` `catecontentfv` `toolsfv` `cateloader` `ddr` `apdp` `dip` `secdata` `storsec` `cdt` |
| **身份/元数据** | **无** | `devinfo` `misc` `metadata` `persist` `frp` `fsc` `fsg` `modemst1/2` `oemowninfo` `keystore` `ssd` `lenovocust` `lenovolock` `lenovoraw` `limits` |
| 日志/调试 | 无 | `logfs` `logdump` `rawdump` `spunvm` `splash` |
| 其它 | 无 | `bluetooth_a/b` `modem_a/b` `dsp_a/b` |

计数：**受保护 = 12 个逻辑名 / 17 个镜像**（10 个 GPT 分区 + 7 个 super 逻辑分区）；其余全部裸奔。
其中最要紧的一条：**引导固件（xbl/abl/tz/hyp/keymaster）一个都不在 vbmeta 描述符里** ——
它们的完整性靠 XBL 自己的签名链（Elm 证书）+ 熔丝，**与 AVB 无关**。
所以「改 vbmeta 让 AVB 过」永远不会让你获得改 `xbl`/`abl` 的能力（这两个还被 ABL 的 24 条 critical 白名单硬拦，见 §3 第 5 条）。

### 2.5 槽位机制（★ 本轮的机制级新结论：元数据在 GPT 属性里，不在 misc）

#### 2.5.1 元数据放在哪

`GetActiveSlot` 读的是**分区表条目的 8 字节 attributes 字段**（GPT entry 偏移 `+0x30`），不是 misc 的 BCB。

| 证据 | 地址/指令 |
|---|---|
| 读 priority | `0x202d0 ldrh w8,[x8,#0x36]` → `0x202d4 and x8,x8,#3` |
| 读 retry | `0x202e4 ubfx x8,x8,#0x13,#3`（high word 的 bit19..21） |
| 判 active / successful / unbootable | `0x202f4 tbnz w8,#2` / `0x20304 tbnz w8,#6` / `0x20314 tbnz w8,#7`（byte@`+0x36` 的 bit2/6/7） |
| 打印 | `0x207d8–0x207f0` 组装 5 个参数 → `0x207f8` 串 `0xa5777 "GetActiveSlot: Slot attr: Priority %ld, Retry %ld, Active %ld, Success %ld, unboot %ld"`；其中 `0x207e8 ubfx x4,x9,#0x12,#1` = bit50，`0x207ec/0x207f0 and …#0x4000…/#0x8000…` = bit54/bit55 |
| 写回 | `0x21190`（唯一的"把属性写回分区表"入口；同族 GPT 更新函数里的日志点：`0x232ec "Updating GPT partition"`、`0x247c0 "Slot suffix %s Part Attr 0x%lx"`、`0x23c2c "Failed to patch GPT"`） |
| 失败日志 | `0x9e954 "Attemping to update partition table"`、`Error writing primary GPT header: %r`、`Error flushing blocks primary GPT header: %r`、`Error Calculating CRC32 on the Gpt header: %x` |

**位域（从 `and/orr` 掩码逐位还原，两处独立印证）**

| bit | 含义 | 掩码证据 |
|---|---|---|
| 48–49 | **priority**（0–3） | `0x202d4 and #3` |
| **50** | **active** | `0x207e8 ubfx #0x12,#1`；`0x202f4 tbnz #2`（byte@0x36） |
| **51–53** | **retry count（0–7，3 bit）** | `0x27b2c and x8,x8,#0xffc7ffffffffffff`（清 51/52/53）+ `0x27b58 orr x8,x8,x10,lsl #51`（写入） |
| **54** | **successful** | `0x207f0 and #0x80000000000000`…（打印）；`0x203f4 and x8,x8,#0xff3fffffffffffff`（清 54/55） |
| **55** | **unbootable** | `0x2714c orr w8,w8,#0x800000`（high word bit23 = u64 bit55） |

> 用原厂 GPT 复核：`gpt_main4.bin`（LUN4，96 项）里 `boot_a`（项 10，first=65414 last=89989）与 `boot_b`（项 34）的 `attr = 0x0000000000000000`
> ⇒ **出厂态全零**，正好命中"首次启动初始化"分支（下条）。这也说明：**刷回原厂 GPT = 槽位状态全部归零**。

**★ 真机复核（本轮实测，2026-11-24，`dd if=/dev/block/sde bs=1 skip=… count=128 | od`）**

LUN4 = `/dev/block/sde`（`boot_a`=`sde11`、`boot_b`=`sde35`），GPT 条目数组在 LBA2 = 字节 8192，项 128 字节 ⇒
`boot_a` 项在 `8192+10*128 = 9472`、`boot_b` 项在 `8192+34*128 = 12544`，属性在项内 `+48`：

| 槽 | first/last LBA（与出厂一致） | **attributes（实测 8 字节）** | 翻译 |
|---|---|---|---|
| `boot_a` | `0xFF86` / `0x15F85` ✓ | `00 00 00 00 00 00 77 00` → **`0x0077000000000000`** | priority=**3**、active=**1**、retry=**6**、successful=**1**、unbootable=**0** |
| `boot_b` | `0x3486E` / `0x3A86D` ✓ | `00 00 00 00 00 00 22 00` → **`0x0022000000000000`** | priority=**2**、active=**0**、retry=**4**、successful=**0**、unbootable=**0** |

⇒ **位域结论在真机上完全对上**：a 槽是"当前活动槽 + 已成功启动（successful=1）+ retry 已从 7 递减到 6"，
b 槽是"备份槽、非活动、priority 低一档、retry=4、未成功"。**这条同时证明 `misc` 里没有第二份槽位元数据**（见 §2.5.3 的实测）。

#### 2.5.2 三种状态转换（地址级）

| 转换 | 触发条件 | 指令 | 写入值 |
|---|---|---|---|
| **首次启动初始化** | priority==0 且 !active 且 !successful 且 !unbootable | `0x202f4/0x20304/0x20314/0x20320` 四个测试全不跳 → `0x203c0` 打印 `0x9a174 "GetActiveSlot: First boot: set default slot _a"` → `0x203f4` 清 54/55 → `0x20418 orr w8,w8,#0x3f0000`（bits48–53 = 全 1） | **priority=3, active=1, retry=7**, successful=0, unbootable=0 |
| **每次启动 retry 递减** | `[sp+0x80]`（读到的 retry）非 0，且通过 `0xfd40`/`0xfcf0`/`0x9749c` 三个前置判断 | `0x27b10 subs x8,x8,#1` → `0x27b14 str` → `0x27b2c` 清 51–53 → `0x27b58 orr …lsl #51` → `0x27b70 bl 0x21190`（写 GPT） | retry = retry-1；成功后 `0x27c14` 打印 `0xa3290 "Active Slot %s is bootable, retry count %ld"` |
| **标 unbootable** | 走 `HandleActiveSlotUnbootable`：`0x27054 ldrb w8,[0xd4000+0xb89]`（引导期标志）为 0 时 | `0x2713c ldr x9,[sp,#0x98]` → `0x27140 ldr w8,[x9,#0x30]!` → `0x2714c orr w8,w8,#0x800000` → `0x27160 bl 0x21190` | 置 bit55 |
| **跳过标 unbootable** | 同上标志非 0（首启/首次尝试） | `0x27108` 打印 `0xa9c67 "FirstBoot, skipping slot Unbootable"` → `0x2712c strb wzr,[0xd4b89]` | 不写 |

配套字符串（都在 ABL 里，构成完整状态机）：
`GetActiveSlot` / `SetActiveSlot` / `FindBootableSlot` / `HandleActiveSlotUnbootable` / `IsCurrentSlotBootable` /
`Slot %s is unbootable, trying alternate slot`(`0xa12e3`) / `No bootable slots found enter fastboot mode` /
`Reset unbootable slots failed enter fastboot mode`(`0xa9d6c`) / `Non Multi-slot: Unbootable entering fastboot mode`(`0xa48a2`) /
`A/B retry count NOT decremented`(`0xa4925`) / `Booting from slot (%s)`(`0xa288b`) /
`GetActiveSlot: found active slot %s, priority %d`(`0x9c1d5`)。

#### 2.5.3 `misc` 里的 BCB（**只放启动命令**）

实测（`dd if=/dev/block/by-name/misc bs=4096 count=1 | od`；`misc` = `/dev/block/sda3`，1 MiB = 2048×512 B，getvar `0x100000`）：

```
000000  00 00 00 00 00 00 00 00 2d 62 6f 6f 74 6c 6f 61
000010  64 65 72 00 00 00 00 00 00 00 00 00 00 00 00 00
（0x13 之后到 0xFFF 全零）
```
**整块 1 MiB 抽样核对**（扇区 0/1/2/64/128/200/255，`od -A n -t x1` 只输出 `*`）：**除上面这 11 字节外全零**，
⇒ **`misc` 里没有 AOSP `bootloader_message_ab` 的槽位副本**（偏移 2048 处也是零）。槽位状态的唯一存放地就是 GPT 属性（§2.5.1）。
即：`command` 字段（32 B，偏移 0）此刻**没有有效命令**，`0x08` 处残留 `-bootloader`（很可能是"进 bootloader"命令的残尾）。
ABL 侧的读写点：

| 功能 | 地址 | 行为 |
|---|---|---|
| `SetBootCommand(str)` | `0x6a300`（fastboot 侧 thunk `0x81458`） | 读 misc → 改 `command[32]` → 写回；失败打印 `0xa1784 "Error Reading from misc partition: %r"` / `0xa95e1 "Error in loading Data from misc partition"` |
| `GetBootCommand()` | `0x6a710` | 读 misc → `0x6a9ac strb wzr,[x9,#0x1f]`（`command[31]=0`）→ `0x6ab14 bl 0x21f4` memcmp(buf, `"boot-recovery"`@`0xa42a3`, strlen) / `0x6abb8` memcmp(buf, `"boot-fastboot"`@`0xaf0f6`, strlen) |
| `reboot-recovery` | `0x7ffdc` → `0x7fff0 x0=0xa42a3 "boot-recovery"` → `0x81458` | 写命令后复位 |
| `reboot-fastboot` | `0x80070` → `0x80080 x0=0xaf0f6 "boot-fastboot"` → `0x81458` | 同上 |

⇒ **`misc` 不是槽位数据库，是"下次从哪个模式起"的便签**。
想重置槽位状态：写 GPT 属性（需 9008），不是擦 `misc`。想进 recovery/fastboot：写 `misc` 的 `command`。

#### 2.5.4 `set_active` 的门槛（fastboot 侧）

`0x79c1c`（`set_active` handler）：
```
0x79c74 bl 0x69e0            ; 平台/分区表可用？
0x79c80 bl 0x2cf40           ; IsDeviceUnlocked()
0x79c88 b.eq 0x79ce8         ; 未解锁 → 0x79cf8 x0=0xabab0
                             ;   "Slot Change is not allowed in Lock State"
0x79ca4 bl 0x69960 ; cmp w0,#3 → 0x79d04   ; 快照 merging 状态检查
0x79d04 bl 0x811fc           ; 取参数
0x79d68 x0=0xa17ec           ; "set_active _a or _b should be entered"
0x79e78 x0=0xad199           ; "Invalid Slot Suffix"
```
真正干活的核心在 `0x25xxx`（`SetActiveSlot` 串在 `0x2517c / 0x253f8 / 0x2556c / 0x25710`），最终同样落到 `0x21190` 写 GPT。

#### 2.5.5 只读查询槽位状态的办法（不用刷机、不用 reboot）

| 手段 | 命令 | 返回 |
|---|---|---|
| 当前槽 | `adb shell getprop ro.boot.slot_suffix` | `_a`（实测） |
| **retry 计数** | `fastboot getvar slot-retry-count` | 变量确实存在（`0xabb96`，注册/分发在 `0x7d74c`） |
| **unbootable 位** | `fastboot getvar slot-unbootable` | 同上（`0xa1876`，`0x7d6b0`） |
| 槽位属性原始值 | `fastboot getvar all` + `oem device-info` | 见 `abl-cmd-surface\REPORT.md` §5 |
| 离线看 GPT 属性 | **root 下直接 `dd if=/dev/block/sde bs=1 skip=<8192+i*128+48> count=8 \| od`**（本轮就是这么取到 §2.5.1 的真机值）；或用本仓 `_scripts\gptattr.py` 解 `gpt_main4.bin`；或 9008 读 LUN4 头 34 扇区 | §2.5.1 的位域 |

### 2.6 当前机上状态（设备 USB 反复掉线，vbmeta 侧据台账 + 本地同源镜像）

| 项 | 值 | 依据 |
|---|---|---|
| 系统 | A17 / 澎湃 4.0（`release=17`、`sdk=37`） | `adb getprop`（本轮实测，掉线前） |
| `ro.boot.verifiedbootstate` / `veritymode` | `orange` / `eio` | 同上 |
| `ro.boot.slot_suffix` | `_a` | 同上 |
| `vbmeta_a` | 原厂 544（8192 B，RSA4096 `2597c218…`，chain→`cdbb7717…`） | 台账 2026-11-12 更正 + 本轮 `info_image` 复核文件 |
| `vbmeta_system_a` | `vbmeta_system_fix.img`（4096 B，RSA2048 `cdbb7717…`，3 条 hashtree，**无 FEC**，salt `00…01`） | 本轮 `info_image` 实测该文件 |
| 结果 | 可复现起桌面（product 的 hashtree 与数据自洽） | `docs\突破_A17可复现启动与根因_2026-11-13.md` |

---

## 3. 失败模式归纳（症状 → 机制 → 证据地址）

| # | 症状 | 机制 | 证据（分区 + 地址） |
|---|---|---|---|
| **1** | 刷自编 UEFI FD 到 `boot` 后**永久黑屏、USB 不出现、不复位** | **appended DTB 检查**：ABL 要求"内核后面最多一棵 FDT"。6 棵 FDT 的 blob 使 `p+totalsize` 处正好是第 2 棵 FDT 的 magic ⇒ 命中 `Not the single appended DTB` ⇒ 返回 `0x800000000000000E` ⇒ BootLinux 在 `0x7fc0` 直接返回，**`blr` 一次都没执行** | `boot_a` 镜像布局：`ImageBuffer+PageSize+out①`；`0xa950–0xa994 fdt_check_header(p)`；`0xaaa8 p2=p+totalsize`；`0xaab4 fdt_check_header(p2)`；`0xab54/0xab58` → 串 `0x9fb0d`；`0xab78 mov x8,#0xe`；调用点 `0x7fa4`，失败出口 `0x7fc0 b 0x8648`。实测：`0x800+950884=0xE8A64` 处即 FDT#1，`totalsize=0x443D1` |
| **2** | 校验失败但**照常启动**（解锁机） | AVB 只降级为警告：`unlocked==1` 时把 `{OK, ERROR_VERIFICATION, ERROR_ROLLBACK_INDEX, ERROR_PUBLIC_KEY_REJECTED}` 视为可继续 | `vbmeta_a` 消费链：`0x1c3f8 cset w23,ne`（flags bit0）→ `0x1c880 csel w27` → `0x1cd78 bl 0x608dc`（`avb_slot_verify`）→ `0x1cd8c tst w8,#0xff` + `0x1cd90 b.eq 0x1ce14`（未解锁 → 致命分支）→ `0x1cd94 cmp w27,#5` + `0x1cd9c bl 0x1f920`（掩码 `0x39`）→ **`0x1cdf0/0x1cdf4` 打印 `0xa63e0 "State: Unlocked, AvbSlotVerify returned %a, continue boot"`** → `0x1cdf8 str wzr,[sp,#0xc]` → `0x1cdfc b 0x1cf98` → 返回 0 |
| **3** | 载荷一进去就**静默挂死**，没有复位、没有打印 | ABL **没有异常向量表**（全 `.text` 零条 `msr vbar_el*`），且**正常启动路径完全不碰 WDT**（唯一 WDT 串在 fastboot 路径）⇒ `blr` 之后任何异常 = 原地打死；`blr` 之后 ABL 仍活在同一地址空间 | `boot_a`/FD：`0x862c blr x8`；`0x8634 bl 0x66ec`（只有"载荷返回"才会走到，返回 `0x8000000000000013`）；WDT 串 `0xa1812`（fastboot 专用）；无 VBAR 见 `abl-avb-semantics\REPORT.md` §5.1 |
| **4** | 起 ~20–35 s 后掉 **900E**（`05C6:900E`），fastbootd/recovery 全不可达 | 内核起来后 **dm-verity 失败 → init 退出（`exitcode=0x7f00` = 127 = ENOENT）→ `Attempted to kill init!` → panic → Qualcomm crash dump**。典型触发：`init_boot`（first-stage init）与 `system` 不配套 ⇒ init 去 exec 一个该版本里不存在的工具；或 product/system 的 hashtree 与数据不符 | 实测日志：`[2.174089] device-mapper: verity: 254:5: data block 0 is corrupted`、`[2.174785] Kernel panic - not syncing: Attempted to kill init! exitcode=0x00007f00`（`docs\取证_900E转储与A17崩溃根因_2026-11-13.md`）；转储目录 `forensics_900e\auto_20261113_114831\`；product 根哈希不符的离线复算见 `tools\verify_hashtree.py` |
| **5** | `fastboot boot` 返回 **unknown command** | 命令表里**根本没有 `boot`**（不是被条件屏蔽）：24 条静态 + 3 条条件 = 27 条，无 boot/boot-recovery/oem boot；且全二进制无"跳到下载缓冲"的指令 | 表基址 `0xb1e60`（条目 `0xb1e70`，`cmp x19,#0x180` = 24 条）；注册器 `0x7bea8`；分发器 `0x7a338`（无匹配 → `0x7a6e4` 串 `0xa36ee "unknown command"`）；条件注册 `0x7bbd0`（守卫 `0x8900` = super 存在）；**唯一**把控制权交给镜像的指令 `0x862c blr` |
| 6 | 想刷 `abl`/`xbl` 被拒 | **24 条 critical 分区白名单**，`flash:`/`erase:` 无条件检查（与锁定状态无关） | `IsPartitionCritical` `0x8026c`，表 `0xb2018`（UTF-16，24 条，含 `abl rpm tz sdi xbl hyp pmic bootloader devinfo partition devcfg ddr frp cdt cmnlib cmnlib64 keymaster mdtp aop multiimgoem secdata imagefv qupfw uefisecapp`）；检查点 `0x7c680`（flash）/`0x7dcd0`（erase）；串 `0xac7ea "Flashing is not allowed for Critical Partitions"` |
| 7 | `fastboot flashing unlock` 无效 | 表里**没有** `flashing unlock`，只有 `flashing lock` / `unlock_critical` / `lock_critical` / `get_unlock_ability`；唯一解锁入口是 `oem unlock`（前缀匹配 `oem unlock-go`），需要 356 B Lenovo 令牌 | 表项见 §2.1；`0x7c4c0 cmp x22,#0x164`（=356）；令牌魔数 `0x9a6a7 "1a2blenovo3c4d5e"`；校验函数 `0x85214`（串 `verify_oem_unlock: MAGIC/VERSION/algo_type/check sha256(sn)/verify_signature`） |
| 8 | 改了 `boot` 却"没生效" | ABL 只从**当前槽**的 `boot_<slot>` 读；切槽写的是 GPT 属性 | `0x202d0` 一族读属性；`set_active` handler `0x79c1c`；写回 `0x21190` |
| 9 | 刷完 `vbmeta` 反而开不了机 | `vbmeta` 分区 64 KiB、文件 8 KiB（flags=0）；用 64 KiB 版（flags=2）会导致链式/描述符口径不一致 | `vbmeta_a` 分区 `0x10000`（getvar）；原厂文件 8192 B；`vbmeta_system` 4096 B |
| 10 | 屏全黑但"可能只是没显示" | `splash` 区在 `0x5C000000+0xF00000`（已被原厂 dtbo overlay 证实），XBL 用 `EnableDisplayThread=1` 并行初始化；ABL 里 `Splash region not found in device tree, powering down the display and controller` 会把显示**关掉** | `zui17_images\dtbo.img` fragment@30 `cont_splash_region`；ABL 串族见 `abl-hang-analysis\REPORT.md` §6.4；XBL `uefiplat.cfg` |

---

## 4. 空白与未知（明确列出，附"要补需要什么手段"）

| # | 还不知道什么 | 为什么现在拿不到 | 补它需要什么 |
|---|---|---|---|
| 1 | **XBL 的算法主体**（`0xC0000–0x28FFFF`，≈1.7 MiB，熵 7.98） | 高熵加密/压缩段，静态无解；可读部分只占 2.50% | ① 厂商内部明文（不可得）；② **运行时抓**：9008 dump 运行中的 XBL 内存段（`0x45E00000` 区 XBL AOP / `0x5FC00000` UEFI FD 都是已知地址）；③ 读 `xbl_config` 里的配置 DT |
| 2 | **PBL 的验签细节**（用什么算法、验哪些段、失败后具体走哪条路） | PBL 在 SoC mask ROM 里，**不在任何分区**，无法 dump | 只能靠**外部资料/熔丝表**推断；或用 9008 观察"改坏 XBL 后落到什么模式"（破坏性实验，不建议） |
| 3 | **谁写 `KernelBaseAddr` / `KernelSize` 这两个 UEFI 变量** | 变量名在 XBL 可读区 **0 命中**；ABL 只读不写 | ① 9008 读 `uefivarstore`（512 KiB，`partition-size:uefivarstore: 0x80000`）里的变量条目；② 读 `logfs` 里的 ABL 打印 `Kernel Load Address: 0x%x`（但见 #4） |
| 4 | **ABL 的运行时日志**（`Device unlocked: %a`、`Kernel Load Address`、`Single appended DTB found`、`Selecting Panel:`） | XBL 的 `uefiplat.cfg` 明确写 **`EnableLogFsSyncInRetail = 0x0`** ⇒ retail 下日志不同步到 `logfs`；ABL 也没有任何 `getvar` 暴露日志（`logfs`/`last_log`/`abl_log`/`memlog` 在 ABL 里零命中） | **UART**（`ttyMSM0`，115200n8 —— `vendor_boot` 的 cmdline 里就有 `console=ttyMSM0`）或 **拆机找测试点**；软件侧唯一替代是"屏上探针"（`abl-hang-analysis\REPORT.md` §9 的 E0：在载荷第一行直接写 `0x5C000000`，二值化判读） |
| 5 | **display splash 到底由谁扫描输出**（XBL 的 `GraphicsConsoleDxe`？`SimpleFbDxe`？还是 ABL 的 splash 代码？） | 三处都有嫌疑：XBL 有 `EnableDisplayThread=1` + `SimpleFbDxe`（`fd-audit` 已证实驱动在 Mu 的 FV 里、出厂 FV 里也有）；ABL 有整套 splash 字符串；dtbo 里有 `cont_splash_region` | ① 反汇编 ABL 的 splash 函数族（有字符串锚点，可做）；② 屏上探针实验（在 FD 第一行直接写 `0x5C000000`，二值化判读）；③ UART 看 `Selecting Panel:` |
| 6 | **`SecurityFlag = 0xC4` 是否意味着安全启动真的关着** | 位定义注释里 `SecBootEnableFlag = 0x1` 未置位（0xC4 = 0x80 LoadKeymaster + 0x40 LoadSecApp + 0x04 CommonMbn），但 `getvar` 报 `secure: yes`，两者口径不同；熔丝状态未知 | 9008 读熔丝/OEM PK hash 区；或读 `devinfo`（4 KiB，`partition-size:devinfo: 0x1000`）里的解锁/安全位 |
| 7 | **`misc` 里 `0x08` 处 `-bootloader` 的来源** | 整块 1 MiB 已抽样确认**除这 11 字节外全零**（§2.5.3），但 ABL 里没有 `-bootloader` 这个独立字符串（只在 `reboot-bootloader` / `version-bootloader` 里作为子串），所以它不是 ABL 写的 —— 疑为出厂/Lenovo 工具留下的残尾 | 若要追：`dd` 整块做完整非零扫描（本轮只抽样 7 个扇区）；或对比 9008 回刷后的 `misc` 是否同样带这 11 字节（可判定"出厂就有的"还是"某次操作留下的"） |
| 8 | **`super` 内 7 个逻辑分区 footer 的 algorithm/salt** | `avbtool info_image` 要读整份镜像（system 5.4 GB / product 594 MB），本轮只跑了 boot/init_boot/dtbo/vendor_boot/recovery | 逐个小镜像跑（`super_3/4/6.img` 已是各逻辑分区 RAW，可直接跑）；或只读尾部 64 KiB 手工解 footer |
| 9 | **`0x5FC00000` 在 ABL 运行时是否仍被 XBL 的 UEFI 占用** | 只能证明 XBL 的 ELF 声明了这段 PT_LOAD；运行时是否已释放/搬迁未知 | 9008 dump `0x5FC00000`（掉线前/后各一次）看是否非零；或换基址重编 FD 做 A/B |
| 10 | **`xbl_config_a`（`0x20000`）的内容** | 只看了 `xbl.img`；`xbl_config.elf` 43,056 B 未解析 | 直接解析（QCOM ELF，明文概率高），里面应有内存/时钟/PMIC 配置 |

---

## 5. 复现与产物

### 5.1 本轮新脚本（`E:\rom\work\bootchain-profile\_scripts\`）

| 脚本 | 用途 |
|---|---|
| `s.py "字符串"` | 在 ABL 里定位字符串 VA + 全量 `adrp+add`/`adrp+ldr` 交叉引用 |
| `r.py out.txt start end …` | 按区间直接线性反汇编（避免全局扫描失步），落盘 |
| `bits.py start end` | 列出区间内所有 64 位掩码的位域操作（`and/orr/bfi/ubfx/tst`）—— §2.5 的位域就是这么解的 |
| `strva.py` / `strva2.py` | 按 VA 打印 ASCII 串（前者针对 ABL PE，后者任意文件） |
| `xbl.py` / `xbl2.py` | QCOM ELF 布局 + 逐 64 KiB 熵/可打印比 + 可读串 + 关键字命中 |
| `fvlist.py <file> <off>` | FV 头逐字段校验（EDK2 16 位截断累加）+ FFS 链（含 PAD）+ UI 段 |
| `gptattr.py <gpt_mainN.bin> [名字…]` | 解 GPT 条目并**按 §2.5.1 位域翻译 attributes** |
| `bh.py` | 解析 Android boot header v0–2 / v3–v4 |
| `tk.sh` / `tk2.sh` | 用 avbtool 导出 testkey 公钥并算 sha1（§2.3 的证明） |

### 5.2 关键复现命令

```powershell
# 1) vbmeta 全描述符
python E:\rom\work\tools\avbtool.py info_image --image "E:\rom\TB331FC\刷机包\TB331FC_ZUI_16.0.544\image\vbmeta.img"
python E:\rom\work\tools\avbtool.py info_image --image "E:\rom\TB331FC\刷机包\TB331FC_ZUI_16.0.544\image\vbmeta_system.img"

# 2) 证明 AVB 用的是公开 testkey
wsl -d ub -u root -- bash /mnt/e/rom/work/bootchain-profile/_scripts/tk2.sh
#   期望：tk4 1032 B sha1 2597c218…f011 / tk2 520 B sha1 cdbb7717…617d

# 3) XBL 里的 UEFI FV（4 个 FFS、校验和 VALID）
wsl -d ub -u root -- python3 /mnt/e/rom/work/bootchain-profile/_scripts/fvlist.py /mnt/e/rom/work/zui17_images/xbl.img 0x7d4b0

# 4) 出厂 GPT 的槽位属性（全零）
python E:\rom\work\bootchain-profile\_scripts\gptattr.py "E:\rom\TB331FC\刷机包\TB331FC_ZUI_16.0.544\image\gpt_main4.bin" boot_a boot_b

# 5) 槽位位域 / retry 递减 / unbootable 的写入点
wsl -d ub -u root -- python3 /mnt/e/rom/work/bootchain-profile/_scripts/r.py /tmp/a.txt 0x202b0 0x20430 0x27a80 0x27e40 0x270f0 0x271a0
```

### 5.3 落盘的反汇编（`_d\`）

`misc.txt` `misc2.txt` `setbootcmd.txt` `setboot2.txt` `rebootcmd.txt` `slots.txt` `attr.txt` `prio.txt` `retry.txt` `unboot.txt` `wr.txt` `setactive.txt` `slotstr.txt` `spot.txt` `xbl.txt`

### 5.4 本轮未完成 / 受限

1. **设备的 USB 反复掉线**（`adb devices` 里时有时无，掉线时只剩 `SM_R880` 手表）。已抢到的现场数据：
   `misc` 首 4 KiB 的 BCB 内容 + 整块 1 MiB 的 7 扇区抽样（§2.5.3）、**LUN4 上 `boot_a`/`boot_b` 的 GPT 属性（§2.5.1，决定性）**、
   `misc` 分区大小 1 MiB（`sda3` = 2048×512）、`getprop` 的启动状态。
   没抢到的：**整份 1 MiB `misc` 的逐字节非零扫描**（只抽样 7 个扇区）、
   以及现场复核当前 `vbmeta_a` / `vbmeta_system_a` 的内容（用的是台账 + 本地同源镜像）。
2. `super` 内 7 个逻辑分区的 footer 未逐个 `info_image`（体积原因，见 §4 #8）。
3. XBL 加密段、PBL、`xbl_config` 未触及（见 §4 #1/#2/#10）。

---

## 6. 给刷机/移植的三条"最要紧"

1. **AVB 不是门槛，`appended DTB` 才是。** 整条链用的是 AOSP 公开 testkey（`2597c218…` / `cdbb7717…`，本轮已用本地 pem 复算证明），随便重签都能过；但 ABL 在 `0x7fa4` 之后会拒绝"内核后面跟了不止一棵 FDT"（`0xab58`），失败时**连一条载荷指令都不执行**。任何往 `boot` 塞自编镜像的实验，第一件事是把 DTB 压成单棵。
2. **槽位状态活在 GPT 属性里（bits48–55），不在 `misc`。** 真机实测：`boot_a` attr = `0x0077000000000000`（priority 3 / active 1 / retry 6 / successful 1）、`boot_b` = `0x0022000000000000`（priority 2 / active 0 / retry 4）。
   这意味着：擦 `misc` 不会重置 retry/unbootable；而**刷回原厂 GPT（含 9008 整包）会把槽位状态归零**，下次启动走"First boot: set default slot _a"（`0x203c0`）。反过来，`fastboot getvar slot-retry-count` / `slot-unbootable` 是不刷机就能读状态的两个只读窗口。
3. **UEFI 在 XBL 里，ABL 只是它的一个应用。** 所以：(a) 想让 ABL 接受自己的载荷，改 `abl` 就够，不必碰 XBL；(b) 但 `abl`/`xbl` 都在 24 条 critical 白名单里，fastboot 一律拒刷，只能 9008；(c) 自编 FD 的基址 `0x5FC00000` 恰好是 XBL 自己那份 UEFI FV 的装载地址（`xbl.img` ph16），这很可能就是"三版全黑"的真正原因，值得优先验证。
