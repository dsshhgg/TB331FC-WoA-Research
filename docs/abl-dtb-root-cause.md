# khaje（TB331FC / SM6225-AD）ABL 装载地址与入口偏移 —— 静态逆向定论

- 执行日期：2026-11-23
- 对象：`E:\rom\work\zui17_images\abl.img` → `Z17_9e21fd93_lz_f536d559_PE32_at_0xb4.bin`
  （970,752 B，PE32+ AArch64，**sha256 33ca0240027d83cb930b4c26…，与 ZUI16 的 ABL 逐字节相同**，见上一份报告 §1.2）
- 性质：**只读静态分析**。未刷机、未构建、未改 `uefi-tb128fu`、未删除任何文件。
- 配套产物：`E:\rom\work\woa\abl-jump-analysis\`（`full.asm` = llvm-objdump 全量反汇编；`_scripts\` = 本次新写的 6 个小工具）

## 0. 一句话结论（Top1）

**ABL 把镜像解压到 `KernelBaseAddr + 0x80000`，然后 `blr` 到同一个地址——即入口偏移 = 0（相对解压输出）；代入 `KernelBaseAddr = 0x40000000` 得物理入口 `0x40080000`。
所以埋的三种颜色里，应该看到「洋红 `0x00FF00FF`」（offset 0 那一支），不是黄也不是青。**

---

## 1. 判定表（本任务核心产出）

| 假设 | 期望屏幕颜色 | 是否符合 ABL 代码 | 依据（指令地址） |
|---|---|---|---|
| **ABL 从 load_addr 起跳（偏移 0）** | **洋红 `0x00FF00FF`** | ✅ **符合（唯一成立的）** | `0x8610 ldr x8,[sp,#0x260]`（=BootInfo+0x40）→ `0x862c blr x8`，中间**不加任何偏移**；而 `0x9824` 已把 +0x80000 加进 load_addr **本身**，且解压 dst 用的就是这个 load_addr（`0x9e88 ldr x2,[x8,#0x40]`）⇒ dst == entry |
| ABL 从 load_addr+0x400 起跳（page 对齐） | 黄 `0x00FFFF00` | ❌ 不符合 | 全函数没有把 `0x400`/page_size 加到入口的代码；page_size 只出现在 `0x957c`/`0x9e7c`（算内核起点）、`0x9b14`/`0x9b3c`（算 ramdisk/dtb 边界），与 0x862c 无数据依赖 |
| ABL 从 load_addr+0x80000 起跳 | 青 `0x0000FFFF` | ❌ 不符合（但**这正是本实验要排除的“二次偏移”**） | `+0x80000` 只在 `0x9824` 出现一次（`add x8,x8,#0x80,lsl#12`），作用对象是 **base**，之后 dst 与 entry 都读 `BootInfo+0x40`，没有第二次加法 |
| 先把镜像搬到 FD_BASE(0x5FC00000) 再从 0 起跳 | 洋红（**与第 1 行同色，探针本身分不开**） | ❌ 不符合 | 唯一的搬运是 `0xa394-0xa3b4 gBS->CopyMem(dst=KernelLoadAddr, src=[sp+0x80])`，而压缩路径下 `[sp+0x80]` 在 `0xa04c` 被写成 **同一个 KernelLoadAddr** ⇒ **dst==src 自拷贝**。没有任何代码把镜像搬到 0x5FC00000；FD_BASE 只是我们 BootShim 自己搬（探针镜像里没有 shim） |

> **实验设计提醒**：第 1 行与第 4 行的预测颜色完全相同，探针无法区分「原地起跳」与「先搬到 FD_BASE 再起跳」。
> 第 4 行只能靠静态证据排除（上面那条），或另做实验（在 0x5FC00000 放哨兵并观察是否被破坏）。

### 若三种颜色都不出现，说明什么

1. **ABL 根本没走到 `0x862c` 的 `blr`**。前置的任一失败都会走 `0x8648` 的错误返回：`UpdateBootImageParams`(0x783c) / `QueryBootParams`(0x7860) / `LoadKernel`(0x7894) / `0x345d0`(0x8488) 任一非 0。
2. 最可能的三个具体原因（按可疑度）：
   - **`QueryBootParams` 失败** → `0x9918` 打印 `QueryBootParams Failed: `，返回 5；
   - **空间检查失败** → `0x9b50` 比较 `BootInfo+0x58 - BootInfo+0x40`，为 0 就打印 `Not Enough space left to load kernel image`（0xa077d）返回 5；
   - **解压失败** → `0x9e98` 返回非 0，打印 `Decompressing kernel image failed!!!`（0xa268b）返回 9。
3. 另一种「全黑」：**ABL 走了未压缩分支**（`IsGzip` 没命中）。此时 `0x9808` 会把镜像头里的 `text_offset`（探针里是 0x5FC00000）**加到 base 上**，得到 0x9FC00000，把几百字节拷到那里再跳过去执行 gzip 字节 → 立刻异常/挂死，屏幕不会变。
4. 屏幕本身没被点亮/画的地址不对（本报告不覆盖，见上一份报告 §6.4，0x5C000000 已被证实）。

---

## 2. 方法与新增工具

复用上一轮的解包链与 `abl_zui16.strings.txt`，本次新写（都在 `_scripts\`）：

| 脚本 | 作用 |
|---|---|
| `rng.py` | 从 `full.asm` 按地址区间取反汇编 |
| `strva.py` | 按 VA 取 ASCII 字符串（VA==文件偏移） |
| `utf16.py` | 按 VA 区段列 UTF-16LE 字符串（**UEFI 变量名是 UTF-16，这是找到 `KernelBaseAddr` 的关键**） |
| `strings_kw.py` | 关键字过滤 ASCII 串 |
| `strrefs.py` | 在一个代码区间里自动解 `adrp+add` 的字符串引用（用来“读”函数打印的日志） |
| `branch_trace.py` | 对每个 `br/blr` 反向找目标寄存器的来源（用来定位最终跳转） |
| `probe_layout.py` | 读 `/root/woa/probe_entry/` 里探针镜像的三份 stub 与 boot header |

环境：WSL `ub`，`llvm-objdump`（`--triple=aarch64 --no-show-raw-insn`），python3 + capstone 5.0.7。

**关键反汇编基址约定**（沿用上一份）：PE32+/ImageBase=0，三节 rawsz==vsz 且 rawoff==va ⇒ **VA == 文件偏移**；`.text 0x1000..0xc0000`。

---

## 3. Q1 装载基址：完整数据流

### 3.1 调用链（全部地址可点）

```
BootLinux                        = 0x6a34   (frame 0x310；BootInfo 结构体在 sp+0x220，0xd0 字节，0x6a80-0x6a8c memset)
 ├─ 0x7838  add x0,sp,#0x220 ; 0x783c bl 0x9470     = UpdateBootImageParams（判 IsGzip → BootInfo+0xc2）
 ├─ 0x785c  add x0,sp,#0x220 ; 0x7860 bl 0x9660     = ★ QueryBootParams（算 KernelLoadAddr/边界）
 │    ├─ 0x9764 bl 0x10160                            = GetKernelBaseAddr 的“桩”实现（恒写 0）
 │    ├─ 0x9770 bl 0x101c0                            = ★ 真 GetKernelBaseAddr（读 UEFI 变量）
 │    │    ├─ 0x101fc ldr x8,[x8,#0x48]               = gRT->GetVariable
 │    │    ├─ 0x10208/0x1020c  x0 = 0xafa0e           = L"KernelBaseAddr"
 │    │    ├─ 0x10210/0x10214  x1 = 0xbf0bc           = GUID 882f8c2b-9646-435f-8de5-f208ff80c1bd
 │    │    ├─ 0x10224 blr x8                          ; 取 8 字节 → [sp+0x68]
 │    │    ├─ 0x10250/0x10254  x0 = 0xaf964           = L"KernelSize"
 │    │    └─ 0x10258 blr x8                          ; 取 8 字节 → [sp+0x70]
 │    ├─ 0x9780 bl 0xfc50                             = 恒返回 0 的编译期桩（0xfc50: mov w0,wzr … ret）
 │    ├─ 0x97a0-0x97a8 ldr x8,[sp,#0x68] ; ldr x9,[sp,#0x48] ; str x8,[x9,#0x40]   ; KernelLoadAddr = KernelBaseAddr（先原样）
 │    ├─ 0x97b0-0x97cc KernelNotArm64? → +0x8000
 │    ├─ 0x97e8 KernelCompressed? → 0x9824
 │    ├─ 0x97f8 image_size(+0x10)==0? → 0x9824
 │    ├─ 0x9808 x10=[kernel+0x8](text_offset) ; 0x9818 KernelLoadAddr += text_offset   ← 仅未压缩
 │    ├─ 0x9824 ldr x9,[sp,#0x48] ; ldr x8,[x9,#0x40] ; add x8,x8,#0x80,lsl#12 ; str x8,[x9,#0x40]
 │    │                                        ★ KernelLoadAddr = base + 0x80000（压缩路径）
 │    ├─ 0x9864/0x986c/0x9874                  BootInfo+0x48 = base + size（区域顶）
 │    ├─ 0x9af4-0x9b30                         BootInfo+0x50 = +0x48 - align(ramdisk_size+second_size+[+0x94]+[+0x98]+page)
 │    ├─ 0x9b34-0x9b48                         BootInfo+0x58 = +0x50 - (page_size + 0x200000)   → DTB 装载地址
 │    └─ 0x9b50-0x9b5c                         若 +0x58-+0x40 == 0 → "Not Enough space left to load kernel image" 返回 5
 ├─ 0x7894 bl 0x9c70                                 = LoadKernel（解压 → 校验 → 自拷贝，见 §4）
 └─ … 0x8488 bl 0x345d0 → 0x855c → 0x8610/0x862c     = 最终起跳（见 §5）
```

`0x9660` 的返回值被 `0x7864 str x0,[sp,#0x1e0]` 保存，非 0 就 `0x8648` 直接返回——**所以基址变量取不到时，Linux 不会被启动**。

### 3.2 BootInfo 结构体布局（本次新解出，供后续复用）

`BootInfo` = `sp+0x220`，长度 **0xd0**（`0x6a80 mov w8,#0xd0; 0x6a88 add x0,sp,#0x220; 0x6a8c bl memset`）。

| 偏移 | 含义 | 证据 |
|---|---|---|
| +0x00 | （memset 清零后**无写入点**，只被 fallback 读） | 见 §3.4 |
| +0x08 | ImageBuffer | `0x9574 ldr x8,[x9,#8]`、`0x9e78` |
| +0x40 | **KernelLoadAddr** | `0x7ae4` 用 `0x%x` 打印（串 `Kernel Load Address: 0x%x` @0xa0762）、`0x9e88` 当解压 dst、`0x8610` 当入口 |
| +0x48 | 内核区域顶（base+size） | `0x9874` |
| +0x50 | Ramdisk 装载地址 | `0x9b30` |
| +0x58 | **DtbLoadAddr**（解压空间上界 / 最终 x0） | `0x9b48`、`0x9d84`、`0x861c` |
| +0x6c | PageSize（来自 boot header +0x24） | `0x8c84` |
| +0x70 | KernelSize（boot header +0x08，**压缩流长度**） | `0x8c0c`、`0x9e84` |
| +0x74 / +0x78 | SecondSize / RamdiskSize | `0x8c5c` / `0x8c34` |
| +0x80 | `0x14` —— 仅 UNCOMPRESSED_IMG 用的 20 字节头长度 | `0xa234` |
| +0x84 | out①：**已消费的输入字节数**（含 gzip 头） | `0x9e90` → `0x6b7f8` |
| +0xb8 | Cmdline（= hdr+0x40） | `0x8c94` |
| +0xc0 | KernelNotArm64 | `0x9614` / `0x85b4` |
| +0xc1 | KernelPatched（UNCOMPRESSED_IMG 标记） | `0x95dc` |
| +0xc2 | **KernelCompressed**（IsGzip 命中） | `0x95ac` |
| +0x458 | header_version | `0x7130-0x7154`（读 `ImageBuffer+0x28`） |
| +0x45c | 「init_boot 是 v4 且 +0x0c != 0」的 GKI 链标记 | `0x1b170-0x1b1b8` |

### 3.3 常量页 0xbefd8（实测重读，修正上一份报告的笔误）

```
0xbefd8 = 0x00080000      ← 内核相对 base 的偏移
0xbefdc = 0x05600000      ← 区域顶上界（base + 0x5600000 = 0x45600000，正好在 HYP 0x45700000 之下）
0xbefe0 = 0x03c00000      ← 60 MB（内核区域大小的典型值）
0xbefe4 = 0x00008000      ← 32 位内核的偏移
```

### 3.4 base 从哪里来，值是多少

**来源（已确证）**：不是 DDR 探测、不是 DT，也不是 boot header 的 `kernel_addr` 字段——
是 **UEFI 变量 `KernelBaseAddr` / `KernelSize`**（`gQcomTokenSpaceGuid`），由更早的引导阶段写好，ABL 用 `gRT->GetVariable` 读两次（`0x101c0`，调用点 `0x9770`）。

**为什么没有写入方**：把 `E:\rom\work\zui17_images\` 下**所有**镜像按 UTF-16 扫过，`KernelBaseAddr` 只在 ABL（解压后）里出现；
`xbl.img` 3,227,648 B 里可打印字节只有 **73,482 B（2.3%）**，`strings` 连一个 `Kernel` 都找不到 ⇒ **XBL 是加密镜像**，写入点不可见。这不是「没有写入方」，是「我们看不到」。

**数值（推断，强）**：**`KernelBaseAddr = 0x40000000`，`KernelSize = 0x03C00000（60 MB）`** ⇒ **load = 0x40080000**。四条独立证据：

1. `0x9824` 的语义是 `base + 0x80000` 作为内核装载地址。对高通 arm64，**0x40080000 是标准的 kernel load address**（DDR 基址 + 512 KiB）。
2. 回退常量只有 base=0x40000000 时才自洽：`0x40000000 + 0x5600000 = 0x45600000`，正好是 MemoryMapLib 里 **HYP(0x45700000) 以下最后一个可用地址**——这个「怪数字」就是「低内存顶端」。
3. 设备自己的 panic 日志（`forensics_900e\auto_20261113_114831\ramdump_scan.md:380`）写着 **`PHYS_OFFSET: 0x40000000`**，即 DDR 物理基址 = 0x40000000。
4. 同一次崩溃转储的物理地址带（`memory_table.txt`）落在 `0x420e3e18`（KDATABSS）/`0x430a5000`（KISTK）/`0x48f40000`（KCNTXT）/`0x49xxxxxx`，与「内核区 0x40080000 起、0x43C00000 结束、其上继续分配」完全吻合。

**探针不能验证基址**：探针的三份 stub 都是相对偏移（0 / 0x400 / 0x80000），不管 base 是 0x40000000 还是别的，颜色结论都一样。要 100% 钉死数值只有两条路：
- 读 ABL 日志。ABL 自己会打印 **`Kernel Load Address: 0x%x`**（串 @0xa0762，打印点 `0x7ae4`，参数就是 `BootInfo+0x40`）——走 UART 或 `logfs` 分区（`logfs_ufs_8mb.bin`，设备上 8 MB）即可；
- 9008 读 UEFI 变量存储，找 `KernelBaseAddr` 那条（名字 30 字节 UTF-16，后跟 8 字节值）。

**对我们的意义**：`0x40080000` 在 4 GiB DDR 内、远离 ABL 自己所在的 FD（0x5FC00000），也是一个 2 MiB 对齐点（0x40080000 % 0x200000 == 0）——arm64 内核要求的最小对齐也满足。这也反过来排除了「ABL 把内核解压到自己脚下」的可能。

---

## 4. Q2 解压目标与输出长度

```
0x9d74  ldrb w8,[BootInfo+0xc2]        ; KernelCompressed
0x9d78  cbz  w8, 0xa118                ; 未压缩 → 另一条路
0x9d84  x8 = [BootInfo+0x58]           ; DtbLoadAddr
0x9d88  x9 = [BootInfo+0x40]           ; KernelLoadAddr
0x9d8c  available = x8 - x9            ; dstSize
0x9d94  if (available >> 32) != 0 → 打印 "Integer Overflow: the length of decompressed data = %u"（0xab543）
0x9e78  x0 = [BootInfo+0x08] + [BootInfo+0x6c]   ; src  = ImageBuffer + PageSize
0x9e84  w1 = [BootInfo+0x70]                     ; srcSz = boot header 的 kernel_size（压缩流长度）
0x9e88  x2 = [BootInfo+0x40]                     ; ★ dst = KernelLoadAddr（== base+0x80000）
0x9e8c  w3 = available                           ; dstSz
0x9e90  x4 = BootInfo+0x84                       ; out①：已消费输入字节数
0x9e94  x5 = sp+0xa4                             ; out②：★ 解压输出总长
0x9e98  bl 0x6b0a0                               ; DecompressImage
0x9f6c  w8 = [sp+0xa4] ; if (w8-8 <= 0) → "Decompress kernel size is smaller than image header size"（0x9c038）
```

- **解压目标 = `load_addr` 本身**（不是另一个 buffer）。所以「解压缓冲区起始」与「跳转目标」是同一个地址。
- **输出长度来源 = zlib `z_stream.total_out`**：`0x6b810 ldr x8,[x8,#0x28]`（z_stream+0x28 = total_out）→ `0x6b81c str w8,[x9]`（`x9` = 第 5 个参数，即 `sp+0xa4`）。
- 另一个 out（`BootInfo+0x84`）是 **`0x6b7e4 ldr w8,[x8]`（total_in）+ `subs w8,w8,#…` + `add w8,w8,#8`** ⇒ 「已消费的输入字节数（含 8 字节 gzip 头）」，**不是**输出长度。
- **解压输出长度没有回写 `BootInfo+0x70`**：`0x9f6c..0xa26c` 整段只把 outSize 用于「>8」的合理性检查与耗时打印（`0xa0e8`）。`BootInfo+0x70` 全程保持 header 里的**压缩** kernel_size，后面 `0xa3ac` 的 CopyMem 长度也用它（见 §5 Q4）。

---

## 5. Q3 入口（核心）

### 5.1 最终起跳指令

```
0x8490  ldr x8,[sp,#0x1e0]           ; 0x8488 bl 0x345d0 的返回值（EFI_STATUS）
0x8494  tbz x8,#0x3f,0x855c          ; bit63=0（成功）→ 0x855c
0x855c  x0=[sp+0x218] x1=[sp+0x260] x2=[sp+0x2f8] x3=[sp+0x270] … 
0x8590  bl 0x34810                   ; 起跳前准备（把 entry 作为参数带进去，含 C++ 虚调用）
0x8594  mov w0,#1 ; bl 0x60510
0x859c  bl 0x68290 → 0x85ac bl 0x68760
0x85b4  ldrb w8,[sp,#0x2e0]          ; = BootInfo+0xc0 = KernelNotArm64
0x85b8  cbz  w8, 0x8610              ; 0（arm64）→ 0x8610
────────── arm64 路径 ──────────
0x8610  ldr  x8,[sp,#0x260]          ; ★ x8 = BootInfo+0x40 = KernelLoadAddr
0x8614  str  x8,[sp,#0x1c0]
0x8618  ldr  x8,[sp,#0x1c0]
0x861c  ldr  x0,[sp,#0x278]          ; x0 = BootInfo+0x58 = DtbLoadAddr（arm64 启动协议：x0=FDT）
0x8620  mov  x3,xzr
0x8624  mov  x1,x3                   ; x1 = 0
0x8628  mov  x2,x3                   ; x2 = 0
0x862c  blr  x8                      ; ★★ 真正的入口跳转
────────── 32 位路径（不是我们） ──────────
0x85f0  ldr x8,[sp,#0x260] ; 0x85fc ldr x2,[sp,#0x278] ; w1=0 ; w0=w1
0x8608  blr x8                       ; r0=0, r1=0, r2=atags
```

**关键点：`0x8610` 取的是 `BootInfo+0x40` 的原始值，`0x861c..0x862c` 之间没有任何加法。**
而 `0x9824` 已经把 `+0x80000` 加进 `BootInfo+0x40`，`0x9e88` 又用它当解压目标 ⇒

```
解压缓冲区起始 = KernelBaseAddr + 0x80000
入口            = KernelBaseAddr + 0x80000     ⇒ 相对解压输出 offset = 0
物理地址（base=0x40000000） = 0x40080000
```

旁证：`0x7ae4` 在起跳前打印 `Kernel Load Address: 0x%x`，参数正是 `[sp,#0x260]`（同一字段）——说明 ABL 自己也把「它打印的装载地址」当成入口。

### 5.2 为什么不会 +0x400 / +0x80000

- `0x400`：全 PE 里没有对这个值的任何加法。`PageSize`（我们的 v1 头是 0x800）只用于 `0x957c`（ImageBuffer+PageSize = 内核起点）、`0x9e7c`（解压 src）、`0x9b14`/`0x9b3c`（边界对齐），**都不流入 0x862c**。
- `0x80000`：只在 `QueryBootParams` 内出现一次（`0x9824`），加的对象是 base。跳转侧不再加。

---

## 6. Q4 `text_offset` / `image_size` 是否参与搬运

### 6.1 `text_offset`（arm64 Image 头 +0x08）

**只在未压缩路径被使用**：

```
0x97e8  ldrb w8,[BootInfo+0xc2] ; KernelCompressed
0x97f0  cbnz w8, 0x9824          ; 压缩 → 走 +0x80000，根本不读 text_offset
0x97f8  ldr x8,[sp,#0x40]        ; kernel = ImageBuffer + PageSize
0x97fc  ldr x8,[x8,#0x10]        ; image_size
0x9800  cbz x8, 0x9824
0x9808  ldr x10,[kernel+0x8]     ; ★ text_offset
0x9818  add x8,x8,x10 ; str → BootInfo+0x40   ; KernelLoadAddr += text_offset
```

⇒ **压缩路径（我们的情况）：不读、不参与。未压缩路径：直接加到装载地址上。**
⚠️ **这是一个雷**：我们的 BootShim 头把 `text_offset` 写成 `0x5FC00000`。现在靠 gzip 挡住它；一旦把 `kernel_compression` 改成 `none`，ABL 会算出 `0x40000000 + 0x5FC00000 = 0x9FC00000` 并把镜像拷过去再跳——**换压缩方式 = 直接换死法**，不要动。

### 6.2 `image_size`（+0x10）

**只做上界校验，不参与搬运/跳转**：

```
0xa270  ldr x8,[sp,#0x80] ; ldr w8,[x8,#0x38] ; 比对 0x644d5241("ARM\x64")
0xa28c  if (BootInfo->KernelSize <= 0x2c) → 0xa368 补 4 字节（小镜像特例）
0xa394  gBS->CopyMem(dst = BootInfo+0x40, src = [sp,#0x80], n = BootInfo+0x70)
0xa3bc  再查 magic；不是 arm64 → +0xc0=1 但仍 return 0（放行）
0xa3e8  image_size(+0x10)  vs  (BootInfo+0x58 - BootInfo+0x40)   ; 越界才报错
```

- 压缩路径里 `0xa04c str x8,[sp,#0x80]` 把 src 设成 `BootInfo+0x40` ⇒ **`CopyMem` 是 dst==src 的自拷贝（无操作）**。
- 真正带搬运的 `CopyMem` 只在 **UNCOMPRESSED_IMG** 分支（`0xa1f4-0xa268`：先拷 4 字节到 `+0x84`、`+0x80=20`、再 `CopyMem(dst=load_addr, src=kernel+20, n=KernelSize)`）。

**明确结论：`text_offset`/`image_size` 不参与搬运与跳转；`image_size` 只做「不超出可用空间」的校验，`text_offset` 只在未压缩路径参与算装载地址。ABL 从不把镜像搬到 FD_BASE。**

---

## 7. Q5 第二路径：v3/v4（GKI）会不会改变入口

**不会。入口计算与版本无关。**

1. `header_version` 的唯一来源：`0x7130-0x7154` 读 `ImageBuffer + 0x28` 写 `BootInfo+0x458`（boot header v1 的 +0x28 就是 header_version；v3/v4 同样在 +0x28）。
2. GKI 链标记 `BootInfo+0x45c` 在 `0x1b170-0x1b1b8` 由 **init_boot 分区**（UTF-16 `L"init_boot"` @0xafc0e）决定：读它的 `+0x28`（version）≥ 4 且 `+0x0c != 0` 时置 1。**我们机器上这个标志真机大概率是 1**（原厂 init_boot 是 v4），但那不影响我们的 v1 内核。
3. `BootLinux` 里的分叉：
   ```
   0x7910  if (BootInfo+0x45c && BootInfo+0x458 > 3) → 0x7a50
   0x7930  … 计算 align_up(KernelSize)+PageSize ；非 0 → 0x7a4c → 0x7a50
   0x7a50  → 0x7ae4 打印 "Kernel Load Address: 0x%x" → 继续
   ```
   两条都**收敛到 0x7a50**，只是 v3/v4 跳过了一段 legacy 对齐计算。
4. v3/v4 真正的差别在 `GetBootImageInfo` 的 `0x8cb4`（v3）/`0x8ffc`（v4）分支：从 **vendor_boot** 读 `+0x0c page_size`、`+0x18 vendor_ramdisk_size`、`+0x834 dtb_size`、`+0x84c bootconfig_size`，而 v0/1/2 从 boot header 读 `+0x08/+0x10/+0x18/+0x24`。**这些只改「大小从哪来」，不改「装到哪、从哪跳」**——`QueryBootParams`(0x9660) 与最终 `blr`(0x862c) 是公共代码。
5. **不存在「ANDROID! 失败 → fallback v4」**：`0xcc60` 函数里 `0xccf0 memcmp(buf,"ANDROID!",8)`（串 @0x9bff2），只有 `0xccf4 cbz x0`（相等）才进 `0xcdc4` 的解析块；不等则进 `0xccfc..0xcdb0` 的错误日志并走错误返回。版本号也读自同一 buffer，**没有第二条「猜 v4」的路**。

⇒ 就算因为某种原因走了 v4/GKI 分支，入口仍然是 `BootInfo+0x40` = `KernelBaseAddr+0x80000`，**颜色结论不变**。

---

## 8. 对入口探针实验的预期

### 8.1 探针镜像现状（我读了 `/root/woa/probe_entry/`，只读）

```
probe_fix.img      6144 B  ANDROID! / hdrver 1 / kernel_size 804 / kernel_addr 0x10008000
                          ramdisk 5 / page 2048 / gz@0x800 = 1f 8b 08 … → 解压 0x800A0
                     内含 image_size@+0x10 = 0x800A0（已修，覆盖整段）
stub 三份（payload 内，capstone 实测）：0x0 洋红 0x00FF00FF / 0x400 黄 0x00FFFF00 / 0x80000 青 0x0000FFFF
（三份都是 A=0x00 的 RGB，scan-out 一般忽略 alpha；`movz/movk x2` 三条指令，见 `probe_layout.py`）
每份都是：adr x1,_Payload ; b _Start ; Image 头(ARM\x64, text_offset=0x5FC00000) ; 画满 0x5C000000 的 9,216,000 B ; 等 8 s ; smc PSCI SYSTEM_RESET
```

### 8.2 预期

| 现象 | 解读 |
|---|---|
| **整屏洋红约 8 s 后自动重启** | ✅ 与我们结论一致：`entry = load = 解压起点 = offset 0`，跑的是 0x0 那份 stub |
| 整屏黄 | ❌ 入口 = dst+0x400（page 对齐假设成立）；但代码里不存在这个加法 ⇒ 若真出现，说明真机 ABL ≠ 我们反汇编的这一版（先复核 sha256 33ca0240…） |
| 整屏青 | ❌ 入口 = dst+0x80000（二次偏移）；同样与代码矛盾 |
| **屏幕不变、设备静默/重启/卡 fastboot** | ABL 没走到 `blr`：见 §1「全黑说明什么」；优先查 `QueryBootParams` 与「Not Enough space」两条 |

### 8.3 探针本身的三个坑（静态核对过）

1. **`image_size` 校验**：`0xa3e8` 用解压后内容里的 `+0x10`（stub 里是 `0x80040`）比 `DtbLoadAddr-KernelLoadAddr`（约 58 MB）⇒ 通过。
2. **`outSize > 8`**：解压 0x800A0 ⇒ 通过。
3. **`IsGzip`**：payload 首 3 字节 `1f 8b 08` ⇒ `+0xc2=1`，走压缩路径；**如果哪天有人把 gzip 去掉，`text_offset=0x5FC00000` 会立刻把装载地址变成 0x9FC00000**（§6.1）。

另外：探针**无法**区分「原地起跳」与「先搬到 FD_BASE 再起跳」（同色），也**无法**验证 `KernelBaseAddr` 的绝对值（三份 stub 全是相对偏移）。

---

## 9. 对上一份 REPORT 的四处修正（重要，避免继续传错）

| 上一份的说法 | 实测 | 影响 |
|---|---|---|
| §3.3：`adrp x9,#0xbe000 … str x8,[x9,#0x40]`，读起来像「把 base\|0x80000 写到常量页」 | 实际是 `0x99b0-0x99c4` 的 **fallback 分支**：`ldr x8,[sp,#0x60]`(桩=0) / `[BootInfo+0]`，`orr` 0x80000，`ldr x9,[sp,#0x48]; str x8,[x9,#0x40]`。**主路径是 `0x9824` 的 ADD** | base 的语义被写成「未定义的 base」，现在是 `KernelBaseAddr` |
| §3.3：「加载地址由 ABL 自己算 = base\|0x80000」 | **压缩：base + 0x80000（ADD）；未压缩：base + text_offset** | 决定我们绝不能关压缩 |
| §4.3 / §7：「ABL 不读 shim 头 +0x08（text_offset）」 | **压缩路径不读；未压缩路径 `0x9808-0x981c` 会读并加上去** | 关压缩会把 load 变成 0x9FC00000 |
| §2.3c 注释「`&out`(BootInfo+0x84)」暗示是输出大小 | `+0x84` = **已消费输入字节数**；输出长度在 `sp+0xa4` | 只影响阅读，不影响结论 |

---

## 10. 证据不足与补法

| 缺什么 | 影响 | 怎么补 |
|---|---|---|
| `KernelBaseAddr` / `KernelSize` 的**真机数值** | 只影响「0x40080000」这个绝对数；入口偏移（0）不受影响 | ① ABL 自己打印 `Kernel Load Address: 0x%x`（0x7ae4，串 0xa0762）——读 UART 或 `logfs` 分区；② 9008 读 UEFI 变量存储 |
| XBL 里写这两个变量的代码 | 只能推断 | `xbl.img` 是加密的（可打印字节 2.3%）；需要 XBL 明文（厂商内部）或运行时抓变量 |
| 起跳前 `0x34810` 具体做什么 | 不影响入口值（它只收到 entry 作为参数，不回写 `sp+0x260`；全函数对该槽只有读，无写） | 若要完全闭合，可反汇编 `0x34810`（C++ 虚调用密集，是「kernel info / display shutdown」一族） |
| 探针里 0x400 黄到底对应哪个假设 | 代码里找不到 +0x400 | 已按「不符合」处理；若真出现黄色，请先复核 ABL 版本 |