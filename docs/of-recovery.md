# TB331FC（khaje / SM6225-AD）OrangeFox R12.0 · **显示与触摸**通路核实

> 日期：2026-11-24 · 子任务：recovery 适配核实（显示 / 触摸两条最小可用通路）
> 设备侧**全程只读**（`adb shell ls/cat`、`exec-out cat` 取文件），未 push、未 flash、未改槽位。
> 写入范围：本文件 + WSL `/root/woa/ofdr/`（分析用）。v1/v2 产物零改动。
> 标注：【实测】= 本轮字节级/设备回显证据 ·【推断】= 由实测推演 ·【未证】= 无证据

---

## 0. 一句话结论

| 通路 | 结论 | 依据强度 |
|---|---|---|
| **显示** | **能出画面**。OF 的 `libminuitwrp.so` 是「**DRM 优先、fbdev 兜底**」的运行时选择，而这个内核 `# CONFIG_FB is not set`、`/dev/fb0` 不存在 ⇒ 只能走 DRM；DRM 这条路**原厂自己的 recovery 就在用**（`librecovery_ui.so` 里同一套 drmMode* + `/dev/dri`） | 【实测】三方独立证据（OF 二进制反汇编、原厂 recovery 库、实机 `/dev/dri` + `/sys/class/drm`） |
| **触摸** | **能起，但不是零风险**：整条链里**只缺 `hxchipset.ko` 一个文件**（其依赖 `panel_event_notifier`、`nopmi-chg` 原厂 vendor ramdisk 已经提供并在 recovery 列表里）；DT（GPIO80/86、10 MHz、CS0、1200×1920）、固件（`/vendor/firmware` + ueventd `firmware_directories`）都齐。**唯一没证的是"探测时序"**（触摸 IC 在面板点亮前 probe 会不会失败） | 【实测】模块 depmod/modinfo、实机 device-tree、固件通道；【未证】时序 |
| **最少必要改动** | **2 条**（显示 1 条 1 行；触摸 1 条 = 把 TWRP 的模块清单改成单行）。可选第 3 条是省 6.3 MB 的清理 | 见 §4 |

**顺带纠正 v2 的一个隐含假设（重要）**：v2 认为"显示/触摸都得靠 OF ramdisk 里那 15 个模块"。实测那 15 个里 **14 个与原厂 `vendor_boot` vendor ramdisk 的 `/lib/modules/*.ko` 逐字节相同**，只有 `hxchipset.ko` 是新的 —— 显示链根本不需要 OF 再带一遍，它由 **init 从 `/lib/modules` 加载**（原厂 recovery 就是这么拿到显示驱动的）。

---

## 1. 证据来源（可复现）

| 对象 | 位置 |
|---|---|
| v2 成品 ramdisk 解出 | `E:\rom\work\of\recovery_of_tb331fc_v2.img` → v4 头 kernel_size=43,092,480 / ramdisk_size=47,627,842 @0x1000+43,094,016 → LZ4-legacy 13 块 → **cpio 103,027,712 B / 4,263 项**（复算与 `REPORT_v2.md` 一致） |
| 原厂 vendor ramdisk（MODE=2 的 `/lib/modules` 来源） | `E:\rom\work\of\v2work\live_vendor_ramdisk.bin` → cpio 34,556,672 B / 248 项 / **237 个 .ko** |
| 原厂 recovery ramdisk（旁证） | `E:\rom\work\zui16_flash\image\recovery.img`（kernel_size=0）→ cpio 30,172,672 B / 471 项 |
| 原厂 dtbo | `E:\rom\work\zui16_flash\image\dtbo.img`（45 个 overlay） |
| 实机 device-tree / DRM | `adb shell cat /sys/firmware/devicetree/base/...`、`/sys/class/drm/...` |
| 分析工作区（WSL） | `/root/woa/ofdr/`：`v2rd/v2.cpio`、`stock_vendor.cpio`、`stock_recovery.cpio`、`dtbo_2.dts`、`dtbo_*.dtb`、`hxchipset.ko` |

---

## 2. 显示通路

### 2.1 内核侧硬事实【实测】

`/root/woa/ofbuild/config`（195,208 B，`Linux/arm64 5.15.167 Kernel Configuration`，与实机 `uname -a` = `5.15.167-android13-5.15.167_r00-dirty` 同版本）：

```
line 3995: CONFIG_FB_CMDLINE=y
line 3996: # CONFIG_FB is not set          ← 没有任何 fbdev
CONFIG_DRM=y / CONFIG_DRM_MIPI_DSI=y / CONFIG_DRM_KMS_HELPER=y
# CONFIG_DRM_MSM is not set                 ← msm_drm 由 vendor 模块提供，不是内核内置
CONFIG_MODULES=y / CONFIG_MODVERSIONS=y / CONFIG_MODULE_SIG_FORCE not set
```

实机（运行中的 Android，同一内核）：
```
/dev/fb0                 → No such file or directory        ← 印证 CONFIG_FB=n
/dev/dri/card0           226,0   crw-rw-rw- root graphics
/dev/dri/renderD128      226,128
/sys/class/drm/          card0  card0-DSI-1  renderD128  sde-conn-0-DSI-1  sde-crtc-0  version
/sys/class/drm/card0-DSI-1/status = connected
/sys/class/drm/card0-DSI-1/modes  = 1200x1920x90vid        ← 就是我们这块 BOE p255 / HX83102J
```

⇒ **fbdev 这条路在物理上不存在**；只剩 DRM。

### 2.2 OF 的图形后端：**运行时 DRM 优先**，不是编译期开关【实测·反汇编】

`system/lib64/libminuitwrp.so`（338,728 B，AArch64）：

| 事实 | 证据（文件偏移） |
|---|---|
| `gr_init()` 里有**两条**分支，先 `open_drm()` | `gr_init` @0x205e0；`bl open_drm` @0x206a4；`adrp/add` 到 `"Using drm graphics."` @0x1326f |
| DRM 成功才打印 DRM 那句；否则 `open_fbdev()` | `bl open_fbdev` @0x206d8；`"Using fbdev graphics."` @0x1313f |
| `open_drm()` 扫 `/dev/dri/card0..card15` | `" /dev/dri"` @0x124b2、`"%s/card%d"` @0x138cf；`asprintf` @0x1d0a8、`open(O_RDWR)` @0x1d0bc；循环上限 `cmp w20,#0x10` @0x1d08c |
| 要求 dumb buffer 能力 | `drmGetCap(fd, DRM_CAP_DUMB_BUFFER=1, ...)` @0x1d0d8；`drmModeGetResources` @0x1d0fc |
| 连接器优先级 **LVDS(7) → eDP(14) → DSI(16)**，且必须 `connection==1`(connected) 且 `count_modes>0` | `cmp w8,#0x7` @0x1d1bc、`cmp w8,#0xe` @0x1d224、**`cmp w8,#0x10` @0x1d28c** |
| 取 **PREFERRED** 模式 | 扫描 `mode->type` bit3（`DRM_MODE_TYPE_PREFERRED`）：`tbnz w10,#3` @0x1d32c |
| 用完形 atomic 提交 | `drmModeAtomicAlloc` @0x1d374、`drmModeAtomicCommit` 在`.dynsym` |

⇒ **不需要打开任何 `TW_TARGET_USES_DRM` 类开关**；`twrp.flags`（4,574 B，51 行，已逐行读过）里也**没有**任何图形相关键（全是分区/备份/挂载），这解释得通：后端选择根本不读 flags。
⇒ 本机 `card0-DSI-1`（type=16、connected、首选模式 1200×1920@90）**正好命中第 3 条优先级分支**。

### 2.3 决定性旁证：**原厂 recovery 自己就是 DRM**（同一台机、同一个内核）【实测】

| 对象 | 事实 |
|---|---|
| 原厂 `recovery.img` ramdisk → `system/lib64/librecovery_ui.so`（364,720 B） | 含 `/dev/dri`(×2)、`/dev/dri/`、`/dev/graphics/fb0`、`card%d`，并含 `drmModeSetCrtc`、`drmModeAddFB2`、`drmModeAtomicCommit`、`drmModeGetResources`、`drmGetCap` —— **与 OF 的 minui 是同一套 DRM 后端** |
| 原厂 `init.recovery.qcom.rc`（2,175 B） | `on init` 里第一行就是 `write /sys/class/backlight/panel0-backlight/brightness 200` |
| 原厂 vendor ramdisk `/lib/modules/modules.load.recovery`（3,889 B） | 尾部按顺序含 `… pinctrl-msm.ko … spmi-pmic-arb.ko … panel_event_notifier.ko … msm_drm.ko → ktz8866_leds.ko → msm-mmrm.ko → hdcp_qseecom_dlkm.ko → smcinvoke_dlkm.ko → qseecom_dlkm.ko` |
| 原厂 vendor ramdisk `/lib/modules/modules.dep` | `msm_drm.ko: ktz8866_leds.ko spmi-pmic-arb.ko qcom_va_minidump.ko pinctrl-msm.ko qcom_iommu_util.ko panel_event_notifier.ko msm_dma_iommu_mapping.ko secure_buffer.ko qcom-scm.ko minidump.ko smem.ko` |
| 实机 `/sys/class/backlight/panel0-backlight` | → `…/soc/5e00000.qcom,mdss_mdp/backlight/panel0-backlight`，`max_brightness=255`（**这个 backlight 是 msm_drm 自己注册的**，不是 ktz8866 的 `bkl-bl`） |

⇒ 原厂 recovery 的显示链路 = **init 从 `/lib/modules` 加载 msm_drm → DRM `/dev/dri/card0` → 写 `panel0-backlight` 亮度 → 画图**。这条链在本机是**OEM 已量产验证过**的，不是我们新开的路径。

### 2.4 `/dev/dri/card0` 出现的条件清单（缺一即无画面）

| # | 条件 | 本轮证据 | 不满足时的现象 |
|---|---|---|---|
| 1 | `vendor_boot` 的 **vendor ramdisk 段保留原厂内容**（含 `/lib/modules` 237 个 .ko + 6 个 `modules.*`） | MODE=2 的 `vendor_boot_of_tb331fc_v2_split.img` 结构；`live_vendor_ramdisk.bin` 解包 248 项 | 连 `msm_drm.ko` 都不存在 → 黑屏无 USB（若内核还活着则白屏/黑屏，见 §5） |
| 2 | `init` 走 recovery 分支并读 **`/lib/modules/modules.load.recovery`** | OF `system/bin/init`（1,979,448 B）含 `/lib/modules`(×5)、`modules.load.recovery`(×2)、`/modules.load.recovery` @0x1a927；原厂 init（2,164,264 B）同一套字符串 | `I:Unable to open module directory … skipping`，`/proc/modules` 空 → 无 card0 |
| 3 | `msm_drm` 的 **11 个依赖**全部先加载（见 §2.3 的 dep 行） | 全部在 237 个里；依赖闭包顺序也在 `modules.load.recovery` 里 | `Failed to insmod 'msm_drm.ko'`（unknown symbol） |
| 4 | 时钟/电源域/互连：`dispcc-khaje`、`clk-qcom`、`gcc-khaje`、`gdsc-regulator`、`icc-rpm`、`qnoc-bengal`、`pinctrl-khaje`、`qcom-spmi-pmic`、`regmap-spmi`、`spmi-pmic-arb` | 全在 237 个里，且实机 `/proc/modules` 里全是 Live（`pinctrl_msm 53248 65 msm_drm,…`、`dispcc_khaje 28672 12`、`clk_qcom 258048 11`） | probe defer / 超时 → 无 card0 |
| 5 | **DT**：base dtb 有 `qcom,mdss_mdp` / `qcom,mdss_dsi_ctrl0@5e94000` / `qcom,mdss_dsi_phy0@5e94400` / `qcom,dsi-display-primary` / `dsi_panel_pwr_supply_no_labibb`；**面板与触摸节点只在 dtbo 里** | `live_dtb.bin`（1,290,690 B）里 `mdss`×88、`dsi0`×3、但 **`himax`/`hx83102`/`p255` 命中 0**；dtbo 里 `dtbo_2/4/8/9/18/21` 含 `himax`+`p255` | dtbo_b 若被替换成"自制/空 dtbo" → 面板不 probe（这正是"必须用原厂 dtbo"的硬理由） |
| 6 | `ueventd` 建 `/dev/dri/*`（0666 root:graphics）并让 `msm_drm` 的 uevent 落进去 | OF 的 `system/etc/ueventd.rc` 有 `subsystem drm / dirname /dev/dri` 与 `/dev/dri/* 0666 root graphics`（与原厂 3,168 B 的 ueventd.rc 同段） | card0 存在但节点没建 → `open_drm` 打不开 → 回落 fbdev → 必然失败 |
| 7 | **背光**：`panel0-backlight` 亮度被写成非 0 | 实机 `brightness=0` / `max=255`（屏当前是灭的）；原厂 recovery 在 `on init` 写 200；OF 的 `init.recovery.qcom.rc`（51 行）**没有这一行**；libminuitwrp 硬编码同一路径 @0x12bc6（`"cannot open LCD backlight"` @0x12dd0） | 有 card0、有 modeset，但**屏全黑**（会被误判成"驱动没起"） |

### 2.5 结论

**DRM 后端能用**，且优先级、连接器类型（DSI=16）、首选模式、atomic 提交、亮度路径全部实测对齐。剩下的不是"能不能"，而是"**要不要补那一行背光**"和"**必须保住原厂 vendor ramdisk + 原厂 dtbo**"这两个约束。

【推断】失败概率主要来自 §2.4 的 1/2 两条（ABL 到底把哪块 ramdisk 交给内核），与本报告无关但决定一切：MODE=2 有 2026-10-24 的实机前例（同机起到 Linux root shell），MODE=1 大概率只是正常进 Android。

### 2.6 万一没画面，备选通路各自可行性

| 备选 | 可行性 | 证据 / 限制 |
|---|---|---|
| **adb shell 直接下命令**（首选兜底） | **高** | `system/bin/adbd`(2,104,280 B) 在 ramdisk；`init.recovery.usb.rc` 建 gadget（**idVendor 0x2717 / idProduct 0x4EE7**，Xiaomi VID）；`init.recovery.qcom.rc` 的 `on boot` 里 `setprop sys.usb.config adb`。recovery 下 adb 是 root，可 `dd`/`twrp` CLI/挂载/重启 |
| **OF 命令行（`system/bin/twrp`，19,448 B）** | 高 | 二进制内字符串：`Allows command line usage of OrangeFox via openrecoveryscript commands.`、`--help`、`--version` ⇒ 可在 adb shell 里跑"刷包/挂载/重启"全流程 |
| **音量键 + 电源键盲操作** | 中 | TWRP 天生支持物理键导航；`/dev/input/*` 权限 0660 root:input（recovery 是 root）；OF 还起了 `vibratorfeature-hal-service` + `write /sys/class/leds/vibrator/trigger transient` ⇒ 有**震动反馈**可以当"盲操作的确认音"。但"看不见菜单"意味着每一步都要靠记忆，实际只适合"重启/退出"这类单步动作 |
| 纯文本串口 | **不可行** | 本机无对外 UART；cmdline 无 `console=ttyMSM0` 之类可用通道 |

---

## 3. 触摸通路

### 3.1 只缺一个文件【实测·逐字节】

v2 ramdisk `/vendor/lib/modules/1.1/` 有 15 个 .ko。把它们与**原厂 vendor ramdisk 的 `/lib/modules/`** 同名文件比 sha256：

```
class-dual-role.ko      SAME      msm_drm.ko              SAME
dispcc-khaje.ko         SAME      msm_geni_serial.ko      SAME
i2c-msm-geni.ko         SAME      nopmi-chg.ko            SAME
ktz8866_leds.ko         SAME      panel_event_notifier.ko SAME
mm8013c10_battery.ko    SAME      qcom_pmic_voter.ko      SAME
sc8960x_charger.ko      SAME      qcom_va_minidump.ko     SAME
spi-msm-geni.ko         SAME      tcpc_class.ko           SAME
hxchipset.ko            607,560 B  ← 原厂 vendor ramdisk 里【没有】，唯一新增
```
（`hxchipset.ko` sha256 前 16 位 `a50c2430b06fabc1`，与实机 `/vendor/lib/modules/hxchipset.ko` 逐字节相同。）

同时确认原厂 vendor ramdisk 的 237 个里**一个触摸驱动都没有**（没有 `hxchipset`、`nvt36523_spi`、`focaltech`、`goodix`…），且 `modules.load.recovery` 也不含任何触摸驱动 ⇒ **原厂 recovery 是"无触摸"设计**（靠硬件键）。所以"recovery 里能用触摸"这件事**没有 OEM 先例**，是本轮新开的路径（风险见 §3.5）。

### 3.2 `hxchipset.ko` 依赖链【实测·`.modinfo` 原文】

```
name=hxchipset          size=607,560 B
depends=panel_event_notifier,nopmi-chg
softdep=pre: msm_drm
vermagic=5.15.74-ga0aa332d6eec-dirty SMP preempt mod_unload modversions aarch64
scmversion=g4be80beb8c5e
license=GPL   description=Himax_common driver
```
展开（原厂 `modules.dep` 与 `modules.softdep` 原话）：

| 模块 | 谁提供 | 在 recovery 列表里？ |
|---|---|---|
| `panel_event_notifier.ko`（40,624 B） | 原厂 `/lib/modules` | ✅（`modules.load.recovery` 中段） |
| `nopmi-chg.ko`（231,440 B）→ `softdep pre: sc8960x_charger mm8013c10_battery` | 原厂 `/lib/modules` | ✅（`modules.load.recovery` 里 `sc8960x_charger`/`mm8013c10_battery`/`nopmi-chg` 依次） |
| `msm_drm.ko`（softdep **pre**） | 原厂 `/lib/modules` | ✅（列表尾部） |
| SPI 控制器 `spi-msm-geni.ko`（166,352 B）→ dep `qcom_ipc_logging/minidump/smem` | 原厂 `/lib/modules` | ✅（`…/modules.dep`: `spi-msm-geni.ko: qcom_ipc_logging.ko minidump.ko smem.ko`） |
| GPIO/中断：`pinctrl-msm.ko`、`pinctrl-khaje.ko`、`pinctrl-spmi-gpio.ko` | 原厂 `/lib/modules` | ✅ |
| 触控 **固件**：`Himax_firmware.bin` / `Himax_mpfw.bin` / `hx_criteria.csv`（`request_firmware()` 按裸名请求，见 hxchipset.ko 字符串） | v2 已放 `vendor/firmware/`（261,120 / 261,120 / 44,482 B，取自实机 `/vendor/firmware`） | ✅ |

⇒ **触摸需要的新增 = `hxchipset.ko` 一个文件**；其余全在原厂 `/lib/modules` 里，并由 init 在 TWRP 之前加载好。

### 3.3 谁加载、按什么顺序【实测·两个加载器】

| 加载器 | 路径 | 本轮证据 |
|---|---|---|
| **AOSP `init`**（PID1，先跑） | `/lib/modules` + **`modules.load.recovery`**；也扫 `/vendor/lib/modules`（OF 的模块在 `/vendor/lib/modules/**1.1**/` 子目录，AOSP 的 kModuleDirs 只有 `/lib/modules`、`/vendor/lib/modules`、`/odm/lib/modules` 三处、不递归版本子目录【推断，但与本机原厂的加载结果一致】） | OF init 字符串：`/lib/modules`×5、`modules.load.recovery`×2、`/modules.load.recovery`@0x1a927、`/vendor/lib/modules`@0x1267c |
| **TWRP `recovery`**（后跑） | `/vendor/lib/modules` + `/1.1` + `.ko`（0x34a5c / 0x34a70 / 0x34a75）与 **`modules.load.twrp`**（0x4290d、`/modules.load.twrp`@0x464ee），底层是静态链进来的 **AOSP libmodprobe**（字符串：`Failed to insmod '`、`Loading soft pre-dep for '`、`is blocklisted`、`malformed modules.softdep at token`、`I:Modules Loaded: %d`、`I:Unable to open module directory: %s. Skipping`） | 见左；`twrp.modules.loaded` 属性再由 `init.recovery.qcom.rc` 触发 `/firmware` 挂载、`boot_adsp`、health HAL |

⇒ 顺序天然正确：**init 先起 msm_drm（→ card0、panel0-backlight、面板通电）→ TWRP 再只补 hxchipset**。
⇒ 也说明 **v2 那 590 B 的 `modules.dep` 是残缺的**：它给 `msm_drm.ko` 只写了 3 个依赖，而原厂 dep 是 11 个（缺 `spmi-pmic-arb`、`pinctrl-msm`、`qcom_iommu_util`、`msm_dma_iommu_mapping`、`secure_buffer`、`qcom-scm`、`minidump`、`smem` —— 这 8 个**都不在** `/vendor/lib/modules/1.1/` 里）。一旦 init 没先加载 msm_drm，TWRP 这条路也补不上。

### 3.4 触摸初始化条件（DT 全部取自**实机** `/sys/firmware/devicetree/base`）【实测】

```
节点  /soc/qcom,qupv3_0_geni_se@4ac0000/spi@4a80000/touch@0
compatible        = "himax,hxcommon\0novatek,NVT-ts-spi"
status            = ok
reg               = 0                      → CS0
spi-max-frequency = 0x00989680 = 10,000,000 → 10 MHz
himax,irq-gpio    = <&tlmm 0x50 0x01>      → GPIO 80, ACTIVE_HIGH
himax,rst-gpio    = <&tlmm 0x56 0x02>      → GPIO 86, ACTIVE_LOW
himax,display-coords = <0 1200 0 1920>     (0x2ee0 × 0x4b00)
himax,panel-coords   = <0 1200 0 1920>
himax,3v3-gpio       = (不存在)             → 无 GPIO 供电控制，靠常开电源轨
```
实机 `/proc/bus/input/devices`：`N: Name="himax-touchscreen"`、`N: Name="himax-stylus"`（`/devices/virtual/input/input2/input3`）。
权限：`/dev/input/* 0660 root input`（ueventd.rc），recovery 以 root 跑 → TWRP 能读 `event*`。

**固件通道**（容易漏的一条）：`ueventd.rc` 的 `firmware_directories /etc/firmware/ /odm/firmware/ /vendor/firmware/ /firmware/image/` + OF 的 `init.recovery.qcom.rc` `on early-init` 里 `write /proc/sys/kernel/firmware_config/force_sysfs_fallback 1` ⇒ `request_firmware("Himax_firmware.bin")` 会由 ueventd 在 `/vendor/firmware/` 命中。**这条是 v2 已经无意中配好的**（v2 把 3 个 Himax 文件放进了 `vendor/firmware/`）。

### 3.5 结论：能起，但有一处**未证**的时序风险

- 有利：模块/固件/DT/权限/SPI 控制器全齐；`hxchipset` 的 3 个依赖都在 init 阶段就位；`softdep pre: msm_drm` 保证 msm_drm 先到。
- 风险【未证 1】：TWRP **很可能在 `gr_init()` 之前**就加载模块（`I:Modules Loaded: %d` 是早期日志；本轮没有 recovery 实测日志，属【推断】），此时面板可能**还没被 OF 自己的 modeset 点亮**。若触摸 IC 的 VCC/复位依赖面板已经上电，probe 会失败（`[HXTP][ERROR] request firmware fail` / `unable to request gpio` / IC ID 读不到），且**不会重试**。
  - 缓解 A（零成本）：原厂 ABL 通常保留 continuous splash，进 recovery 时面板往往已经亮着 → probe 有机会成功。
  - 缓解 B（推荐兜底）：进 recovery 后 `adb shell insmod /vendor/lib/modules/1.1/hxchipset.ko` 再 `getevent -pl`；失败就先 `getevent` 确认面板是否已亮（`/sys/class/backlight/panel0-backlight/brightness > 0`）。
- 风险【未证 2】：`libmodprobe` 的**失败语义**。`LoadModulesFromList` 一旦某个模块 `insmod` 失败（v2 现状里 `msm_drm.ko` 是**已加载**的，会 `EEXIST` 失败），后续模块可能整条不再加载 ⇒ **`hxchipset` 永远轮不到**。这是 §4 里 C2 那条改动存在的唯一理由。

### 3.6 触摸不可用时的兜底（够不够完成"刷包/挂载/重启"）

**够。** 三条独立通道：
1. **音量键 + 电源键**：TWRP 原生键导航；震动反馈可当确认（`vibratorfeature-hal-service` + `leds/vibrator` trigger）。
2. **adb shell**（root）：`dd` 写分区、`mount`、`twrp` CLI、`/sbin` 里有 `magiskboot`/`busybox`/`gnutar`/`lz4` 全套。
3. **openrecoveryscript**：`twrp` CLI 支持 `--help`，可直接跑脚本化流程。

⇒ 触摸只是"体验项"，不是"能不能刷机"的阻塞项。

---

## 4. 改动清单（可落地）

> 基线 = v2 成品（`E:\rom\work\of\recovery_of_tb331fc_v2.img` 的 ramdisk / `E:\rom\work\of\tools\build_v2.py` 的 `build_ramdisk()`）。
> 全部改动都在 **OF ramdisk 内部**，不碰内核、不碰分区表。

### C1（显示，必做，1 行）— 补背光

| 项 | 内容 |
|---|---|
| 文件 | `init.recovery.qcom.rc`（ramdisk 根，当前 51 行 / 1,380 B） |
| 动作 | 在现有 `on init` 段（第 17–18 行，目前只有 `start boot-hal-1-2`）追加一行 |
| 内容 | `    write /sys/class/backlight/panel0-backlight/brightness 200` |
| 来源 | **原厂 recovery ramdisk 的 `init.recovery.qcom.rc` 第 30 行同款**（`on init` → `write /sys/class/backlight/panel0-backlight/brightness 200`），逐字符照抄 |
| 证据 | 实机 `/sys/class/backlight/panel0-backlight` 存在（`max_brightness=255`，路径挂在 `…/5e00000.qcom,mdss_mdp/backlight/` ⇒ 由 **msm_drm 注册**）；`libminuitwrp.so` 硬编码同一路径 @0x12bc6；原厂 recovery 就是靠这行点屏 |
| 风险 | **低**。若 msm_drm 未起则该 sysfs 文件不存在，init 的 `write` 失败只打日志、不致命。副作用为零（TWRP 后面自己也会写亮度） |

### C2（触摸，必做，1 个目录里的 4 个文件）— 让 TWRP 只加载 `hxchipset.ko`

| 项 | 内容 |
|---|---|
| 目录 | `vendor/lib/modules/1.1/` |
| 动作 | ① 只保留 `hxchipset.ko`（删掉另外 14 个 .ko）；② `modules.load` / `modules.load.recovery` / `modules.load.twrp` **三份都改成单行** `hxchipset.ko\n`；③ `modules.dep` 改成单行 `hxchipset.ko:\n`；④ `modules.softdep` 删除（或改成 `softdep hxchipset pre: msm_drm` 并接受一条"模块不在本目录"的告警）；⑤ `modules.alias` / `modules.blocklist` 可保留（无害），也可删 |
| 来源 | 三个 list 名与目录名都是**二进制里读出来的**：`recovery` 的 `/vendor/lib/modules`(0x34a5c) + `/1.1`(0x34a70) + `.ko`(0x34a75)、`modules.load.twrp`(0x4290d / `/modules.load.twrp`@0x464ee)；`init` 的 `modules.load.recovery`(0x154dc) |
| 证据 | ① 14 个与原厂 `/lib/modules` **逐字节相同** ⇒ OF 再带一遍纯属冗余，且它们由 init 先加载；② v2 的 590 B `modules.dep` 给 msm_drm 只写 3 个依赖，原厂 dep 是 11 个，缺的 8 个**不在本目录** ⇒ 一旦 libmodprobe 走依赖解析就会失败；③ `libmodprobe` 的 `LoadModulesFromList` 是 fail-fast 语义风险（见 §3.5 风险 2） |
| 风险 | **中**。收益：insmod 列表里不再有"必然失败"的项（`msm_drm` 已加载 → `EEXIST`），hxchipset 一定能轮到；代价：若 **init 因故没加载 msm_drm**，触摸也不会自己补（但那种情况下屏也是黑的，触摸本来就无意义） |

### C3（可选，-6.3 MB）— 清理冗余

`vendor/lib/modules/1.1/` 删 14 个 .ko（6,936,400 − 607,560 = **6,328,840 B**）。纯收益，无功能影响（与 C2 同一次操作顺带完成）。

### 不是"改动"但必须守住的三个约束

| 约束 | 理由 |
|---|---|
| `vendor_boot_b` 的 **vendor ramdisk 段必须是原厂内容**（MODE=2 的 split 镜像保留了；MODE=1/3 也走原厂 vendor_boot） | `/lib/modules`（237 个 .ko + `modules.load.recovery`）是**显示链的唯一来源**（§2.3） |
| `dtbo_b` 必须是**原厂 `dtbo.img`** | 面板节点 `qcom,mdss_dsi_panel_p255_hx83102j_fhd_video` 与触摸节点 `touch@0` **只在 dtbo 里**（`live_dtb.bin` 里 `himax`/`p255` 命中 0） |
| 不要给 `init.recovery.qcom.rc` 的 `on early-init` 加东西 | 那里已经有 `write /sys/fs/selinux/enforce 0` 和 `force_sysfs_fallback 1`（后者是触摸固件能加载的前提） |

---

## 5. 上机验证清单（进 recovery 后逐条判定，全部只读）

```sh
# ① 内核与 fb 事实
uname -a                                   # 期望 5.15.167-android13-5.15.167_r00-dirty
ls /dev/fb0                                # 期望 No such file（CONFIG_FB=n，可忽略）
cat /proc/modules | grep -E 'msm_drm|hxchipset|panel_event|spi_msm|pinctrl_msm|dispcc'
                                           # 期望 msm_drm 在；hxchipset 在（C2 生效的标志）

# ② 显示：card0 + 连接器 + 模式
ls -l /dev/dri                             # 期望 card0 (226,0)；无则 §2.4 的 1/2/3/4 条没过
cat /sys/class/drm/card0-DSI-1/status      # 期望 connected
cat /sys/class/drm/card0-DSI-1/modes       # 期望 1200x1920x90vid

# ③ 背光（C1 生效）
ls /sys/class/backlight/                   # 期望 panel0-backlight（msm_drm 注册的）；bkl-bl 是 ktz8866 的
cat /sys/class/backlight/panel0-backlight/brightness   # 期望 200（不是 0）

# ④ OF 图形后端到底选了谁（决定性一行）
grep -aE 'Using (drm|fbdev) graphics' /tmp/recovery.log
#   期望 "Using drm graphics."
#   若出现 "Using fbdev graphics." ⇒ 是 fallback 失败路径，必然黑屏（CONFIG_FB=n，fb0 不存在）

# ⑤ 触摸
getevent -pl | grep -iE 'himax|ABS_MT'      # 期望 himax-touchscreen + ABS_MT_POSITION_X/Y
dmesg | grep -iE 'hxchipset|himax|HXTP'     # 期望 "DT:gpio_irq=80, gpio_rst=86"、firmware 成功
#   失败补救：insmod /vendor/lib/modules/1.1/hxchipset.ko && getevent -pl | grep -i himax

# ⑥ 万一黑屏，走兜底前先确认 adb 可用
getprop sys.usb.config                      # 期望 adb
```

**判读铁律**（沿用 v2 §10）：`Using drm graphics.` + `connected` + `brightness=200` ⇒ 屏必须亮；三者都对还黑，问题在面板上电/背光 IC，不在 TWRP。

---

## 6. 未证与边界

1. **【未证】ABL 到底把哪块 ramdisk 交给内核**（决定 OF 的 `/init` 是否被采纳）。这是本报告之外、但决定 §2.4 条件 1/2 是否成立的前提；MODE=2 有 2026-10-24 实证前例。
2. **【未证】hxchipset 在 recovery 下的探测时序**（面板是否已上电）。见 §3.5，带兜底命令。
3. **【未证】libmodprobe 的 fail-fast 行为**：本轮只从字符串确认它确实是 AOSP libmodprobe，没有实机日志。C2 的改法使这条无关紧要。
4. 本轮**没有**刷机、没有 push、没有改 v1/v2 任何产物；设备侧只做了 `ls`/`cat`/`exec-out cat`。
5. 本轮**没有**分析 crypto/fstab/super 挂载（不在任务范围），只确认了 `twrp.flags` 51 行里**没有**图形相关键、`recovery.fstab` 56 行里 system/vendor 走 `avb` + `logical`。