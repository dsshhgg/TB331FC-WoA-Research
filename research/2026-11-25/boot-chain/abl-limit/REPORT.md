# ABL（LinuxLoader）ramdisk 总量上限 —— 地址级定论

- 日期：2026-11-25
- 对象：`E:\rom\work\zui17_images\abl.img` → 内层 `Z17_9e21fd93_lz_f536d559_PE32_at_0xb4.bin`
  （970,752 B，PE32+ AArch64，**sha256 `33CA0240027D83CB930B4C263CEB54C5B9884442FE5EB84D20E23E18B9D25123`**）
- **二进制同一性已闭环**：设备 9008 回读的 `abl_a` 整分区（`readback_abl_a.bin`，1,048,576 B）
  == `abl.elf`(274,432 B) + 全零填充（逐字节比对通过）；`abl.elf` 的 sha256 = `FB5F9C18…`。
  所以下面这些地址说的就是**这台设备上正在跑的那份代码**。
- 反汇编：`E:\rom\work\woa\abl-jump-analysis\full.asm`（llvm-objdump，VA == 文件偏移；
  PE 头实测：`.text VA=0x1000 rawptr=0x1000`，`.data 0xc0000/0xc0000`，`.reloc 0xeb000/0xeb000` → 约定成立）
- 复核工具（本次新写，在 `E:\rom\work\abl-limit\`）：`csdis2.py`（capstone 按 VA 反汇编任意 PE）、
  `grepva.py` / `writes.py`（区间内指令/写点扫描）、`strref.py` / `refs_any.py`（adrp+add 串交叉引用）、
  `boothdr.py` / `probe_boot.py`（boot 头与内核 `image_size` 实测）、`calc.py`（上限数值推算）
- 性质：**只读静态分析**，未刷机、未改任何镜像。

---

## 0. 一句话结论（先说会给 lead 的那个数）

**0xbff4 那条检查不是"上限"，它是一个 64 位回绕检查**：`[sp+0x98]` 是**在函数入口被写成 0、此后全函数再无任何写点**的局部变量，
所以 0xbfe0–0xbff4 实际算的是 `0 − RamdiskLoadAddr − total`，等价于
**`RamdiskLoadAddr + total` 是否溢出 2^64**——也就是「`bi+0x50` 是否下溢成巨值 / 是否为 0」的合法性检查；
只要 `top` 正常（本机 `bi+0x50 ≈ 0x43C18000`），它**恒放行**，与 ramdisk 是 14 MB 还是 200 MB 无关。
**真正管 ramdisk 大小的闸门在别处**：`QueryBootParams` 的 `0x9b5c`（DTB 区要给内核留位置）和
`LoadKernel` 的 `0xa400`（可用空间必须 ≥ 内核镜像 `image_size`）。两者都由
`top = KernelBaseAddr + KernelSize` 与 `KernelLoadAddr` 之差决定。

> **单位约定**：`xxx B` 为精确字节数；括号里的 `xx.xx MB` 一律是 **MiB（1 MiB = 1,048,576 B）**。
> 例：31,707,004 B = 30.24 MiB = 31.7 MB（十进制）。能不能过只看字节数，别看"MB"。

代入本机实际布局（`KernelBaseAddr=0x40000000`、`KernelSize=0x5700000`、`top=0x45700000`、
原厂内核是非压缩 `Image`（`text_offset=0`）⇒ `KernelLoadAddr=0x40000000`）：

| 内核（boot.img 里的 `image_size`） | ramdisk **总量**上限 | **recovery ramdisk 单项**上限 |
|---|---|---|
| 原厂 ZUI16 A14（`0x2D50000` = 47,513,600） | 41,607,168 B（**39.68 MiB**） | 27,971,452 B（**26.68 MiB**） |
| **当前 KSU 内核**（`0x29C0000` = 43,778,048） | 45,342,720 B（**43.24 MiB**） | **31,707,004 B（30.24 MiB）** |
| 自编 Linux 内核（`0x25F0000` = 39,780,352） | 49,340,416 B（47.05 MiB） | 35,704,700 B（34.05 MiB） |

→ **给 lead 的口径**：recovery ramdisk **安全上限 = 30,000,000 B**（实测已过）；
**理论极限 = 31,707,004 B（30.24 MiB，当前 KSU 内核）**。
一旦换回原厂内核，极限掉到 27,971,452 B（26.68 MiB），安全值要按 26,000,000 算。
详见 §4、§5。

---

## 1. Q1 —— `[sp+0x98]` 到底是什么

### 1.1 它是"入口清零、全程只读"的局部变量

`LoadRamdisk`（`0xbe10`）的序：

```
0xbe10  sub   sp, sp, #0xe0          ; 帧 0xe0
0xbe14  str   x30, [sp, #0xd0]
0xbe18  adrp  x8, 0xc0000            ; 栈金丝雀（全局 @0xc0000）
0xbe1c  ldr   x8, [x8]
0xbe20  str   x8, [sp, #0xc8]
0xbe24  str   x0, [sp, #0xb8]        ; x0 = Info   （ii）
0xbe28  str   x1, [sp, #0xb0]        ; x1 = BootInfo（bi）
0xbe2c  mov   x8, xzr
0xbe30  str   x8, [sp, #0x98]   ★★★  ← 唯一写点：写 0
0xbe34  str   x8, [sp, #0x90]        ; 局部 2（本函数内也未再写）
0xbe38  str   x8, [sp, #0x80]        ; 局部 3（本函数内也未再写）
```

**排除法（穷举）**：对 `0xbe10 … 0xc7d0`（整个函数，含全部 5 段 `CopyMem` 分支）做「任何指令里出现 `0x98`」的扫描，
命中只有 7 条，其中**写点仅 `0xbe30` 一条**：

```
0xbe30  str  x8, [sp, #0x98]     ← 写（=0，入口）
0xbfd4  ldr  w9, [x9, #0x98]     ← 读 bi+0x98（recovery ramdisk 大小）
0xbfe0  ldr  x8, [sp, #0x98]     ← 读，就是那条"上限"
0xc250  ldr  w8, [x8, #0x98]
0xc27c  ldr  w9, [x9, #0x98]
0xc28c  ldr  w8, [x8, #0x98]
0xc4ac  adrp x1, 0x99000         ← 恰好含 "0x98" 的地址常量，非本槽
```

并且函数体内**没有任何 `add x?, sp, #0x98`**（即没有把它当 out 参数传出去），**没有 `add sp` / `stp` 改写帧基址**，
`0xbe10→0xbfe0` 之间**没有任何 `bl`**（所以也没有"被调函数往调用者栈槽里写"这条路）。

⇒ **`[sp+0x98] ≡ 0`（整个函数生命周期）**。它既不是 `KernelLoadAddr`，也不是 `0x60000000` 之类的常量，
也不是从 `bi` 取来的字段——它是 Qualcomm 源码里那个"理论上该填上限、本 build 被编译成 0"的局部。

> 字节级复核：capstone 直接读原始 PE（不是读 full.asm）：
> `0xbe2c: mov x8, xzr` / `0xbe30: str x8, [sp, #0x98]` / `0xbfe0: ldr x8, [sp, #0x98]`，
> 与 objdump 完全一致 ⇒ 不是反汇编错位。ZUI15 的 ABL（966,656 B 的 PE）在同样地址上是**逐条相同**的代码，
> 所以这不是 ZUI16 独有的一次事故。

### 1.2 因此 0xbff4 是"回绕检查"，不是"上限检查"

```
0xbfc4  ldr  x9, [sp, #0xb0]        ; x9 = bi
0xbfc8  ldr  w8, [x9, #0x78]        ; bi+0x78  init_boot ramdisk 大小（已被 0x7634 改写成 align_up）
0xbfcc  ldr  w10,[x9, #0x94]        ; bi+0x94  vendor_ramdisk_size
0xbfd0  add  w8, w8, w10            ; 32 位加（会回绕也没有检查）
0xbfd4  ldr  w9, [x9, #0x98]        ; bi+0x98  recovery ramdisk 大小
0xbfd8  add  w8, w8, w9             ; total（u32）
0xbfdc  str  w8, [sp, #0x8c]        ; [sp+0x8c] = total
0xbfe0  ldr  x8, [sp, #0x98]        ; x8 = 0（见 §1.1）
0xbfe4  ldr  x9, [sp, #0xa0]        ; x9 = RamdiskLoadAddr（§2：= bi+0x50）
0xbfe8  subs x8, x8, x9             ; x8 = 0 − addr = 2^64 − addr（借位 C=0，除非 addr==0）
0xbfec  ldr  w9, [sp, #0x8c]        ; w9 = total（零扩展）
0xbff0  subs x8, x8, x9             ; x8 = 2^64 − addr − total；C=1 ⇔ addr+total ≤ 2^64
0xbff4  b.hs 0xc0c4                 ; C=1 → 放行
```

- **放行侧 `0xc0c4`**：接着做「`ImageBuffer + bi+0x7c` 是否回绕」的检查，然后往下走 5 段 `CopyMem`。
- **拒绝侧 `0xbff8…0xc0b4`**：`0xc090` 取串 **`0xaa894` = `"Error: Ramdisk size is over the limit\n"`**，
  最后 `0xc0b4: mov x8,#4; movk x8,#0x8000,lsl#48; str x8,[sp,#0xc0]; b 0xc7c0` ⇒ 返回 `0x8000000000000004`。

**语义换算**：`2^64 − addr − total` 只有两种情况会借位（= 报错）——

1. **`addr + total > 2^64`**，也就是 **`RamdiskLoadAddr` 本身是由下溢算出来的**（`top` 太小，
   `0x9b2c subs x8, x8, x10` 借位，`bi+0x50` 变成接近 2^64 的巨值）。这对应"`KernelBaseAddr`/`KernelSize`
   变量取不到 / `top` 异常小"——**这才是这条检查真正的用途：拦 `bi+0x50` 的下溢**。
2. **`addr == 0` 且 `total > 0`**（`top` 恰好等于 `align_up(total)+page` 时的退化情形）。

⇒ 换句话说：**它是 `RamdiskLoadAddr` 的合法性（非下溢、非 0）检查，不是 ramdisk 大小检查**。
只要 `top` 正常（本机 `bi+0x50 ≈ 0x43C18000`），它**恒放行**，无论 ramdisk 是 14 MB 还是 200 MB。

> **对前两份报告的更正/确认**：
> - `work\img-abl\REPORT.md` §2.2 已把 0xbff4 正确写成"2^64 回绕"，但它把这条列进「会拒绝跳转的原因（L5/L5'）」时
>   容易让人误读成"有上限"。**准确说法：它不是上限；它在正常机器上恒放行。**
> - `work\of\_study\ABL_RAMDISK_EVIDENCE.md` §3 把 0xbfe0 写成 `if (bi+0x50 + 总长 > 可用)`——**这句是错的**，
>   正确读法是 §1.2 的"回绕检查"。

---

## 2. Q2 —— `RamdiskLoadAddr`（`bi+0x50`）从哪来

写完在 **`0x9b30`**，出自 `QueryBootParams`（`0x9660`）尾部：

```
0x9af4  ldr  x9, [sp, #0x48]        ; x9 = bi
0x9af8  ldr  x8, [x9, #0x48]        ; x8 = bi+0x48 = top（内核区域顶，= KernelBaseAddr + KernelSize，见 §3）
0x9afc  ldr  w10,[x9, #0x78]        ;   bi+0x78  init_boot ramdisk（GKI 路径已被改写成 align_up(ramdisk_size,page)）
0x9b00  ldr  w11,[x9, #0x94]        ;   bi+0x94  vendor_ramdisk_size
0x9b04  add  w10,w10,w11
0x9b08  ldr  w11,[x9, #0x98]        ;   bi+0x98  recovery ramdisk size
0x9b0c  add  w10,w10,w11            ; w10 = total（u32）
0x9b10  ldr  w11,[x9, #0x6c]        ; w11 = page_size
0x9b14  add  w10,w11,w10            ; total + page
0x9b18  subs w10,w10,#1
0x9b1c  mov  w12,wzr
0x9b20  subs w12,w12,w11            ; w12 = −page
0x9b24  and  w10,w10,w12            ; w10 = align_up(total, page)
0x9b28  add  w10,w10,w11            ; w10 = align_up(total, page) + page
0x9b2c  subs x8, x8, x10
0x9b30  str  x8, [x9, #0x50]   ★    ; RamdiskLoadAddr = top − (align_up(total,page) + page)
0x9b34  ldr  x9, [sp, #0x48]
0x9b38  ldr  x8, [x9, #0x50]
0x9b3c  ldr  w10,[x9, #0x6c]
0x9b40  add  w10,w10,#0x200, lsl #12 ; page + 0x200000（2 MB DTB 预留）
0x9b44  subs x8, x8, x10
0x9b48  str  x8, [x9, #0x58]   ★    ; DtbLoadAddr = RamdiskLoadAddr − (page + 2 MB)
0x9b4c  ldr  x9, [sp, #0x48]
0x9b50  ldr  x8, [x9, #0x58]        ; Dtb
0x9b54  ldr  x9, [x9, #0x40]        ; KernelLoadAddr
0x9b58  subs x8, x8, x9
0x9b5c  b.hi 0x9c2c                 ; Dtb > KernelLoadAddr → 放行；否则↓
        …（0x9bf8/0x9bfc 取串 0xa077d）"Not Enough space left to load kernel image" → 返回 5
```

**所以本机的内存布局是"从顶往下摊"**：

```
KernelLoadAddr (= bi+0x40)                 ← 内核被解压/拷到这里（见 §3.3 的两种算法）
        │  ← 这段就是「留给内核的空间」= 唯一真正会卡住 ramdisk 的资源
DtbLoadAddr  (= bi+0x58)                   ← DTB
        │  2 MB + page
RamdiskLoadAddr (= bi+0x50)                ← ①vendor_ramdisk ‖ ②recovery_ramdisk ‖ ③init_boot ramdisk ‖ ④bootconfig
        │  align_up(total,page) + page
top (= bi+0x48 = KernelBaseAddr + KernelSize)
```

由此得到两条**与 ramdisk 大小直接相关的硬闸门**：

| # | 地址 | 条件 | 失败表现 |
|---|---|---|---|
| **G1** | `0x9b5c` | `top − align_up(total,page) − 2·page − 0x200000 > KernelLoadAddr` | `"Not Enough space left to load kernel image"`（`0xa077d`），`QueryBootParams` 返回 5，`BootLinux` 在 `0x7860` 早退 |
| **G2** | `0xa400`（在 `LoadKernel` 里） | `image_size(内核) ≤ Dtb − KernelLoadAddr` | `"DTB header can get corrupted due to runtime kernel size"`（`0x98760`，打印点 `0xa4a0`），返回 `0x8000000000000009`，`BootLinux` 在 `0x7894` 早退 |

G2 的代码（`LoadKernel` 收尾，两段 `CopyMem` 之后）：

```
0xa3e8  ldr  x8, [sp, #0x80]
0xa3ec  ldr  x8, [x8, #0x10]        ; x8 = 内核镜像头 +0x10 = image_size
0xa3f0  ldr  x10,[sp, #0x90]
0xa3f4  ldr  x9, [x10, #0x58]       ; Dtb
0xa3f8  ldr  x10,[x10, #0x40]       ; KernelLoadAddr
0xa3fc  subs x9, x9, x10            ; available
0xa400  subs x8, x8, x9             ; image_size − available
0xa404  b.ls 0xa4d4                 ; ≤0 → 放行
```

> 补充：`0x9d8c` 还有一条 `available >> 32 != 0` → `"Integer Overflow: the length of decompressed data"`（`0xab543`，打印点 `0x9e3c`），
> 只在 4 GB 以上才可能命中，与本机无关。

**结论**：上限**不是常量**，而是 `top − KernelLoadAddr − 2 MB − 2·page − 内核所需空间`。
下面把 `top`、`KernelLoadAddr`、`内核所需空间` 三项逐个钉死。

---

## 3. Q3 —— 设备真实布局：`KernelBaseAddr` / `KernelSize` / `KernelLoadAddr`

### 3.1 `top`（`bi+0x48`）= `KernelBaseAddr + KernelSize`，两者都读 UEFI 变量

```
0x975c  add  x0, sp, #0x60 ; add x1, sp, #0x58 ; bl 0x10160     ; 桩（恒写 0，供 fallback 用）
0x9768  add  x0, sp, #0x68 ; add x1, sp, #0x70 ; bl 0x101c0     ; ★ GetKernelBaseAddr：gRT->GetVariable
                                                               ;   L"KernelBaseAddr" @0xafa0e（UTF-16）
                                                               ;   L"KernelSize"     @0xaf964（UTF-16）
                                                               ;   GUID 882f8c2b-9646-435f-8de5-f208ff80c1bd @0xbf0bc
0x984c  ldr  x8,[sp,#0x60] ; ldr x9,[sp,#0x58] ; add x8,x8,x9 ; str → bi+0x48   ← fallback（变量取不到）
0x9864  ldr  x8,[sp,#0x68] ; ldr x9,[sp,#0x70] ; add x8,x8,x9 ; str → bi+0x48   ★ 主路径
```

### 3.2 `KernelSize = 0x5700000`、`KernelBaseAddr = 0x40000000` ⇒ `top = 0x45700000`

| 证据 | 内容 |
|---|---|
| **XBL 的板级内存表**（`E:\rom\work\img-xbl\cfg\FD_uefiplat.cfg`，第 9–10 行） | `0x40000000, 0x05700000, "Kernel", …, Reserv`；下一行 **`0x45700000, 0x00600000, "HYP"`**。<br>⇒ 「Kernel」保留区**正好是 DDR 基址到 HYP 基址**：`0x40000000 + 0x5700000 = 0x45700000` |
| **内核看到的实际内存**（`work\system-profile\dmesg_head.txt`） | `node 0: [mem 0x0000000040000000-0x00000000456fffff]`（第一段可用内存**止于 `0x456fffff`**）；随后 `hyp_region@45700000`<br>⇒ 与 `top = 0x45700000` 严丝合缝 |
| DDR 基址 | `PHYS_OFFSET: 0x40000000`（900E 转储 `forensics_900e\auto_20261113_114831\ramdump_scan.md:380`）；`Normal zone [0x40000000-0x1BFFFFFFF]`（6 GiB） |
| **两侧夹逼（本报告新增，能反证其它取值）** | ① 下界：原厂 boot 必须能起 ⇒ `KernelSize ≥ image_size(0x2D50000) + 0x200000 + 2·page + align_up(原厂 total)` = **`0x4A39000`**（77,828,096）；<br>② 上界：ramdisk 顶点不能压到正在运行的 HYP（0x45700000）⇒ `KernelSize ≤ 0x5700000`。<br>⇒ `KernelSize ∈ [0x4A39000, 0x5700000]`，而**板级表给的唯一值 0x5700000 正好在区间顶端** |

**因此可以确定：`KernelBaseAddr = 0x40000000`、`KernelSize = 0x5700000`（87 MB）、`top = 0x45700000`。**

> **更正 `woa\abl-jump-analysis\REPORT.md` §3.3/§3.4 的一处硬伤**：那里把 `KernelSize` 推断成 **`0x3C00000`（60 MB）**。
> 60 MB 是**错的**，反证：若 `top = 0x43C00000`，则原厂启动的 available =
> `0x3C00000 − align_up(28,208,670) − 2·page − 0x200000` = **31,944,704**，
> 小于原厂内核 `image_size = 47,513,600` ⇒ **原厂机子当场就该在 0xa400 报错、开不了机**，与"设备正常开机"矛盾。
> `0x3c00000`（以及 `0x5600000`）只是常量页 `0xbefd8/0xbefdc/0xbefe0/0xbefe4` 里**给"UEFI 变量取不到"的 fallback 分支用的**：
> 对应代码 `0x9990..0x99f0`（`0x9994 ldr w8,[x8,#0xfe0]` → 32 位内核用 `0xfe4=0x8000`、arm64 用 `0xfe0=0x3c00000`；
> `0x99ec ldr w8,[x8,#0xfdc]` → `0x5600000`），且那段路径里 base 来自桩 `0x10160`（=0）。
> **实测常量页内容**（直接读 PE 字节）：`0xbefd8=0x80000`、`0xbefdc=0x5600000`、`0xbefe0=0x3c00000`、`0xbefe4=0x8000`。

### 3.3 `KernelLoadAddr`（`bi+0x40`）：本机走"非压缩"分支 ⇒ `= KernelBaseAddr + text_offset = 0x40000000`

```
0x97a0/0x97a8  主路径：KernelLoadAddr = KernelBaseAddr（先原样）
0x97b0..0x97cc KernelNotArm64? → += 0x8000
0x97e8/0x97f0  KernelCompressed(bi+0xc2)?  → 0x9824（压缩路径）
0x97f8..0x9800 未压缩且 image_size==0 → 0x9824
0x9808..0x981c ★ 未压缩：KernelLoadAddr += text_offset（内核头 +0x08）
0x9824..0x9830 ★ 压缩：  KernelLoadAddr = base + 0x80000
```

**实测三个内核都是"非压缩 `Image` + EFI stub"**（这不是猜的，是读 boot 头与内核头实测）：

| 来源 | `kernel_size`（boot 头 +0x08） | 内核头 `text_offset`(+0x8) | `image_size`(+0x10) | 头 `+0x38` |
|---|---|---|---|---|
| 原厂 `ZUI_16.0.544\image\boot.img` | 46,819,840 (`0x2CA6A00`) | **0** | **47,513,600 (`0x2D50000`)** | `ARMd` ✓ |
| `work\TB331FC-kernel\boot-main-1.3.2.img`（现役 KSU） | 43,092,480 | **0** | **43,778,048 (`0x29C0000`)** | `ARMd` ✓ |
| `work\linux-boot\out\boot_a-linux.img` | 38,959,616 | **0** | **39,780,352 (`0x25F0000`)** | `ARMd` ✓ |

（payload 首 2 字节实测 `4d 5a` = `MZ`，即 EFI-stub 裸 `Image`；`0x95f0` 用 `"ARMd"`(0x644d5241) 比 `+0x38` 命中 ⇒ `bi+0xc0=0`，
走不到 32 位分支。压缩探测在 `0x9598 bl 0x6b950`，返回 0 ⇒ `bi+0xc2=0`。）

⇒ **`KernelLoadAddr = 0x40000000 + 0 = 0x40000000`**（原厂与现役 KSU 内核都是）。
（若换成 gzip 内核，`KernelLoadAddr` 变 `0x40080000`，所有上限**统一减 0x80000 = 512 KiB**。）

### 3.4 三项 `ramdisk` 字段的实测值（决定 total）

| 字段 | 含义 | 原厂实测 | 来源 |
|---|---|---|---|
| `bi+0x78` | **init_boot** 的 ramdisk，且已被 `0x7634` 改成 `align_up(ramdisk_size, page)` | `init_boot.img` 头 `+0x0c` = **2,005,893** → **2,007,040** | `0x92bc`（先写 boot 头的 0）→ `0x7634`（GKI 覆盖） |
| `bi+0x94` | vendor_boot 的 `vendor_ramdisk_size`（头 `+0x18`） | **11,628,676** | `0x92e4` |
| `bi+0x98` | recovery 分区 ramdisk（recovery 头 `+0x0c`），仅恢复模式非 0 | **14,572,954** | `0x922c` |

> **小更正**：lead 给的总量 `11,628,676 + 14,572,954 + 2,005,893 = 28,207,523` 用的是 init_boot 的**未对齐**值。
> ABL 实际用的是 `align_up(…)=2,007,040`，所以原厂 total = **28,208,670**（差 1,147 B，不影响结论，但算边界时要用对齐值）。

---

## 4. Q4 —— 数值推算表

记 `P = page_size = 4096`（v4 头恒 0x1000），`KL = KernelLoadAddr`，`K = 内核 image_size`：

```
total      = bi+0x78 + bi+0x94 + bi+0x98   （本机固定部分 = 2,007,040 + 11,628,676 = 13,635,716）
RamdiskLoadAddr = top − align_up(total,P) − P
DtbLoadAddr     = RamdiskLoadAddr − (P + 0x200000)
available       = DtbLoadAddr − KL = (top − KL) − align_up(total,P) − 2P − 0x200000
G1（0x9b5c）: available > 0
G2（0xa400）: available ≥ K
```

本机 `top − KL = 0x5700000 = 91,226,112`（非压缩内核）⇒ **`total_max = 91,226,112 − 8,192 − 2,097,152 − K = 89,120,768 − K`**，
再取页对齐（`total_max` 必须是 4096 的倍数）即：

```
total_max      = floor((89,120,768 − K) / 4096) × 4096
recovery_max   = total_max − 13,635,716        （再向下对齐到 align_up(13,635,716+R) ≤ total_max）
```

### 4.1 三个内核代入

| 内核 `K` | `total_max` | `recovery ramdisk` 上限 |
|---|---|---|
| 原厂 A14 `0x2D50000` = 47,513,600 | 41,607,168（0x27AE000，**39.68 MiB**） | **27,971,452**（0x1AACF7C，**26.68 MiB**） |
| 现役 KSU `0x29C0000` = 43,778,048 | 45,342,720（0x2B3E000，**43.24 MiB**） | **31,707,004**（0x1E3CF7C，**30.24 MiB**） |
| 自编 Linux `0x25F0000` = 39,780,352 | 49,340,416（0x2F0E000，47.05 MiB） | 35,704,700（0x220CF7C，34.05 MiB） |

### 4.2 门限对内核的敏感度（比"记住一个数"更有用）

每**少** 1 MB 内核，ramdisk 总量就**多** 1 MB（1:1 线性，无折扣）；反之换大内核会立刻吃掉余量：

| 场景 | 触发点（原厂内核口径） |
|---|---|
| 把 `vendor_boot` 的 `vendor_ramdisk` 从 11.63 MB 换成 5 MB 的自制 initramfs | 总量上限从 41.6 MB 掉到 34.98 MB（recovery 上限 21.3 MB） |
| 换成 gzip 压缩内核（`KL=0x40080000`） | 全部上限 **−512 KiB** |
| `init_boot` 打 KernelSU 补丁后 ramdisk 尺寸变化 | 1:1 抵消（`bi+0x78` 就是它的对齐值） |

---

## 5. Q5 —— 与实测三点交叉验证

### 5.1 计算 vs 实测

| 实测点 | total（用对齐值） | 现役 KSU 内核：available / 判定 | 原厂内核：available / 判定 |
|---|---|---|---|
| 原厂 recovery **14,572,954**（"能过"） | 28,208,670 | 60,911,616 ≥ 43,778,048 → **PASS**（余 17.1 MB） | 60,911,616 ≥ 47,513,600 → **PASS**（余 13.4 MB） |
| 补到 **30,000,000**（"过得了 ABL，init 后挂"） | 43,635,716 | 45,481,984 ≥ 43,778,048 → **PASS**（余 1.70 MB） | 45,481,984 < 47,513,600 → **FAIL**（差 2.03 MB） |
| 补到 **47,628,167**（"被拒"） | 61,263,883 | 27,852,800 < 43,778,048 → **FAIL**（差 15.9 MB） | 27,852,800 < 47,513,600 → **FAIL**（差 19.66 MB） |

**自洽性**：只要假设"那三次实验跑的是**现役 KSU 内核**（`image_size=0x29C0000`）"，三个点**全部命中**，且
第 2 点的通过余量恰好 **1.70 MB**——这正解释了为什么 30 MB 能过、而再往上一截就死（极限 31,707,004）。
第 3 点被拒得余量充足（差 15.9 MB），任何内核都过不了。
第 1 点两个内核都过。

**反向利用（这一条其实能反推 `KernelSize`，比"夹逼"更硬）**：把三个点当成约束解 `KernelSize`：

| 用哪个点 | 能得到的不等式 | 解出的 `KernelSize` 范围 |
|---|---|---|
| 14,572,954 过 | `KernelSize ≥ total + 2,105,344 + image_size` | `≥ 74,092,544`（0x46A9000） |
| **30,000,000 过** | 同上，total = 43,635,716 | **`≥ 89,519,108`**（0x555F404） |
| 47,628,167 被拒 | `< 61,263,883 + 2,105,344 + K` | `< 107,147,275`（KSU）/ `< 110,882,827`（原厂） |
| HYP 上界（§3.2） | ramdisk 顶点不得压 0x45700000 | `≤ 91,226,112`（=0x5700000） |

⇒ 三个点合起来把 `KernelSize` 卡在 **[89,519,108 , 91,226,112]** 这个 **1.7 MB 宽的窗口**里，
而板级内存表给的 **0x5700000 = 91,226,112 正好是这个窗口的上端点**。这是本报告最有力的自洽证据：
**三点实测 + 板级表 + HYP 位置，在同一个数上闭合。**（前提仍是"实验用的是 KSU 内核"。）

### 5.2 唯一可能的矛盾点，以及最可能的原因

- **矛盾**：若那三次实验用的是**原厂 47.5 MB 内核**，则 30,000,000 这一档本应在 `0xa400` 就被拒（差 2,031,616 B），
  与"过得了 ABL"冲突。
- **最可能的解释（按可能性排序）**：
  1. **当时跑的确实是 KSU 内核**（设备常态就是 KSU boot，`boot-main-1.3.2` 的 `image_size = 0x29C0000`）。
     这台机器上 `KernelSU 修补 init_boot` 是既定流程，recovery 启动用的内核 = `boot_a` 里的内核 ⇒ 完全对得上。
     这是最省事的解释，也解释了为什么 30 MB 只余 1.7 MB 就死。
  2. 若当时确实是原厂内核，则说明 `KernelSize` 比 0x5700000 大 ≥ 2 MB（要到 `0x5900000` 才能容纳 30 MB 这一档）。
     但 `0x5900000` 会把 ramdisk 顶点推到 0x45800000，**压进 HYP 保留区 1 MB**，与"机器稳定开机"不相容 ⇒ 我不采信这条，
     除非将来实测到"压 HYP 不致命"。
  3. "过得了 ABL"这一判定本身可能是间接推断（例如只看到重启后仍能进系统/进了 Android 而不是 recovery），
     那样这条观测就不能当作 G2 的反证。
- **不构成矛盾的部分**：`0xbff4` 那条 `"Error: Ramdisk size is over the limit"` 与三点**没有关系**——
  在本机 `RamdiskLoadAddr ≠ 0`，它恒放行（§1.2）。所以**如果历史上见过这句串**，那只能说明当时
  `bi+0x50` 算成了 0（`KernelBaseAddr/KernelSize` 变量异常），不是"ramdisk 超限"。

### 5.3 一次实验就能钉死（建议照做，30 秒）

```
A. recovery ramdisk = 31,700,000 B（< 31,707,004）  → 预测：ABL 放行，内核能起
B. recovery ramdisk = 31,710,000 B（> 31,707,004）  → 预测：ABL 报错退出，屏幕出现
      "DTB header can get corrupted due to runtime kernel size"（0x98760，打印点 0xa4a0）
```
- 若 B 打的是这句串 ⇒ §4 的模型与"现役 KSU 内核"同时被确认；
- 若 B 打的是 `"Not Enough space left to load kernel image"`（0xa077d）⇒ `top` 比 0x45700000 小，说明 `KernelSize` < 0x5700000；
- 若 B 又能过 ⇒ `KernelSize` > 0x5700000（去查 HYP 是否真被踩）。
- **拍照**：ABL 的错误文案会打在屏幕上（这是本机唯一可用的 ABL 观测通道；`logfs`/`logdump`/`pstore` 三处都取不到日志）。

---

## 6. 最终可用上限（给"安全值"和"理论极限"两个数）

**recovery ramdisk（单项）**

| 口径 | 安全值 | 理论极限 | 依据 |
|---|---|---|---|
| **现役 KSU 内核**（`image_size=0x29C0000`） | **30,000,000 B（28.61 MiB）** ← 已实测通过，余量 1.70 MB | **31,707,004 B（30.24 MiB）** | §4.1、§5.1 |
| 原厂 A14 内核（`0x2D50000`） | **26,000,000 B（24.80 MiB）**（余 1.97 MB） | **27,971,452 B（26.68 MiB）** | 同上 |
| 自编 Linux 内核（`0x25F0000`） | 33,000,000 B（31.47 MiB） | 35,704,700 B（34.05 MiB） | 同上 |

**ramdisk 总量**：KSU 内核极限 **45,342,720 B（43.24 MiB）**，安全取 42 MB；原厂内核极限 41,607,168 B（39.68 MiB），安全取 38 MB。

**使用规则（避免踩坑）**

1. 记这三条式子，别记数：
   `total_max = (KernelBaseAddr + KernelSize) − KernelLoadAddr − 0x200000 − 2×0x1000 − image_size(内核)`，
   `recovery_max = total_max − 13,635,716`（原厂 init_boot+vendor_boot 时）。
2. 换 `boot.img`（改内核）或换 `vendor_boot`/`init_boot`（改另两项 ramdisk）之后，**阈值必须重算**，1:1 变化。
3. 压缩内核（gzip）比非压缩内核少 512 KiB 余量。
4. 补零只改 `bi+0x98` 的字段值，ABL 只看 size；补零会让 `init` 挂，那是用户态的事，不要误判成 ABL 拒绝。
5. 只有 `RamdiskLoadAddr`（`bi+0x50`）为 0 或由下溢算出时，才会看到 `"Error: Ramdisk size is over the limit"`——
   看到这句请去查 `KernelBaseAddr`/`KernelSize` 两个 UEFI 变量（或 `top` 是否异常小），**不要去缩 ramdisk**。

---

## 7. 复现命令（全部可重跑）

```powershell
cd E:\rom\work\abl-limit
# 1) 原始字节级反汇编（不依赖 full.asm）
python csdis2.py 0xbe10 0xc100
# 2) 全函数写点扫描：证明 [sp+0x98] 只有 0xbe30 一个写点
python writes.py 0xb000 0xd000 "#0x98]"
# 3) 串 → 代码交叉引用（adrp+add）
python strref.py 0xaa894      # "Error: Ramdisk size is over the limit" → 0xc094
python strref.py 0xa077d      # "Not Enough space left to load kernel image" → 0x9bfc
# 4) 内核 image_size 实测（决定上限的那个数）
python probe_boot.py "E:\rom\work\TB331FC-kernel\boot-main-1.3.2.img" `
                      "E:\rom\TB331FC\刷机包\TB331FC_ZUI_16.0.544\image\boot.img"
# 5) 上限推算表
python calc.py
```

脚本清单：`rng.py` `csdis2.py` `grepva.py` `writes.py` `strref.py` `refs_any.py` `strva.py`
`pehdr.py` `boothdr.py` `probe_boot.py` `calc.py`（本目录）。

---

## 8. 本次闭合 / 未闭合

| 项 | 状态 |
|---|---|
| `[sp+0x98]` 的语义 | ✅ **闭合**：入口清零的局部，全函数无第二写点；0xbff4 是 64 位回绕检查 |
| `bi+0x50` 的来源与公式 | ✅ **闭合**：`0x9af4..0x9b30` 全链；`R = top − align_up(total) − page` |
| `KernelBaseAddr` | ✅ `0x40000000`（板级表 + `PHYS_OFFSET` + `node 0` 起点） |
| `KernelSize` | ✅ **`0x5700000`（夹逼确定；板级表值）**，并反证了旧报告的 `0x3C00000` |
| `KernelLoadAddr` | ✅ `0x40000000`（三个内核实测 `text_offset=0`、非压缩） |
| 上限公式与三档数值 | ✅ §4 |
| 三点实测交叉验证 | ✅ 2/3 无条件命中；第 3 点（30 MB）需假设"走的是 KSU 内核"才自洽 ⇒ §5.2 列了三种解释与判别法 |
| 真机日志直读 `Kernel Load Address` / `Ramdisk Load Address` | ❌ 取不到（`logfs` 8 MB 几乎全零、`logdump` 零命中、`uefivarstore` 是 `PTBL` 私有格式且 `KernelBaseAddr` 零命中）<br>⇒ 只能靠屏幕拍照 + §5.3 的二分实验做最终确认 |
