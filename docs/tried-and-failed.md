# 试过并失败的 UEFI 配置（按时间顺序，共 9 条）

> 这份清单的作用：**别人不用再走这些死路**。
> 每条都记录「改了什么 / 怎么验证的 / 看到什么现象 / 因此排除了什么」。
> 验证手段只有两个：① 屏幕现象（用户观察）② `fastboot continue` 是否返回（机器可读）。

## 结论速查

| # | 尝试 | 现象 | 排除了什么 |
|---|---|---|---|
| 1 | v1 boot 头 | 卡 logo，USB 静默，不复位 | v1 头不兼容（**不成立**，见 #2 备注） |
| 2 | v4 boot 头 | 同上 | v1/v4 头差异不是原因 |
| 3 | 内核 gzip 压缩 | 同上 | 压缩不是原因（反而必须压缩，见 #8） |
| 4 | 入口偏移调整 | 同上 | `text_offset` 只在未压缩路径生效，压缩路径入口固定为偏移 0 |
| 5 | 装载地址调整（`KernelBaseAddr + 0x80000`） | 同上 | 装载地址不是原因 |
| 6 | 多棵 DTB（6 棵 FDT 拼接） | **设备直接回 fastboot** | ✅ **真因之一**：ABL 要求「内核后最多一棵 FDT」，见 `abl-dtb-root-cause.md` |
| 7 | 单棵 DTB（279,147 B） | 卡 logo，但 `continue` 后离开 fastboot | ✅ 通过 ABL 检查，**ABL 确实跳了** |
| 8 | 单棵 DTB + MMU-off 涂屏探针 | 卡 logo、不复位 | 涂屏不可见（MMU 假设也不成立） |
| 9 | FD 基址 `0x5FC00000` → `0x80000000` | 卡 logo、不复位 | 基址冲突不是唯一原因 |

## 详细记录

### 1–5. 镜像头与装载参数（2026-11 上旬，8 次刷写）

全部组合出同一种现象：**刷完重启后卡在 Lenovo logo、USB 完全静默、设备不自动复位**，必须人工长按电源 15–20 秒再进 fastboot 还原。

排除依据：ABL 反汇编显示内核入口是 `0x8610 ldr x8,[BootInfo+0x40]` → `0x862c blr x8`，**偏移为 0，不额外加 `text_offset`**；`text_offset` 只在未压缩路径被加；`image_size` 仅做上限检查（`0xa3e8`）。所以 3/4/5 三条从机制上就不可能有效果。

> 教训：这 8 次刷写是在**根因未知**的情况下盲试参数，代价是 8 次人工断电。应该先做反汇编。

### 6. 多棵 DTB —— 唯一一个「设备自己退出」的失败

我们最早的 `tb331fc.dtb` 是 **6 棵树拼接**（279,505 B 起是第二棵）。

ABL 函数 `0xa520`（`BootLinux` 在 `0x7fa4` 调用）的逻辑：
```
p  = ImageBuffer + PageSize + BootInfo[0x84]
fdt_check_header(p)        → 通过
p2 = p + totalsize
fdt_check_header(p2)       → 又是一个 FDT！
→ 打印 "Not the single appended DTB" (0xab58)
→ 返回 0x800000000000000E (14)
→ BootLinux 在 0x7fc0 直接返回，0x862c blr 一次都不执行
```

6 棵树必然命中：tree1 的 `totalsize = 279,505`，而 tree2 正好从 `0x443D1` = 279,505 开始。

**改成单棵树（279,147 B，其后字节为 0）后立即通过检查** —— 这是整个项目里第一个被指令级证实并实验验证成功的修复。

### 7. 单棵 DTB + 真实 UEFI FD

`fastboot continue` 测试（`0x7f0fc` → LoadKernel → BootLinux，**不重启**）：

```
刷入 probe → fastboot continue → 5 秒内设备离开 fastboot
判定：ABL branched into the payload (EXECUTED)
```

这是「ABL 跳转成功」的机器可读证据。**注意**：`continue` 返回并不能区分「我们的代码跑起来了」和「ABL 跳进去后立刻崩」——两种情况下设备都会离开 fastboot。

### 8. MMU-off 涂屏探针

SEC 自己的入口代码第一件事就是 `msr sctlr_el2, xzr`（关 MMU），说明 ABL 交接时 MMU 可能是开着的。于是做了一个 176 字节的 stub：

```
读 CurrentEL → 若 EL2 则 msr sctlr_el2, xzr / 若 EL1 则 msr sctlr_el1, xzr
→ 往 0x5C000000（framebuffer）写 64 KB 洋红
→ 等 3 秒
→ smc PSCI SYSTEM_RESET
```

现象：仍然卡 logo，没有洋红，也没有复位。

结论：要么载荷没执行，要么执行了但涂屏/复位都没生效。**这个实验没有给出判据**——因为它依赖屏幕，而屏幕正是不可靠的观测通道。

### 9. FD 基址迁到 `0x80000000`

启动链研究发现 `xbl.img` 的 ph16 是 `PT_LOAD vaddr=0x5FC00000 filesz=0x220400` 的完整 UEFI 固件卷，而 BootShim 把 3 MB 的 FD 拷到**同一个地址**。假设：这覆盖了 XBL 自己仍在运行的 UEFI，等于自杀。

改法（三处联动）：`tb331fc.toml` 的 `[uefi_fd] base`、`MemoryMapLib.c` 的 `UEFI FD` 条目、BootShim 的 `FD_BASE`（由 toml 自动推导）。

自检：`shim text_offset = 0x80000000` ✓、DTB 单棵 ✓、镜像 1,234,944 B。

现象：**仍然卡 logo，40 分钟无 USB、无复位**。

结论：基址不是（唯一）原因。但这次实验也**不能排除**它——因为 `0x80000000` 可能在 ABL 阶段还不可访问（第二段 DRAM 未初始化），那会导致另一种崩溃。

## 由此确立的两条方法要求

1. **任何 UEFI 实验都必须先有机器可读判据**。
   屏幕颜色和 `continue` 返回都不够。目前正在做的：用看门狗强制复位 + `slot-retry-count` 递减作为「执行过」的证据（见 `probe/` 与 `docs/sec-memory.md`）。
2. **不要一次改多个变量**。
   #8 同时改了「关 MMU」和「涂屏」，#9 同时改了「FD 基址」和「BootShim 拷贝目标」——两次都无法归因。