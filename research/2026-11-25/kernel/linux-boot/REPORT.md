# TB331FC（khaje / SM6225）mainline Linux 启动包 · 交付报告

> 日期 2026-11-25 · 设备联想小新 Pad 2024 TB331FC · 内核 6.14.0-rc5-next-20250306（已编好，本轮**未重编内核**）
> 本轮性质：**只做镜像与脚本，一次 fastboot 都没跑**（设备当前不在线，也不需要在线）
> 产物目录：`E:\rom\work\linux-boot\out\`　脚本：`E:\rom\work\linux-boot\scripts\`

---

## 0. 结论速览

| 形态 | 做法 | 可行性 | 依据强度 |
|---|---|---|---|
| **A3**（推荐先试） | `boot_a`=内核 ＋ `vendor_boot_a`=DTB+cmdline（**无** vendor_ramdisk）＋ `init_boot_a`=我们的 initramfs | ✅ 最稳 | ABL 反汇编：ramdisk 段 C 恒执行且取 init_boot；段 A 空则无拼接 |
| **A**（推荐正式用） | `boot_a`=内核 ＋ `vendor_boot_a`=initramfs+DTB+cmdline ＋ `init_boot_a`=空 cpio | ✅ 稳（社区同机型实测跑过同一形状） | 参考移植项目的 prebuilt 就是这一形状 |
| **A2**（最便宜的探针） | 只刷 `boot_a`（内核 + **恰好一棵** appended FDT） | ⚠️ 只用来确认「内核能跑、屏能出字」；没有 rootfs 会 panic | 单 FDT 校验点 `0xa520` 已定位；dtb 走 boot 的语义**未实测** |
| **B** | `boot_a`=内核 ＋ `recovery_a`（`kernel_size=0` + 我们的 initramfs） | ⚠️ 低概率 | recovery 标记只有一个写入点，冷启动可达性存疑（详见 §6.4） |
| **C** | `\EFI\BOOT\BOOTAA64.EFI` 走 UEFI/BDS | ❌ 当前不可行（缺固件，不是缺 FAT 支持） | 见 §6.5；FAT 4096B 扇区这一关卡本身**能过** |

**一句话**：先按 **A2（1 个分区，测内核）→ A3 或 A（3 个分区，测 initramfs 与 shell）** 的顺序走；整个过程 `boot_a` 永远可以一条命令刷回。

同时纠正了原计划里两处会直接导致失败的点：

1. **`ramdisk` 放进 `boot_a` 是被 ABL 丢弃的**（不是"可能"，是代码路径决定的，§5.2）。
2. **`boot-v3-linux.img` 与本机 DTB 都不能直接用**：前者是 v3 头、且本机要求 v4/GKI 路径；后者 `sm6225-lenovo-tb331fc.dtb` **没有 `__symbols__`**（编译时没加 `dtc -@`），ABL 应用 dtbo overlay 会失败并拒绝启动（§3.3）。

---

## 1. 交付清单（`out\`）

| 文件 | 字节 | 用途 |
|---|---|---|
| `boot_a-linux.img` | 38,965,248 | 形态 A / A3 / B 的内核载体：`ANDROID!` **v4**、page 4096、kernel=`Image`（未压缩）、ramdisk=0 |
| `boot_a-linux-gz.img` | 14,090,240 | 同上，但 kernel=`Image.gz`（**省内存的备选，ABL 是否解压未实测**） |
| `boot_a-linux-dtb.img` | 39,043,072 | 形态 A2：内核 + 恰好一棵 appended FDT（FDT 计入 `kernel_size`） |
| `vendor_boot_a-linux.img` | 1,003,520 | 形态 A：vendor_ramdisk=我们的 initramfs ＋ dtb ＋ cmdline |
| `vendor_boot_a-linux-nord.img` | 86,016 | 形态 A3：dtb ＋ cmdline，vendor_ramdisk **为 0** |
| `init_boot_a-initramfs.img` | 921,600 | 形态 A3：`kernel_size=0` ＋ 我们的 initramfs（与 recovery 同格式，能放 init_boot 是因为它也是 boot 头） |
| `init_boot_a-empty.img` | 8,192 | 形态 A：512B 空 cpio 占位，避免 stock Android ramdisk 参与拼接 |
| `recovery_a-linux.img` | 921,600 | 形态 B：`ANDROID!` v4、**`kernel_size=0`**、ramdisk=我们的 initramfs |
| `initramfs-tb331fc.cpio.gz` | **914,098** | 最小 initramfs（gzip cpio，≤5 MB 要求达成，见 §7） |
| `sm6225-lenovo-tb331fc-linux.dtb` | 75,566 | 修好蓝牙、`dtc -@` 重编、`__symbols__`=122、abl-stubs=121 |
| `dts-bt-fix.diff` | 1,592 | DTS 两处修改的 diff |
| `SHA256SUMS` / `init_boot-empty.cpio` | — | 校验清单 / 空 cpio 原件 |

脚本（`scripts\`）：`fix_dts_bt.py`（DTS 修正，幂等）· `mkboot.py`（v4 打包/自检）· `mk_initramfs.sh` · `build_all.sh`（一键重建全部）· `get_busybox.sh` · `check_busybox.sh` / `test_busybox_qemu.sh`（离线校验 aarch64 busybox）· `verify_dtb.sh` · `flash-tb331fc.ps1`（**每条命令都带 `-s 5e367954`**）

---

## 2. 修正一：DTS 蓝牙节点（本轮必交项）

### 2.1 diff（`out\dts-bt-fix.diff`，节选蓝牙段）

```diff
--- a/sm6225-lenovo-tb331fc.dts
+++ b/sm6225-lenovo-tb331fc.dts
@@ -1993,12 +2000,19 @@
 				bluetooth {
-					compatible = "qcom,wcn3988-bt";
+					/* BTFM partition carries crbtfw21.tlv + crnv21.bin
+					 * (WCN3990 naming). Do NOT use wcn3988-bt here:
+					 * that path asks for apbtfw21.tlv/apnv21.bin and
+					 * uses a different rom_ver shift.
+					 */
+					compatible = "qcom,wcn3990-bt";
 					vddio-supply = <0x4c>;
 					vddxo-supply = <0x59>;
 					vddrf-supply = <0xa8>;
 					vddch0-supply = <0xa9>;
 					max-speed = <0x30d400>;
+					/* GPIO 87 是 WCN3990 的 SW_CTRL *状态* 线：
+					 * hci_qca 按 GPIOD_IN 申请，不能带输出标志。 */
 					swctrl-gpios = <0x28 0x57 0x00>;
 				};
```

修正后的完整节点（可直接抄）：

```dts
serial@4a8c000 {				/* bluetooth 走这一路 geni-uart */
	...
	status = "okay";
	bluetooth {
		compatible = "qcom,wcn3990-bt";
		vddio-supply  = <0x4c>;		/* 保持原有 phandle，未改 */
		vddxo-supply  = <0x59>;
		vddrf-supply  = <0xa8>;
		vddch0-supply = <0xa9>;
		max-speed = <0x30d400>;		/* 3.2 Mbaud */
		swctrl-gpios = <0x28 0x57 0x00>;	/* tlmm gpio 87, ACTIVE_HIGH, 输入 */
	};
};
```
（该 DTS 是从厂商 DTB 反编译来的，全文用裸 phandle；不要改成 `<&tlmm 87 GPIO_ACTIVE_HIGH>` 标签写法，否则要连带改 include。）

### 2.2 为什么（三条独立证据，任一条都足以否定 `wcn3988`）

1. **固件文件名对不上（决定性）**
   `drivers/bluetooth/btqca.c`：
   - `QCA_WCN3990/3991/3998` → `qca/crbtfw%02x.tlv`（第 827 行）
   - `QCA_WCN3988` → `qca/apbtfw%02x.tlv`（第 831 行）
   而本机 `bluetooth_a` 里的固件是 **`crbtfw21.tlv`（227 KB）＋ `crnv21.bin`（4.8 KB）**
   （出处：`TB331FC-Linux-main\docs\PORTING-NOTES.zh-CN.md` §B，从 `BTFM.bin` 提取；本轮又直接解析 `E:\rom\work\zui17_images\bluetooth.img` 确认它是一个 1,028,096 B 的 **FAT16（4096 B/扇区）** 镜像）。
   → 用 `wcn3988-bt` 时驱动会去找 `apbtfw21.tlv`/`apnv21.bin`，**设备上根本没有这两个文件**，`request_firmware` 直接 `-ENOENT`，蓝牙必然起不来。

2. **`rom_ver` 的算法都不一样**（btqca.c 第 806–808 行）
   ```c
   if (soc_type == QCA_WCN3988)
       rom_ver = ((soc_ver & 0x00000f00) >> 0x05) | (soc_ver & 0x0000000f);
   else
       rom_ver = ((soc_ver & 0x00000f00) >> 0x04) | (soc_ver & 0x0000000f);
   ```
   → 即使固件文件名前缀对了，`%02x` 那个数字也会算错一位，仍然找不到文件。

3. **`swctrl-gpios` 的语义只对 wcn3990 成立**
   `hci_qca.c` 第 2432 行：`devm_gpiod_get_optional(dev, "swctrl", **GPIOD_IN**)` —— SW_CTRL 是**状态反馈输入**；参考移植项目实测「GPIO 87 = 状态反馈脚（非使能脚）」，与 `GPIOD_IN` 一致。
   而 4 路稳压器（vddio/vddxo/vddrf/vddch0）在 `qca_soc_data_wcn3988` 与 `qca_soc_data_wcn3990` 里**完全相同**（hci_qca.c 2075/2086 行），所以换 compatible **不需要动稳压器**，这也解释了当初"只改 compatible"为什么看起来"改动很小"——但方向是反的。

> ⚠️ **诚实边界**：换回 `wcn3990` 只保证「驱动走对固件路径」，**不保证蓝牙能用**。参考移植项目在正确 compatible 下仍然卡在「芯片对 `0xFC00` 无应答（tx timeout）」，那是 UART/上电时序层面的问题（引脚 mux、geni SE 寄存器、PMU 顺序）。所以蓝牙这项的正确说法是：**修掉了一个必然失败的原因，剩下一个已知未解的原因。**

### 2.3 顺带修掉的第二个坑：`/chosen/bootargs` 里的 `noinitrd`

原 DTS（继承自 TB128FU）：
```dts
bootargs = "root=/dev/sda18 rw rootwait noinitrd init=/sbin/init console=tty0 PMOS_NOSPLASH";
```
`noinitrd` 会让内核**完全忽略 initramfs**，`root=/dev/sda18` 会让它去等一个我们没有的根。ABL 每次启动都会用自己的 cmdline 覆写 `/chosen/bootargs`（这正是参考项目带着这串坏参数仍能启动的原因），但依赖"别人的覆写"是没必要的风险，已改成：

```dts
bootargs = "console=tty0 keep_bootcon loglevel=8 rdinit=/init clk_ignore_unused pd_ignore_unused";
```
（ABL 覆写时这串被无视；万一某条路径不覆写，这串也是安全的。）

`linux,initrd-start/end`（`0x44986000`/`0x456fe3fc`，原厂 vendor_boot 的遗留值）**保留未动**——参考项目带着它成功启动过，删它属于无据改动。

---

## 3. DTB：为什么必须重编、以及编成了什么

### 3.1 旧的 `out\sm6225-lenovo-tb331fc.dtb` 有两个致命问题

| 问题 | 后果 | 检出方式 |
|---|---|---|
| 编译时**没有 `dtc -@`** → DTB 里**没有 `__symbols__`** | TB331FC 的 ABL 会把原厂 `dtbo` 的 vendor overlay 应用到基础 DTB 上，overlay 用 `__fixups__` 按标签名找节点、靠 `__symbols__` 解析；缺符号 → overlay 失败 → **ABL 拒绝启动**（表现为 fastboot 卡约 5 s 后自动重启） | `verify_dtb.sh`：`__symbols__: MISSING` |
| 蓝牙节点是 `wcn3988-bt` | §2 | 同上 |

（`abl-stubs` 子树本来就在 DTS 里，有 121 个 stub 节点，缺的只是 `-@` 这一步。）

### 3.2 重编方式（不重编内核，只重编 dtb）

kbuild 的 `arch/arm64/boot/dts/...dtb` 目标从仓库根目录调用会二次进入子目录报 `No rule to make target`，所以 `build_all.sh` 里直接复刻 `scripts/Makefile.lib` 的 `cmd_dtc`：

```sh
cd /root/linux-tb331fc
gcc -E -nostdinc -I include -I arch/arm64/boot/dts -I arch/arm64/boot/dts/include \
    -I scripts/dtc/include-prefixes -I arch/arm64/boot/dts/qcom \
    -undef -D__DTS__ -x assembler-with-cpp \
    arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dts -o /tmp/pre.dts
dtc -@ -I dts -O dtb -o out/sm6225-lenovo-tb331fc-linux.dtb /tmp/pre.dts
```

### 3.3 校验结果（`scripts\verify_dtb.sh`）

```
dtb        : sm6225-lenovo-tb331fc-linux.dtb (75566 bytes)
__symbols__: 122 entries          ← 关键，旧 dtb 是 MISSING
abl-stubs  : 121
model      : "Lenovo Xiaoxin Pad 2024 (TB331FC)"
bt node    : compatible = "qcom,wcn3990-bt"
chosen bootargs: console=tty0 keep_bootcon loglevel=8 rdinit=/init clk_ignore_unused pd_ignore_unused
```
318 条 `dtc` warning 全是反编译残留的既有噪声（`unit_address_vs_reg`、`clocks_property` 等），与本轮改动无关，且原厂 DTB 同样存在。

---

## 4. ABL 三条硬约束 —— 逐条复核（代码级，不是猜）

依据：`E:\rom\work\img-abl\REPORT.md`（对 `zui17_images\abl.img` 的静态逆向，含地址与判定条件）。下面每条都给出对应判定点。

### 4.1 「kernel 后面最多一棵 FDT」→ 实测是**恰好 0 或 1 棵**

| 项 | 值 |
|---|---|
| 判定点 | `0x7fa4  bl 0xa520  CheckAppendedDtb` |
| 失败串 | `Not the single appended DTB`（另有 `Dtb offset goes beyond the image size`） |
| 返回码 | `0x800000000000000E` NOT_FOUND —— ABL 不跳转 |
| 通过条件 | 追加 DTB 数 = 0（DTB 来自 vendor_boot）或 = 1（DTB 跟着内核走）；≥2 直接 0xE |

**推论**：参考移植项目 `boot_b` 里**没有** appended DTB、DTB 放在 `vendor_boot`，实测能启动 → 0 棵是合法的；这同时说明 `x0 = BootInfo+0x58`（传给内核的 DTB 指针）在没追加时来自 vendor_boot 的 dtb。**没有哪一处证明"必须恰好 1 棵"**，原任务里"最多一棵"的表述是对的。

### 4.2 「ramdisk 总量上限」→ 真正只有两条判定，且我们的余量极大

| 判定点 | 条件 | 串 |
|---|---|---|
| `0xbff4` | `RamdiskLoadAddr + 总长` 64 位回绕（`RamdiskLoadAddr==0` 且 total>0 必中） | `Error: Ramdisk size is over the limit` → `0x…04` |
| `0xc3f8`/`0xc40c` | `KernelLoadAddr + 追加段 > DTB 载入地址`（`bi+0x58`） | `Kernel size is over the limit` → `0x…02` |
| 总长定义 | `bi+0x78 + bi+0x94 + bi+0x98` = init_boot ramdisk + vendor_ramdisk + recovery ramdisk（`0xbfc4..0xbfdc`） | — |

关于实测的「28.2 MB 可过 / 47.6 MB 被拒」：按本机原厂数字，三段 ramdisk 之和 = vendor 11,779,605 ＋ init_boot 2,005,872 ＋ recovery 14,581,386 ≈ **28.37 MB**，与"28.2 MB 可过"吻合；被拒的那次是 47.6 MB 级别（拼了多份 ramdisk）。
**我方最坏情形**：`vendor_ramdisk 914,098 ＋ recovery 914,098 ＋ init_boot 0` ≈ **1.75 MB**，连上限的十分之一都不到。

### 4.3 ★ 关键更正：**`boot_a` 里的 ramdisk 字段在 arm64 + GKI v4 下根本不会被加载**

`LoadRamdisk 0xbe10` 的 5 段 `CopyMem`（REPORT §2.1）：

| 段 | 来源 | 门控条件 |
|---|---|---|
| A | **vendor_boot** 的 vendor_ramdisk（+0x18） | `header_version >= 3` |
| B | **recovery** 分区的 ramdisk（recovery 头 +0x0c） | `Info+0x2 != 0` **且** recovery 模式标记 `0xc66d0 != 0` **且** `recovery.ramdisk_size != 0` |
| C | `[sp+0x68]` ＝ **init_boot**（GKI 且 v4）否则 boot；取 `bi+0x7c` 偏移处 | **恒执行** |
| D | **boot** 镜像（把 ramdisk 追加到内核之后） | 仅 `BootInfo+0xc0 != 0`，即**只有 32 位内核** |
| E | vendor_boot 的 bootconfig → 拼进 **cmdline**（不是 ramdisk） | `header_version >= 4` |

`[sp+0x68]` 的选择在 `0xbf74..0xbfb0`：`if (Info+0x45c && Info+0x458 >= 4) → init_boot else → boot`。

⇒ **本机是 arm64 + v4 头 ⇒ 段 D 永不执行、段 C 取的是 init_boot**。所以把 initramfs 塞进 `boot_a` 头部 `ramdisk_size` 字段，ABL 连读都不读。原任务形态 a 的写法（"ramdisk = 一个最小 initramfs" 放在 boot_a）**照做必然拿不到 `/init`**，这就是本报告把它改成 A / A3 两种落点的原因。

同样地，段 A 与段 C 是**拼接**关系：`vendor_ramdisk + init_boot ramdisk` 给内核，而内核只解第一层压缩、后面明文的 cpio 被丢弃 —— 所以：
- 形态 A：我们的 gz cpio 在段 A 最前面 → 生效；后面 stock init_boot 的 Android cpio 被丢弃（无害）。
- 形态 A3：段 A 空 → 段 C 的 gz cpio 直接就是唯一内容。

---

## 5. 三种（实为五种落点）形态，逐条给命令与风险

> 所有命令模板都带 `-s 5e367954`。`<FB>` = `E:\rom\tools\platform-tools\fastboot.exe`。
> 推荐用脚本：`cd E:\rom\work\linux-boot; powershell -File .\scripts\flash-tb331fc.ps1 -Form A3`（不带 `-Go` 只打印计划，带 `-Go` 才写）。

### 5.1 形态 A —— `boot_a` 直刷（含 initramfs，**推荐正式用**）

**构成（3 个分区）**

| 分区 | 镜像 | 说明 |
|---|---|---|
| `boot_a` | `boot_a-linux.img`（或 `-gz`） | `ANDROID!` v4、page 4096、kernel=`Image`、ramdisk=0 |
| `vendor_boot_a` | `vendor_boot_a-linux.img` | vendor_ramdisk=我们的 initramfs（gzip cpio）；dtb=修好的 DTB；cmdline 见下 |
| `init_boot_a` | `init_boot_a-empty.img` | 512 B 空 cpio，把 Android 的 init_boot ramdisk 从拼接里摘掉（严格说被丢弃也无害，刷掉更干净、更可控） |

cmdline（写在 vendor_boot 头里，189 字符）：
```
console=tty0 keep_bootcon ignore_loglevel loglevel=8 fbcon=rotate:1 nomodeset
clk_ignore_unused pd_ignore_unused rdinit=/init
earlycon=qcom_geni,0x4a90000 androidboot.hardware=qcom panic=10
```
- **不写 `root=`、不写 `noinitrd`**（前者会让内核等根分区，后者会让它忽略 initramfs）
- `clk_ignore_unused pd_ignore_unused`：不写的话内核会关掉 ABL 留给我们的显示时钟/电源域 → 黑屏
- `nomodeset`：这一版先让 simpledrm + fbcon 占住屏幕（`/chosen/framebuffer@5c000000`，1200×2000，stride 4800，落在 `splash_region@5c000000` 的 15 MB 保留区里）
- `fbcon=rotate:1`：面板原生竖屏 1200×1920，横着用要旋转

命令：
```
<FB> -s 5e367954 getvar current-slot
<FB> -s 5e367954 flash boot_a        out\boot_a-linux.img
<FB> -s 5e367954 flash vendor_boot_a out\vendor_boot_a-linux.img
<FB> -s 5e367954 flash init_boot_a   out\init_boot_a-empty.img
<FB> -s 5e367954 reboot
```
`Image.gz` 变体把第一条换成 `boot_a-linux-gz.img`（见风险 R3）。

**风险**
- **R1（低）**：DTB 里的 `abl-stubs`/`__symbols__` 已按参考项目要求补齐（122/121），但 stub 会被当成 clock consumer，可能打印 `sync_state() pending due to abl-stubs`——只是日志噪声。
- **R2（低）**：`kboot` 的 vendor_boot 段序（ramdisk | dtb | **table** | bootconfig）是按原厂镜像逐字节核对过的；若段序写错 ABL 会立刻硬失败，本包的 `mkboot.py dump` 已自检 `layout ok: True`。
- **R3（中）**：`Image.gz` 的可用性**未实测**。原厂 boot_a（A17，43,092,480 B）与 ZUI17 boot（47,172,096 B）里装的都是**未压缩 `Image`**（首 4 字节 `4d5a..` = arm64 Image 头），ABL 反汇编里也确有压缩路径（`0x9824` 处有 `+0x80000`），但"支持 gzip"这件事没有任何一次真机成功记录。**默认用未压缩 `Image`。**
- **R4**：`vendor_boot_a`/`init_boot_a` 被改写。回滚镜像与哈希已备好（§8），但那是"整包一致"的原厂 ZUI16 544 版本，不是你机器上那份的字节级快照。

### 5.2 形态 A3 —— ramdisk 放 `init_boot_a`（**推荐先试**）

| 分区 | 镜像 |
|---|---|
| `boot_a` | `boot_a-linux.img` |
| `vendor_boot_a` | `vendor_boot_a-linux-nord.img`（dtb + cmdline，vendor_ramdisk=0） |
| `init_boot_a` | `init_boot_a-initramfs.img`（`kernel_size=0` + 我们的 initramfs） |

```
<FB> -s 5e367954 flash boot_a        out\boot_a-linux.img
<FB> -s 5e367954 flash vendor_boot_a out\vendor_boot_a-linux-nord.img
<FB> -s 5e367954 flash init_boot_a   out\init_boot_a-initramfs.img
<FB> -s 5e367954 reboot
```
**为什么它比 A 更"干净"**：内核收到的 ramdisk 缓冲区里**只有一份 cpio**，不存在"gz 流 + 拼接尾巴"的层次问题。代价是必须动 `init_boot_a`（`init_boot` 分区 8 MB，我方 921,600 B，余量充足）。

风险同 R1/R3；另加 R5：`init_boot` 分区上如果还留着旧 Android ramdisk 的尾巴，`fastboot flash` 只写镜像长度，但头部 `ramdisk_size` 已声明为 914,098，ABL 只读这段，**不会读到旧尾巴**。

### 5.3 形态 A2 —— 只刷 `boot_a`，内核 + 一棵 appended FDT（最便宜的探针）

```
<FB> -s 5e367954 flash boot_a out\boot_a-linux-dtb.img
<FB> -s 5e367954 reboot
```
- **期望结果**：屏上出现内核日志（simpledrm + fbcon），跑到 `Run /init as init process` 之前就找不到 init（cmdline 用的是 stock A17 vendor_boot 的，没有 `rdinit=`、也没有 `root=`）→ `panic=…` 或 `Kernel panic - not syncing: No working init found`。
- **这一步的价值**：只用一次 flash 就能分辨"ABL 放行 + 内核起来 + 屏幕能用"这三件事；失败也只会看到 fastboot 循环，回滚一次即可。
- **风险 R6（中，语义未实测）**：FDT 我放在**紧邻内核之后、8 字节对齐**，并**计入 `kernel_size`**（这样它必然落在 ABL 已加载的内核缓冲区内；`CheckAppendedDtb` 报错串里有 `Dtb offset goes beyond the image size`，暗示它是在 `kernel_size` 范围内找的）。若 ABL 实际要求页对齐或在 `kernel_size` 之外，则会返回 `0xE`/`Not the single appended DTB` —— 那就是把这条路否掉、改走 A3/A，代价仅一次 flash。
- 附带风险：stock `vendor_boot_a` 里的 DTB 也存在。若 ABL 把 vendor dtb 也算进"追加树"计数 → 同样 0xE。**这正是必须做 A2 试验才知道的事**，也是我把它排在第一位、且明确标为"只测内核"的原因。

### 5.4 形态 B —— `recovery_a`（`kernel_size=0`）

| 分区 | 镜像 |
|---|---|
| `boot_a` | `boot_a-linux.img`（内核来自这里 —— 本机 recovery 语义确实是"内核来自 boot"） |
| `recovery_a` | `recovery_a-linux.img`（`ANDROID!` v4、`kernel_size=0`、ramdisk=我们的 initramfs） |

```
<FB> -s 5e367954 flash boot_a     out\boot_a-linux.img
<FB> -s 5e367954 flash recovery_a out\recovery_a-linux.img
<FB> -s 5e367954 reboot
```
**机理（REPORT §2.3）**：`LoadImageAndAuth` 在 `0x1b0d8` 处，只有"本次不是 recovery 启动（`Info+0x1 == 0`）"时才检查 recovery 分区；若 `recovery.header_version >= 3` 且 **`recovery.kernel_size == 0`** → 打印 `Recovery partition has no kernel` → 调 `0xfca0()` 把全局 `0xc66d0` 置 1 → 之后 `LoadRamdisk` 的**段 B** 才会把 recovery 的 ramdisk 接到段 A 后面。

**为什么判低概率**：同一个标记 `0xc66d0` 的唯一读取点 `0x89a0()` 又是"往镜像表里加 recovery 条目"的前置条件（`Info+0x2 && 0x89a0()`），形成"要读 recovery 得先有 recovery 标记、要有标记得先读 recovery"的环。静态看这条链是**半闭环**的；只有 `Info+0x1 != 0`（PMIC/aboot 判定为 recovery 重启）时确定能走。若你愿意多花一次 flash 验证，值；否则直接跳过。

**风险 R7**：`recovery_a` 被改写；回滚镜像是 `E:\rom\TB331FC\刷机包\TB331FC_ZUI_16.0.544\image\recovery.img`（100,663,296 B，`ea89e4c3…`）。另外注意本机 `recovery` 分区 100 MB，镜像 921,600 B，写入后分区剩余内容不清零——不影响 ABL（只按头部长度读）。
**风险 R8**：历史教训——ABL 对 **带内核的第三方 recovery** 有独立白名单（TWRP/OrangeFox 全部劝退）。本形态 `kernel_size=0`，理论上不触发白名单，**但这正是"未验证"的部分**。

### 5.5 形态 C —— UEFI/BDS 的 EFI 应用（`\EFI\BOOT\BOOTAA64.EFI`）

**结论：当前不可行，瓶颈不在 FAT，而在"没有能跑 BDS 的固件"。**

**(1) FAT 4096 B 扇区这一关卡：能过。** 直接解析本机镜像的 BPB：

| 分区 | 证据 | 几何 |
|---|---|---|
| `modem_a`（= `NON-HLOS.bin`，40,980,480 B） | OEM `MSDOS5.0`、`0xaa55`、`FSTYPE "FAT16  "` | **`BytsPerSec = 4096`**、`SecPerClus = 4`（16 KB 簇）、2 份 FAT、每个 FAT 6 扇区、`HiddenSectors = 0`、`TotalSectors32 = 46080`（约 188.7 MB 的卷，镜像只带前 41 MB） |
| `bluetooth_a`（= `bluetooth.img`，1,028,096 B） | 同上 | **`BytsPerSec = 4096`**、`SecPerClus = 4`、FAT 3 扇区、`TotalSectors32 = 16384` |

EDK2 FatPkg 的 BPB 校验接受 `BytsPerSec ∈ {512,1024,2048,4096}`，而 4096 恰好是 Mu/Silicium 系 UFS 驱动对外发布的 BlockIo 块大小 → 1:1 映射，不存在"半扇区读"问题；即便固件把 BlockIo 做成 512，`4096 % 512 == 0` 也在允许范围内。**所以"EDK2 挂不上 4K 扇区 FAT"这个担心可以划掉。**

**(2) 真正的前置条件（缺一不可）**

1. **一台能跑 BDS 的固件**。本机 `XBL` 是 EDK2 系（`gBS+0x160` CopyMem / `LocateProtocol` 都在），但 stock XBL + ABL 的路径是 `LoadImageAndAuth → BootLinux → LinuxLoader`，**没有 Boot Manager 去扫 ESP 里的 `\EFI\BOOT\BOOTAA64.EFI`**。要跑 EFI 应用必须换/加固件：Mu-Silicium 的 `uefi-tb128fu`（同平台 SM6225 兄弟机型 TB128FU）是唯一现成参考，但它**尚未发布**（`xpkg`/`Binaries` 未公开），且是 TB128FU 的板级包；TB331FC 没有对应包。
2. **ESP 放在哪**。能当 ESP 的只有 `modem_a`（FAT16/188 MB）与 `bluetooth_a`（FAT16/67 MB）。写 `modem_a` 会**销毁 `NON-HLOS` 里的 WiFi/BT 固件**（`wlanmdsp.mbn` + 34 个 `bdwlan.*` 就在这个 FAT 里），等于用 Android 的 WiFi/蓝牙换一个 ESP；写 `bluetooth_a` 则毁掉 `crbtfw21.tlv`/`crnv21.bin`。两者都必须先整区备份，且都不便宜。
3. **EFI 应用本身**。`E:\rom\release\BDS-EFI-Probe\` 里已有 lead 做的 2,048 B 探针（PE machine `0xaa64`、subsystem 10），先用 U 盘验"BDS 到底会不会扫可移除介质"——这一步对设备零写入，**是形态 C 唯一值得先做的动作**。

**(3) 建议**：形态 C 在拿到 TB331FC 的 UEFI 包之前直接搁置；它的价值是"以后能加载任意 EFI 引导器/Windows-on-ARM"，与"先把 mainline Linux 跑起来"这件事没有依赖关系。

---

## 6. 最小 initramfs（914,098 B，要求 ≤5 MB ✅）

### 6.1 内容

```
/init                     <- shell 脚本（busybox sh）
/bin/busybox              <- BusyBox v1.36.1-osm0sis，ELF64 aarch64，**静态**
/bin/{sh,mount,umount,...,switch_root,...}   52 个 applet 软链（构建期就建好，不依赖 --install）
/sbin/{poweroff,reboot,switch_root,modprobe,insmod}   5 个
/bin/gadget.sh            <- CDC-ACM USB 串口控制台（configfs）
/dev/{console,null}       <- 静态兜底节点
/{proc,sys,dev,tmp,run,newroot,lib/firmware}
```

`init` 做的事（顺序即代码顺序）：

1. `mount devtmpfs /dev` → `busybox --install -s /bin`（双保险）→ 挂 `proc/sys/devpts/tmpfs×2`（**不挂 configfs**，留给 `gadget.sh`）
2. `dmesg -n 8`：把 `KERN_DEBUG` 也打到屏上
3. `exec 0</dev/console 1>/dev/console 2>&1`：之后自己所有输出都上屏
4. 打印 banner＋`/proc/cmdline`＋uptime
5. 后台起 `gadget.sh`（`/dev/ttyGS0`，Windows 上就是新出现的 COM 口）
6. 装一个 `/sbin/diag`：一次打印 cmdline / uptime / 块设备 / mounts / remoteproc 状态 / backlight / input 设备 / `dmesg | tail -40`
7. **尝试持久根**：cmdline 里有 `root=/dev/xxx` 就等最多 20 s，`mount -t ext4 -o rw`，`mount --move` 三个伪文件系统后 `exec switch_root /newroot /sbin/init`；失败则打印原因并**留在 initramfs**
8. 兜底：前台 shell（`sh -i` on `/dev/console`），后台每 15 s 打一行 `[init] alive #N uptime=…s` 心跳，并在 `ttyGS0` 出现时补一个 shell

> 心跳那行是**最省事的判据**：屏上只要出现一次 `[init] alive #1`，就说明「ABL 放行 + 内核起来 + simpledrm/fbcon 出图 + initramfs 被解出 + `/init` 在跑」五件事全成立。

### 6.2 大小

| 阶段 | 字节 |
|---|---|
| 解包后 cpio（newc，`--owner 0:0`） | 1,513,984 |
| **gzip -9 → `initramfs-tb331fc.cpio.gz`** | **914,098**（892 KiB，上限 5 MiB 的 17%） |

占用主体就是 busybox 本身（1,498,688 B 静态）。不加 `/lib/modules`（参考项目那套 676 个 `.ko` 会直接超 5 MB，且 WiFi 驱动 `ath10k_snoc` 只能是 `=m`）——**这一版的目标是"看到 console"，不是 WiFi**。

### 6.3 离线校验（没有真机也能做）

- `check_busybox.sh`：`ELF 64-bit ARM aarch64, statically linked`（无 `PT_INTERP`）、版本串 `BusyBox v1.36.1-osm0sis`
- `test_busybox_qemu.sh`：用 `qemu-aarch64-static` 实跑，`--list` 出 **353 个 applet**，init 需要的 37 个里只缺 `mdev`（不需要，用 devtmpfs）
- 构建时自动 `qemu-aarch64-static busybox sh -n /init` → `init: syntax OK` / `gadget.sh: syntax OK`

### 6.4 重建

```bash
wsl -d ub -u root bash /mnt/e/rom/work/linux-boot/scripts/get_busybox.sh   # 取静态 aarch64 busybox
wsl -d ub -u root bash /mnt/e/rom/work/linux-boot/scripts/build_all.sh      # DTB + initramfs + 全部镜像 + sha256
```

---

## 7. 验证判据表（照这个读结果）

| 屏幕 | `adb devices` | 串口/USB 串口 | 判定 | 下一步 |
|---|---|---|---|---|
| 直接弹回 fastboot（约 5.3 s） | — | — | **ABL 拒绝**（DTB overlay/符号、单 FDT 校验、vbmeta） | 换 A3/A；A2 失败就说明 dtb 不宜放 boot |
| 回 fastboot 约 4.1 s 且 `unbootable: yes` | — | — | vbmeta descriptor 硬拒 | 别动 vbmeta（本包默认不动），换回原厂 vbmeta |
| **企鹅/内核日志滚屏**，末尾 `Kernel panic - not syncing: No working init found` 之类 | 无 | 无 | 内核起来了但没 initramfs ⇒ ramdisk 落点不对（A2 就是这样） | 上 A3/A |
| 屏上出现 `TB331FC mainline initramfs`＋`cmdline:` 两行 | 无 | — | initramfs 解出且 `/init` 在跑 | 继续看 §7 后两行 |
| 出现 `[init] alive #N  uptime=Xs` 且 N 递增 | 无 | 出现新 COM 口 | **完全成功（console 阶段）** | 用 `diag` 收集 dmesg；下一步做 rootfs |
| USB 插上后 Windows 多出一个 COM 口 | 无 | 115200 8N1 有回显 | CDC-ACM gadget 绑定成功（`USB_CONFIGFS_ACM=y` 已在 config 里） | — |
| `[init] mounted, switching root` 后卡住 | 无 | 有 | rootfs 挂上了但它的 `/sbin/init` 不可用 | 检查 `/dev/sda18` 内容 |
| 黑屏有背光 | — | 无 | 显示被 msm 抢走或时钟被关 | 确认 cmdline 有 `clk_ignore_unused pd_ignore_unused nomodeset` |
| 花屏（蓝绿网格） | — | — | DPU 时钟掉了（参考项目已定位：DPU OPP 只留 384 MHz） | 与本包无关，查 DTS OPP |
| 屏幕无反应、也不回 fastboot，但 USB 上出现 `05C6:900E` | — | — | 内核 panic 后掉 Qualcomm crash dump | 长按电源 30–40 s 重来；A 槽本身未动 |

补充：
- **`adb` 不可用是正常的**——mainline Linux 没有 adbd，也没有 Android 的 USB 配置。控制台只有两条：面板（fbcon）与 USB CDC-ACM（`/dev/ttyGS0` → Windows COM 口）。**不需要接 UART**。
- 若面板不出图但 USB 有 COM 口：说明内核活了，只是显示没接管，可直接在 COM 口里 `diag`、`dmesg` 查原因。
- 回 fastboot 后**不要连刷多个镜像**（历史教训：未回滚就连试 → 900E）。一次一个形态。

---

## 8. 回滚

**一条命令（只回 `boot_a`）**
```
E:\rom\tools\platform-tools\fastboot.exe -s 5e367954 flash boot_a E:\rom\work\a17dump\boot_a.img
```
镜像 SHA256 `2510b098380a573a40ee6600aa9124ced06a047c14c21e6bf7cd596fbbc3c14b`（本轮已复算一致）。

**脚本（推荐，带哈希校验 + 只写 `_a`）**
```powershell
cd E:\rom\work\linux-boot
powershell -File .\scripts\flash-tb331fc.ps1 -Form rollback -Go          # boot_a
powershell -File .\scripts\flash-tb331fc.ps1 -Form rollback -Go -Full    # + vendor_boot_a / init_boot_a / recovery_a
```

`-Full` 用的原厂件（都来自 `E:\rom\TB331FC\刷机包\TB331FC_ZUI_16.0.544\image\`，哈希已写入脚本，不匹配就拒绝刷）：

| 分区 | 镜像 | 字节 | SHA256 |
|---|---|---|---|
| `boot_a` | `a17dump\boot_a.img` | 100,663,296 | `2510b098…c14b` |
| `vendor_boot_a` | `vendor_boot.img` | 100,663,296 | `d526c77b243c5277fd6fb715c9108f9bdc6f7728359ee19a383bc0442ed7a8a1` |
| `init_boot_a` | `init_boot.img` | 8,388,608 | `2d090fb59244cf3cf55b95478b98234f4a27615fd1c63220e685f76ae79bb01b` |
| `recovery_a` | `recovery.img` | 100,663,296 | `ea89e4c32e490b5eacd6323d577467ec76d2b7943a18bd0df8e31c310e93bd08` |

> 说明：`vendor_boot_a`/`init_boot_a` 的原件是按"机器上装的是 A17 内核 + 原厂 ZUI16 544 boot 链"这一已知组合取的（skill 记录里 A17 那套就是这么配的），**不是从你这台机器上抓的字节级快照**（fastboot 不支持回读分区）。要字节级快照，只能用 9008 的 `fh_loader --sendxml` 读（`E:\rom\work\edl\` 那套），代价是约 10 分钟。若你打算把 A 槽当长期试验田，建议先做这一次回读。
> 另注：A 槽的 `vbmeta_a`、`system_a`、`product_a`、`system_ext_a` 本轮**完全没碰**，它们不受影响。

---

## 9. 未验证项 / 风险清单（按重要度）

| # | 事项 | 影响 | 处置 |
|---|---|---|---|
| 1 | ABL 是否接受**未压缩 `Image` 之外**的形式（`Image.gz`） | 只影响选哪个内核镜像 | 默认用 `Image`；`-gz` 作备选 |
| 2 | `boot` 里 appended FDT 的对齐/计数语义（A2） | 决定 A2 是否成立 | 用一次 flash 试；失败即弃 |
| 3 | recovery 标记 `0xc66d0` 冷启动可达性（形态 B） | 决定 B 是否成立 | 可试，不值得优先 |
| 4 | 蓝牙换回 `wcn3990` 后仍可能 `0xFC00` 无应答 | 蓝牙仍不可用 | 已知未解，属 UART/时序层 |
| 5 | TB331FC 无 UEFI 包（形态 C） | 形态 C 不可行 | 搁置；保留 U 盘 BDS 探针 |
| 6 | `initramfs` 里的 busybox 来自 OrangeFox 构建（osm0sis 版） | 静态且 applet 齐全（qemu 已验） | 若要更"干净"可换 Ubuntu `busybox-static:arm64`（脚本支持） |
| 7 | 没有真机，全部结论为静态/离线推导 | — | 已把每条结论的判定点写进本报告，便于真机对照 |

---

## 10. 建议的动手顺序（每步都可一条命令回滚）

| 步 | 动作 | 期望 | 失败就 |
|---|---|---|---|
| 1 | `-Form A2 -Go` | 屏出内核日志后 panic（说明 ABL 放行 + 内核活 + 屏可用） | `-Form rollback -Go`，改走步 2 |
| 2 | `-Form A3 -Go` | `[init] alive #N` 心跳 + USB COM 口 | `-Form rollback -Go -Full`，改走步 3 |
| 3 | `-Form A -Go` | 同上（若 A3 因 init_boot 写坏才失败） | 回滚 |
| 4 | （可选）`-Form B -Go` | 同上（验证 recovery 通道） | 回滚 |
| 5 | 在 shell 里 `diag`，把 dmesg 存下来 | 拿到 display/UFS/USB 的真实状态 | — |
| 6 | 下一步工作：把 rootfs 放进 `/dev/sda18`，或按参考项目用「FAT32 SD 卡 + ext4 镜像文件 + losetup/switch_root」 | 进 userspace | — |

每条失败后都建议先 `fastboot getvar current-slot` 确认还停在 `a` 槽（ABL 重试耗尽会自动回落，但别指望）。

---

## 11. 附录

### 11.1 目录

```
E:\rom\work\linux-boot\
  REPORT.md                     本报告
  out\                          全部镜像 + SHA256SUMS + dts-bt-fix.diff
  scripts\
    build_all.sh                一键：DTS 修正 → DTB(-@) → initramfs → 6 个镜像 → 自检 → sha256
    fix_dts_bt.py               DTS 两处修正（蓝牙 compatible、/chosen/bootargs），幂等
    mkboot.py                   v4 打包器（boot / recovery / vboot / dump 自检）
    mk_initramfs.sh             initramfs 构建（含 applet 软链 + qemu 语法检查）
    get_busybox.sh              取静态 aarch64 busybox（本地优先，失败走清华源）
    check_busybox.sh            ELF/静态性检查
    test_busybox_qemu.sh        qemu 实跑，核对 applet 清单
    verify_dtb.sh               __symbols__ / abl-stubs / model / bt / bootargs 五项
    flash-tb331fc.ps1           刷机与回滚（A / A2 / A3 / B / rollback / status，全部 -s 5e367954）
```

### 11.2 bash 命令模板（若不在 Windows 上跑）

```bash
FB="fastboot -s 5e367954"
O=/mnt/e/rom/work/linux-boot/out

# 形态 A3（推荐先试）
$FB flash boot_a        $O/boot_a-linux.img
$FB flash vendor_boot_a $O/vendor_boot_a-linux-nord.img
$FB flash init_boot_a   $O/init_boot_a-initramfs.img
$FB reboot

# 回滚
$FB flash boot_a /mnt/e/rom/work/a17dump/boot_a.img && $FB reboot
```

### 11.3 关键判据速查（给下次接手的人）

| 现象 | 结论 | 出处 |
|---|---|---|
| `Not the single appended DTB` / 0xE | 追加 FDT ≥2 棵 | ABL `0xa520` |
| `Error: Ramdisk size is over the limit` | `RamdiskLoadAddr+总长` 回绕或 loadaddr=0 | ABL `0xbff4` |
| `Kernel size is over the limit` | 内核段越过 DTB 载入地址 | ABL `0xc40c` |
| `Recovery partition has no kernel` | recovery `kernel_size==0` → 置 recovery 标记 | ABL `0x1b150` |
| `Not the single appended DTB` 之外的 overlay 失败 | DTB 缺 `__symbols__` | 参考项目 README §6.1 |
| 屏黑但有 USB 串口 | 内核活了、显示没接管 | 本文 §7 |
