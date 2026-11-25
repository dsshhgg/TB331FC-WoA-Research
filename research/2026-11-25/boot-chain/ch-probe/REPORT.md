# 用真内核做「0x5C000000 到底会不会变」的判定实验（paint proof）

> 2026-11-25 · 子代理产出 · **未刷机**（设备当前停在 v9 ctl 镜像上，需要人工上电）
> 目录：`E:\rom\work\woa\ch-probe\`

---

## 0. 一句话

**把 `boot_a` 里那个确定能开机的 A17 内核的 `code1`（4 字节）改成 `b` 到内核尾部新加的一段 168 字节桩，桩关 MMU/DCache → 把 15 MiB 纯红写满 `0x5C000000` → 恢复 SCTLR → 跳回原 `primary_entry`。**

于是「能不能开机」本身就成了「桩有没有执行」的证据：**原内核唯一的入口就是 `0x40000004`，而它现在是一条指向桩的 `b`；能进 Android ⇒ 桩一定跑了。**

| 现象 | 结论 |
|---|---|
| **屏幕变红，然后正常进 Android** | **通道有效** ⇒ v9 全黑 = ABL 没走到 `blr` |
| **屏幕不变，正常进 Android** | **通道无效（决定性否定）** ⇒ 之前所有「卡 logo = 载荷没执行」的结论作废 |
| **屏幕变红，但没进 Android** | 桩破坏了交接（SCTLR 恢复/涂色范围），改桩再试 |
| **卡 logo / 回 fastboot** | 补丁破坏了内核（或 ABL 没跳）⇒ 先刷控制图区分 |

---

## 1. 为什么这个镜像能把「通道」判死

上一轮的漏洞是：`Mu-tb331fc-v9-sentinel-ctl.img`（画完 RED 就死循环）刷进去后屏幕只有 Lenovo logo，
于是「**没颜色**」既可能是「ABL 没跳」，也可能是「跳了但 `0x5C000000` 不在扫描」——两者的结论完全相反。

这个镜像把两件事**绑死**：

```
0x40000000  ccmp x18,#0,#0xd,pl      ← code0，原样保留（"MZ" 魔法字节还在）
0x40000004  b    0x42918A00          ← code1，唯一被改写的数据流入口
0x42918A00  桩：关 MMU/DC → 涂红 15 MiB @0x5C000000 → 恢复 SCTLR → b 0x42550000
0x42550000  primary_entry（原 code1 的目标，一个字节没动）
```

- **进入内核正文的唯一路径**就是 `0x40000004`，而它现在是一条指向桩的 `b`。桩执行完才把控制权交回 `0x42550000`。
  所以 **Android 能开机 ⇔ 桩执行过**。
- 那有没有可能 ABL 根本不从 `0x40000000` 进（改走 PE 入口 `0x2550404`）？**不会**：
  `0x2550404` 是 arm64 EFI-stub 的 PE 入口，它的调用约定是 `x0 = EFI ImageHandle`；而 ABL 在 `0x862c` 的
  `blr x8` 传的是 `x0 = DtbLoadAddr`（`0x861c ldr x0,[sp,#0x278]`，FDT 物理地址）。拿 DTB 当 EFI handle 用必崩。
  这也正是内核为什么把 `code0` 做成 `ccmp`("MZ") + `b primary_entry`——它本来就是给「直接跳到镜像开头」的加载器准备的。
- 于是：
  - **有红** ⇒ 写 `0x5C000000` 在屏幕上是可见的（通道有效）。
  - **没红但开机** ⇒ 桩执行过、涂了 15 MiB、却看不见 ⇒ **`0x5C000000` 不是这一段被扫描的缓冲**（或面板已停止扫描）
    ⇒ **所有「卡 logo 所以载荷没执行」的推理全部作废**，v9 的「ABL 没跳」也就不成立。

---

## 2. 逐字节改了什么

源：`E:\rom\work\a17dump\boot_a.img`，sha256 `2510b098380a573a40ee6600aa9124ced06a047c14c21e6bf7cd596fbbc3c14b`
（= 现在机器上 A17 能开机的那份 dump）。

| 位置 | 原值 | 新值 | 说明 |
|---|---|---|---|
| boot header +0x08 (`kernel_size`) | `0x00000000_02918A00` (43,092,480) | `0x02919A00` (43,096,576) | 只 +0x1000（一页），因为尾部追加了桩 |
| kernel +0x00 (code0) | `fa405a4d` (`ccmp x18,#0,#0xd,pl`，"MZ") | **不变** | 保住 PE/EFI 的 `MZ` 与原有语义 |
| kernel +0x04 (code1) | `14953fff` (`b 0x42550000`) | `14a4627f` (`b 0x42918a00`) | **唯一被改写的指令** |
| kernel +0x2918A00 … +0x2918AA8 | （原为 .bss 首字节，文件里不存在） | 168 字节桩 | 追加；其余补 0 到 0x1000 |
| 其余全部 | — | **逐字节相同** | 见 `out\verify.txt` 与脚本自检第 5/6 项 |

> 没有做「整体后移」：`text_offset`(+0x08) 与 `image_size`(+0x10) 一个字节都没动，
> 所以 ABL 的装载地址计算与 `image_size <= Dtb-KL` 闸门**与出厂镜像完全等价**。

### 复算

```powershell
cd E:\rom\work\woa\ch-probe
wsl -d ub -u root -- bash -lc "cd /mnt/e/rom/work/woa/ch-probe && aarch64-linux-gnu-as -o paint_stub.o paint_stub.S && aarch64-linux-gnu-ld -Ttext=0x42918A00 -o paint_stub.elf paint_stub.o && aarch64-linux-gnu-objcopy -O binary --only-section=.text paint_stub.elf out/paint_stub.bin"
python patch_boot_a.py          # 生成 + 全量自检（任一不符就退出非 0）
python patch_boot_a.py --ctl    # 对照图：只有一条 b，不涂色
```

`patch_boot_a.py` 的自检项（全部打印 `[ok]` 才算通过）：
输出尺寸、`kernel_size` 增量、header 其余字节不变、`MZ`/code0 不变、code1 指向桩、
`kernel[8:0x2918A00]` 与出货镜像逐字节相同、`text_offset`/`image_size`/`ARM\x64` 不变、桩落位、尾部补零。

### 桩在干什么（168 B，PC 相对，与 KernelBaseAddr 无关）

```
mrs  x9, CurrentEL ; ubfx x9,#2,#2          ; 1/2/3
按 EL 选 sctlr_el1/el2/el3：读 → 清 M(bit0)、C(bit2) → 写回（读改写，绝不 msr sctlr,xzr）
isb
x13 = 0x5C000000 ; x12 = 0xFFFF0000FFFF0000 ; x14 = 0xF0000 (983,040 × 16 B = 15 MiB)
loop: stp x12,x12,[x13],#16 ; subs x14,#1 ; b.ne loop
dsb  sy
按 EL 把原 SCTLR 写回 → isb        ; 交班状态与出厂镜像**完全相同**
b    0x42550000                    ; primary_entry
```

- 只碰 `x9..x14`，**`x0`(DTB)/`x1..x3` 一个都不碰**（arm64 启动协议只保证这四个）。
- 全程不用栈、不用 cache 维护（没改任何会被当指令执行的内存）。
- 颜色用 `A=0xFF`：万一 MDP 主平面还开着 per-pixel alpha 混合，`A=0` 会被混掉。
- 涂满 `cont_splash_region` 的 **15 MiB**（DTBO：`splash_region@5c000000 { reg = <0 0x5c000000 0 0xf00000> }`），
  即使 mixer 扫的是第二缓冲（+9.6 MB）也在范围内。上限 0x5CF00000 仍低于 UEFI FD 的 0x5FC00000。

---

## 3. ABL 闸门核算（都用 `abl-jump-analysis\full.asm` 的地址）

| 闸门 | 代码 | 本镜像 |
|---|---|---|
| 版本 | `0x7130` 读 header+0x28 | v4，`header_size=1584`（与出厂一致） |
| 压缩? | `IsGzip` (`0x6b950`) → `+0xc2` | 否，未压缩 `Image` |
| `UNCOMPRESSED_IMG` 特例 | `0x95b4` 比较前 16 B 与 `"UNCOMPRESSED_IMG"` | 我们是 `MZ…`，不命中 ⇒ 不会走「src=kernel+20」那条 |
| 装载地址 | `0x97f8` 若 `image_size==0` → `+0x80000`；否则 `0x9808` `KL = base + text_offset` | `image_size=0x29C0000≠0`、`text_offset=0` ⇒ **KL = base = 0x40000000** |
| **G1** | `0x9b50` 若 `Dtb-KL == 0` 报 `Not Enough space…` | `Dtb-KL = 0x47FE000`，非 0 ✅ |
| 搬运 | `0xa394` `CopyMem(dst=KL, src=ImageBuffer+PageSize, n=kernel_size)` | 只多搬 0x1000 字节；区域顶 0x45700000 富余 71 MiB ✅ |
| 魔数 | `0xa270`/`0xa3bc` 查 `kernel+0x38 == "ARM\x64"` | 未改 ✅ |
| **G2** | `0xa3e8` `image_size <= DtbLoadAddr - KernelLoadAddr` | 41 MiB vs **71 MiB**，余量 30 MiB ✅（`image_size` 未改，与出厂逐位相同） |
| 单棵 DTB | `0xa520` `fdt_check_header(p2)` | 本镜像 **ramdisk_size=0、没有尾接 DTB**，这条检查路径不触发（与出厂 `boot_a` 同构） |

G1/G2 用的具体数：`KernelBaseAddr=0x40000000`、`KernelSize=0x5700000`（top `0x45700000`）、
vendor_boot ramdisk `13,635,716` → `align=0xD01000`，`Dtb = 0x45700000 − 0xD01000 − 0x201000 = 0x447FE000`。
即便 KernelSize/ramdisk 的实测值有几 MB 偏差，30 MiB 的余量也吃得下；且 `image_size` 与出厂一致，出厂能过这里就能过。

---

## 4. 产物

| 文件 | 大小 | sha256 |
|---|---|---|
| `out\boot_a-paint-proof.img` | 43,100,672 | `ad4e7cd6f74cb33f0d162ebb8e7a3dfd70f03179c65e524b7adde53b6d6e7cdb` |
| `out\boot_a-patch-ctl.img`（对照，无涂色） | 43,100,672 | `85f4b96e4c57581c851afc2e6765f2dfa3e642d9a1325f6bcccc705665727639` |
| `out\paint_stub.bin` | 168 | `92f62b91767d949471fbe26337afe5a9e5b2017ba5ff5a6dc74594a412dafece` |
| `out\verify.txt` | — | 头部字段 + 入口反汇编 + 桩反汇编（本文件 §2/§4 的数据来源） |
| `paint_stub.S` / `patch_boot_a.py` / `run.ps1` | — | 可复算源 |

**对照图**（`-Ctl`）只有一个 `b 0x42550000`，什么都不画：用来把「补丁机制本身有问题」和「桩的代码有问题」分开。
如果主图卡 logo，先刷对照图——对照图能开机就说明机制无害、问题在桩体。

---

## 5. 上机（**本子代理没有刷机**）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:\rom\work\woa\ch-probe\run.ps1
```

脚本会：① 校验回滚包 sha256 = `2510b098…`；② 校验镜像 sha256 与 sidecar 一致；③ 离线检查 boot header
（`ANDROID!` / v4 / `kernel_size` / `code0=MZ` / `code1→0x42918a00` / `text_offset=0` / `image_size=0x29c0000` / `ARM\x64`）；
④ 等 `5e367954` 进 fastboot；⑤ 检查 `current-slot = a`；⑥ 刷 + 重启；⑦ 问「有没有变红」「有没有进 Android」；
⑧ 按 §0 判定表下结论；⑨ **无论如何都回滚**并等 `sys.boot_completed=1`。

`-s 5e367954` 出现在每一条 fastboot 上（本机偶尔会多出 `HF06872291105783`）。

手动等价路径：

```powershell
$fb='C:\platform-tools\platform-tools\fastboot.exe'
& $fb -s 5e367954 flash boot_a E:\rom\work\woa\ch-probe\out\boot_a-paint-proof.img
& $fb -s 5e367954 reboot
# 盯屏（重启后 1-10 s 内）：整屏纯红一闪？
```

**观察要点**：设备现在停在 v9 ctl 的 logo 上 → 先长按电源 15-20 s 强制关机，再「按住音量− → 按电源」进 bootloader。
红只会出现在「桩跑完 → 内核接管显示」这段窗口（预计 0.5-5 s；内核若继承 continuous splash 会停留更久）。
**建议一个人举着手机录像**，别只靠眼睛。

---

## 6. 回滚（任何结论之前先做）

```powershell
$fb='C:\platform-tools\platform-tools\fastboot.exe'
& $fb -s 5e367954 flash boot_a E:\rom\work\a17dump\boot_a.img
& $fb -s 5e367954 reboot
```
| 项 | 值 |
|---|---|
| 回滚包 | `E:\rom\work\a17dump\boot_a.img`（100,663,296 B） |
| sha256 | `2510b098380a573a40ee6600aa9124ced06a047c14c21e6bf7cd596fbbc3c14b` |
| 只动 boot_a | 不碰 vbmeta / 槽位 / 其它分区 |
| 最坏兜底 | 9008（`fh_loader` + `prog_firehose`）+ persist 已在手 |
| 脚本 | `run.ps1 -RestoreOnly` |

---

## 7. 前提与已知风险（诚实清单）

1. **依赖「ABL 从 `0x40000000` 进」**：静态反汇编（`0x862c blr x8`，`x8 = BootInfo+0x40`，中间无加法）+ 内核
   `code0/code1` 的写法 + EFI 入口的调用约定，三条独立证据指向它。若真不是，现象是「卡 logo」，**不会**伪装成
   「通道无效」——因为桩不执行时内核正文也进不去。
2. **关 MMU 依赖 UEFI 的 identity map**（VA=PA）。高通 UEFI 一向如此；桩执行完会把原 SCTLR 写回，
   交班状态与出厂镜像一致。若某台机器不是 identity map，现象同样是「卡 logo」（可回滚）。
3. 「**没红但开机**」严格说是「`0x5C000000` 这一段在交接后不可见」——可能因为 mixer 已停扫、已换缓冲、
   或面板 command-mode。**这三条都等于「卡 logo 不能当载荷没执行的证据」**，正是我们要证伪的东西。
4. 15 MiB 强序写（MMU 关时按 Device-nGnRnE 处理）会吃掉几十毫秒到几百毫秒，属于正常现象。
5. 本镜像 `kernel_size` 比出厂大 0x1000，`image_size` 未动；刷入后 boot 分区仍有 50 MiB 空余。

---

## 8. 如果结果落在「C/D」档，下一刀

| 现象 | 下一步 |
|---|---|
| 有红但不开机 | 先刷 `-Ctl`：能开机 ⇒ 问题在桩体。首选把「恢复 SCTLR」改成「保持 MMU/DC 关闭」（内核本来就接受 MMU off 入场），再不行把涂色量从 15 MiB 降到 64 KiB |
| 无红也不开机 | 刷 `-Ctl`：能开机 ⇒ 机制 OK、桩体有问题；也不能开机 ⇒ 怀疑追加页/`code1` 改写本身，退化为「只改 `kernel_size` 不动 `code1`」的纯机制测试 |
| 有红且开机 | 通道有效 ⇒ 直接重跑 v9 哨兵（它现在的结论才有意义），并把「ABL 没跳」写进档案 |
| 无红但开机 | 通道无效 ⇒ **先不要**再做任何「卡 logo = 没执行」的推理；改用 9008/UART 抓 ABL 日志，或改写 `0x5C000000` 以外的候选缓冲（DTBO 里的 `splash_region`/`memory-region`）重做本实验 |
