# v9 三色哨兵 · 构建报告（shim RED / shim GREEN / SEC BLUE）

> 2026-11-25 · 依据 `work\woa\sec-memory\REPORT.md` §3 第 1 条建议
> （「在把『哪一段死了』变成两三个像素之前，不要再改地址」）。
> 本文只加观测点，**不动任何地址**。镜像已编出、已离线逐字节校验；**未刷机**。

---

## 0. 一句话

BootShim 现在先关 MMU，然后往 ABL 仍在扫描的 `cont_splash_region`（`0x5C000000`）
打 **RED**；FD 拷贝完成、`br x5` 之前改成 **GREEN**；SEC 的第一条 C 语句再盖成 **BLUE**。
屏幕上最后剩下哪种颜色，就是这一段里谁死了。

| 屏幕主色带（`0x5C000000 + 0` 起 64 KiB） | 含义 |
|---|---|
| **红 RED** `0xFFFF0000` | shim 执行了，但 FD 拷贝/跳转没走完（或 FD 根本没被跳进去） |
| **绿 GREEN** `0xFF00FF00` | FD 已拷到 `0x5FC00000`、`br x5` 已发生 ⇒ 死在 SEC/DXE |
| **蓝 BLUE** `0xFF0000FF` | 进了 SEC 的 C 入口 ⇒ FD 与跳转都没问题，死在 DXE 初始化 |
| **全黑 / logo 不动** | shim 根本没执行 ⇒ ABL 侧（`0x8634` CpuDeadLoop 或更早） |

辅助色带（更靠下、更细，见 §3）。

---

## 1. 改了什么（file:line）

### 1.1 `BootShim/BootShim.S`（WSL `/root/woa/uefi-tb128fu/`）

| 行 | 内容 |
|---|---|
| 40–45 | 五个 `#define`：`SENTINEL_FB 0x5C000000`、`SENTINEL_FB_CYAN 0x5C020000`、`SENTINEL_PIXELS 0x4000`(64 KiB/4)、三色常量 |
| **47–48** | `_Start:` 第一条指令 `mov x17, x0` —— **保住 x0**（ABL 给的 DT 指针，SEC 后面会用 `gSecEntryArg0` 塞进 HOB） |
| **50–72** | 按 `CurrentEL` 关 MMU：EL1 走 `sctlr_el1`、EL2 走 `sctlr_el2`；`bic` 清 **M(bit0)=0、C(bit2)=0**，再 `isb`。**读改写，不是 `msr sctlr_elX, xzr`**（后者会把 RES1 位写成 0，架构上是 unpredictable）。同时在 `x11` 里留下「交班时 MMU 本来就是开的」这个事实 |
| **75–79** | **SENTINEL 1/3**：向 `0x5C000000` 写 64 KiB RED，`dsb sy` |
| 80–85 | 若 `x11 != 0`（交班时 MMU 是开的），在 `0x5C020000` 额外写 4 KiB **CYAN** |
| 87–93 | `#if SENTINEL_HALT` —— 只有控制图才编进去的 `b _Dead`（见 §8） |
| **109–114** | **SENTINEL 2/3**：`_Entry` 开头（FD 拷完、`br x5` 之前）把同一块 64 KiB 改写成 GREEN |
| 135 | `mov x0, x17` —— 跳转前把 DT 指针放回 x0 |
| 136 | `br x5`（原样，未改） |
| 142–153 | `_SntPaint`：`x13`=基址、`x14`=像素数、`w0`=颜色；`str w0,[x15],#4` 循环 + `dsb sy` + `ret`。只用 `x0/x13/x14/x15/x16/x30`，**不碰栈、不碰 x1/x5** |

`_Payload` 的位置随 shim 变大自动由 `adr x1, _Payload` 与 `_StackSize`（`FD_SIZE + (_Payload-_Head)`）重算：
shim 从 **0xC0 → 0x160** 字节，FD 在载荷里的偏移同步从 `0xC0` 变成 `0x160`（已校验，见 §4）。

### 1.2 `Silicon/Silicium/SiliciumPkg/Sec/Sec.c`

只改颜色/偏移，**调用次数不变（4 处），所以 SEC 模块尺寸仍是 `0xdfb8`，`_ModuleEntryPoint=0x5FC01158`、`SecEntry=0x5FC01E08` 都没变**。

| 行 | 改动 |
|---|---|
| 109 | `SEC_PAINT_FRAME_BUFFER_BASE 0x5C000000ULL`（沿用树里已有的定义） |
| **140** | `SecPaintEarly`：`0x00FF00FF`（magenta）→ **`0xFF0000FF`（BLUE）**，`+0x00000`、64 KiB |
| 141 | `0xFFFFFFFF` WHITE，`+0x10000`、4 KiB（未改） |
| **169** | `InitializeMemory`：原来「绿 4 KiB @ +0」→ **`0xFFFF8000`（ORANGE）@ `+0x12000`**（原来那条会把 64 KiB 主色带咬掉一块） |
| **229** | `SecMain` 内存初始化完成：「红 @ `+0x11000`」→ **`0xFFFFFF00`（YELLOW）@ `+0x11000`**（红留给 shim 专用） |
| 196 | `SecPaintEarly ();` 仍是 `SecMain` 的第一条语句 |

> 说明：这段 SEC 画屏代码是**上一轮就已经在工作树里**（未提交）的诊断代码；本轮只把配色改成与 shim 不撞色。

### 1.3 `BootShim/Makefile`

| 行 | 内容 |
|---|---|
| 5–8 | `SENTINEL_HALT ?= 0` + `CFLAGS += -DSENTINEL_HALT=$(SENTINEL_HALT)` |

默认 0 ⇒ **普通构建逐字节不变**（已验证：加这个变量前后 `BootShim.bin` 完全相同，`e50a22bb…`）。

### 1.4 备份（回滚用，都在原地）

```
BootShim/BootShim.S.bak-v9-20261125
BootShim/Makefile.bak-v9-20261125
Silicon/Silicium/SiliciumPkg/Sec/Sec.c.bak-v9-20261125
```

还原：

```bash
wsl -d ub -u root
cd /root/woa/uefi-tb128fu
cp -a BootShim/BootShim.S.bak-v9-20261125 BootShim/BootShim.S
cp -a BootShim/Makefile.bak-v9-20261125   BootShim/Makefile
cp -a Silicon/Silicium/SiliciumPkg/Sec/Sec.c.bak-v9-20261125 \
      Silicon/Silicium/SiliciumPkg/Sec/Sec.c
```
（**不要用 `git checkout`** —— 工作树里还有上一轮未提交的改动，会被一起丢掉。）

patch 全文：`work\woa\sentinel\v9-sentinel.patch`（相对 `.bak` 的 my-changes-only diff，3 个文件 204 行）。

---

## 2. 凭什么「往 0x5C000000 写」就能在屏上看见（三条独立证据）

| # | 证据 | 结论 |
|---|---|---|
| 1 | `img-xbl\cfg\FD_uefiplat.cfg:18`：`0x5C000000, 0x01000000, "Display Reserved", AddMem, MEM_RES, SYS_MEM_CAP, Reserv, WRITE_THROUGH_XN` | 这块 16 MB 是 UEFI 侧登记的显示保留区，起点就是 `0x5C000000` |
| 2 | 设备 DTBO（`work\dtwork\dtbo460\dtbo_01/03/04_*.dts`）：`splash_region@5c000000 { label = "cont_splash_region"; reg = <0x00 0x5c000000 0x00 0xf00000>; }` | **ABL 的 continuous splash 缓冲区就在这儿**，15 MB |
| 3 | 设备 dmesg（`work\device-profile\hw\dmesg.txt:92` cmdline、`:1561` 绑定日志）：`msm_drm.dsi_display0=qcom,mdss_dsi_panel_p255_hx83102j_fhd_video` → `Successfully bind display panel '...p255_hx83102j_fhd_video'` | **面板是 DSI video 模式** ⇒ MDP 一直按帧从 DDR 重读这块内存。**这条是决定性的**：如果是 command 模式面板（内部 GRAM），改 DDR 根本不会变，整个哨兵实验就是瞎的 |

所以写这块 DDR = 直接改正在扫描的那一帧，不需要任何 DSI 命令、不需要 GOP、不需要驱动。

**颜色带 alpha 用 `0xFF` 而不是题目里的 `0x00`**：色相完全一样（`0xFFRRGGBB` vs `0x00RRGGBB`），
但如果 MDP 主平面还留着 per-pixel alpha 混合，`A=0` 的像素会被混成背景色 —— 那样就白干了。
这条是可以回退的：若真机上出现的是**怪色而不是纯红**，只改 `BootShim.S:42-44` 的低 24 位即可。

---

## 3. 判定表

### 3.1 主色带（`0x5C000000 + 0x00000`，64 KiB，≈屏顶 8 行 @1920×1200×32）

| 看到 | 谁走完了 | 下一刀往哪切 |
|---|---|---|
| **RED** | shim `_Start` 跑了；没走到 `br x5` | ABL→shim 交班（MMU/缓存/`kernel_size`），或 3 MB 拷贝本身 |
| **GREEN** | FD 拷到 `0x5FC00000` 且 `br x5` 执行过 | SEC/DXE：`SecEntry` 的栈写、cache 维护、`ArmMmuBaseLibConstructor` |
| **BLUE** | SEC 的 C 入口跑起来了（`SecMain` 第一条语句） | `PlatformInitialize` / `MemoryPeim` / DXE core 装载 |
| **黑 / logo 不变** | shim 没执行 | ABL 侧（`0x8634` CpuDeadLoop，或更早的 `Not the single appended DTB` 之类） |
| **CYAN 也在**（仅辅助带） | 与主色带无关的附加事实：**ABL 交班时 MMU 是开的** | 这是 sec-memory §3 第 2 条的动态答案，值得记进档案 |

### 3.2 辅助色带（全部由 SEC 画，`+offset` 从 `0x5C000000` 算）

| offset | 大小 | 颜色 | 含义 | 代码 |
|---|---|---|---|---|
| `+0x10000` | 4 KiB | WHITE `0xFFFFFFFF` | `SecPaintEarly` 两条带都画完了（比 BLUE 只多一点） | `Sec.c:141` |
| `+0x11000` | 4 KiB | YELLOW `0xFFFFFF00` | `InitializeMemory` 走完 ⇒ HOB + `MemoryPeim` 都过了 | `Sec.c:229` |
| `+0x12000` | 4 KiB | ORANGE `0xFFFF8000` | 找到了 `"DXE Heap"` 内存区（在 `MemoryPeim` 之前） | `Sec.c:169` |
| `+0x20000` | 4 KiB | CYAN `0xFF00FFFF` | shim 画的：交班时 MMU 是开的 | `BootShim.S:80-85` |

**读法**：主色带是状态机（红→绿→蓝只会剩一个，因为后写覆盖前写）；辅助带是「又往前走了多远」。
典型组合：

- 主带 GREEN + 有 CYAN + 无 WHITE ⇒ FD 跳了，SEC 连第一条语句都没到（`SecEntry` 的 cache/栈/VBAR 段）。
- 主带 BLUE + WHITE + 无 ORANGE ⇒ SEC 进了 C，死在 `PlatformInitialize` 或 `LocateMemoryRegionByName` 之前。
- 主带 BLUE + ORANGE + 无 YELLOW ⇒ 死在 `HobConstructor`/`MemoryPeim`。
- 主带 BLUE + YELLOW ⇒ SEC 全过了，死在 DXE core / DXE 驱动。

---

## 4. 产物与校验

### 4.1 主产物

`E:\rom\work\woa\out\Mu-tb331fc-v9-sentinel.img`

| 项 | 值 |
|---|---|
| 大小 | **1,239,040 B** |
| sha256 | **`6d3c5096e936d6747b337f4c22fb52b2a342840ca65c243fdf3e00144fed264d`** |
| boot header | `ANDROID!` / **v1** / page 2048 |
| `kernel_size` | 1,234,193 字节 = gzip 流 955,046 + 尾接 DTB 279,147 ✅ |
| 载荷解压后 | 3,146,080 B = `0x300160` = FD `0x300000` + shim `0x160` |
| **shim text_offset** | **`0x5FC00000`** |
| shim 的 `image_size` 字段 | `0x300160` |
| shim 本体 | 352 B，sha256 `e50a22bb5da789f8…`，与 `BootShim/BootShim.bin` **逐字节相同**（`shim_identical True`） |
| FV 头 | `_FVH` @ 载荷 `0x188`，`FvLength=0x300000` |
| **DTB 单棵校验** | `totalsize = 279,147` 与 `kernel_size` 尾部长度相等；**DTB 之后 4 字节 = `00 00 00 00`** ⇒ ABL 的 `fdt_check_header(p2)` 失败 ⇒ 过 `Not the single appended DTB` 检查 ✅ |
| gzip | 单 member，`ISIZE` 与实际解压长度一致 ✅ |

### 4.2 控制图（可选，见 §8）

`E:\rom\work\woa\out\Mu-tb331fc-v9-sentinel-ctl.img` · 1,239,040 B · sha256
**`58eabccc6a7a3a678137297733c298838bf5c2fa0c361c9f56c0589f7e4be408`**
（shim 352 B，sha256 `494acb88…`，多一条 `b _Dead` 在 RED 画完之后）

### 4.3 SEC 配色确实编进去了

对最终 FD `Build/tb331fcPkg/RELEASE_CLANGPDB/FV/SILICIUM_UEFI.fd` 取画屏调用点的指令字（`fdwords.py`）：

| FD 偏移 | 指令字 | 反汇编 | 对应色带 |
|---|---|---|---|
| `0x1e60` | `0x32083FE0` | `mov w0, #0xFF0000FF` | **BLUE** @ `+0x00000` ✅ |
| `0x1e70` | `0x12800000` | `mov w0, #0xFFFFFFFF` | WHITE @ `+0x10000` ✅ |
| `0x26e4` | `0x12801FE0` | `mov w0, #0xFFFFFF00` | YELLOW @ `+0x11000` ✅ |
| `0x20e8` | `0x128FFFE0` | `mov w0, #0xFFFF8000` | ORANGE @ `+0x12000` ✅ |

这四个偏移与 `Sec.dll` 反汇编里同名调用点**逐个对上**，说明 FD 里的 SEC 就是本次源码编出来的，
不是缓存里的旧模块。

---

## 5. 上机步骤（lead 执行；本子代理**没有刷机**）

**最快路径**：`run_sentinel.ps1` 全包（闸门 → 刷 → 重启 → 问颜色 → 无论结果自动回滚）。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:\rom\work\woa\sentinel\run_sentinel.ps1
```

手动路径（等价，注意每一条都带 `-s 5e367954`）：

```powershell
$fb='C:\platform-tools\platform-tools\fastboot.exe'
$adb='C:\platform-tools\platform-tools\adb.exe'

# 0) 闸门：回滚包必须是这一份
(Get-FileHash E:\rom\work\a17dump\boot_a.img -Algorithm SHA256).Hash.ToLower()
#   期望 2510b098380a573a40ee6600aa9124ced06a047c14c21e6bf7cd596fbbc3c14b

# 1) 进 bootloader
& $adb -s 5e367954 reboot bootloader

# 2) 必须刷 a 槽（我们写的是 boot_a）
& $fb -s 5e367954 getvar current-slot          # 期望 current-slot: a
& $fb -s 5e367954 devices                      # 只认 5e367954，别碰 HF06872291105783

# 3) 刷
& $fb -s 5e367954 flash boot_a E:\rom\work\woa\out\Mu-tb331fc-v9-sentinel.img
& $fb -s 5e367954 reboot

# 4) 看屏（5–20 s）：主色带是红/绿/蓝/没有？CYAN 小带有没有？
```

**看完立刻做**（设备多半是挂死的，需要手动回 bootloader）：
长按电源 15–20 s 强关 → **按住音量− 再按电源** 进 bootloader → 然后按 §6 回滚。

---

## 6. 回滚（务必先做这个，再做任何分析）

```powershell
$fb='C:\platform-tools\platform-tools\fastboot.exe'
& $fb -s 5e367954 flash boot_a E:\rom\work\a17dump\boot_a.img
& $fb -s 5e367954 reboot
```

| 项 | 值 |
|---|---|
| 回滚镜像 | `E:\rom\work\a17dump\boot_a.img`（100,663,296 B） |
| sha256 | **`2510b098380a573a40ee6600aa9124ced06a047c14c21e6bf7cd596fbbc3c14b`**（与现网逐字节核对过） |
| 脚本回滚 | `run_sentinel.ps1 -RestoreOnly` |
| 只刷了 boot_a | `vbmeta_a` / `init_boot` / `super` 一个字节都没动，理论上无需一起回滚 |
| 最坏兜底 | 9008 + `fh_loader`（`prog_firehose_sm6225_ddr.elf` 已验证） |

---

## 7. 这一版同时引入的「新变量」（诚实标注）

1. **shim 现在会主动关 MMU**（题目要求「按 CurrentEL 关 MMU」）。
   如果 ABL 交班时 MMU 是开的、并且 `HCR_EL2.VM=1`（stage-2 生效），那么在 EL1 上清 `SCTLR_EL1.M`
   **并不能**取消 stage-2 翻译 —— 这种情况 CYAN 会亮，主色带的行为可能不如预期。
   反过来说：**如果 v9 的行为突然和 v8 不一样（不是颜色的差别），第一嫌疑人就是这条**。
   它同时也是 sec-memory §3 第 2 条的候选根因，所以这里是「实验」而不是「已知安全」。
2. **x0 被保住了**：旧 shim 不碰 x0，新 shim 用 `x17` 存/取，`br x5` 前放回。SEC 依赖它往 HOB 里塞 DT 指针。
3. **alpha = 0xFF**（见 §2 末）。若出现怪色，改 `BootShim.S:42-44`。
4. **shim 变长 0xA0**（0xC0 → 0x160）。`_Payload`、`_StackSize`、安卓头 `kernel_size` 全部自洽并已校验；
   但若以后有人手改 shim 头部偏移，先跑 `verify_v9.py`。
5. **FVMAIN 没动**（仍然只差 2,112 B 满）：没有新增模块，SEC 在自己的 FFS 里，尺寸 `0xdfb8` 不变。

---

## 8. 控制图 `-ctl` 什么时候用

只有一种情形：**v9 刷上去屏幕什么都没变**。这时「shim 没执行」和「这块 framebuffer 根本没被扫描」
在现象上完全一样，而两者结论相反（前者判 ABL，后者说明观测手段失效）。

`Mu-tb331fc-v9-sentinel-ctl.img` 画完 RED 就 `b _Dead`，**不碰 FD**：

| ctl 图的结果 | 结论 |
|---|---|
| 出现 RED | framebuffer 通道有效 ⇒ v9 若全黑，就是「shim 真没执行」，判 ABL 侧，别改 UEFI 了 |
| 也没有任何颜色 | **观测通道失效**（面板不是在扫这块内存 / 混合方式不同）⇒ v9 的「全黑」什么都不能证明，须换观测手段 |

刷它同样只用 `-s 5e367954 flash boot_a`，回滚一样。

---

## 9. 「全黑」到底意味着什么（写进结论前请先过这一关）

1. **全黑** = shim 的 RED 没出现。可能原因按概率排：
   - ABL 没跳（`0x8634` CpuDeadLoop / `0xa520` 返回非 0 / `kernel_size` 不符）；
   - ABL 跳了但 shim 第一条指令就 abort（VBAR 未设 ⇒ 静默死循环，症状完全相同）；
   - 观测通道失效（用 §8 的 ctl 图排除）。
2. 因此**「全黑」单独一条不能判 ABL**——必须配 ctl 图。这正是 sec-memory 说的「现在最大的信息缺口」。
3. 若出现 RED：ABL 交班是好的，别再查 ABL 了，直接查 3 MB 拷贝与 `br x5` 后的 SEC 入口状态。
4. 若出现 GREEN：shim 无罪。SEC 的第一条 C 语句之前就死了 ⇒ 重点 `SecEntry`（`Sec.c` 的
   `SecCleanInvalidateDataCacheAll` / `ArmDisableDataCache` / 栈写 / `ArmWriteVBar`）与
   `ArmMmuBaseLibConstructor`。

---

## 10. 复核命令（全部只读）

```powershell
# 镜像结构 + text_offset + 单棵 DTB + shim 逐字节
wsl -d ub -u root -- bash -lc "python3 /mnt/e/rom/work/woa/sentinel/verify_v9.py /mnt/e/rom/work/woa/out/Mu-tb331fc-v9-sentinel.img /mnt/e/rom/work/woa/sentinel/BootShim.v9-normal.bin"

# FD 里的 SEC 入口（_ModuleEntryPoint / SecEntry 字面量）
wsl -d ub -u root -- bash -lc "python3 /mnt/e/rom/work/woa/sec-memory/fdcheck.py /root/woa/uefi-tb128fu/Build/tb331fcPkg/RELEASE_CLANGPDB/FV/SILICIUM_UEFI.fd"

# 三色常量是否在 FD 里
wsl -d ub -u root -- bash -lc "python3 /mnt/e/rom/work/woa/sentinel/fdscan.py /root/woa/uefi-tb128fu/Build/tb331fcPkg/RELEASE_CLANGPDB/FV/SILICIUM_UEFI.fd"

# 重新编译（约 75 s）
wsl -d ub -u root -- bash -lc "cd /root/woa/uefi-tb128fu && export CLANGPDB_AARCH64_PREFIX=aarch64-linux-gnu- && python3 build_uefi.py -d tb331fc -r RELEASE"
```

---

## 11. 本次新增/改动的文件清单

| 路径 | 作用 |
|---|---|
| `out\Mu-tb331fc-v9-sentinel.img` | **主产物**（§4.1） |
| `out\Mu-tb331fc-v9-sentinel-ctl.img` | 控制图（§8） |
| `sentinel\REPORT.md` | 本文 |
| `sentinel\run_sentinel.ps1` | 闸门→刷→看色→自动回滚（纯 ASCII，PS 5.1 已验证 0 语法错误） |
| `sentinel\v9-sentinel.patch` | 我的改动（相对 `.bak`，3 文件） |
| `sentinel\BootShim.S` | 改后的 shim 源（便于对照，权威版本在 WSL 构建树里） |
| `sentinel\BootShim.v9-normal.bin` / `BootShim.v9-ctl.bin` | 两个 shim 产物（校验基准） |
| `sentinel\verify_v9.py` / `fdsec.py` / `fdscan.py` / `fdwords.py` / `make_patch.sh` | 只读校验脚本 |
| `sentinel\verify_v9.txt` / `verify_v9_ctl.txt` | 两张图的校验输出快照 |
| `sentinel\run_sentinel_*.log` | 脚本自检日志（闸门自测：错哈希 → exit 2，未碰设备） |
