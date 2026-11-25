# 「木马内核」（把 UEFI 伪装成真内核）三条路线评估

- 执行日期：2026-11-25
- 对象：TB331FC / khaje / SM6225-AD；ABL PE `sha256 33ca0240…`（`E:\rom\work\woa\abl-jump-analysis\full.asm`，VA == 文件偏移）
- 性质：**只读 + 离线静态分析**。未刷机、未编译、未修改既有产物；本目录只有本报告。
- 前置报告（已读，本报告对其做 2 处修正）：`abl-jump-analysis`、`abl-hang-analysis`、`abl-dtb-gzip`、`sec-memory`、`woa\CONCLUSIONS.md`

---

## 0. 一句话结论

**「木马内核」这条路在机械层面拿不到任何东西：ABL 交接给「真内核」和交接给「我们的 payload」是同一条指令（`0x862c blr x8`）、同一组寄存器、同一份 CPU 状态——差异只存在于数据驱动的分支上。** 因此三条做法里，A 与 C 的可行性完全等价（C 是 A 的劣化版），B 不可行。真正有价值的是把「数据面差异」一条条钉死（§3），其中一条**新发现且可直接改**：v1 头 + gzip 时，`LoadDtb` 的「追加 DTB 兜底路径」算出来的地址恒定比真实 DTB **早一个 `PageSize`**（`0x9e90` 写入的 `+0x84` 与 `0xa95c` 的取址基准不匹配），只有 `GetDtb()`（`0x45da0`）成功时才会绕过它。

| 路线 | 判定 | 一句话依据 |
|---|---|---|
| **A. 真内核外壳 + 最早入口跳转** | **机械不可行 / 数据面可做（收益有限）** | `blr` 只有一条、寄存器与 CPU 状态与真内核完全相同（§2）；A 能多过的只有「未压缩内核」这一条数据分支（§3.2），而这条**用现有 192 B shim 改成不压缩也能拿到**，不需要真内核 |
| **B. 真内核 + initramfs，在 Linux 里跳 SEC** | **不可行** | 5 条硬障碍（§5）；且没有任何公开先例（LinuxBoot 方向相反） |
| **C. stext 之后、start_kernel 之前 hook** | **可行但严格劣于 A** | 同一批 ABL 检查、同样的死法，却额外要求整颗 40 MB 内核能装进 ABL 的可用窗口，并要在 MMU 已开、cache 已配好的状态下二次拆机（§6） |

**核心问题「真内核到底多过了 ABL 的哪些检查」的答案（§3）**：只多过**一条**——`LoadDtb` 的「追加 DTB 兜底路径」（`0xa520`，入口判据 `0xa868 cbnz`）。因为原厂内核是**未压缩** Image 且 DTB 来自 vendor_boot，`BootParams+0x84` 恒为 0，兜底路径必然算错，所以原厂能开机这件事本身就证明 `GetDtb()` 对它返回非 NULL、整段被 `0xa868 cbnz → 0xae68` 跳过。其余 11 条检查我们本来就全过（§3.1 表）。

---

## 1. 素材核实（先纠正三处事实）

| 素材 | 状态 | 实测 |
|---|---|---|
| `E:\rom\work\of\v3\stock\boot_a.bin` | **不存在** | 本机无此路径（`Test-Path` = False）。下文的「原厂内核」一律用 `E:\rom\work\a17dump\boot_a.img`（A17，100,663,296 B）代替 |
| `E:\rom\work\a17dump\boot_a.img` | 存在 | `ANDROID!` / hdr v4 / `page_size` 字段 = 0（v4 固定 4096）/ `kernel_size` 43,092,480 / `ramdisk_size` 0 / 内核在 `0x1000` |
| **A17 内核本体** | **未压缩**（重要） | 首 4 字节 `4d 5a 40 fa` = `efi_signature_nop`（`MZ` + `ccmp x18,#0,#0xd,pl`），即裸 arm64 `Image`；`text_offset=0`、`image_size=0x29C0000`(43,646,976)、`magic@0x38="ARMd"`、`0x40` 起是内嵌 PE/COFF 头（EFI stub） |
| `Image-6.14.0-rc5-tb331fc` | 存在 | 38,959,616 B，同样未压缩；`code0=0xFA405A4D`(`MZ`)、`text_offset=0`、`image_size=0x25F0000`(39,780,352)、`"ARMd"` @0x38、PE 头 @0x40 |
| `Mu-tb331fc-v8-hobsfalse.img` | 存在 | `ANDROID!` / hdr v1 / page 2048 / `kernel_size` 1,232,233 / `ramdisk_size` 5 / 载荷首 3 字节 `1f 8b 08`（gzip） |
| `E:\rom\work\woa\out\SILICIUM_UEFI.fd` | 存在 | 3,145,728 B = `0x300000`，与 FD 窗口一致 |

> **第一处事实纠正**：本任务书与 `CONCLUSIONS.md` 的「原厂 boot 100 MB，kernel 46,841,856」这一组数字对不上现存文件；现存可用的原厂 boot 是 A17 的 `43,092,480`。凡涉及「原厂内核」的推论，本报告只用实测过的 `boot_a.img`。

---

## 2. ★ ABL 交接到 payload 那一刻的 CPU/寄存器状态（本次的核心新证据）

这条是 A 与 C 的全部立论基础，因此逐指令核过。

### 2.1 `BootLinux`（`0x6a30`–`0x8678`，**1811 条指令**）内部没有任何状态切换

对整段区间做系统寄存器/维护指令穷举，**命中 0 条**：

```
msr / mrs / tlbi / dc / ic / dsb / isb / smc / hvc / at  → 0 命中
```

即：**在 `BootLinux` 自己的函数体里，ABL 不做 MMU 关闭、不做 cache 清理、不做 TLB 无效、不插屏障，直接把 `blr` 打出去。**

### 2.2 真正的「交接准备」在 `0x34810`，由 `0x8590` 调用

`0x855c`–`0x8590` 把 9 个参数塞好后 `bl 0x34810`。`0x34810` 的实质内容（逐指令）：

```
348a8  bl 0x141b8                  ; （cache/CTR 相关辅助）
348ac  bl 0x35030                  ; ★ msr DAIFSet,#3   → 屏蔽 IRQ + FIQ
348b0  bl 0x35018                  ; ★ msr DAIFSet,#4   → 屏蔽 SError
348b4  bl 0x350a4(loadAddr, len1)  ; ┐
348c0  bl 0x350a4(ramdisk, len2)   ; │ dc civac（clean+invalidate D-cache）
348cc  bl 0x350a4(dtbAddr, 0x200000); │ 六段，见 0x350a4 → 0x3503c 的循环
348f4  bl 0x350a4(kernelStart..)   ; │   fn 硬编码 = 0x14054 = `dc civac, x0`
34904  bl 0x350a4(x7 .. [sp+0x80]) ; ┘   步长 = 2 MiB 对齐
34918  bl 0x35234
3491c  bl 0x14064                  ; ★ `ic iallu` —— 整颗 I-cache 无效
34920  bl 0x140e8 / 34924 0x14150 / 34928 0x14074   ; dsb/isb 一族
3492c  bl 0x35190                  ; ArmReadCurrentEL（返回值被丢弃）
34954  ret
```

`0x351a8` 是 `ArmInvalidateTlb`，按 `CurrentEL` 三选一：`tlbi vmalle1` / `tlbi alle2` / `tlbi alle3`，随后 `dsb sy; isb`（`0x351bc`–`0x351c0`）。

### 2.3 MMU 是**开**的（关键，且与直觉相反）

全 PE 里 `SCTLR` 的读写只有 18 处，**全部集中在 `0x1408c`–`0x141a8`**（ArmLib 的 `ArmRead/WriteSCTLR` 一族，每个都是 EL1/EL2/EL3 三选一）。**没有任何一处在 `0x862c` 之前被调用**，也没有任何一处置 `SCTLR_EL1.M = 0`。`TTBR` / `TCR` / `MAIR` / `VBAR` **全 PE 零命中**。

⇒ **ABL 是在 MMU 开着的状态下 `blr` 进内核的**，把「换页表」这件事留给了对方。这与 arm64 启动协议的字面要求（MMU off）不同，但两边都能容忍：
- **真 Linux 内核**：`stext` → `init_kernel_el` 里第一件事就是 `msr sctlr_el1, x0`（MMU off，同址 identity，不会炸），随后自建页表；所以「MMU 开着交给我」它不在乎。
- **UEFI SEC**：`_ModuleEntryPoint` 只做 `msr SPSel,#1` → `SecCleanInvalidateDataCacheAll` → 设 SP → 清 256 KB → `SecEntry`（见 `sec-memory/REPORT.md` §1.3）。它**既不关 MMU 也不换页表**，整段「设栈 + 清栈」都跑在 **ABL 留下的页表**上。
  ⇒ **这是我们与真内核最大的一处「隐含依赖差异」**：真内核在头 100 条指令内就把页表换成自己的；我们的 SEC 全程借用 ABL 的页表，而 ABL 的页表是它自己 UEFI 环境那一套（`0x5FF8D000` 起的 MMU PageTables 只服务 ABL 自身窗口）。

### 2.4 交接状态一览（`0x862c blr x8` 那一瞬间）

| 项 | 值 | 证据 |
|---|---|---|
| 入口地址 | `BootParams+0x40` = `KernelBaseAddr + 0x80000`（推断 `0x40080000`） | `0x8610`→`0x862c`，中间无加法 |
| `x0` | `BootParams+0x58` = DtbLoadAddr（FDT） | `0x861c` |
| `x1` `x2` `x3` | **全 0**（`mov x3,xzr; mov x1,x3; mov x2,x3`） | `0x8620`–`0x8628` |
| EL | 未在 ABL 里看到改 EL 的代码；`eret` 全 PE 1 处、`elr_el*` 1 处 ⇒ ABL 不做 EL 切换 | 全 PE 扫描 |
| MMU | **开**（ABL 自己的 identity 表） | §2.3 |
| D-cache | 已对 内核/ramdisk/dtb 六段做 `dc civac`；**未覆盖 `0x5FC00000`（FD 窗口）与 `0x5FF90000`（SEC 栈）** | §2.2 |
| I-cache | 已 `ic iallu` | `0x3491c` |
| IRQ/FIQ/SError | 全屏蔽 | `0x348ac`/`0x348b0` |
| SP | ABL 自己的栈（不是 `0x5FFD0000`） | — |
| payload 若 `ret` | `0x8630 b 0x8634` → `0x66ec` = **CpuDeadLoop**（edk2 的 `volatile UINTN i; for(i=0;i==0;);`，`str xzr,[sp]; ldr x8,[sp]; cbz x8,self`） | `0x66ec`–`0x6708` |

> **对 D-cache 那一行要特别注意**：ABL 的 `dc civac` 覆盖范围是**按它自己的 `BootParams` 算的**（内核、ramdisk、DTB），**不包含我们的 FD 窗口**。`sec-memory` 报告把「覆盖」与「清理」混在一起谈了，这里要分清：ABL **不写** `0x5FC00000`，所以不存在脏数据问题；FD 的可见性由 BootShim 自己负责。

### 2.5 ★ 由此得到 A 的判据

**真内核与我们的 shim，在 `0x862c` 处拿到的东西逐位相同**（同一地址公式、同一组寄存器、同一份 MMU/cache/DAIF 状态、同一段前序代码）。所以：

> 「把 payload 换成真内核」**不可能**改变 ABL 递过来的任何状态，也不可能多过任何「机制性」检查。A 唯一能改变的是**数据驱动的分支走向**（下一节）。

---

### 2.6 ★ 追加：这条「MMU 是开的」直接动摇了现有观测手段（必读）

`E:\rom\work\woa\sentinel\BootShim.S`（v9，2026-11-25，**并行进行中**）已经把「ABL 交过来时 MMU 是开的」写进注释（CYAN 带 = "ABL handed over with MMU *on*"），与本报告 §2.3 独立吻合。但由此推出两条对**判读**的硬约束：

1. **凡是「MMU 开着、映射是 cacheable」的上下文里画出来的哨兵，都可能停在 D-cache 里，永远到不了面板。**
   `0x5C000000`（Display Reserved）在 MemoryMapLib 里被声明为 `SYS_MEM / SYS_MEM_CAP / BsData / WRITE_BACK_XN`（`sec-memory/REPORT.md` §1.1），即 **cacheable write-back**。ABL 留下的页表大概率就是这么映的。
   ⇒ **v9 里由 SEC（`SecPaintEarly`）画的那三条带（BLUE / WHITE / YELLOW）不可信**：SEC 一旦在 `ArmMmuBaseLib` 里把 MMU 打开，它的 `str` 只是写进 cache；只要没人 `dc civac`，面板上永远看不到。
   ⇒ 若这三条带没出现，**不能**推出「SEC 没跑到那里」——这与团队「DEBUG 构建屏黑 ⇒ SEC 没跑到第一次打印」的既有推论（`abl-hang-analysis` §8 前置）直接冲突。**那条推论需要重新审视。**
2. **shim 那三条带（RED / GREEN / CYAN）是可信的**，因为 v9 先 `msr sctlr_elN`（M=0, C=0）再画，un-cached + Device-nGnRnE，直落 DRAM。**⚠️ 但缺一步**：关 C 之前没有 `dc civac` 那一带 64 KiB——若该带在 cache 里已有脏行，关 C 后再写，脏行会在之后某次替换时**把旧像素写回去**，把哨兵冲掉。**建议在 `_SntMmuOff` 之后、`_SntPaint` 之前，先按 CTR_EL0 的 line size 对 `0x5C000000..+0x40000` 做一遍 `dc civac`**（三行循环，与 `_CleanLoop` 同构）。
3. **v9 把 MMU 永久留在了「关」的状态**（画完不恢复），这本身是一个新的实验变量：SEC 会在「MMU off」下启动，而原厂/真内核那条路是「MMU on」。它不影响「shim 跑没跑」的判读，但会改变 SEC 的行为。CYAN 带已经把原状态记录下来了，够用；只是**别把 v9 的结果当成「ABL 原样交接」下的结论**。

**最稳的读出口仍然是不依赖显示的那一个**：让 payload 在最后调 PSCI `SYSTEM_RESET`（见 §7 E0）。复位是 USB 层可见的，绕开所有 cache / 面板 / ABL splash 的干扰。

---

## 3. 核心问题：真内核到底多过了 ABL 的哪些检查

### 3.1 全量对照表（逐条给地址）

| # | 检查 | 地址（判据点） | 原厂（未压缩 / v4） | 我们（gzip / v1） | 差异？ |
|---|---|---|---|---|---|
| 1 | boot 分区可读、长度 > 0x65f | `0x6f94` / `0x1cbac` | ✅ | ✅ | 否 |
| 2 | `header_version` 分派 | `0x8bd4` (`+0x458`) | v4 → `0x8ffc` | v1 → `0x8be8` | **是（分支不同，但不改入口）** |
| 3 | v4 需 vendor_boot 可载入 | `0x901c`→`0x8680` | ✅ 原厂 vb | — 不适用 | 是（v4 才有的硬依赖） |
| 4 | `IsGzip(内核前3字节)` | `0x9598`→`0x6b950` | **否**（`MZ`）→ `+0xc2=0` | **是**（`1f 8b 08`）→ `+0xc2=1` | **是（§3.2 的根）** |
| 5 | `memcmp(内核,"UNCOMPRESSED_IMG")` | `0x95c8` | 不命中 | 不命中 | 否 |
| 6 | `*(u32*)(内核+0x38) == "ARMd"` | `0x95f0` / `0xa270` / `0xa3bc` | ✅ | ✅（我们已对齐） | 否 |
| 7 | 装载地址 = base(+text_offset)(+0x80000) | `0x97a0`–`0x982c` | `text_offset=0` → `0x40080000` | 压缩路径不读 `text_offset` → 同址 | **否（同址）** |
| 8 | `CopyMem(dst=load, src, n=kernel_size)` | `0xa394` | **真拷贝 43 MB** | **dst==src，空操作** | **是（见 §3.3 风险）** |
| 9 | `image_size <= (DtbLoadAddr − KernelLoadAddr)` | `0xa3e8`–`0xa404` | `0x29C0000`=43.6 MB | `0x3000C0`=3.1 MB | 是（量级差 14×） |
| 10 | 解压输出长度 > 8 | `0x9f6c` | — | 3,145,920 ✅ | 是（仅压缩路径） |
| 11 | `Not Enough space`（`+0x58 > +0x40`） | `0x9b50`–`0x9b5c` | ✅ | ✅（差 ~25 MB） | 否 |
| 12 | **`LoadDtb` 追加 DTB 兜底** | `0xa868 cbnz` / `0xa98c` / `0xaab8` | **被跳过**（`GetDtb != NULL`） | **会进入**（`+0x84 ≠ 0`） | **★ 唯一实质差异** |
| 13 | `GetDtb()` best-match | `0xa85c`→`0x45da0` | 非 NULL | 未闭合 | 见 §3.4 |
| 14 | AVB（解锁态放行） | `0x1c3f8` `cset ne` | 放行 | 放行 | 否 |
| 15 | `fastboot boot` 未注册 | 命令表 27 条 | — | — | 否 |

**逐条结论：能称为「真内核多过了」的，只有第 12 条。** 其余要么两边都过（6/7/11/14），要么只是「走的代码不同但都不拦」（2/4/8/9/10）。

### 3.2 第 12 条的机制（本次把它钉死了）

`LoadDtb`（`0xa520`，由 `0x7fa4` 调用，**在 `blr` 之前**）的两条互斥走法：

```
a848  x0 = [sp+0x198]           ; "kernel" 缓冲
a84c  w1 = [sp+0x194]           ; "kernel" 长度
a850  x8 = &BootParams
a854  w2 = [x8, #0x84]          ; ★ dtb_offset
a858  x3 = [x8, #0x58]          ; dtb 目标地址
a85c  bl 0x45da0                ; GetDtb(kernel, len, dtb_offset, dtb_addr)
a868  cbnz x8, 0xae68           ; ★★ 非 NULL → 整段追加 DTB 逻辑被跳过
```

**原厂为什么必然走 `0xae68`：** 原厂内核**未压缩**，`+0xc2 = 0`，走 `0xa118` 未压缩路径；而全 PE 里写 `[BootParams+0x84]` 的只有 6 处（`0xa768`(v2)、`0xa7e4`(v3/v4)、`0x6bfac/0x6c228/0x6c3f0/0x6ca88`(无关结构)），**没有一处在未压缩路径上**。`BootParams` 被 `0x6a8c memset(0xd0)` 清零 ⇒ 原厂的 `+0x84` **恒为 0**。
若 `GetDtb` 返回 NULL，则会走到 `0xa87c subs` → `0xa880 b.lo 0xa950` → `a954 x8=ImageBuffer` → `a95c p = ImageBuffer + 0`（= `"ANDROID!"` 那 8 个字节）→ `0xa990 fdt_check` 必失败 → `0xae28 "Error: Device Tree blob not found."` → **状态 14**。
⇒ 原厂能开机这件事，**当且仅当 `GetDtb()` 对它返回非 NULL**。这是逻辑上的硬结论，不是推断。

**我们为什么必然进兜底路径：** gzip ⇒ `+0x84` 由 `0x9e90`（`x4 = BootParams+0x84`）交给 `DecompressImage` 写：
`0x6b7e4 ldr w8,[z_stream]`（`next_in`） − `0x6b7ec [sp+0xa8]`（`src` = `ImageBuffer+PageSize`） `+ 0x8` ⇒ **`+0x84 = gzip 流长**（`+8` 补的是 raw-deflate 没吃的 8 字节 trailer）。
我们的 DTB 实际在 `ImageBuffer + PageSize + gzip流长`，而兜底路径取 `p = ImageBuffer + 0x84`（`0xa964 cbnz` 对 v≠0 **不加** PageSize）⇒ **`p` 恒定早一个 `PageSize`** ⇒ `0xa990 fdt_check` 默认会失败。

**代入 v8 实测值（可复算）**：

```
page_size   = 2048
kernel_size = 1,232,233      (含尾接 DTB)
DTB 大小     = 279,147        ⇒ gzip 流长 = 953,086
真实 DTB 在  ImageBuffer + 2048 + 953,086 = +955,134
兜底取 p    = ImageBuffer + 953,086     → 差 2,048 B，指向 gzip 流尾部 ⇒ fdt_check 失败
```

⇒ **v1+hdr 的「追加 DTB 兜底路径」在算术上是坏的**（它只对 v0 成立：`0xa964 cbnz` 为 0 时会 `+PageSize`，正好补回）。要让判据成立，唯一出路是让 `GetDtb()`（`0x45da0`）成功——而它拿到的参数 `(kernel=[sp+0x198], len=[sp+0x194], offset=+0x84)` 与兜底路径**不是同一套基址**：`0x45da0` 内部做的是 `x8 = arg0 + arg1`（`0x45dc4`–`0x45dd0`）后再用 offset 去找，理论上可以正好落在真 DTB 上。

**这解释了团队观察到的现象**：6 棵 FDT 会多一条死法（`0xaab8`→`0xab58 "Not the single appended DTB"`），单棵版本少一条死法，但**两条路都只有 `GetDtb` 失败时才走**。所以「改单棵后通过 `0xa520`」这句话是否成立，**取决于 `GetDtb` 的返回值**——这是本报告 §8 里最该补的一条。

### 3.3 第 8 条里藏着一个对「木马内核」致命的反向结论

原厂走 `0xa394` 的 **43 MB `CopyMem`**（真搬运）；我们走 `dst==src` 的空操作。这不是风险，反而对我们有利。反过来说：**如果按路线 A 把 payload 换成真内核，我们就自动继承了那条 43 MB 拷贝和 43.6 MB 的 `image_size`**（检查 9），而 ABL 的可用窗口按 `abl-dtb-gzip` §2.3 的推导只有 **≈25.5 MiB**。
⇒ **真内核在 ABL 眼里比我们的 3 MB shim「更难过」而不是更好过。** 这一条单独就足以否定 A 作为「更容易通过的路径」的直觉。

（⚠️ 但这也暴露一个矛盾：原厂 `image_size = 43.6 MB > 25.5 MB` 却通过了检查 9 ⇒ §3.1 第 9 条用的「可用空间」数值或 `KernelSize` NV 变量的真值与本报告引用的推导不符。**这是团队此前结论里的一处内部矛盾，必须在做任何 A 类实验前先解决**，否则一切「过/不过」的判断都不可靠。）

---

## 4. 路线 A：真内核外壳 + 最早入口跳转

### 4.1 判定：**机械不可行；数据面收益只能用「不压缩」拿到，而那不需要真内核**

- **机械面 = 零**：§2 已证明交接状态与 payload 内容无关。把 192 B shim 换成 43 MB 真内核，`0x862c` 处的一切不变。
- **数据面**：唯一差异是第 12 条，而第 12 条的触发条件是「`+0x84 ≠ 0`」，即**压缩流路径**；真内核走的是未压缩路径（`+0x84 = 0`）。
  ⇒ **要把第 12 条变成「跟原厂一样」，需要的是「改成未压缩」，不是「换成真内核」。** 我们的 shim 也能未压缩（`kernel_compression = "none"`），体积还只有 3 MB。
  ⇒ **A 被自己的目的掏空：它想买的那张票，用一行 toml 就能买，而且不用背 43 MB。**

### 4.2 如果仍然要做（例如为了别的目的），具体步骤

前提：先用一支**未压缩**的 shim 验证 §3.2 的因果（见 §7 的 E1），因为 A 的价值完全建立在那个因果上。

1. **取真内核并保留其头部**：用 `E:\rom\work\linux-build\out\Image-6.14.0-rc5-tb331fc`（未压缩，38,959,616 B）。
   - `+0x00 code0/code1` = EFI stub 的 `MZ`+`ccmp` + 一条 `b`，**不要动**（`0xa270` 只查 `+0x38` 的 `"ARMd"`，头部原样最安全）。
2. **改 `stext` 而不是改 offset 0**：
   - 真内核的入口是 `Image+0x00` 的 `code1` 那条 `b`（本例 `0x146cb03b` → 目标 `0x1B2C0F0`）。把 `code1` 换成一条 `b` 指向**你插在内核尾部的跳板**（相对偏移可在 ±128 MB 内），跳板做「拷 FD 到 `0x5FC00000` → `dc civac` → `ic iallu` → `br`」。
   - 更省事的等价做法：**改 `stext` 的头 4 字节为 `b trampoline`**，把原指令保存到跳板里执行完再回来——但这条对我们没用（跳完就不回来了），直接 `b` 走即可。
3. **FD 放哪**（这一步决定成败）：
   - 不能放内核尾（会让 `image_size` 与实际不符，且 `+0x84` 语义更乱）；
   - 推荐**放进 ramdisk 段**：v1 头的 `ramdisk_size`（`+0x10`）改成 `192 + 0x300000`，把 `shim+FD` 作为 ramdisk 塞在 `boot+page+kernel_size` 之后。ABL 会把 ramdisk 拷到 `BootParams+0x50`，但**不会告诉内核它在哪**（v1 路径只传 `x0=FDT`）——所以还需要一条：跳板里从**固定物理地址**读，或者干脆用 `x0` 指向的 FDT 的 `/chosen` 传一个 `linux,initrd-start`（要改 DTB，工作量大）。
   - **更简单的做法：不放 ramdisk，直接复用现有 `requires_kernel_header` 布局**——即把 FD 放在内核之后并用 `image_size` 覆盖它，然后让 `stext` 跳板按**已知的固定偏移**（`Image + image_size_original`）读 FD。这要求 ABL 真的把那 3 MB 搬进内存（未压缩路径的 `CopyMem` 会搬，因为 `n = kernel_size` 包含 FD）。**这是 A 唯一在机制上成立的做法。**
4. **打包**：`header_version = 1`、`page_size = 2048`、`kernel_compression = "none"`、`kernel_size = 内核 + 192 + 0x300000`、`+0x08 text_offset = 0`（**必须为 0**，否则 `0x9808` 会把它加到装载地址上——这是 `abl-jump-analysis` §6.1 已经警告过的雷）、`+0x10 image_size` = 内核原值（**不要**加上 FD 的长度，否则检查 9 更容易越界）。
5. **判据**：
   - 屏幕出现我们画的色带/文字 ⇒ `blr` 到了、payload 跑了（A 成立，问题在 SEC）；
   - 8 s 后 PSCI 复位（即使屏黑）⇒ 同上，只是显示通道不通；
   - 一切静默且 30 s 无复位 ⇒ 没到 `blr`，A 无价值，转 §7 的 E1。

### 4.3 卡在哪（如果失败）

- 卡在 `0xa3e8`（`image_size` 越界，报 `DTB header can get corrupted due to runtime kernel size`）：无绕过，除非 `KernelSize` NV 变量确实 ≥ 40 MB。**做 A 之前必须先证伪 §3.3 的矛盾。**
- 卡在 `0xa87c`/`0xa91c`（`Dtb offset goes beyond the image size`）：说明 `GetDtb` 返回了 NULL 且 `+0x84 ≥ [sp+0x194]`，即 FD 被算进了「追加 DTB」的长度基准里。绕过方式：把 FD 放到**内核之后但 `+0x84` 之外**（`+0x84` 由 `DecompressImage` 只对压缩路径写，未压缩路径恒 0 —— 所以未压缩时 `+0x84 = 0 < len` 必然走 `0xa950`，`p = ImageBuffer + 0`，必失败）。**⇒ 未压缩 + `GetDtb==NULL` 是必死组合，没有绕过。**

---

## 5. 路线 B：真内核 + 最小 initramfs，在用户态/内核态跳 SEC

### 5.1 判定：**不可行**。五条硬障碍，任一条都是独立的否决理由

| # | 障碍 | 依据（机制，不是空谈） |
|---|---|---|
| B1 | **SEC 不重置 DRAM，但它依赖 XBL 留下的 SDRAM 训练/时钟状态之外的整片物理内存视图** —— 好消息是本题里「SEC 重init DDR」这个担心**不成立**；坏消息是它**不重 init 也照样要重写同一片地址**：Mu-Silicium 的 `MemoryMapLib` 是**硬编码**地址表（`sec-memory/REPORT.md` §1.1），SEC 一起就把 `0x5FF90000`+256 KB 清零、把 `0x5FF8D000` 起当 MMU 页表、并最终在 `0x5FC00000` 铺自己的 FV。这些地址此刻**正被 Linux 内核/页表/slab/页缓存使用** | `sec-memory/REPORT.md` §1.1/§1.3；`Sec/AArch64/ModuleEntryPoint.S:54-76` |
| B2 | **多核**：SEC 的进入前提是「只有 BSP 在跑，其余核停在 spin-table/WFI」。Linux 起来后 8 个核都在 `idle`/调度器里跑，`kexec` 的 `machine_kexec` 会用 PSCI `CPU_OFF` 收核，但**收完之后它们停在 PSCI 内部的安全世界**，而 SEC/PEI 之后会用 `ArmPsciMpCoreInfo`/spin-table 去找它们——两套约定不兼容 | arm64 `machine_kexec` 的行为属通用知识；Qualcomm PSCI 收核后由 TZ 掌控 |
| B3 | **异常级别不可逆**：Linux 在 EL1，`PSCI CPU_SUSPEND`/`OFF` 由 EL3 处理。要把 EL 抬回 EL2/EL3 才能在 EL2 上重建 UEFI 环境，而 AArch64 **没有「升高 EL」的指令**——只能靠 PSCI `SYSTEM_RESET` 或 TZ 的 `smc` 服务。所以「在 Linux 里原地降级/升级到固件环境」在 ISA 层面**做不到**，除非走一次真复位 | AArch64 特权模型 |
| B4 | **MMU/cache 状态无法干净倒退**：Linux 的 `SCTLR_EL1` 带 `RES1` 位（`SCTLR_EL1` bit 11/20/22/23/28 必须为 1，ARMv8.0+ RES1），用户态无法写系统寄存器；内核态要「先把所有 cache 清干净再关 MMU 再跳」，但 FD 需要的 3 MB 目标区间可能已被当作 normal memory 且**没有 identity 映射**，一关 MMU 就取不到指令 | 通用 arm64 知识 + §2.3（ABL 自己都没关 MMU） |
| B5 | **没有任何 UEFI 运行期服务能帮上忙**（反例排除）：`efi_reboot`/`efi_set_virtual_address_map` 只调 **runtime services**，而 Mu-Silicium 的 FD 一旦被 `ExitBootServices` 过就不再有 Runtime 段可用；我们的 FD 是「从 SEC 起全新固件」，不是 runtime 服务 | — |

**唯一的「看似可行」变体**：不在 Linux 里跳 SEC，而是 `kexec` 到**另一个内核**。那等于把 B 退化成「真内核 → 真内核」，与本题目标（拿到 UEFI）无关。

### 5.2 变体：kexec 到「EFI stub 形态的 UEFI FD」——先例检索结果

- **方向性反例（确凿）**：`LinuxBoot`（coreboot/UEFI → Linux → kexec 再启动）是**固件 → Linux**，与本路线相反的正是本项目要的那一段；`heads`、`u-root`、`coreboot` 的 payload 体系同理（web 检索命中的 [coreboot](https://www.coreboot.org/) 只覆盖「刷固件」这一侧）。
- **「Linux 里直接跳进一颗完整固件镜像」没有公开先例**：`kexec` 的内核目标、`kexec_file_load` 的 PE 支持（`CONFIG_KEXEC_FILE` 的 arm64 PE 装载器）都只认「内核/PE 内核」，而**PE 支持不等于 EFI 应用支持**——它要求 PE 里有 `Image` 头 + `"ARMd"`，而 UEFI FD 的 SEC 是 TE 镜像（`sec-memory/REPORT.md` §6 附注实测：TE，`ImageBase=0x5FC00000`、`EntryPoint=0x1000`），既不是 `Image` 也不是 PE32+。
- **Qualcomm 平台上的反例**：Mu-Silicium / Renegade 在小米、联想机型上**全部**走「BootShim + FD 塞 boot 分区」，没有一台是「先起 Linux 再跳固件」。
- **结论**：**证据不足 + 无先例**。且这不是「没人想到」，而是被 B1–B4 四条机制挡住。

---

## 6. 路线 C：`stext` 之后、`start_kernel` 之前 hook

### 6.1 判定：**可行，但严格劣于 A，且 A 本身已经证明机械上无收益**

技术上能做：`__primary_switched`（`arch/arm64/kernel/head.S`，在 `start_kernel()` 之前、MMU 已开、栈已切到 init_task）插入「拷 FD → 跳 SEC」是可行的——它就是 A 的跳板往后挪了几百条指令。

但代价严格更大：

| 项 | A（`stext`/`code1` 跳板） | C（`__primary_switched` 跳板） |
|---|---|---|
| ABL 侧检查 | 完全相同 | **完全相同** |
| 需要 MMU 状态 | 与 ABL 交来的相同（开） | 必须**先关自己的 MMU**、清 cache、再跳 → 多一层自我拆解，且 C 关 MMU 后 SEC 又要在**没有页表**的状态下设栈（SEC 不建页表就先写 `0x5FF9xxxx`）→ 必挂 |
| 需要能装下整颗内核 | 是（43 MB） | **是（同样 43 MB，不可能更小）** |
| 多余工作 | 无 | 内核已经跑过 `init_kernel_el`/`__cpu_setup`，改写了 `SCTLR_EL1`（开 MMU、开 D-cache、`TCR`/`TTBR` 全换），要把这些**逐位还原到 ABL 交来时的样子**，而我们并不知道 ABL 的原值（§2.3 已证明 ABL 从不写 SCTLR，值是 XBL 留下的，我们没读过） |

⇒ **C 的唯一「优势」是内核先把自己初始化了一遍**，但那恰恰是它更危险的原因：它把「我们不知道原值」的那些寄存器全改了。

### 6.2 若坚持要做（不推荐）

可以，但必须先解决 §6.1 表格最后一行：在 `stext` 第一行保存 `SCTLR_EL1/TTBR0_EL1/TCR_EL1/MAIR_EL1` 到固定内存（`0x5FFF7000` 是 MemoryMapLib 的 Log Buffer，8 KB，`RtData`），C 的跳板再把它们写回去。**这等于自己写一遍 kexec 的 arm64 CPU 状态保存/恢复**，而收益是 0（ABL 检查一条都不多过）。

---

## 7. 建议的下一步（按信息增益排序，全部离线可做，判据二值化）

> 原则：**先把「payload 到底有没有跑起来」变成两三个像素/一次复位，再谈改什么。** 现在所有结论都挂在这个洞上。

### E0（必做，0 成本，已有镜像）——把「复位」当读出口

> 注：`E:\rom\work\woa\sentinel\`（v9，并行进行中）已经在做像素哨兵。本报告不重复它，只补两条它需要的东西：**SEC 那三条带不可信**（§2.6-1），**shim 画之前要补一遍 `dc civac`**（§2.6-2）。

现有 `Mu-tb331fc-probe-single.img` 是「整屏洋红 → 停 30 s → PSCI `SYSTEM_RESET`」。
**判据不看颜色，看复位**：`continue` 之后 **25–35 s 内** 设备是否自己重启（USB 重枚举 / logo 重新开始 / `btime` 归零）。

- **有复位** ⇒ `blr` 到了、payload 跑了、SEC 前的链条全通 ⇒ **全部 ABL 侧假设（含 §3 的表）作废，问题在 SEC**；
- **60 s 无复位** ⇒ `blr` 没到（或到了但连 PSCI 都调不动）⇒ §3.2 的 `GetDtb` 假设成为头号嫌疑。

这一条**不需要改任何东西**，只需要一次刷机 + 盯 30 s。

### E1（高价值，改一个字段）——把 payload 改成**未压缩**，让第 12 条与原厂一致

`abl-jump-analysis` §6.1 警告过「关压缩 = 换死法」，但那是因为它把 `text_offset` 留成了 `0x5FC00000`。**`text_offset` 改 0 之后这条警告不成立**（`0x9818` 加 0，装载地址仍是 `base(+0x80000)`，且 shim 是 PC 相对的，`0x40000000` 与 `0x40080000` 都能跑）。

- 改哪里：构建树 toml 的 `kernel_compression` 改 `"none"`；`BootShim/Makefile:13` 的 `REQUIRES_KERNEL_HEADER` 保持 1；**`BootShim.S` 里 `text_offset` 那个 `.quad FD_BASE` 改成 `.quad 0`**（第 7 行附近）。
- 为什么值得：未压缩 ⇒ `+0xc2 = 0` ⇒ `+0x84` 恒 0 ⇒ 与原厂**在同一条数据路径上**。这是唯一能把「我们 vs 原厂」的差异从 1 条降到 0 条的单点改动。
- 判据：与 E0 同一套（看复位/颜色）。若 E0 显示「无复位」，E1 之后出现复位 ⇒ §3.2 因果成立，且我们拿到了与原厂同构的打包方式。

### E2（诊断向，最贵但最硬）——`0x5FFF7000` 进度戳 + 9008 回读

`0x5FFF7000` 是 MemoryMapLib 的 `Log Buffer`（8 KB，`RtData`），且**不在** ABL 的 `dc civac` 覆盖范围内（§2.4）。
在 `BootShim.S` 第一行、`br x5` 前、`SEC._ModuleEntryPoint` 第一行各写一个 u32 魔数（`0x5EC00001/02/03`），挂了之后用 `auto_900e.py` 的 Sahara `MEMORY_DEBUG` 回读。**这能把「谁死了」变成三段二值。** 团队已有这套工具链（`work\tools\auto_900e.py`、`work\forensics_900e\`）。

---

## 8. 未闭合 / 证据不足（不要当结论用）

| 缺口 | 影响 | 怎么补 |
|---|---|---|
| **`GetDtb()`（`0x45da0`）对本机到底返回 NULL 还是非 NULL** | 决定 §3.2 第 12 条是否真的被执行；是本报告唯一无法静态闭合的点 | 反汇编 `0x45da0` 全部 best-match 分支（它会打 `"Best match DTB tags …"` / `"DTB offset is incorrect, kernel image does not have appended DTB."`）；或 E2 的进度戳 |
| **`KernelBaseAddr` / `KernelSize` 真值**，以及由此推出的「可用窗口 ≈25.5 MiB」 | §3.3 存在内部矛盾：原厂 `image_size = 43.6 MB > 25.5 MB` 却通过了检查 9 ⇒ 二者必有一错 | 读 `logfs`/UART 里 ABL 打印的 `"Kernel Load Address: 0x%x"`（`0x7ae4`，串 `0xa0762`）；或 9008 读 UEFI 变量 |
| `BootLinux` 的调用者（`bl 0x6a34` 全 PE 零命中，也无 `adrp 0x6a000`；`0x6a34` 的 8 字节小端指针全文件零命中） | 决定「`BootLinux` 返回非 0 之后设备是留在 fastboot 还是 CpuDeadLoop」。**这直接决定「离开 fastboot」能不能证明 `blr` 到了** | 找 `.data` 里的命令表（`0xb0000`–`0xc0000` 的指针池）或看 fastboot `continue` 的 handler |
| `0x28ad0`（`0xa834` 调用，返回值写 `[sp+0x1e0]`，为真就跳过整个 `GetDtb`+兜底） | 可能是「DTB 已从 dtbo 拿到」的快速通道 ⇒ 若它对本机返回真，`LoadDtb` 全程无害 | 反汇编 `0x28ad0` |
| A17 内核的 `image_size = 0x29C0000` 与 `KernelSize` NV 的关系 | §3.3 | 同上 |
| 原厂 `boot_a.bin`（`E:\rom\work\of\v3\stock\`）已不存在 | 本报告改用 A17 的 `boot_a.img`；若要对比 ZUI 内核需另找 | — |

---

## 9. 附录：本报告新增/复核的地址

| VA | 含义 | 证据 |
|---|---|---|
| `0x6a30`–`0x8678` | `BootLinux` 全身，**1811 条指令，0 条 sysreg/cache/tlb/barrier** | 全区间穷举 |
| `0x6a58` | `strb w1,[sp,#0x1d4]`（`BootLinux` 第 2 个参数的字节） | — |
| `0x7154`→`0xa678` | `BootInfo+0x458`（header_version）→ `[sp+0x1d4]` | `0xa678`–`0xa680` |
| `0x8590` | `bl 0x34810` ← **交接前的唯一准备函数** | — |
| `0x348a8` / `0x348ac` / `0x348b0` | `bl 0x141b8` / `DAIFSet #3`（IRQ+FIQ） / `DAIFSet #4`（SError） | 逐指令 |
| `0x350a4` → `0x3503c` → `0x14054` | `CleanDataCacheRange(start,len)`，2 MiB 对齐，`fn = dc civac` | `0x350a4` 内 `adrp 0x14000; add #0x54` |
| `0x3491c` → `0x14064` | `ic iallu`（整颗 I-cache） | — |
| `0x351a8`–`0x351c0` | `ArmInvalidateTlb`：`tlbi vmalle1`/`alle2`/`alle3` + `dsb sy; isb`，按 `CurrentEL` 分支 | — |
| `0x1408c`–`0x141a8` | 全 PE **仅有的** 18 处 `SCTLR` 访问（ArmLib 辅助），**跳转前无一被调用** | 全 PE 扫描 |
| `0x8610`/`0x861c`/`0x8620`–`0x8628`/`0x862c` | 入口 / `x0=FDT` / `x1=x2=x3=0` / `blr` | — |
| `0x8630` → `0x8634` → `0x66ec` | payload `ret` → **CpuDeadLoop**（`str xzr,[sp]; ldr x8,[sp]; cbz x8,self`） | `0x66ec`–`0x6708` |
| `0x7fa4` / `0x7fb0` / `0x7fc0` / `0x8648` | `LoadDtb` / 非 0 → `0x7fbc` → **`0x8648` = 正常 epilogue（不是 deadloop）** | 逐指令 |
| `0xa848`–`0xa868` | `GetDtb(kernel,len,+0x84,+0x58)`；`cbnz → 0xae68` **跳过整段追加 DTB** | 逐指令 |
| `0xa87c`–`0xa880` | `+0x84 < [sp+0x194] ? b.lo 0xa950`（否则 `0xa91c` 状态 4） | — |
| `0xa954`–`0xa95c` | `p = ImageBuffer + [+0x84]` ← **兜底路径的基址是 `ImageBuffer`，不含 PageSize** | 逐指令 |
| `0xa964`–`0xa988` | `if (header_version == 0) p += PageSize` ⇒ **v1 拿不到这一补** | 逐指令 |
| `0xa684`–`0xa68c` | `version < 2 → 0xa82c`，**v0/v1 不写 `+0x84`** | 逐指令 |
| `0xa6f8`–`0xa700` | `version != 2 → 0xa7ac`（v3/v4 分支） | — |
| `0xa768` / `0xa7e4` | `+0x84 = PageSize × pagecount`（v2 / v3-v4 各自一套），**v0/v1 走不到** | 逐指令 |
| `0x6b7e4`–`0x6b7fc` | `out1 = (UINT32)next_in − (UINT32)src + 8`（`src = ImageBuffer+PageSize`）⇒ **= gzip 流长** | 逐指令 |
| `0x102c0` | `align_up` 辅助（`(x + a − 1) / a`，返回**页数**不是字节数） | 逐指令 |
