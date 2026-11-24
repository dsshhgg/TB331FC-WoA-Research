# 更正清单（CORRECTIONS）

> 本轮推翻了 **43 条**旧结论。每条给「**旧说法 → 现证据 → 正确结论**」三段。
> 证据一律给原始地址/偏移/哈希，不给"摘要转述"。
>
> 编号说明：本文按**主题分组**编号 `C-01…C-43`；[`PANORAMA.md`](PANORAMA.md) §6 按**领域顺序**编号 `F-01…F-43`。
> 两份清单覆盖**同一批 43 条**，但编号顺序不同（例如"解锁会弄坏 TEE"在本文是 `C-21`、在 PANORAMA 是 `F41`）。
> 需要精确交叉引用时，以段落标题里的关键词为准。

**影响面标记**：🔴 = 会改变下一步动作 · 🟡 = 会改变判断/优先级 · ⚪ = 记录一致性，不影响动作。

---

## 一、XBL / UEFI（C-01 … C-06）

### C-01 🔴 改 XBL 需要 OEM 解密 key —— 错，没有加密层

| | |
|---|---|
| **旧说法** | `bootchain-profile\REPORT.md` §518：「XBL 的算法主体（`0xC0000–0x28FFFF`，≈1.7 MB，熵 7.98）**高熵加密/压缩段，静态无解**」 |
| **现证据** | 唯一高熵带（逐 64 KB 熵 7.96–7.98）**完全落在 ph16 之内**，是 FFS `9e21fd93-9c72-4c15-8c4b-e77f1db2d792` 的 GUIDed 段（GUID `1d301fe9-be79-4353-91c2-d23bc959ae0c`，`DataOffset=0x18`，`Attributes=0x1` PROCESSING_REQUIRED），载荷首字节 **`1f 8b 08 00` = gzip**。`zlib` 一条命令解出 **6,631,112 B**，得到一个结构完全合法的 DXE 固件卷（`FvLength=0x652EC0`、`FvName=631008b0-…`、**102 个 FFS 全部头校验成立**）。其余所有段熵在 2.2–6.8 → `xbl` §1.1/§1.2 |
| **正确结论** | 这份 `xbl.img` **没有任何加密段**，102 个 UEFI 驱动已解到可读。真正拦住改动的是**签名**（`ph1` 的 hash/cert 段 + PBL 熔丝根哈希），不是密码学。"没有 OEM key 所以静态无解"这个前提在本板子上不成立。可反汇编、可读全部配置/字符串/驱动；不可改后刷回 |

### C-02 🟡 ZeroVector 是 `4c 33 00 14`（L3 魔数）⇒ FV 头校验和不成立 —— 错

| | |
|---|---|
| **旧说法** | `bds-chainload\REPORT.md` §1：「ZeroVector 前 4 字节是 QCOM 的 `4c 33 00 14`（"L3" 魔数），因此 FV 头校验和**不成立**」 |
| **现证据** | `0x1400334c` 是标准 AArch64 `b` 指令 ⇒ `b +0xCD30`，目标 `0x5FC0CD30`，**逐位等于** SEC TE 的 `ImageBase 0x5FC01000 + AddressOfEntryPoint 0xBD30`。且**FV 头校验和是成立的**：按 EDK2 的 16 位截断累加实算 `sum=0x67a9` → 需要 `0x9857`，文件里正是 `0x9857` → `xbl` §0.3、`x12_fdhdr.py` |
| **正确结论** | ZeroVector 是**正确的分支指令**（跳到 SEC 入口），FV 头校验和**成立**。这条旧结论把一条正常的 AArch64 指令误读成"魔数"，进而错误推断"这个 FV 结构不合法" |

### C-03 🔴 `SecBootEnableFlag = 0x1` ⇒ 安全启动使能 —— 错，那是注释行

| | |
|---|---|
| **旧说法** | `bootchain-profile` / `bds-chainload` 两份报告均引用 `SecBootEnableFlag = 0x1`，据此说"安全启动使能" |
| **现证据** | `cfg\FD_uefiplat.cfg:136` 那一行的原文是 **`# SecBootEnableFlag = 0x1 i.e. 0b00000001`** —— 是**注释**。真正的值是 **`SecurityFlag = 0xC4`**（`0b1100_0100`）：bit0 `SecBootEnableFlag` = **0**、bit2 `CommonMbnLoadFlag` = 1、bit6 `LoadSecAppFlag` = 1、bit7 `LoadKeymasterFlag` = 1 → `xbl` §0.3 #3、§3.3 |
| **正确结论** | `SecurityFlag = 0xC4`，**bit0 = 0**。而且这是 **UEFI 侧**的开关；PBL/TZ 对 XBL/ABL 的签名校验由硬件与 fuse 决定，**不受它影响**。旧说法既读错字段又高估了它的作用域 |

### C-04 🔴 插 U 盘让 BDS 引导是可用备选 —— 错，没有驱动支撑

| | |
|---|---|
| **旧说法** | `bds-chainload\REPORT.md` §6.3 Step 4 把"插 U 盘让 BDS 引导"列为备用方案 |
| **现证据** | DXE 卷 102 个模块里 `UsbKb` / `UsbMouse` / `Xhci` 字符串**零命中**；**没有任何模块包含 `EFI_USB_HC_PROTOCOL`(2f707ebb) 或 `EFI_USB2_HC_PROTOCOL`(240a86d8) 的 GUID**。唯一出现 `EFI_USB_IO_PROTOCOL`(2b2f68d6) 的模块是 **QcomBds（消费者）**；`UsbConfigDxe` 只做控制器时钟/PHY 初始化（`Usb30InitHost`/`SynopsysInitHostConfigSec`）→ `xbl` §4.1/§5.5 |
| **正确结论** | **生产者不存在 ⇒ 消费者永远取不到设备。** BDS 的 USB-first 窗口默认停 **30 秒**（`BootUsbFirstDelayValue` 缺省 `0x1E`），在零售固件里**永远等不到设备**，纯粹把开机拖慢。"插 U 盘"不是可用备选；载体只能用内部 FAT16 卷（`modem_a` sde4 / `bluetooth_a` sde5） |

### C-05 🟡 BDS 有按键菜单 / 热键入口 —— 错（四条独立证据）

| | |
|---|---|
| **旧说法** | 假设 `BDS_Menu.cfg` 里的菜单（`Boot USB First` / `Provision RPMB` / `Enter Shell`…）能被调用 |
| **现证据** | ① 这些串**只出现在 `BDS_Menu.cfg`（FFS #79）内部**，102 个可执行模块里一个都没有（`x06_strscan.py`）；② `QcomBds.efi` 全文对 `BDS_Menu`（ASCII/UTF-16）**0 命中**，对其 FFS GUID `a91d838e-a5fa-4138-825d-455e2303079e` 也 **0 命中**（对比 `DefaultBDSBootApp`@0x13705、`DefaultChargerApp`@0x17BFC 都能命中）；③ 键盘只有两处引用：`SimpleTextInput` 2 处（`0xEDF8`/`0xEFD4`，**控制台重建**）、`SimpleTextInputEx` 1 处（`0x34D8`，**按任意键关机**）——**没有"StartTimer + WaitForEvent → 按键进菜单"的代码**；④ `APPLICATION` 型只有 `QcomChargerApp` 一个，没有 Shell/BootManagerMenu/UiApp → `xbl` §5.4 |
| **正确结论** | **BDS 里没有任何按键菜单。** `BDS_Menu.cfg` 只是躺在卷里的死数据；`EnableShell=0x1` 空转（卷里没有 Shell）。**真正会吃按键的是 ABL（LinuxLoader）。** 任何"进菜单改 SecureBoot/EDL/BootUSBFirst"的设想在此固件上不成立 |

### C-06 ⚪ 改 `DefaultBDSBootApp` 可以换启动目标 —— 错（复核维持）

| | |
|---|---|
| **旧说法** | 通过改 cfg 里的 `DefaultBDSBootApp` 指向别的东西来实现"BDS 引导我们的镜像" |
| **现证据** | ① 它**不是路径**，是"在某个 **guided FV** 里按 UI 名找 app"的名字，FV 由固件常量 `046fae99-cf2e-49ed-a6a8-a1488b7e80d3` 指定，而那个 FV 只来自 `abl` 分区；② cfg 在**签名固件**里，改不了；③ 它解析不到 FAT 上的 `.efi`（只有充电 app 走 `fv1:\QcomChargerApp` 的**路径**机制）→ `xbl` §5.2 |
| **正确结论** | 前序报告"改 `DefaultBDSBootApp` 不可行"**成立**。且要注意两者机制不同：默认启动 app 走 **guided FV + UI 名**，充电 app 走**文件路径** |

---

## 二、ABL / 启动决策（C-07 … C-14）

### C-07 ⚪ `BootLinux` 的入口是 `0x6a34` —— 错，是 `0x6a30`

| | |
|---|---|
| **旧说法** | 上一份报告写 `BootLinux` 入口 `0x6a34` |
| **现证据** | `0x6a30` 是 `stp x29,x30,[sp,#-0x10]!`（函数第一条指令，即 prologue）；`0x6a34` 只是函数体第二条指令。两个调用点 `0x7f178`、`0x97d18` 都 `bl 0x6a30` → `abl` 头部注、§5 |
| **正确结论** | 入口 **`0x6a30`**。`0x6a34` 是 `+4` 的偏移，按它取地址会在 prologue 之后进入，读到的栈布局是错的 |

### C-08 🔴 走到 `0x8634` 会"返回错误码" —— 错，是 `CpuDeadLoop` 卡死

| | |
|---|---|
| **旧说法** | `0x8634` 是"通用失败尾"，返回 `0x8000000000000013` |
| **现证据** | `0x8634` 先 `bl 0x66ec`，而 `0x66ec` 是 **`CpuDeadLoop()`**（`str xzr,[sp]` / `ldr x8,[sp]` / `cbz x8,自身`）。后面那条 `return 0x8000000000000013` **不可达** → `abl` §0 |
| **正确结论** | 走到 `0x8634` 的分支表现为**卡死不重启**（屏幕冻结、CPU 停住、不自动重启）。"它会返回一个错误码然后继续"是错的，会误导排障方向（不去查"为什么挂死"而去查"错误码被谁吃了"） |

### C-09 🔴 载荷从入口 `ret` 返回后 ABL 会恢复 fastboot —— 错

| | |
|---|---|
| **旧说法** | 如果我们的 payload 执行完返回，ABL 会继续跑、回到 fastboot |
| **现证据** | 同一条尾也接在 `blr` 之后：`0x862c blr x8` → `0x8630 b 0x8634` → `CpuDeadLoop` → `abl` §0 |
| **正确结论** | **载荷即使 `ret` 返回，ABL 也是死循环。** 所以"让 payload 跑完返回来看反应"这种实验设计不成立——返回 = 挂死，无法区分"跑完了"与"挂了" |

### C-10 🔴「ABL 用 `recovery_a`」—— 错，用当前活跃槽

| | |
|---|---|
| **旧说法** | ABL 固定读 `recovery_a`，所以刷 `recovery_b` 无所谓 |
| **现证据** | ① 名字表（`0xafdf0` 起 6 项）全是**无后缀基名**：`boot` / `dtbo` / `vbmeta` / **`recovery`** / `vendor_boot` / `init_boot`；② 槽后缀 `_a`/`_b` 在 `0xafe20` 起 **UTF-16**，共 6 份，六处代码各自内联一对（`0x1fbe0+4c`→`0xafe44`、`0x24e28`→`0xafe20`、`0x25088`→`0xafe2c`、`0x26e38`→`0xafe38`、`0x2bb5c`→`0xafe50`、`0x34080`→`0xafe5c`）；③ 槽本身由 **UFS boot LUN** 决定（`GetACtiveSlot: ufs device boot lun is %x, select active slot %s`），首启默认 `_a`；④ 表内键名由 `Info+0x06`（上游填的**基名**）决定，槽解析发生在 `0x1c234 LoadPartitionImageHeader`（失败串 `ERROR: Can not determine slot suffix`）→ `dual` FLASH-PLAN §3、`abl` §2.4 |
| **正确结论** | **用当前活跃槽**（`recovery_a` / `recovery_b`）。`current-slot=a` 时刷 `recovery_b` 后 `reboot-recovery` **预期仍是原厂 recovery**。要验证外来 ramdisk 必须写 `recovery_a`（或先 `--set-active=b`）。**反证条件**：若刷 `recovery_b` 后进了 OF，则此结论被推翻（这是零风险的证伪实验） |

### C-11 🔴「recovery 分区这条路死了」（因为 OF/TWRP 进不去）—— 结论下早了

| | |
|---|---|
| **旧说法** | 多轮刷 TWRP/OF 都回 fastboot ⇒ `recovery` 分区这条路是死路 |
| **现证据** | 本机原厂 `recovery.img` 是 **`ANDROID!` v4、`kernel_size=0`、ramdisk ≈14.57 MB** 的**纯 ramdisk 形态**。历史上往 `recovery_a/b` 刷的是 TWRP/OF 的**完整 boot 镜像**（`kernel≠0`，如 `of\v3\recovery_of_tb331fc_v3.img` 是 kernel 43,092,480 + ramdisk 47,627,143）。本机 ABL 的 recovery 语义是「**内核永远来自 `boot`，`recovery` 只提供 ramdisk**」——因为 `recovery` 里根本没有内核可跳。且 `0x1b0d8` 起有 `kernel_size==0 ? "Recovery partition has no kernel" : 直通` 的分叉 → `dual` §1.4、`abl` §2.3 |
| **正确结论** | **"OF 进不去"并不能推出"这条路死了"，因为从没按本机要求的形态（`kernel_size=0`、只有 ramdisk）试过。** 这是本轮最重要的可执行新发现。已逐一证伪的"解释"（对齐 stock 头 / `flags=3` / 全哈希重算 / 改 1 bit / `alg=NONE` / 塞进 boot 分区 / 降级 ZUI15 abl）都动的是**头与签名**，没动**形态** → `ofrec` §0.2 |

### C-12 🔴「开机时按键选 Android / recovery」—— 做不到

| | |
|---|---|
| **旧说法** | 用 A/B 槽 + 按键，在开机时选进 Android 还是 recovery |
| **现证据** | ABL 里**没有任何按键扫描→菜单逻辑**；镜像里**没有 `bootonce` 这个字串**（全表检索 0 命中）；`QcomBds` 的 UTF-16 变量表逐条枚举也没有 bootonce 语义。ABL 在 `command[32]` 上只认 `boot-recovery` / `boot-fastboot` 两个字面量 → `dual` §7、`abl` §3、`small` §3.2 |
| **正确结论** | **选择只能发生在"关机前"**（Android 侧脚本 / fastboot 里），或由自写的引导内核提供。`bootonce-*` 这类"一次性启动"**不被 ABL 支持**，别指望它。BDS 那层也没有菜单（C-05） |

### C-13 🟡 用 `bootctl` 在 Android 侧切槽 —— 不存在这个二进制

| | |
|---|---|
| **旧说法** | 用 AOSP 的 `bootctl set-active` 在 Android 里切槽 |
| **现证据** | 原厂 system 镜像里 **`/bin/bootctl` 不存在**（`debugfs` 列目录 `chk_bootctl.sh` → `File not found`）→ `dual` §1.5 |
| **正确结论** | 只能在 fastboot 里 `--set-active`，或手写 `misc` 槽元数据（不推荐） |

### C-14 🟡 b 槽可以跑第二套 Android —— 不能

| | |
|---|---|
| **旧说法** | `*_b` 是"真备份"，可以用 b 槽跑第二套 Android 做双系统 |
| **现证据** | `super`（12 GiB / 3,145,728 扇区 × 4096）LP 元数据实测：`system_a`/`system_ext_a`/`product_a`/`vendor_a`/`vendor_dlkm_a`/`system_dlkm_a`/`odm_a` 有数据，**7 个 `*_b` extents = 0**。LP magic 在 `0x3000`（不是 `0x2000`）→ `ofrec` §0.1/§3.2、`dual` §7 |
| **正确结论** | **b 槽永远不可能跑 Android**；b 只适合放"恢复环境 / 独立内核"。而且 b 槽现在是个坑（见 C-35） |

---

## 三、分区与小分区（C-15 … C-18）

### C-15 🔴「`fastboot erase misc` 被 critical 拦住了」—— 错，它会被允许

| | |
|---|---|
| **旧说法** | `misc` 在 critical 白名单里，所以 `fastboot erase misc` 被拒 |
| **现证据** | ABL 有**两张不同的表**（→ `abl` §4、`small` §0-C4）：<br>**critical 表**（`0xb2018`，`cmp x21,#0xc0` ⇒ **24 项**）：`abl rpm tz sdi xbl hyp pmic bootloader devinfo partition devcfg ddr frp cdt cmnlib cmnlib64 keymaster mdtp aop multiimgoem secdata imagefv qupfw uefisecapp` —— **任何状态都拒**；<br>**锁态表**（`0xb20d8`，`cmp x21,#0x18` ⇒ **3 项**）：`misc metadata userdata` —— `0x802d4` 判定，前置条件 `0x69960()` 的返回值 `(v & 0xfffffffe) == 2`（bootmode ∈ {2,3}），**只在锁定时拒**。<br>`misc` **只在锁态表里**，本机 `unlocked: yes` ⇒ 会被允许 |
| **正确结论** | 「不能用」不是策略事实。真正不用的理由是它**一次抹整块 1 MiB**，会连带毁掉 `misc+0x8000` 的 15 B 厂商状态（FFBM / virtual-A/B 消息暂存）以及 BCB 取证价值。**要清就只写 `[0,4096)` 全零**（等价于只清 `command[32]`） |

### C-16 🔴「槽元数据在 `misc+2048`（AOSP `bootloader_control`）」—— 错，本机没有

| | |
|---|---|
| **旧说法** | AOSP 的 `bootloader_control` 结构在 `misc+2048`，改槽就改那里 |
| **现证据** | 全量 1 MiB dump（`misc_full.bin`，sha256 `45E7A829…87FC`）实测：`misc+0x800` 起至 `misc+0x7FFF` **全零**；全 1 MiB 搜不到 magic `BLLT`/`0x424C4C54`，也搜不到 `boot-recovery` / `boot-fastboot` / `_a` / `_b` / `recovery` 任何字面 → `small` §0-C2/§3.1/§3.4 |
| **正确结论** | **本机 `misc` 里没有 AOSP slot 元数据。** 而 `getvar` 历史读数（`current-slot:a` / `slot-successful:a=yes` / `slot-retry-count:a=6`）是**有效**的 ⇒ 槽状态在别处（`uefivarstore` 或 `devinfo`），或者"全零 = 出厂态 = 命中首次启动初始化分支"（ABL 默认选 a）。**改槽请用 `fastboot --set-active=a`**（ABL 命令表里 `set_active` 是真命令 `0x79c1c`），别去手改 misc |

### C-17 🔴「`devinfo` 的 `is_unlocked` 在 `0x10`」—— 错，在 `+0x0D`

| | |
|---|---|
| **旧说法** | `devinfo+0x10` 是解锁位（有人据此把 `0x90=0x01` 当成"已解锁"的证据） |
| **现证据** | ABL 写盘函数的**指令级**证据（→ `small` §4.2）：`0x2dc20 strb w8,[x1,#0xd]`（is_unlocked → **+0x0D**）、`0x2dd90 strb w8,[x1,#0xe]`（is_unlock_critical → **+0x0E**）、`0x2d770 strb w8,[x1,#0x90]`（**verity_mode → +0x90**）、`0x2e648 strb w0(=1),[x1,#0x90]`（verity_mode 初始化 = 1）。全量 dump（4 KiB，仅 14 个非零字节）：`0x00..0x0C = "ANDROID-BOOT!"`、`0x0D=0x00`、`0x0E=0x00`、**`0x90=0x01`** |
| **正确结论** | `is_unlocked` = **`+0x0D`**、`is_unlock_critical` = **`+0x0E`**、**`+0x90` 是 `verity_mode`**（值 1 是初始化默认值，与 dump 吻合）。你看到的 `0x90=0x01` **不是**"已解锁"的证据。**别去改它**（`0x2d764` 那条路径会在需要时重写；改错会让 `ro.boot.veritymode` 变化 → 影响 AVB/dm-verity → 起不来） |

### C-18 🟡「读出 `devinfo+0x0D=0` 却已解锁」是矛盾 —— 不是矛盾，是读错了地方

| | |
|---|---|
| **旧说法** | 分区里解锁位是 0，但 `unlocked: yes` ⇒ 数据与状态不一致，说明哪里坏了 |
| **现证据** | ① 初始化函数 `0x2e5f4 bl 0x13230` 的返回值**一步同时决定** is_unlocked / is_unlock_critical（`0x2e5fc cbz w8, 0x2e61c` → 写 1,1；否则写 0,0），而 `0x13230` 是 `gBS->LocateProtocol(GUID {8E5EFF91-21B6-47D3-AF2B-C15A01E020EC})` —— **向固件/安全侧问状态**，不是读分区字节；② 三个写函数都是**幂等**的（先 `bl` getter，`subs` 比当前值，相等就 `ret`：`0x2dc0c`/`0x2dd7c`/`0x2d75c`），且比较发生在"全局 vs 全局"之间，所以**永远不会触发补写**；③ Lenovo 的 `oem unlock-go` 令牌是 **356 B + 头 `1a2blenovo3c4d5e`、只在 RAM**（`0xe9e5a`），没有"顺手把 devinfo 置 1"的证据 → `small` §4.3 |
| **正确结论** | `verifiedbootstate=orange` 的权威来源是**固件/硬件侧**（`0x13230` 那条 LocateProtocol 链）+ TZ 的 `qsee_get_secure_state`，**不是 `devinfo+0x0D` 那个字节**。devinfo 的 `+0x0D/+0x0E` 只是**镜像**，镜像没跟着更新也不会影响 `unlocked: yes`。可上机复核：`fastboot oem device-info` 会打印 ABL 自己算的 `Device unlocked:`（读全局，不读分区） |

---

## 四、TEE（C-19 … C-21）

### C-19 🔴「`cmnlib` 全零是故障，要修」—— 错，是正常态且物理上不可能承载

| | |
|---|---|
| **旧说法** | `cmnlib_a/b`、`cmnlib64_a/b` 全零 = TEE 缺件 = 卡顿/异常的原因，应该想办法补回去 |
| **现证据** | **单体 QSEE**：`tz.mbn`（3,514,087 B）在文件偏移 `0x205000` 有一张 `embed_images` 清单（359 B），声明 3 个内嵌镜像并映射到自己的 LOAD 段：`cmnlib`@`0x10301000` size `0x6a000`（段 filesz 合计 430,552）、`cmnlib64`@`0x1036b000` size `0x87000`（546,640）、`qwes`@`0x103f2000` size `0x63000`（392,180）；`0x103f2000 + 0x63000 = 0x10455000` **正好等于 HASH 段 vaddr** ⇒ 首尾相接填满无缝隙。每项后面跟 `none`（无外部来源/无分区名），与 `rawprogram4.xml` 里 `filename=""` 完全对应。<br>**硬证**：`cmnlib64_a` 槽位只有 128×4096 = **524,288 B**，而内嵌 cmnlib64 段合计 **546,640 B**（含对齐 552,960）⇒ **物理上装不下**。<br>`rawprogram4.xml`/`partition.xml` 全 `filename=""`、GPT attr `bit60 read-only`、ZUI16/17 两版镜像集里都**没有 `cmnlib*.mbn`**。<br>运行时 TZ 是活的：`qsee_version = 0x1402000`、FBE 已解锁、`IKeyMintDevice/default` 在服务、keystore 里有 73 个 key → `tee` §1.4/§2.2、`small` §6.1 |
| **正确结论** | **`cmnlib`/`cmnlib64` 在本平台是 `tz.mbn` 的一部分**（`embed_images = 3`，逐段对齐误差 0），分区上的 512 KB 槽位是**遗留几何，从来没写过内容**。全零是**正常态**，不是故障，也不是 TEE 卡顿的原因。黄金校验值：全零 md5 = **`59071590099d21dd439896592338bf95`**（若哪天它们**有**内容，反而说明 tz 换成分体版本了）。**绝不为了"修 cmnlib"写那 4 个分区**——没有镜像、没有收益，只有给未来构建埋雷 |

### C-20 🟡「`Failure in cmnlib_init(): %u` 说明 TZ 载入 cmnlib 失败」—— 错

| | |
|---|---|
| **旧说法** | 镜里有这条串 ⇒ TZ 要载入 cmnlib 但失败了 ⇒ cmnlib 分区全零就是它缺的件 |
| **现证据** | 该串在 `tz.mbn` 文件偏移 `0x32972d`（确实存在）；但同文件里 `libcmnlib.so`@`0x359ed9`、镜像名表 `cmnlib\0cmnlib64\0CommonLib\0CommonLib64`@`0x12b828`、`cmnlib_gppo_rpmb_enablement`@`0x1223b0`；`keymint.mbn` 有 `DT_NEEDED libcmnlib.so` + 15 个 `qsee_*` import。设备上 cmnlib 全零而 TZ 正常 ⇒ 这条路径**没失败** → `tee` §1.5/§2.4 |
| **正确结论** | **字符串存在只说明代码路径存在。** 本平台该路径走的是**内嵌镜像**、不读分区；「分区全零 + TZ 正常」就是这条路径没失败的直接反证。依赖方向是"TA 依赖 TZ 内嵌库"，不是"TA 依赖分区" |

### C-21 🟡「解锁会弄坏 TEE」—— 误解

| | |
|---|---|
| **旧说法** | 解锁 BL 会让 KeyMint/TEE 出问题，所以解锁有代价 |
| **现证据** | 当前 `unlocked: yes` + `secure: yes`（硬件 Secure Boot 仍开），而 KeyMint **照常工作**：FBE 解锁、73 个 key、`IKeyMintDevice/default` 在服务。`keymint.mbn` 里确有 `km_set_boot_state` / `is_unlocked: %u. color: %u` / `qsee_get_secure_state` ⇒ **attestation 会把"已解锁"写进去**（orange/unlocked 降级），但密钥不擦（在 RPMB）→ `tee` §4.3 |
| **正确结论** | **解锁 ↔ TEE 不冲突。** 真正的代价是 Play Integrity / 银行类 attestation 降级，以及 `keystore` 分区全零 ⇒ Widevine keybox 没了（本机 L1 本来就没有）。真正会弄坏 TEE 的是**重 provision UFS / 擦整盘**，不是解锁 |

---

## 五、900E / 9008（C-22 … C-28）

### C-22 🔴「900E = 另一个 EDL，可以用 QFIL / fh_loader 修」—— 错

| | |
|---|---|
| **旧说法** | 900E 和 9008 都是 Qualcomm 下载模式，拿 QFIL 试就行（试不通就以为工具坏了） |
| **现证据** | 900E 的 Sahara 状态是 **MEMORY_DEBUG（`mode=0x02`）**：`HELLO_RSP(mode=0x02)` → 目标回 `MEMORY_DEBUG_64` + **116 项区域表** → 逐区域 `MEMORY_READ_64` 读回。实测日志：`[+] port COM6 captured at +0.012s` → `[+] MEMORY_DEBUG accepted: MEMORY_DEBUG_64 len=0x18` → `[+] table @0x45ef20b0 len 0x1d00` → `[+] 116 regions in table`。它**不接 programmer**，所以 fh_loader/QSaharaServer 等的是 image-transfer 状态 ⇒ 全超时是**正确反应** → `900e` §0/§1、`9008` §1.4 |
| **正确结论** | 900E 是**内核 panic 之后的内存取证窗口**（`VID_05C6&PID_900E`，Windows 枚举成 `Qualcomm HS-USB Diagnostics 900E`），**只能读、不能写**。要和它说话必须**自己写 Sahara 客户端**（`work\tools\auto_900e.py`）。关键不对称：**900E 能读不能写，9008 能写不能读 RAM** ⇒ "先取证再救砖"是硬顺序 |

### C-23 🔴「进了 900E 只能等 / 换板」—— 错，有软件出口

| | |
|---|---|
| **旧说法** | 900E 状态下 fastboot/adb 全不可用，只能长按断电或当砖处理 |
| **现证据** | Sahara **`RESET_REQ(0x07)`** 发出去之后设备**不会重新崩**，而是落到 fastboot（`18D1:D00D`）。记录在 `work\tools\auto_900e.py` 文件头 docstring（2026-11-13 实测）；本轮 4 轮循环复现 → `900e` §0-3、`9008` §1.4 |
| **正确结论** | 900E 从"砖"降级成"**多一步的取证现场**"。取证完成 → 发 `RESET_REQ` → 回 fastboot → 正常刷回 |

### C-24 🟡「900E 需要设备先'挂死'」—— 错，需要 panic

| | |
|---|---|
| **旧说法** | 设备卡死（死循环/等中断）就能进 900E 取证 |
| **现证据** | 900E 的触发链是 `panic/oops/watchdog → dload dump`（XBL 串：`boot_error_handler: Ramdump allowed. Trying to enter DLOAD`）。**死循环只会让设备"安静地卡住"，USB 还在、但没人应答**。本机 5 份完整转储 100% 都是 `Kernel panic - not syncing: Attempted to kill init! exitcode=0x00007f00` + `msm_watchdog … Causing a QCOM Apps Watchdog bite!` → `900e` §0-1、`9008` §4.1 |
| **正确结论** | **进 900E 的必要条件是"上一次真的 panic/oops 过"**。这条对自编 UEFI 的取证是硬约束：UEFI 挂死**不会**进 900E ⇒ 只能靠"自己写盘（`logdump` 64 MiB / `rawdump` 128 MiB，官方包不写这两块）再 reset"这条路 |

### C-25 🔴「`fastboot oem edl` 存在」/「`adb reboot edl` 不通」—— 两句都错

| | |
|---|---|
| **旧说法** | 有一条记载说"`adb reboot edl` 本机曾 `unknown command`"，于是认为 adb 下 EDL 这条路不通 |
| **现证据** | ① `abl.elf` 的 ASCII 全表（2,877 条）对 `edl\|dload\|reboot\|restart\|fastboot\|oem ` **0 命中**；27 条 fastboot 命令里**没有 `edl`/`reboot-edl`** ⇒ `fastboot` 侧确实没有这条命令；② `unknown command` 是 **fastboot 协议**的报错串，`adb` 侧不会这么回；③ `work\docs\ACTION-LOG.md` 记录 2026-10-25T23:11 从 recovery 发出 `adb reboot edl`，**2 s 后枚举 `05C6:9008 (COM4)`** ⇒ 成功过。机制：`msm-poweroff.ko` 的 `qcom_scm_set_download_mode` + DT `qcom,msm-imem-download_mode` → `9008` §1.3/§1.5、`900e` §2.2 |
| **正确结论** | **`fastboot oem edl` 这条路在本机不存在**（ABL 未注册）；但 **`adb reboot edl` 可用且已实测成功**。那条旧记载应理解为"fastboot 侧下 EDL 命令不存在"，而不是 adb 路径不通 |

### C-26 🔴 firehose 能用 `peek`/`poke` 读内存 —— 双重不可用

| | |
|---|---|
| **旧说法** | 可以用 firehose 的 `peek`/`poke` 读/写物理内存，用来看 UEFI 挂死时的现场 |
| **现证据** | ① `.rodata` @`0x6254` 的命令分派表逐字节读出 **13 个命令**：`program / read / nop / patch / configure / setbootablestoragedrive / erase / power / firmwarewrite / getstorageinfo / benchmark / fixgpt / getsha256digest` —— **表里没有 `peek`/`poke` 标签字面量**（全文件 `\x00peek\x00` 0 命中）；② 即使有，配套报错串还在：`Peek is disabled on secure boot devices` / `Poke is disabled on secure boot devices`；③ `read` 只走 LUN/扇区路径（`physical_partition_number`），**没有物理地址概念** → `9008` §2.1/§2.2/§4.1 |
| **正确结论** | 9008 **读不了 RAM**；能读 RAM 的是 900E（Sahara MEMORY_DEBUG）。而 900E 需要"崩"，不需要"挂"。⇒ 自编 UEFI 挂死的取证只能走"自己写 `logdump`/`rawdump` 再 reset"或 UART |

### C-27 🔴 最小 XML 需要 `label` / `size_in_KB` / `sparse` 等属性 —— 错，只要 5 个

| | |
|---|---|
| **旧说法** | 写 `program`/`read` XML 要带 `label`、`size_in_KB`、`start_byte_hex`、`sparse` 等，`label` 用于定位分区 |
| **现证据** | 设备侧属性名表只有：`SECTOR_SIZE_IN_BYTES` / `physical_partition_number` / `start_sector` / `num_partition_sectors` / `filename` / `NUM_DISK_SECTORS` / `last_sector` / `byte_offset` / `size_in_bytes` / `value` / `skip_bad_block` / `get_spare` / `ecc_disabled`。**`label`、`size_in_KB`、`start_byte_hex`、`sparse`、`readbackverify`、`partofsingleimage` 一个都不解析**（多给的属性会被忽略：`Input XML has %d attributes, larger than expected %d, remaining will be ignored`）。历史那次成功的 `write_persist.xml` 正是最小集 → `9008` §3.2/§3.4 |
| **正确结论** | 只要 **`SECTOR_SIZE_IN_BYTES` + `physical_partition_number` + `start_sector` + `num_partition_sectors` + `filename`** 五个。**`label` 不参与寻址，写错不会报错——会静默写到别的地方** ⇒ 模板里宁可省略 label，也不要用没核对过的 label |

### C-28 🟡「刷官方 EDL 包能修 persist」—— 永远修不了

| | |
|---|---|
| **旧说法** | 反复刷官方 9008 全量包就能把 persist 恢复 |
| **现证据** | `rawprogram0.xml` 里 persist 那行是 `<program … filename="" label="persist" num_partition_sectors="8192" start_byte_hex="0x8000" start_sector="8" />` —— **`filename=""` = 只定义几何，不写任何内容**。同类共 **47 条 `filename=""`**（扣 5 条 `last_parti` 占位 ⇒ **42 个真实分区官方包不写**）。真机回读实测：`real non-zero bytes = 0 (0.00%)`，而包内 `persist.img` 有 22,695 个非零字节 → `small` §6.2、`9008` §3.7 |
| **正确结论** | **官方包从不写 persist**。要修必须用 `fh_loader` **单分区**写（`--memoryname=ufs`、`--sendxml=write_persist.xml`）。同理 `userdata_N.img` 是稀疏镜像、只覆盖非零扇区 ⇒ **刷官方包不会清用户数据** |

---

## 六、镜像与 AVB（C-29 … C-36）

### C-29 🔴「`init_boot` 尺寸不符 ⇒ AVB 已破」—— 错，`2,011,136` 是镜像大小

| | |
|---|---|
| **旧说法** | `init_boot` 的 ramdisk 是 2,005,893，而 vbmeta 声明 2,011,136 ⇒ 对不上 ⇒ init_boot 的 AVB 已破 |
| **现证据** | `2,011,136 = 4096（头页） + round_up(2,005,893, 4096)` —— `2,011,136` 是**镜像大小**（`image_size` 字段语义），不是 ramdisk 长度。复算：`sha256(salt ‖ init_boot[:2011136]) == ab394ed4…` **MATCH** → `bootgrp` §0-1/§1.2 |
| **正确结论** | **init_boot 的 AVB 没破，是自洽的。** 真正的破点是 `boot`（见 C-30）。这条误判会让人去重签 init_boot，白做一轮 |

### C-30 🔴「设备 `boot_a` 是原厂 ZUI16 544 内核」—— 错，是重打包件

| | |
|---|---|
| **旧说法** | 设备上的 `boot_a`（`a17dump\boot_a.img`，sha256 `2510b098…c3c14b`）是原厂 544 内核 |
| **现证据** | 头里 `kernel_size = 43,092,480`（原厂 46,819,840）、`ramdisk_size = 0`，其后 3,743,744 B 是**原厂 boot 的残留字节**；与 `boot_tb331fc_v3_kernel_only.img` 前 43,098,112 B **完全相同**，且 `dev[43098112:46841856] == stock[...]` 为 true。而 `vbmeta_a` 按 46,841,856 B 计算哈希 ⇒ 实测 `89013232…` vs 声明 `ad970718…` **MISMATCH** → `bootgrp` §0-2/§1.2/§3.2 |
| **正确结论** | 设备 `boot_a` 是**"仅内核"重打包件**（含尾部原厂残留），**它就是 boot 链唯一破 AVB 的分区**。`dtbo`/`init_boot`/`vendor_boot` 三个的 hash 描述符**全部 MATCH**。`verifiedbootstate=orange` 是解锁态正常取值；boot 失配说明 ABL 走的是"校验失败但放行"（`0x1cdf0`：`State: Unlocked, … continue boot`），**不是没校验** |

### C-31 ⚪「ABL 需要 120 条 DT 符号」—— 是 143（base 有 829）

| | |
|---|---|
| **旧说法** | 自建 DTB 时要保留 ABL 需要的 120 条符号 |
| **现证据** | base DTB（`dtb_idx=0`）：1,940 nodes / 7,830 props / **`__symbols__` 829 条**；45 棵 overlay 合计只用到 **143 条**不同符号（去重），**base 里 0 缺失**；单棵 `__fixups__` 41–129 条（entry 2 = 115）；base 中未被任何 overlay 用到的 686 条 → `bootgrp` §0-7/§4.5 |
| **正确结论** | 必须原样保留的是 **143 个符号名**（不是 120）。否则 `ufdt_apply_overlay` 解析 `__fixups__` 失败 → fragment 被丢或整体报错 → "overlay 里明明有 panel，起来却没屏" |

### C-32 🟡「修补 `init_boot` 必须保留 `novatek_ts_fw.bin`(196,608 B) 与 `build.prop`(1,302 B)」—— 与 544 原厂不符

| | |
|---|---|
| **旧说法** | 技能库记录：修补 init_boot 必须保留 `lib/firmware/novatek_ts_fw.bin`（196,608 B）与 `system/etc/ramdisk/build.prop`（1,302 B），否则触控失效/密度错误 |
| **现证据** | 原厂 544 的 `init_boot.img` ramdisk 解 lz4-legacy cpio 后**只有 16 个条目**：`init`(2,567,024)、`system/bin/snapuserd`(1,059,856)、`system/etc/init/snapuserd.rc`(507)、`system/etc/ramdisk/build.prop`(**1,064 B**) 和几个空目录（`debug_ramdisk/ dev/ metadata/ mnt/ proc/ second_stage_resources/ sys/ system/ system/bin/ system/etc/ system/etc/init/ system/etc/ramdisk/`）。**没有 `lib/`、没有 novatek 固件** → `bootgrp` §1.2 第 3 行 |
| **正确结论** | 这是**GKI 通用 ramdisk**：first-stage 的 `.rc`/策略都在 `system` 分区。那条记忆应是**别的构建（460/其它）或别的分区**——`novatek_ts_fw.bin` 若确实需要，它在 **`vendor_dlkm`（`/lib/modules` 侧）**而非 init_boot。**待核**，但"544 的 init_boot 里有 196 KB 固件"这条肯定不成立（整个 ramdisk 解压后才 3,630,592 B，16 个条目已全列） |

### C-33 🔴「SEC 栈 `0x5FF90000+0x40000` 踩了 XBL 活跃栈」—— 证伪

| | |
|---|---|
| **旧说法** | Mu UEFI 的 SEC 把 `0x5FF90000` 起 256 KB 清零，踩到了 XBL 还在用的栈 ⇒ 一跳进去就挂死 |
| **现证据** | 三个独立理由（→ `secmem` §2）：<br>**A（地址身份）** 那块地**就是原厂自己声明的 UEFI Stack**：`uefiplat.cfg:26` 明码 `0x5FF90000, 0x00040000, "UEFI Stack", AddMem, SYS_MEM, SYS_MEM_CAP, BsData, WRITE_BACK_XN`；且**原厂 khaje 的 SEC 二进制里**就在 VA `0x5FC0CE48` 写着这对字面量（`PcdCPUCoresStackBase = 0x5FF90000`、`PcdCPUCorePrimaryStackSize = 0x00040000`）。`BsData` = EFI_BOOT_SERVICES_DATA，语义就是"当前 UEFI 环境的栈，ExitBootServices 后作废"。<br>**B（装载事实）** `xbl.img` 的 17 个 phdr 里**没有任何一段被装载到 `0x5FF90000`**：只有 ph16 落在 `0x5FC00000`（`0x220400`）；XBL 常驻代码在 IMEM `0x0C1xxxxx`（ph2–ph11），AOP 在 `0x45E00000`（ph12–ph15）；ABL 自己跑在 `0x40080000`。<br>**C（逐字节）** SEC 清零区 `0x5FF90000..0x5FFD0000` **与原厂 "UEFI Stack" 区间逐字节相等**，左右都没碰到：下边 `CPU Vectors 0x5FF8C000`(4 KB) / `MMU PageTables 0x5FF8D000`(0x3000)，上边留 0x27000 空隙再是 `Log Buffer 0x5FFF7000` / `Info Blk 0x5FFFF000` |
| **正确结论** | **不是踩 XBL，是接手 XBL 的栈。** 假设不成立（证据强）。留着一点不确定度：我们**没有 khaje 自己的 `uefiplat.cfg` 原文**（`xbl_config.img` 两版都只有证书串与 DAL 属性，`uefiplat`/`UEFI Stack`/`MemoryMap` 0 命中），"tapas 的 cfg == khaje 的 cfg"是同 SoC 类推——但 §1.2 那条原厂 **khaje SEC 字面量**把这个缝补上了（那是 khaje 自己的二进制）。<br>**这条被证伪后，不要再改地址。** 下一步是把"哪一段死了"变成 framebuffer 上的 2–3 个哨兵色 |

### C-34 🔴「FD 基址 `0x5FC00000` 覆盖 XBL 驻留 UEFI 是致命操作」—— 证伪

| | |
|---|---|
| **旧说法** | BootShim 把 3 MB 的 FD 拷到 `0x5FC00000`，覆盖了原厂驻留的 UEFI 代码/数据 ⇒ 这是挂死的根因 |
| **现证据** | ① 我们（以及 tapas、tb128fu）的 shim **都**把 3 MB FD 拷到 `0x5FC00000`（`BootShim.S:19-54`：`ldr x5,=FD_BASE … _CopyLoop … br x5`），而原厂 FV 只有 `0x220400` ⇒ **原厂 SEC 本体（`0x5FC00FE8`）和整个 DXE 卷（`0x5FC423C8` 起）都被覆写**，比"清 256 KB 栈"严重得多；② tapas 用完全相同的 `0x5FC00000 + 0x300000` 与 `0x5FF90000 + 0x40000`，而本仓把 tapas 当"已验证能跑"的参考；③ `uefiplat.cfg` 把 `UEFI FD` 标成 **`BsData`** 而非 `Reserv`，XBL 的 FV 实际只占 `0x220400`（剩 `0x5FE20400–0x5FF00000` 的 `0x1DFC00` 从没被使用）；④ 设备 `/proc/iomem` 实测 `55d17000-5fffffff : System RAM`（只留 `0x5C000000+0x100000`）⇒ 整片固件窗口在 OS 运行时就是自由内存 → `secmem` 理由 C、`xbl` §6.3 |
| **正确结论** | **如果这条路线能致死，tapas 也死。** 它无法区分"本机死、tapas 活"，不可能是"本机特有的静默挂死"的根因。<br>**但留两个必须点名的残余风险**（都不是加密问题）：A. ABL 跳转前到底有没有 `ExitBootServices`？若 ABL 跳转后仍用 Runtime Services（`VariableDxe`/`ResetRuntimeDxe` 的代码/数据可能落在 `0x5FC00000–0x5FE20400`），BootShim 一覆盖就会在下一次 `SetVariable/ResetSystem` 时炸——**这是唯一只有上机/抓内存才能定的事**；B. BootShim 写入时的 MMU 属性（cfg 说这段是 `WRITE_BACK` 可写，但若 ABL 在跳转前把它改成只读/未映射，第一次 store 就挂） |

### C-35 🔴「整机更像 ZUI17（因为机上 recovery 的 ramdisk 是 14,581,386）」—— 错，读的是 `recovery_b`

| | |
|---|---|
| **旧说法** | 机上 recovery 头显示 ramdisk 14,581,386 ⇒ 整机内容更像 ZUI17 |
| **现证据** | 按"包内镜像零填充后算同样摘要"的方法逐槽位比对 49 个可比槽位（→ `zuidiff` §5.2/§5.3）：**37 个精确 = ZUI16**、6 个两版本来相同、**只有 3 个 = ZUI17（`init_boot_b`、`vendor_boot_b`、`recovery_b`）**、3 个两版都不是（`boot_a`/`boot_b`/`vbmeta_system_a`）。具体：`recovery_a` head64M = `264aec55…` = **ZUI16**（ramdisk 14,572,954）；`recovery_b` head64M = `e5353d2a…` = **ZUI17**（ramdisk 14,581,386） |
| **正确结论** | **不是"整机像 ZUI17"，而是 B 槽被 ZUI17 内容污染了三个 boot 链分区，A 槽才是 544 原厂。** 最可能成因：那次 9008 全量回刷在 b 槽 boot 链末尾中断——`init_boot_b → recovery_b → vendor_boot_b` 恰好是 `rawprogram4.xml` 里 b 槽 24 个 A/B 分区的**最后三个**（也可能有人事后单独刷过，数据上等价）。<br>**后果**：`vbmeta_b` = ZUI16 原厂，与 b 槽那三个的摘要对不上 ⇒ `set_active b` 会 AVB 失败，**b 槽是个坑**：要么全量刷 544 刷干净，要么永远不要 `set_active b` |

### C-36 🟡「`work\docs\STATE.md` 说 a 槽已恢复为 544 原厂（含 vbmeta_system_a / boot）」—— 与实测不符

| | |
|---|---|
| **旧说法** | `work\docs\STATE.md`：a 槽已由 9008 全量恢复为 544 原厂，含 `vbmeta_a` / `vbmeta_system_a` 原厂 |
| **现证据** | `vbmeta_a` 确实是原厂（`9466f0e8…` = ZUI16 `vbmeta.img` + 零填充）；但 **`vbmeta_system_a` 两版都不是**（机上 `cea948ea…`，与 `rescue-matrix\reads\vbmeta_system_a_now.bin` 同值 ⇒ 是 A17/hashtree 实验留在 a 槽的**重签版**；原厂应为 `1e0688b4…`）；**`boot_a`/`boot_b` 两版都不是**（两者哈希相同 `667e1723…`，成对写入的同一份补丁/实验镜像）→ `zuidiff` §5.4 |
| **正确结论** | 当前"能开机"的状态里 **`boot` 与 `vbmeta_system_a` 是带改动的**。做任何"回到原厂"的动作前必须先认清这一点；`init_boot_a` 已核对是**原厂 544**（`2d090fb5…`），只是 2026-10-24 备份里当时还是补丁版 `f18dc14a…`，之后被恢复了 |

---

## 七、ZUI 基线（C-37）

### C-37 🟡 换 ZUI17 的 `abl` 可能改变白名单行为 —— 不会，两版逐字节相同

| | |
|---|---|
| **旧说法** | ZUI17 换了固件，`abl` 的白名单逻辑可能变了，值得试一把 |
| **现证据** | ZUI16 的 `abl.elf`（274,432 B）与 ZUI17 的 `abl.img`（274,432 B）**文件 sha256 相同，逐字节完全一致**；`dspso.bin` / `dsp.img` 同样逐字节相同。而 `xbl`/`tz`/`hyp`/`keymaster`/`devcfg`/`rpm`/`uefisecapp`/`multiimgoem`/`qupfw`/`xbl_config`/`imagefv`/`bluetooth`/`modem` 两版**真实不同**（首个差异落在 ELF 代码段入口附近 `0x1108`~`0x2F60`），但 **Qualcomm 版本串一个都没变**（`BOOT.XF.4.1-00374-KAMORTALAZ-1`、`TZ.XF.5.1.6-54971-3`、`MPSS.HA.1.1-00356-KD_ALL_PACK-1` 两边完全相同）→ `zuidiff` §3.1/§4.2 |
| **正确结论** | **ABL 的白名单逻辑、`fastboot oem edl`、slot 校验策略在 ZUI17 里没有任何变化** —— 换成 ZUI17 的 abl 不会有任何区别（历史 9008 降级 ZUI15 abl 后第三方 rec 仍被拦，与此一致）。固件 blob 的实质改动**未知**（无符号表，4%~60% 的块不同，但不属 BSP 升级），如实标注 |

---

## 八、判据与方法论（C-38 … C-41）

### C-38 🔴「槽重试计数减 1 = 载荷执行了」—— 错，减 1 是 INCONCLUSIVE

| | |
|---|---|
| **旧说法** | 刷探针后 `slot-retry-count` 变小 ⇒ 载荷执行了 |
| **现证据** | ABL 在**每次尝试启动某槽之前**就把 `tries_remaining` 减 1 并写进 misc（单点写入 `0x27b58`，紧跟 `0x21190` 落盘，然后打印 `Active Slot %s is bootable, retry count %ld`）。递减/落盘/打印全在 `0x276d0`（唯一调用者 `0x1b1ec`），retry 是 slot 元数据 **`+0x34` 字的 bits 19..21**（`0x279d4 ubfx x8,w8,#19,#3`；写回 `0x27b2c and …#0xffc7ffffffffffff` + `0x27b58 orr …,lsl #51`），全镜像**唯一递减点**。递减发生在"决定要启动这个槽"的一刻，**早于**把控制权交给内核（`0x276d0`/`0x26e00` 内部既没有 `LoadKernel`(0x9c70) 也没有 `BootLinux`(0x6a30)，也没有跳内核的 `blr`）→ `wdt` §1.1–§1.5 |
| **正确结论** | **减 1 = 只发生了一次启动尝试**，既可能"载荷跑了但看门狗没咬"，也可能"根本没跑、卡在 logo" ⇒ **INCONCLUSIVE**。判执行要 **减 ≥2**（只有载荷自己造成 SoC 复位才会产生第 2 次尝试），或终态信号（`slot-unbootable:a=yes` / `current-slot` 由 a 变 b）。**前置条件**：`slot-successful:a` 必须为 `no`（ABL 对已标记 successful 的槽**跳过递减**：`0x279e8`/`0x27ac4`），本机实测是 `yes` ⇒ 必须先 ARM（`--set-active=a`）再读基线 |

### C-39 🟡「`logfs` 里有 ABL 运行日志可读」—— 本机为零

| | |
|---|---|
| **旧说法** | 读 `logfs` 分区（8 MB）就能拿到 ABL 的 `DEBUG()` 输出，把 13 条判据压到 1 条 |
| **现证据** | 实测 `E:\rom\work\woa\logfs.bin`（8 MB，分区 `logfs` `0x800000`）内容是 **FAT12 空文件系统**：非零 4K 块只有 4 个（0/4096/8192/12288），对 `Active Slot`、`retry count`、`BootLinux`、`Kernel Load Address`、`Silicium` 的 `grep -aci` **全为 0**。配合 cfg 里 `EnableLogFsSyncInRetail = 0x0`（零售版不同步 logfs）→ `wdt` §3.C、`xbl` §3.3 |
| **正确结论** | 这台机器的 ABL **没有把运行日志落进 logfs**。要开 ABL 日志得有 ABL 源码/签名 ⇒ 做不到。**ABL 日志只能走 UART**（需焊点/测试点，本机未确认可用）。这条让"读 ABL 日志一刀切开 L1~L5 与 L6~L9"这条路暂时堵死 |

### C-40 🟡「载荷可以自己写 misc 留一个'我来过'标记」—— 不可行

| | |
|---|---|
| **旧说法** | 让 payload 跑起来后往 `misc` 写个标记，就一定证明它执行了 |
| **现证据** | ① 我们的载荷是 **Linux arm64 `Image`**，在 `blr x8`（`0x862c`）处进入，`x0=DTB`、MMU 按 stub 自己关——**它不是 EFI 应用，没有 `ImageHandle`/`SystemTable`**；② ABL 在跳转前已经走过关机服务序列（`0x8590 bl 0x34810` 七参数调用 → `0x8594 mov w0,#1; bl 0x60510` → `0x859c bl 0x68290`），到 `blr` 时**已不是 Boot Services 可用状态**；③ 想写 `misc`/`uefivarstore` 必须走块设备，没有 `gBS->LocateProtocol(BlockIo)` 就没有句柄 → `wdt` §3.B |
| **正确结论** | **不可行。** 且"让载荷直接 `bl 0x21190`（ABL 的统一落盘函数）"也不行——它依赖 ABL 的全局 `misc` 缓冲与驱动状态，在没有 Boot Services 的前提下等价于赌博，失败模式是把 `misc` 写坏（BCB 破坏 → 进不了系统/无法回滚） |

### C-41 🟡「改 `super` 里的逻辑分区会影响 TEE / 解锁状态」—— 都不会

| | |
|---|---|
| **旧说法** | 换 system、重签 vbmeta 有踩到 TEE 的风险；解锁会破坏 TEE |
| **现证据** | `vbmeta.img`（8,192 B）描述符里的分区名：`vbmeta_system`(chain) + `boot` `dtbo` `init_boot` `recovery` `vendor_boot` `odm` `system_dlkm` `vendor` `vendor_dlkm`；`vbmeta_system.img`（4,096 B）：`system` `product` `system_ext`。两张 vbmeta 里 `tz`/`hyp`/`keymaster`/`keymint`/`cmnlib` 出现次数 **0/0**；`tz.mbn` 里 `avb`/`vbmeta`/`dm-verity`/`verity` **0** → `tee` §4.1 |
| **正确结论** | **改 system/product/system_ext、重签 `vbmeta_system` 乃至 `vbmeta`，不会碰到 TEE**，也不会让 KeyMint 失效。唯一后果仍是老问题：**hashtree 必须自洽**，否则 dm-verity 失败 → init 退出 → 900E（那是 AVB/verity 层的事，与 TZ 无关）。解锁同理不碰密钥（见 C-21） |

---

## 九、文档一致性（C-42 … C-43）

### C-42 🔴「A17 结构性不可行」—— 已撤回

| | |
|---|---|
| **旧说法** | 澎湃 4.0 / A17 在本机「启动即中止、结构性不可行」，根因是 vendor API level 33 vs `ro.llndk.api_level=202604` |
| **现证据** | A17 **确实起到过桌面**，不止一次：`release=17`、`sdk=37`、`boot_completed=1`、`dumpsys sensorservice` = `Total 29 h/w sensors, 29 running`（BOSCH bmi3x0）、`package:mark.via` 与 `package:com.android.MGC_8_8_224` 已安装、指纹 `Lenovo/miproduct_yupei/TB331FC:17/CP2A.260605.016/OS4.0.5.0.XPZCNXM:user/release-keys`。2026-11-13 已闭合直接根因：`product_D.img` **自身 hashtree 不自洽**（重算 `0bcedeb0…` ≠ 声明 `832596f2…`）→ `dm-13: data block 0 is corrupted` → init 读不到 superblock → `Attempted to kill init!` → panic → 900E → `v4` §5.1、`900e` §4.4 |
| **正确结论** | **「结构性不可行」撤回。** A17 起到过桌面是观测事实；起不来的直接原因是**一个镜像的 hashtree 与自身数据不符**，与 vendor 代差无关。vendor 代差在这台机器上不是阻断启动的点（顶多影响稳定性/外设，例如 `imsdaemon` 每 ~10 s SIGSEGV 一次）。<br>补充：`vbmeta_a` 的"链密钥机制"（`vbmeta_a_D` 链不匹配 → verity 不启用 → 能起）**也已撤回**——2026-11-12 查明成功那次的 `vbmeta_a` 其实是**原厂 544**；且 11-12 21:19/21:22 真机单变量复验（内容一字不改，只换 8 KB `vbmeta_a`）**off/on 两侧均约 31/33 s 掉 900E** ⇒ `vbmeta_a` 不是 900E 的变量 |

### C-43 ⚪「v3 目录是 37 文件」—— 实测 65 文件

| | |
|---|---|
| **旧说法** | 任务书称 v3 是 37 文件 / 6.53 GB |
| **现证据** | 整合前实测 `Get-ChildItem -Recurse -File` = **65 文件 / 6,547,633,424 B**（6.55 GB 十进制 / 6.10 GiB）。37 这个数没能复现（去掉 `ksu_modules\<id>\` 解压目录是 40，再扣掉 ksu 的 README/MANIFEST/addendum 才是 37）。另一条：v3 根清单里 **`README.txt` 自己也是陈旧项**（清单写 `5f0cf58…`，实际 `032d8e41…`），v3 复算结果 `OK 29 / FAIL 6 / MISSING 1` → `v4` §5-1/§5-2 |
| **正确结论** | 以 **65 文件**为准；其余状态描述（5 组 zip + 解压目录 + MANIFEST + service.d 三脚本 + addendum、旧 `fix_logpersist_sepolicy.zip` 已被替换）**全部对得上**。v4 的清单净变化 = `36 − ksu 8 + 新 ksu 10 + selftest 1 = 39` 条 |

---

## 附：本轮"未推翻但要注意"的三条边界

| 项 | 说明 |
|---|---|
| **ABL 白名单与 AVB 是两层，不是一层** | AVB 能过（公钥就是 AOSP `testkey_rsa4096`，ABL 内嵌钉钥也是 testkey4096，`ValidateVbmetaPublicKey` memcmp 1,032 B）**不代表第三方 recovery 能启动**——ABL 另有独立于 AVB 的 recovery 校验/白名单（C-11 已把"这条路死了"降级为"形态没试对"） |
| **`tz` / `keymaster` / `hyp` 必须成套** | 同一构建、同一签发链。混用 ZUI16 的 tz + ZUI17 的 keymint 这类组合**没有任何保证**（TZ 与 TA 的 ABI / 内嵌 cmnlib 都可能变）→ `tee` §5.3 |
| **`hyp` 与 `tz` 是配对件** | hyp 通过 SMC 调 TZ（`SMC call to qsee from hypervisor failed`），都是联想 Elm/QC 签发的那一套 ⇒ **不能只换一个** → `tee` §3.3 |

---

*凡与单份报告冲突处，以报告内标注的原始地址/字节证据为准。本文只记录"被推翻/更正"的部分，未变的结论见 [`PANORAMA.md`](PANORAMA.md)。*
