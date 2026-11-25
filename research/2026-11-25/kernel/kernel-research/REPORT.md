# TB331FC（khaje / SM6225-AD / 骁龙 685）编译真 mainline Linux 内核 —— 调研报告

> 生成日期：2026-11-25 · 环境：WSL `ub`（Ubuntu 24.04，8 核 / 7 GB RAM / 937 GB 可用）
> 本报告只做**只读调研 + 实测编译计时**，未刷机、未动 A 槽、未 clone 大仓库。
> 所有"上游有没有"的判断都来自 GitHub API 对 `torvalds/linux` 的具体 tag 逐文件查询，不是记忆。

---

## 0. 一页结论（先看这个）

**1）"真 6.0" 是这台机器上最差的选项，不是最好的。**
`v6.0` 里 **根本没有 bengal/SM6115/SM6225 的任何支持**：`arch/arm64/boot/dts/qcom/sm6115.dtsi` = 404、
`drivers/clk/qcom/dispcc-sm6115.c` = 404、`gpucc-sm6115.c` = 404。SM6115 系（bengal，SM6225 是它的衍生）
**第一次进 mainline 是 v6.2**。选 6.0 = 把 2023–2025 三年的 qcom 平台工作自己重做一遍。

**2）mainline 从来没有 `sm6225.dtsi`。** 我查了 v6.0 / v6.1 / v6.6 / v6.12 / v6.14 / master 六个点，
全部 404。上游只有 `sm6115.dtsi`（bengal）。我们手上那份 `sm6225.dtsi`（81,522 B / 3468 行，
头部版权 `2025, Ivaylo Ivanov`）是**社区 out-of-tree 文件**，跟着 TB128FU 的 postmarketOS 移植进来的。
⇒ 任何 vanilla 路线都必须自己把 SM6225 这一层搬进去，这跟选 6.0 还是 6.14 无关。

**3）推荐：继续用现有这棵 6.14 树**（它是 `linux-next-20250306` 快照 + 0.60 MB sm6225/板级补丁，
本身**就是 mainline**，不是 CAF 内核）。要 LTS 承诺就退到 **6.12 LTS**，代价是 ADSP 音频节点要从 6.14 抄回去。
6.6 LTS 缺 interconnect（6.12 才有）与 q6asm（6.14 才有），6.1/6.0 直接排除。

**4）上游缺口在驱动级，不在 DTS 级**：缺 3 个时钟控制器（gcc/dispcc/gpucc-sm6225，共 118 KB）、
pinctrl-sm6225、`qcom,sm6225-qmp-ufs-phy` 的 PHY 表、`qcom,sm6225-mdss` 的 mdss 数据。但**移植量是机械的**：
`gcc-sm6225.c` 3468 行里有 **3009 行与上游 `gcc-sm6115.c` 逐字节相同**；`pinctrl-sm6225.c` 与 pinctrl-sm6115 只差 108 行。

**5）从零编译实测**（8 核 / 7 GB，`tb331fc_defconfig`，丢弃副本里全新跑）：
`make -j8 Image` **16 m 06 s**（Image 38,564,352 B）+ `make -j8 modules` **6 m 37 s**（675 个 .ko）
+ `dtbs` 约 20 s ⇒ **全量约 23 分钟，磁盘 3.2 GB**。单编一次内核是"喝杯茶"的量级。

**6）一个必须先修的坑：这棵树有 4 处 zip 解压损坏**（符号链接被压成 0 字节普通文件）。
其中两处本次新发现：`scripts/dtc/include-prefixes/` 12 个条目 + `include/dt-bindings/input/linux-event-codes.h`，
不修则 `make dtbs` **必失败**；只编 tb331fc 的 dtb 时又刚好绕过去了（那个 dts 是反编译产物、没有 `#include`）。
修完实测 `make dtbs` **零错误**，三块 DTB 全部产出——**这棵树的真源码 DTS 链路是通的**。

---

## 1. 事实底座：我们手上这棵树到底是什么

| 项 | 值 | 证据 |
|---|---|---|
| 路径 | `/root/linux-tb331fc`（WSL ext4） | — |
| 体积 / 文件数 | 1.9 GB / 91,596 文件（其中源码约 1.60 GB，`.o` 只有 30 个 → 之前是**树内编译**） | `du -sh`、`find -type f` |
| 版本 | `6.14.0-rc5`，`NAME = Baby Opossum Posse` | `Makefile` 前 6 行 |
| **真实基线** | `linux-next-20250306` 快照（作者原文：源码包 `linux-next-tb128fu-hx83102-panel-port.zip`，291.7 MB / 94,393 文件） | `WORKING-BOOT-RECIPE.md` 第四轮 A 节 |
| 它不是 git 仓库 | `git rev-parse` → `not a git repository` | 无 `.git`，无法 `git log/diff/bisect` |
| 上游血统 | **是 mainline 的真 fork**，不是 CAF/vendor 内核；`arch/arm64/boot/dts/qcom/sm6115.dtsi` 与上游 v6.14 **逐字节相同**（`diff -q` 无差异） | 见 §3.1 |
| 非上游代码量 | **0.60 MB**（19 个文件，见 §3.2）；另有 `drivers/input/touchscreen/himax_v3_mmi/` 0.55 MB（TB128 用的 Himax 方案，TB331FC 不需要） | `du -cb` |
| 自带 defconfig | `arch/arm64/configs/tb331fc_defconfig`（8,336 行，自动生成的完整 .config） | — |
| 已修的 2 处缺陷 | ①`arch/arm64/tools/syscall_64.tbl` 符号链接被压成空文件（应 `→ ../../../scripts/syscall.tbl`）；②`drivers/bluetooth/hci_qca.c` 函数先用后声明 | 上一轮记录 |
| **本次新发现的 2 处（合计 4 处）** | ③`scripts/dtc/include-prefixes/` 下 **12 个条目全是 0 字节普通文件**（应为符号链接）→ `make dtbs` 对任何真源码 DTS 报 `fatal error: dt-bindings/usb/pd.h: No such file`；④`include/dt-bindings/input/linux-event-codes.h` 也是 **0 字节**（上游是 `→ ../../uapi/linux/input-event-codes.h` 的符号链接）→ `pm6125.dtsi:56 syntax error`（`KEY_POWER` 没展开） | 见 §5.3 |

### 1.1 两棵 LzwPluto 仓库的关系（问题 3 的答案）

| | `linux-lenovo-tb331fc` | `lenovo-tb331fc-mainline` |
|---|---|---|
| 内容 | **内核源码树**（267 MB） | **文档 + 工具 + 资产**（27.5 MB，"推送仓库二（工程与资产）"） |
| 创建 / 最后 push | 2026-10-29 14:49 / 10-29 15:00 | 2026-10-29 14:55 / 10-29 15:09 |
| 最后一条提交 | `28b4d6dc36` 2026-10-29 14:36 `arm64: tb331fc: Add devicetree, defconfig, Bluetooth suspend fix, and documentation` | `b89883b575` 2026-10-29 14:42 `docs, tools & assets: …` |
| 分支 | 只有 `main` | 只有 `main` |
| 关键资产 | `sm6225.dtsi`、`sm6225-lenovo-tb331fc.dts`、`tb331fc_defconfig` | `WORKING-BOOT-RECIPE.md`(116 KB / 2802 行)、`HANDOVER.md`、`build/CANONICAL*.dts`(50 份变体)、`tools/`(约 450 个 py/sh) |

**结论：两个仓库是同一个人在 10-29 那半小时里同时推的"源码 + 工程资料"两半，不存在"哪个更新"。**
- 要内核源码 → `linux-lenovo-tb331fc`（我们用的这个）。
- 要"为什么这么做"、要 26 轮调试记录、要现成脚本 → `lenovo-tb331fc-mainline`。**这份 116 KB 的配方是目前最有价值的资料**。

### 1.2 `CANONICAL.dts` 与我们手上的 dts 差异（问题 3 后半）

三份文件实测：

| 文件 | 字节 | 行 | 性质 |
|---|---|---|---|
| `lenovo-tb331fc-mainline/build/CANONICAL.dts` | 89,888 | 4,185 | 2026-10-27 12:45 的**权威基线快照** |
| `linux-lenovo-tb331fc:…/sm6225-lenovo-tb331fc.dts`（仓库 HEAD） | 96,423 | 4,287 | 2026-10-29，**最新** |
| 我们本地那份（改过的） | 92,036 | 4,287 | = 仓库 HEAD + 5 处改动（见下） |

> 注：仓库里那份 dts 是 **`dtc -I dtb -O dts` 反编译产物**（有数字 phandle `<0x28>`、`/dts-v1/;` 开头、
> `chosen.bootargs` 里还有 `PMOS_NOSPLASH`），不是手写源码；且是 **CRLF** 行尾。
> 所以拿它当"源码"是能编译的（无 `#include`），但没法跟上游 sm6115 板级 dts 对照阅读。

**我们本地 5 处改动 vs 仓库 HEAD**（`diff --strip-trailing-cr` 只有 6 个 hunk、58 行）：

| # | 位置 | 仓库 HEAD（正确） | 我们改成的 | 判断 |
|---|---|---|---|---|
| 1 | 第 4 行 | `model = "Lenovo Tab M10 Plus 3rd gen"` | `"Lenovo Xiaoxin Pad 2024 (TB331FC)"` | 无害，建议保留 |
| 2 | 第 5 行 | `compatible = "lenovo,tb128\0qcom,sm6225\0qcom,sm6115"` | `lenovo,tb331fc\0…` | 无害，建议保留 |
| 3 | 第 1996 行 蓝牙 | **`compatible = "qcom,wcn3990-bt"`**（还带注释："**Do NOT use wcn3988-bt here: that path asks for apbtfw21.tlv/apnv21.bin and uses a different rom_ver shift**"） | `"qcom,wcn3988-bt"` | ❌ **改错了，必须改回** |
| 4 | zap-shader | `firmware-name = "qcom/sm6225/LENOVO/TB128FU/a610_zap.mdt"` | `"a610_zap.mdt"` | 取决于你把固件放哪，见 §7 |
| 5 | mpss/adsp/cdsp | `qcom/sm6225/LENOVO/TB128FU/{modem,adsp,cdsp}.mbn` | 去掉前缀 | 同上 |

**第 3 条是本次调研最直接的收获**：作者在源码注释里就把结论写好了，我们上一轮"依据 `apbtfw11.tlv` 推断成
wcn3988"恰好是他在注释里明确否掉的那条路。设备实测 `bluetooth.soc=cherokee` + BTFM 分区里是
`crbtfw21.tlv`/`crnv21.bin`（配方第 20 轮 B 节用 loop 挂载 `BTFM.bin` 提取，FAT16）——都指向 WCN3990 命名。

**`CANONICAL.dts`（10-27）→ 仓库 HEAD（10-29）的净变化**（12 hunk / 280 行）：
+ `kinetic,ktz8866` 背光（`backlight@11`）、+ 4× `awinic,aw88166` 智能功放、+ `qcom,fsa4480-i2c` Type-C 开关、
+ hall 传感器 pinctrl、+ 蓝牙 UART 改成 4 线（cts/rts/tx/rx 分组）、− 幽灵 `silergy,sy6974` 充电器、
− `ti,bq27541` 电量计（换成 `mitsumi,mm8013`）。
⇒ **要用就用仓库 HEAD 那份**，`CANONICAL.dts` 是旧基线。

---

## 2. 版本选择（问题 1）

### 2.1 硬证据：每个 tag 里到底有什么

对 `torvalds/linux` 逐文件查（contents API，404 = 不存在）：

| 文件 | v6.0 | v6.1 | v6.2 | v6.3 | v6.6 | v6.12 | v6.14 | master |
|---|---|---|---|---|---|---|---|---|
| `dts/qcom/sm6115.dtsi` | ❌404 | ❌404 | ✅35,075 | ✅55,686 | ✅69,430 | ✅79,786 | ✅81,920 | ✅83,985 |
| `dts/qcom/sm6225.dtsi` | ❌404 | ❌404 | ❌404 | ❌404 | ❌404 | ❌404 | ❌404 | ❌404 |
| `dts/qcom/sm6115p-lenovo-j606f.dts` | ❌ | ❌ | ❌ | ✅ | ✅7,770 | ✅7,801 | ✅7,801 | ✅7,796 |
| `clk/qcom/dispcc-sm6115.c` | ❌404 | — | — | — | ✅ | ✅ | ✅ | ✅ |
| `clk/qcom/gpucc-sm6115.c` | ❌404 | — | — | — | ✅ | ✅ | ✅ | ✅ |

`sm6115.dtsi` 内部节点计数（上游原文，`grep -c`）：

| 内容 | v6.6 | v6.12 | v6.14 | 说明 |
|---|---|---|---|---|
| `interconnect@` 节点 | **0** | 3 | 3 | 6.12 才补上 icc（CPU/DDR 频率与总线带宽） |
| `q6asm` / `q6adm`（ADSP 音频服务） | **0** | **0** | **8** | **6.14 才有** |
| `ufs_mem_hc` / `qmp-ufs-phy` | ✅ | ✅ | ✅ | 6.6 起就有 |
| `qcom,sm6115-mdss` / `-dpu` / `-dsi-ctrl` | ✅ | ✅ | ✅ | 6.6 起就有 |
| `qcom,adreno-610.0` + gmu-wrapper + adreno-smmu | ✅ | ✅ | ✅ | 6.6 起就有 |
| `qcom,wcn3990-wifi` | ✅ | ✅ | ✅ | 6.6 起就有 |
| `qcom,sm6115-sdhci`（SD 卡） | ✅ | ✅ | ✅ | 6.6 起就有 |
| `camss`（摄像头） | **0** | **0** | **0** | **至今没有**（bengal 的 camss 从没上游化） |

### 2.2 建议表

| 版本 | 性质 | 对 SM6225/bengal 的实际支持 | 要补多少 | 推荐 |
|---|---|---|---|---|
| **v6.0**（2022-10） | EOL | **零**。无 sm6115 dtsi、无 dispcc/gpucc-sm6115、无 pinctrl-sm6115 | 等于把 6.2→6.14 的 qcom bengal 工作全做一遍（≥ 数月） | ❌ **不要** |
| **v6.1 LTS**（2022-12） | LTS(EOL 2026-12?) | 同上，**仍零**（sm6115.dtsi 6.2 才进） | 同上 | ❌ 不要 |
| **v6.6 LTS**（2023-10） | LTS | SoC 骨架齐（UFS/DSI/DPU/GPU/USB/WiFi/SD），**缺 icc 与 ADSP 音频节点** | + sm6225 层 + 手补 3 个 interconnect 节点 + 音频节点 | ⚠️ 只适合"不要音频/不要省电" |
| **v6.12 LTS**（2024-11） | LTS | 骨架 + icc，**无 q6asm** | + sm6225 层 + 从 6.14 抄 q6asm/q6adm 节点 + machine driver | ✅ 想要 LTS 就选它 |
| **v6.14**（2025-03） | stable（非 LTS） | 骨架上最全（含 q6asm）。**我们这棵树就是这个基线** | + sm6225 层（**已经搬好了**） | ✅✅ **推荐** |
| master（6.1x） | 滚动 | 更全，但无稳定承诺、DT 绑定会漂 | 同 6.14 | ⚠️ 追新可以，别用来出一版要刷的镜像 |

**为什么推荐 6.14 而不是 6.12（都是"能跑"的）**：
1. `q6asm`/`q6adm` 节点只在 6.14 的 sm6115.dtsi 里出现——音频链路的 DT 骨架 6.14 才齐；6.12 得自己补。
2. 我们已有的产物（Image 38.9 MB、dtb、boot-v3）就是 6.14 编译出来的，**换版本 = 重新踩一遍所有坑**。
3. 6.14 由 6.12 演进而来，`sm6115.dtsi` 从 79,786 → 81,920 B 的增量都是加法，没有破坏性改动。

**"真 6.0" 这句话怎么理解**：如果用户要的是**字面 v6.0**，答案是"这不可能且没有意义"（见上表第 1 行）；
如果指的是"真真正正的上游 mainline 6.x，而不是高通/联想的 vendor 内核"——**我们手上这棵已经是了**，
它就是 torvalds 树的 fork，只多了 0.60 MB 的 SM6225 与板级补丁。这条要跟用户讲清楚。

---

## 3. 上游支持到什么程度（问题 2）

### 3.1 先说清楚：上游的 `sm6115.dtsi` 与我们树里的 `sm6115.dtsi` 是同一个文件

```
$ diff -q ref/sm6115-v6.14.dtsi /root/linux-tb331fc/arch/arm64/boot/dts/qcom/sm6115.dtsi
（无输出 = 完全相同）
```
⇒ LzwPluto **没有改** sm6115.dtsi，而是**并列新增**了 `sm6225.dtsi`。
两者差异：`diff` 161 行新增 / 146 行删除（共 607 行 diff），即 sm6225.dtsi 是 sm6115.dtsi 的**改写副本**，
主要换掉时钟/互连/pinctrl 的 compatible。

### 3.2 非上游文件清单（vanilla 路线要搬的全部东西）

| 文件 | 字节 | 作用 | 上游有对应物? |
|---|---|---|---|
| `arch/arm64/boot/dts/qcom/sm6225.dtsi` | 81,522 | SoC 设备树 | ❌ 无（sm6115.dtsi 是近亲） |
| `arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dts` | 96,423 | 板级（反编译产物） | ❌ |
| `arch/arm64/configs/tb331fc_defconfig` | 8,336 行 | 完整 .config | ❌ |
| `drivers/clk/qcom/gcc-sm6225.c` | 90,215 | 全局时钟控制器 | ❌（sm6115 有，3468 行中 3009 行相同） |
| `drivers/clk/qcom/dispcc-sm6225.c` | 15,371 | 显示时钟 | ❌（vs dispcc-sm6115 差 378 行） |
| `drivers/clk/qcom/gpucc-sm6225.c` | 12,175 | GPU 时钟 | ❌（vs gpucc-sm6115 差 259 行） |
| `drivers/pinctrl/qcom/pinctrl-sm6225.c` | 31,364 | TLMM | ❌（vs pinctrl-sm6115 **只差 108 行**） |
| `drivers/interconnect/qcom/sm6225.c`(+`.h`) | 43,751 | NoC | ❌（当前 config **未开**，可选） |
| `include/dt-bindings/clock/qcom,gcc-sm6225.h` 等 4 个 | 11,528 | 时钟/互连常量 | ❌ |
| `drivers/gpu/drm/panel/panel-himax-hx83102.c` | 67,519 | 面板 | ✅上游有（29,695 B），但**多 37.8 KB**：`lenovo,p255-inx` 条目 + DSC |
| `drivers/gpu/drm/panel/p255_inx_init.h` | 17,495 | 面板初始化序列（244 行） | ❌ |
| `drivers/gpu/drm/panel/panel-novatek-nt36523.c` | 58,240 | TDDI 面板 | ✅上游有（52,461 B）+ 加了 `lenovo,tb128fu-boe-nt36523w` 等条目 |
| `sound/soc/codecs/aw88166.c` + `.h` | 52,728+ | AW88166 智能功放 | ❌ **上游完全没有** |
| `drivers/input/touchscreen/nt36523_ts.c` + `_fw_update.c` + `.h` + `_mem_map.h` | 58,686+23,830+7,259+17,595 | Novatek 触摸 | ❌（上游的 `novatek-nvt-ts.c` 是另一套，不带 Flash 的 I2C 版） |
| `drivers/input/touchscreen/himax_v3_mmi/` | 550,221 | TB128 的 Himax 触摸（**本机不用**） | ❌ |
| **合计（不含 himax_v3_mmi）** | **≈ 0.60 MB** | | |

**被小改的上游驱动**（用 `grep -c sm6225` 定位，含行号）：

| 文件 | 命中 | 内容 |
|---|---|---|
| `drivers/phy/qualcomm/phy-qcom-qmp-ufs.c` | 22 | 新增 `sm6225_ufsphy_cfg`（:1250）+ `compatible = "qcom,sm6225-qmp-ufs-phy"`（:2072） |
| `drivers/gpu/drm/msm/msm_mdss.c` | 5 | 新增 `sm6225_data`（:684，注释：**UBWC 故意关闭**）+ `"qcom,sm6225-mdss"`（:761） |
| `drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c` | 4 | `"qcom,sm6225-mdss"`（:368）、`"qcom,sm6225-smmu-v2"`（:694） |
| `drivers/gpu/drm/msm/dsi/dsi_host.c` | 2 | p255_inx 的 `slice_per_pkt = 2` 硬编码（:852, :863）——配方第 8/9 轮的关键修复 |
| `drivers/bluetooth/hci_qca.c` | 0 | 上游修 suspend 那段（`patch_qca_suspend.py`） |
| `drivers/power/supply/Makefile` | — | `obj-$(CONFIG_FUEL_GAUGE_MM8013) += mm8013.o`，**但 Kconfig 里没有这个符号** → 该驱动在本树里其实是**不可配置的死代码** |

### 3.3 节点级缺口（`sm6225.dtsi` 视角）

`sm6225.dtsi` 里 **70 处 `status = "disabled"`**（上游 `sm6115.dtsi` 也是 70 处，板级 dts 里 52 处 disabled / 32 处 okay），
这是上游正常写法（SoC 层默认关、板级开）。真正需要"板级 DTS 覆盖"的节点（行号为 sm6225.dtsi）：

| 子系统 | 节点 / 行号 | 上游状态 | 板级要做什么 |
|---|---|---|---|
| UFS（系统盘） | `ufs_mem_hc`:1254、`ufs_mem_phy`:1275（`qcom,sm6225-qmp-ufs-phy`） | 驱动在，**PHY 表是本树新增** | 接 vcc/vccq2/vdda 三路电 + `status=okay` |
| 显示 | `mdss`:1876、`mdss_dsi0`:1987、`mdss_dsi0_phy`:2043（dpu 用 `qcom,sm6375-dpu`，dsi 用 `qcom,sm6375-dsi-phy-7nm`） | 控制器驱动在；**`qcom,sm6225-mdss` 数据本树新增** | 面板节点 `lenovo,p255-inx` + DSC + 背光 |
| GPU | `gpu`:1725（`qcom,adreno-610.0` + `gmu_wrapper`） | ✅ 6.6 起 | zap-shader 固件路径 + opp-table |
| USB | `usb`:1655、`usb_hsphy`:856、`usb_qmpphy`:915 | ✅ | hsphy 三路电；本机是 peripheral/ACM gadget 用法 |
| SD 卡 | `sdhc_1`:1150、`sdhc_2`:1205（`qcom,sm6225-sdhci` + 回退 `qcom,sdhci-msm-v5`） | ✅（靠回退串） | cd-gpios 极性（配方第二轮已趟过：gpio88/45） |
| WiFi | `wifi`:3018（`qcom,wcn3990-wifi`，12 个中断，`qcom,msa-fixed-perm`） | ✅ 驱动在（ath10k_snoc） | 4 路电 + `ath10k-calibration-variant` + bdwlan 固件 |
| 蓝牙 | **dtsi 里没有**（板级挂在 `serial@4a8c000` 下的 `bluetooth {}`） | ✅ btqca | `qcom,wcn3990-bt` + 4 路电 + `swctrl-gpios` |
| 音频 | `remoteproc_adsp`:2728、`q6asm/q6adm` 服务节点（dtsi 内） | 节点 6.14 起 | **缺 machine driver + 缺 `sound{}` 节点**，见 §3.4 |
| 协处理器 | `remoteproc_mpss`:2083、`adsp`:2728、`cdsp`:2869 | ✅ QCOM_Q6V5_PAS | 固件路径（设备上是平铺的 `adsp.mbn` 等） |
| 串口/I2C/SPI | `qupv3_id_0`:1308 + `i2c0..5` / `spi0..5` / `uart3,4` | ✅ geni | 板级分配引脚 |
| 温度 | `tsens`（18 处） | ✅ | 无需处理 |
| **摄像头** | **0 处 camss** | ❌ **上游没有** | **做不了**（除非自己写 camss 支持） |
| **LLCC** | **0 处 llcc** | ❌ 本树 `CONFIG_QCOM_LLCC is not set` | 影响缓存/DVFS 表现，非阻断 |
| 传感器（加速度/霍尔等） | 板级 i2c/spi | 驱动在上游（bmi3x0 等） | 板级节点 |

### 3.4 音频：不是"开个开关"，是缺三样东西

实测这份**已经编过的 .config**：

```
CONFIG_SOUND=y  CONFIG_SND=y  CONFIG_SND_SOC=y          ← 只有框架
# CONFIG_SND_SOC_QCOM is not set                         ← 高通 ASoC 平台驱动没编！
# CONFIG_SND_SOC_AW88166 is not set                      ← 功放 codec 没编
（SND_SOC_QDSP6 / SND_SOC_SM8250 都不在 config 里）
```
再加两条结构性缺口（`grep` 实测）：
- `sm6225.dtsi` 里**没有 `sound {}` 节点**，板级 dts 里**也没有**（只有功放/`q6asm` 子节点）。
- 上游 `sound/soc/qcom/sm8250.c` 只认三个 compatible：`qcom,sm8250-sndcard`、**`qcom,qrb4210-rb2-sndcard`**、`qcom,qrb5165-rb5-sndcard`。
  **好消息**：`qrb4210` 就是 bengal 家族（QRB4210 = SM4250/SM6115 系）——TB331FC 的音频 machine 驱动
  可以复用 `qrb4210-rb2` 那条路径，DT 写 `compatible = "qcom,qrb4210-rb2-sndcard"` 试，大概十几行 + dai-link。
  **坏消息**：本机是 4×AW88166 + WCD937x，dai-link 与 codec 绑定要自己写，`aw88166.c` 还得编进去。

---

## 4. 路线对比（问题 5）

### 路线 A：继续用现成 6.14 树（推荐起点）

| | |
|---|---|
| 要做的 | ① 把 DTS 蓝牙改回 `qcom,wcn3990-bt`；② 重编；③ 打 boot-v3 镜像刷 B 槽验证 |
| 工作量 | **0.5 天**（编译本身十几分钟，见 §6） |
| 拿到什么 | 显示 + 背光 + GPU(freedreno FD610) + Niri + USB 串口 + SD 卡 + ADSP 起来（= 配方已证实的现状） |
| 风险 | 树是 linux-next 快照、非 git、有 4 处 zip 损坏（符号链接被压成 0 字节）；WiFi 无接口 / 触控 DLM 写入 / 音频 machine 层三个未解决问题**换内核也解决不了**（那是驱动/协议问题，不是版本问题） |

### 路线 B：vanilla 6.14 + 只搬 SoC 层（"我要真上游"的最小代价）

要搬（全部 0.60 MB 里剔除面板/触控/功放）：
`sm6225.dtsi` + `gcc/dispcc/gpucc-sm6225.c` + `pinctrl-sm6225.c` + 4 个 dt-bindings +
`phy-qcom-qmp-ufs.c` 的 `sm6225_ufsphy_cfg` + `msm_mdss.c` 的 `sm6225_data` + `arm-smmu-qcom.c` 两行 + 6 处 Kconfig/Makefile 挂钩；
板级 dts 自己写（**直接抄上游 `sm6115p-lenovo-j606f.dts`**，388 行，同一 SoC 家族、同一个 Novatek TDDI 面板控制器，
连 `ufs_mem_hc`/`wifi`/`adc`/regulator 表都能照搬）。

| | |
|---|---|
| 工作量 | **1.5–3 天**（driver 移植是机械的：gcc 3009/3468 行相同、pinctrl 只差 108 行；真正要理解的是 clock 树差异） |
| 拿到什么 | 能启动 + 串口 console + UFS + USB + SD + GPU；**没有显示/触控/音频**（mdss 能开但没面板驱动，会白屏） |
| 风险 | 中。最大不确定性：`sm6225` 的 GCC 与 `sm6115` 的差异是否只是"少几个门控"（若是，甚至可以先试上游 gcc-sm6115 硬套） |

### 路线 C：vanilla + 全部外设（"能当平板用"）

B + 面板（`p255_inx`，+37.8 KB 到 hx83102 + 17.5 KB 初始化序列 + `dsi_host.c` 的 slice_per_pkt）/ 触摸（107 KB）/
功放（53 KB）/ 电量计 compatible。

| | |
|---|---|
| 工作量 | **1–2 周**，而且**不一定能收尾**：配方第 19/25/26 轮记录触控 DLM 段写入 CRC 永不一致、
显示与触控是 TDDI 强耦合——这是驱动协议问题，跟内核版本无关，vanilla 搬迁只是把同样的问题再搬一次 |
| 建议 | 只有"要上交/要长期维护上游化"才值得；否则不值 |

### 路线 D：字面 v6.0

不可行。要自己实现 bengal 的 GCC/DISPCC/GPUCC/PINCTRL/ICC/DPU/DSI/UFS-PHY 与整个 dtsi——那是 **6.2→6.14
跨 8 个大版本、几十位开发者三年**的工作量。**任何"想要 6.0"的需求都应该被翻译成"想要真上游"**，走 B 或 C。

### 工作量速查

| 路线 | 时间 | 显示 | 触控 | 音频 | WiFi/BT | 结论 |
|---|---|---|---|---|---|---|
| A 现成 6.14 | 0.5 天 | ✅ | 🟡 有一版能用（boot_hook） | ❌ | 🟡 驱动起来但没接口/芯片不应答 | **先做这个** |
| B vanilla+SoC 层 | 1.5–3 天 | ❌ | ❌ | ❌ | 同 A | 想要"干净上游"时做 |
| C vanilla+全外设 | 1–2 周 | ✅ | 🟡 | 🟡 | 🟡 | 长期投入才做 |
| D 字面 6.0 | 数月 | — | — | — | — | ❌ |

---

## 5. 从零编译：可照做的命令清单（问题 4）

### 5.1 环境（WSL `ub` 现状，已满足）

```bash
wsl -d ub -u root
nproc                     # 8
free -g | head -2         # 7 GB
df -h /                   # 937 GB 可用
aarch64-linux-gnu-gcc --version | head -1   # 13.3.0 (Ubuntu 13.3.0-6ubuntu2~24.04.1)
# 已有：make gcc bc bison flex libssl-dev libelf-dev lz4 zstd dtc python3
```
缺的话一次装齐：
```bash
apt-get update && apt-get install -y build-essential bc bison flex libssl-dev libelf-dev \
  lz4 zstd device-tree-compiler python3 crossbuild-essential-arm64 git
```

### 5.2 拿源码（两条路，都别下 267 MB 的 zip）

```bash
# 路线 A / B 都先拿一份干净的上游基线（浅克隆，只 1 个 commit；或用 tarball 更省）
git clone --depth 1 --branch v6.14 \
  https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git ~/linux-v614
#   tarball 等价物（更省事，约 145 MB）：
#   curl -LO https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.14.tar.xz

# 想要 LTS 的 6.12：
git clone --depth 1 --branch linux-6.12.y \
  https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git ~/linux-612
```
> **不要在 `/mnt/e` 下编译**（9p 文件系统，速度掉 5–10 倍）。放 `/root` 或 `~/`（ext4）。

### 5.3 如果沿用现成那棵树：先修 4 处损坏

```bash
K=/root/linux-tb331fc
# ① syscall 表符号链接（上一轮已修，确认一下）
ls -l $K/arch/arm64/tools/syscall_64.tbl      # 应 → ../../../scripts/syscall.tbl

# ② dtc 头文件搜索路径（本次新发现，修完 make dtbs 才不会对真源码 DTS 报错）
cd $K/scripts/dtc/include-prefixes
for d in arc arm arm64 dt-bindings microblaze mips nios2 openrisc powerpc riscv sh xtensa; do
  rm -f "$d"
  case "$d" in
    dt-bindings) ln -s ../../../include/dt-bindings "$d" ;;
    arm64)       ln -s ../../../arch/arm64/include   "$d" ;;
    *)           ln -s ../../../arch/$d/include      "$d" ;;
  esac
done

# ③ include/dt-bindings/input/linux-event-codes.h 是 0 字节（上游是符号链接）
cd $K/include/dt-bindings/input
rm -f linux-event-codes.h && ln -s ../../uapi/linux/input-event-codes.h linux-event-codes.h
#    症状：pm6125.dtsi:56.19-20 syntax error（`linux,code = <KEY_POWER>` 里的 KEY_POWER 没展开）
#    只有 tb128 那两块 dts 用到 pm6125.dtsi；tb331fc 的 dts 是反编译产物、无 #include，所以之前没踩到。
#    校验：两条修完后 `make dtbs` 应零 fatal error（tb331fc / tb128 / tb128-hx83102 三块都能出）。
```

### 5.4 配置（先 defconfig，再按需改）

```bash
cd $K
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-

# 现成树自带（推荐，2897 个 CONFIG_）
make tb331fc_defconfig

# 纯上游树则是：
make defconfig          # arch/arm64/configs/defconfig 里已含 CONFIG_ARCH_QCOM=y / SM_GCC_6115=y / PINCTRL_SM6115=y
                        # 但没有 sm6225 的东西，得先按 §4-B 把 sm6225 层搬进来
```

**必须存在的配置项**（名字已从真实的 `.config` 里核对过，不是猜的）：

```ini
# —— SoC 与电源/时钟 ——
CONFIG_ARCH_QCOM=y
CONFIG_QCOM_SMEM=y
CONFIG_QCOM_SMSM=y
CONFIG_QCOM_SMD_RPM=y            # RPM 稳压器
CONFIG_QCOM_RPMPD=y              # 电源域
CONFIG_QCOM_CLK_SMD_RPM=y
CONFIG_SM_GCC_6225=y             # ← sm6225 全局时钟（本树新增驱动）
CONFIG_SM_DISPCC_6225=y          # ← 显示时钟
CONFIG_SM_GPUCC_6225=y           # ← GPU 时钟
CONFIG_PINCTRL_SM6115=y          # ← 同时编出 pinctrl-sm6225.o（Makefile 里挂在一起）
CONFIG_PINCTRL_SM6115_LPASS_LPI=m
CONFIG_ARM_QCOM_CPUFREQ_NVMEM=y
CONFIG_QCOM_TSENS=y
# CONFIG_QCOM_LLCC 若为 y 需要 DT 有 llcc 节点，本机没有 → 保持 not set
# CONFIG_INTERCONNECT_QCOM_SM6225 可选（开了要 icc 节点齐全，现 config 未开）

# —— 存储 ——
CONFIG_SCSI_UFS_QCOM=y
CONFIG_PHY_QCOM_QMP_UFS=y
CONFIG_MMC_SDHCI_MSM=y

# —— USB（本机主要当 gadget 串口 console 用）——
CONFIG_USB_DWC3=y
CONFIG_USB_DWC3_QCOM=y
CONFIG_PHY_QCOM_QUSB2=y
CONFIG_USB_CONFIGFS=y
CONFIG_USB_CONFIGFS_ACM=y
CONFIG_USB_GADGET=y

# —— 显示 ——
CONFIG_DRM=y
CONFIG_DRM_MSM=y
CONFIG_DRM_FBDEV_EMULATION=y
CONFIG_DRM_SIMPLEDRM=y            # simpledrm 控制台（没面板驱动时的兜底）
CONFIG_DRM_PANEL_HIMAX_HX83102=y  # ← 含 lenovo,p255-inx
CONFIG_BACKLIGHT_KTZ8866=y        # ← 上游就有，本机背光 IC
CONFIG_BACKLIGHT_CLASS_DEVICE=y

# —— 串口 / I2C / SPI（GENI）——
CONFIG_SERIAL_QCOM_GENI=y
CONFIG_SERIAL_QCOM_GENI_CONSOLE=y
CONFIG_I2C_QCOM_GENI=y
CONFIG_SPI_QCOM_GENI=y            # ⚠️ 默认是 =m，必须 =y（配方第三轮：否则没有 spi_master，触控永远绑不上）

# —— 协处理器 ——
CONFIG_QCOM_Q6V5_PAS=m            # adsp/cdsp/mpss
CONFIG_QCOM_Q6V5_COMMON=y
CONFIG_QCOM_APR=m
CONFIG_QCOM_QMI_HELPERS=m

# —— WiFi / 蓝牙 ——
CONFIG_ATH10K=y
CONFIG_ATH10K_SNOC=m             # ⚠️ 设不成 y：依赖隐藏符号 QCOM_RPROC_COMMON
CONFIG_BT=y
CONFIG_BT_HCIUART=y
CONFIG_BT_HCIUART_QCA=y
CONFIG_BT_QCA=y
CONFIG_BT_LE=y                    # 上一轮补的
CONFIG_RFKILL=y

# —— 音频（要出声还得补 machine driver，见 §3.4）——
CONFIG_SOUND=y
CONFIG_SND=y
CONFIG_SND_SOC=y
CONFIG_SND_SOC_QCOM=y            # ⚠️ 现有 config 里是 not set，这就是"没声"的第一层原因
CONFIG_SND_SOC_AW88166=y         # 本树新增的功放 codec

# —— 触摸 / 充电 ——
CONFIG_TOUCHSCREEN_NT36523_SPI=y # 本树新增（out-of-tree）
CONFIG_TYPEC_TCPM=y
CONFIG_TYPEC_RT1711H=y           # 注意符号名是 TYPEC_RT1711H
CONFIG_TYPEC_MUX_FSA4480=m

# —— 编译友好 ——
CONFIG_DEBUG_INFO_BTF=n          # 省 pahole 依赖、快很多
CONFIG_DEBUG_INFO=n
CONFIG_MODULE_COMPRESS_NONE=y
```

改配置用脚本化方式（不要手点 menuconfig）：
```bash
scripts/config --file .config -e SM_GCC_6225 -e SPI_QCOM_GENI -d DEBUG_INFO_BTF
make olddefconfig
```

> ⚠️ **`tb331fc_defconfig` 本身不含音频与 BLE**（实测：`# CONFIG_SOUND is not set`、`# CONFIG_BT_LE is not set`）。
> 上一轮那版镜像是"defconfig + 手工加 4 项"得到的（`config-6.14.0-rc5-tb331fc` 与 defconfig 差 398 行）。
> 要复现上一版必须补：
> ```bash
> make tb331fc_defconfig
> scripts/config --file .config -e SOUND -e SND -e SND_SOC -e BT_LE
> make olddefconfig
> ```
> 本报告 §5.6 的计时用的是**纯 defconfig**（因此那次 Image 是 38,564,352 B，比上一版 38,959,616 B 小 395 KB，
> 差异就是 ALSA/ASoC 那整套）。

### 5.5 编译与产物

```bash
cd $K
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
make -j8 Image Image.gz dtbs modules      # dtbs 只有在 §5.3② 修好后才能全量通过
# 产物：
#   arch/arm64/boot/Image                （未压缩，Android boot v3 头用它）
#   arch/arm64/boot/Image.gz
#   arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dtb
#   .config  → 存一份 config-6.14.0-rc5-tb331fc
```
打包成可刷镜像（Android boot v3 / GKI header，page size 4096）：
```bash
# 上一轮用的是自写脚本 mkv4.py（在资材仓库 tools/ 里：mkv4.py --mode boot --kernel Image）
# 产物 boot-v3-linux.img = 14,090,240 B，就是 Image 灌进 v3 头后的样子
```

### 5.6 实测耗时与磁盘（本机 8 核 / 7 GB，本次真跑，不是估算）

在一个**丢弃副本**（`/root/kbtest`，`make mrproper` 后全新）里跑，原树未被碰：

| 阶段 | 命令 | 实测耗时 | 产物 |
|---|---|---|---|
| 解压/拷贝源码 | `cp -a`（1.9 GB） | 88 s | 1.9 GB |
| `mrproper` + defconfig | `make mrproper` + `make tb331fc_defconfig` | 10 s | `.config` 2,897 个 `CONFIG_` |
| **内核** | `make -j8 Image` | **966 s = 16 m 06 s** | `Image` 38,564,352 B |
| **模块** | `make -j8 modules` | **397 s = 6 m 37 s** | **675 个 `.ko`** |
| 设备树（全量） | `make -j8 dtbs` | 约 20 s（增量 1 s） | `sm6225-lenovo-tb331fc.dtb` 69,341 B；tb128 62,272 B；tb128-hx83102 62,532 B |
| **合计（全新 → Image+modules+dtbs）** | | **≈ 23 分钟** | |
| 磁盘占用 | | 源码 1.7 GB → 构建完 **3.2 GB** | 建议预留 **≥ 10 GB** |

对照：作者在 24 核 / 9 GB 上记录 `make -j10 Image` 约 **3 分 19 秒**，与本次 8 核 16 分钟的线性关系吻合
（核数 3 倍 → 时间 1/5）。**结论：这台机器编一次内核是"喝杯茶"的量级，不需要为省时间做任何取舍。**

> 注意：**不要用 `make O=xxx` 出树编译**——现有树里已经有树内编译残留（`include/config/auto.conf`、
> `arch/arm64/boot/dts/qcom/*.dtb`），`O=` 会直接报
> `*** The source tree is not clean, please run 'make mrproper'`。要出树编译先 `make mrproper`。
>
> 另注：`make dtbs` **只有修完 §5.3②③ 两处符号链接才能全量通过**；修之前只编
> `make qcom/sm6225-lenovo-tb331fc.dtb` 这一块是能过的（实测 exit=0），这也是上一轮没发现问题的原因。

---

## 6. 风险清单：哪些是"能编但跑不起来"（问题 6）

| 项 | 状态 | 根因（有实测证据的） | 换内核能解决吗 |
|---|---|---|---|
| **触控 Novatek NT36523** | 🟡 时好时坏 | 固件 DLM 段写入后回读 CRC 永不一致（配方第 19 轮：`dlm bin crc = 0x49618174 golden = 0x49618174 result = 每次不同`）；写入落错 SRAM 地址 → 同时造成显示条纹。`nvt_read_pid` 读出乱码（厂商是稳定的 `0x6072`） | ❌ 是驱动/协议问题。需要 **Novatek SPI 版厂商源码**对照（TB128FU 是 I2C 版，不能直接用） |
| **显示（p255_inx / TDDI）** | ✅ 主链路通，🟡 窗口区域仍有条纹 | 条纹只在下固件时出现（`boot_nofw.img` 干净），DPU 时钟必须钉 384 MHz，`slice_per_pkt=2` + 标准 DSC PPS 才点亮 | 🟡 与触控共用一条因果链 |
| **WiFi WCN3990（ath10k_snoc）** | ❌ 驱动 probe 后静默 | `Adding to iommu group 7` 之后无日志、无 wiphy。固件/供电/MSA/ADSP/QRTR 已逐项排除。**顺序差异**：Android 是 PIL 先载 wlanmdsp，主线是 ath10k_qmi 先等 WLFW QMI 服务 | ❌ 版本无关；需要 `CONFIG_ATH10K_DEBUG` 深挖 WLFW 服务由谁提供 |
| **蓝牙 WCN3990（hci_qca）** | 🟡 链路通、芯片不应答（最近已到 serdev 绑定 + hci0） | UART 别名路径（`/soc@0` vs `/soc`）、4 路稳压器、pinctrl、`swctrl-gpios` 极性——已逐个修过 | 部分可解：**先把 compatible 改回 wcn3990-bt**（见 §1.2） |
| **音频** | ❌ | ①`CONFIG_SND_SOC_QCOM is not set` ②`SND_SOC_AW88166 is not set` ③**没有 `sound{}` 节点、没有 machine driver** | 🟡 可解但要写代码（复用 `qrb4210-rb2-sndcard` 路径最省） |
| **摄像头** | ❌ 做不了 | 上游 `sm6115.dtsi`/`sm6225.dtsi` 里 **camss 节点 0 处**，bengal 的 camss 从未上游化 | ❌ 除非自己写 camss |
| **GPU Adreno 610** | ✅ 可用 | freedreno FD610，GL 4.6 / GLES 3.2；需 `a610_zap.mdt`（设备上要从原厂取） | — |
| **电量计 mm8013** | ⚠️ 隐患 | 驱动文件在、`Makefile` 有 `CONFIG_FUEL_GAUGE_MM8013`，但 **Kconfig 里没有这个符号** → 实际编不进去 | 需要补 Kconfig 条目（8 行） |
| **ABL 启动门** | ⚠️ 与内核无关但会挡路 | DTB 必须带 `__symbols__`（120 个符号，`dtc -@`），否则 ABL overlay 应用失败 → **拒启**（~5.3 s 回 fastboot）；`/chosen/bootargs` 里不能有 `noinitrd`、不能有 `root=` | 打包层问题，不是内核 |
| **cmdline** | ⚠️ | 必须带 `clk_ignore_unused pd_ignore_unused`，否则内核关掉 ABL 留下的显示时钟 → 黑屏 | 打包层 |
| **`CONFIG_INTERCONNECT_QCOM_SM6225` 未开** | 🟡 | 无 icc → 总线不做 DVFS。能跑，但性能/功耗不理想；开了要求 icc 节点齐全 | 需要验证 |
| **`CONFIG_QCOM_LLCC` 未开** | 🟡 | 上游 sm6115.dtsi 里也没有 llcc 节点 | 同上 |

---

## 7. 关于"上一版镜像"的待修项（可直接执行）

1. **DTS 蓝牙改回 wcn3990**（一行，且仓库里有注释说明原因）：
   ```diff
   - compatible = "qcom,wcn3988-bt";
   + compatible = "qcom,wcn3990-bt";
   ```
2. **固件路径**：`zap-shader`/`modem`/`adsp`/`cdsp` 的 `firmware-name` 已去前缀，需保证
   rootfs 的 `/lib/firmware/` 下真有 `a610_zap.mdt`、`adsp.mbn`、`cdsp.mbn`（从原厂分区取）。
   蓝牙固件按 `btqca.c` 的硬编码路径放：`/lib/firmware/qca/crbtfw21.tlv` + `qca/crnv21.bin`
   （从 `BTFM.bin` 挂载提取；`apbtfw11.tlv` 那条线是错的）。
3. **音频**：至少先 `CONFIG_SND_SOC_QCOM=y` + `CONFIG_SND_SOC_AW88166=y`，再谈 machine driver（§3.4）。
   注意 `tb331fc_defconfig` 连 `CONFIG_SOUND` 都是 not set——上一版能编进 ALSA 是因为手工加了 4 项（§5.4）。
4. **`make dtbs` 全量失败**：按 §5.3 修 ②`scripts/dtc/include-prefixes/` 12 个符号链接
   与 ③`include/dt-bindings/input/linux-event-codes.h` 符号链接（实测修完 `make dtbs` 零错误、三块 DTB 全出）。
5. **重编用的命令**（实测 16 分钟）：
   ```bash
   wsl -d ub -u root
   cd /root/linux-tb331fc && export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
   make tb331fc_defconfig && scripts/config --file .config -e SOUND -e SND -e SND_SOC -e BT_LE && make olddefconfig
   make -j8 Image Image.gz modules      # Image 38.6 MB / 675 个 .ko
   ```

---

## 8. 交付物与复现

| 路径 | 内容 |
|---|---|
| `E:\rom\work\kernel-research\REPORT.md` | 本报告 |
| `E:\rom\work\kernel-research\ref\WORKING-BOOT-RECIPE.md` | 作者的 116 KB 完整配方（2802 行，26 轮调试记录） |
| `E:\rom\work\kernel-research\ref\CANONICAL.dts` | 2026-10-27 权威 DTS 快照（旧的） |
| `E:\rom\work\kernel-research\ref\repo-tb331fc.dts` | 仓库 HEAD 的板级 DTS（最新，CRLF） |
| `E:\rom\work\kernel-research\ref\sm6115-v6.6/v6.12/v6.14.dtsi` | 上游三个版本的 sm6115.dtsi，用于对照 |
| `E:\rom\work\kernel-research\ref\j606f-v6.14.dts` | **上游联想 Tab P11（同 SoC 家族）板级 DTS，写自己 DTS 的最佳模板** |
| `E:\rom\work\kernel-research\ref\HANDOVER.md`、`TB331FC-FULL-PORT-GUIDE.md` | 作者交接文档 |
| `probe*.sh` / `probe_gh*.ps1` | 所有取证脚本（可复跑） |

---

## 附录 A：证据来源与复现命令

```bash
# 上游每个 tag 有没有某个文件（本报告最核心的证据）
curl -H "Authorization: token <TOKEN>" \
  "https://api.github.com/repos/torvalds/linux/contents/arch/arm64/boot/dts/qcom/sm6225.dtsi?ref=v6.14"
#   → 404（v6.0/v6.1/v6.6/v6.12/v6.14/master 全部 404）

curl -H "Authorization: token <TOKEN>" \
  "https://api.github.com/repos/torvalds/linux/contents/arch/arm64/boot/dts/qcom/sm6115.dtsi?ref=v6.0"
#   → 404（v6.2 才是 200，35,075 B）

# 两棵树的关系
curl -H "Authorization: token <TOKEN>" "https://api.github.com/repos/LzwPluto/linux-lenovo-tb331fc"
curl -H "Authorization: token <TOKEN>" "https://api.github.com/repos/LzwPluto/lenovo-tb331fc-mainline"

# 本地取证
diff --strip-trailing-cr ref/repo-tb331fc.dts /root/linux-tb331fc/arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dts
diff -q ref/sm6115-v6.14.dtsi /root/linux-tb331fc/arch/arm64/boot/dts/qcom/sm6115.dtsi
grep -c 'status = "disabled"' /root/linux-tb331fc/arch/arm64/boot/dts/qcom/sm6225.dtsi   # 70
```

> 备注：`raw.githubusercontent.com` 在本机不通，所有文件内容都走 `api.github.com` 的 contents API（base64）。
> GitHub API 额度：token 5000 次/小时，本次调研约用了 120 次。
