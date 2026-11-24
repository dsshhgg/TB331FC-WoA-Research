# TB331FC（khaje / SM6225-AD）mainline Linux 移植 · 缺项归因与修复方案

生成时间：2026-11-24
分析对象：`D:\Desktop\linux-lenovo-tb331fc-main.zip`（Linux 6.14.0-rc5，已解压 `E:\rom\work\linux-src\`）
设备取证：adb `5e367954`（ZUI 16.0.544 / A14 / KSU root），只读查询，未改任何设备文件
铁律遵守：**未刷机、未改设备系统文件**，全部结论来自 PC 侧源码阅读 + 设备只读取证

标记约定：**【已核实】** = 有源码/配置/设备回显直接证据；**【需上机】** = 推断，必须真机确认后才能当作事实。

---

## 0. 全局前置发现（读这一节能省掉后面一半的返工）

### 0.1 这棵树的 `sm6225-lenovo-tb331fc.dts` 是 **dtc 反编译产物**，不是可维护源码

**【已核实】** `arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dts`（96,423 B / 4,287 行，zip 内同一文件同尺寸）特征：

- phandle 全是裸数字（`<0x28>`、`<0x4c>`、`<0x226>`），没有 `&tlmm` / `&rpmhcc` 这类 label
- 常量全是十六进制（`width = <0x4b0>` = 1200）
- 整个 `sm6225.dtsi` + `pm6125.dtsi` 已被**合并展开**进这一个文件
- 文件头部是 `/dts-v1/;` + `/ {`，不是 `#include "sm6225.dtsi"`

对比真正的上游源码 `sm6225-lenovo-tb128.dts` 只有 **700 行**、带 SPDX 头和 `Copyright (c) 2025, Ivaylo Ivanov`。

**后果**：这个文件能编译（dtc 接受数字 phandle），但**没法按 label 打补丁**，任何 `&uart3 { ... }` 式修改都要手工换算 phandle。维护成本极高。

**建议（本报告所有 DTS 片段都按这个前提写）**：不要继续改这 4,287 行 dump。以 `sm6225-lenovo-tb128.dts` 为骨架重建 `sm6225-lenovo-tb331fc.dts`，只把 TB331FC 的真实差异写成 override。差异清单见 §0.3。

### 0.2 这棵树里 **model / compatible / 固件路径全是 TB128 的**，从来没改成 TB331FC

**【已核实】** 三个独立证据：

| 位置 | 内容 | 应该是 |
|---|---|---|
| DTS:7 | `model = "Lenovo Tab M10 Plus 3rd gen"` | TB331FC / 小新 Pad 2024 |
| DTS:8 | `compatible = "lenovo,tb128", "qcom,sm6225", "qcom,sm6115"` | `lenovo,tb331fc`, ... |
| DTS:3135 | `firmware-name = "qcom/sm6225/LENOVO/TB128FU/adsp.mbn"` | `.../TB331FC/adsp.mdt` |
| DTS:2484 | `firmware-name = "qcom/sm6225/LENOVO/TB128FU/modem.mbn"` | （本机无 modem，可删） |

⚠️ 注意：**`qcom,msm-id` / `qcom,board-id` 不能用来区分这两台机器**。TB128 与 TB331FC 的 bootloader ID 完全相同：

```
tb128.dts:20-21   qcom,msm-id = <518 0x10000>;  qcom,board-id = <0x10022 0x0>;
设备实测           msm-id = 00 00 02 06 00 01 00 00  (0x206 0x10000)
                  board-id = 00 01 00 22 00 00 00 00 (0x10022 0x0)
tb331fc.dts:10-11 qcom,msm-id = <0x206 0x10000>; qcom,board-id = <0x10022 0x00>;
```

三者一致 ⇒ **board-id 匹配成功不代表选对了板级文件**。这是本移植最容易自欺的一条。

### 0.3 TB331FC 相对 TB128 的真实硬件差异（**【已核实】**，逐条来自设备回显）

设备 `/sys/bus/i2c/devices/*/name` 全量：

| bus | addr | name | 说明 | mainline DTS 有? |
|---|---|---|---|---|
| 0 | 0x08 | `i2c-pmic` | PM8008 | ✗ 缺 |
| 0 | 0x09 | `i2c-pmic` | PM8008 第二地址 | ✗ 缺 |
| 0 | 0x11 | `bkl-bl` | **KTZ8866 背光** | ✓ |
| 0 | 0x28 | `sn-nc` | 未知（见 §5） | ✗ |
| 0 | 0x34 | `aw883xx_smartpa` | **AW88166 #1** | ✓ |
| 0 | 0x35 | `aw883xx_smartpa` | **AW88166 #2** | ✓ |
| 0 | 0x42 | `fsa4480-i2c` | Type-C 音频开关 | ✓ |
| 0 | 0x6b | `sc89601d_slave` | **SC89601D 充电 IC** | ✗ 缺 |
| 1 | 0x34 | `aw883xx_smartpa` | **AW88166 #3** | ✓ |
| 1 | 0x35 | `aw883xx_smartpa` | **AW88166 #4** | ✓ |
| 1 | 0x55 | `mm8013c10` | 电量计 | ✓ |
| 1 | 0x6b | `sc89601d` | **SC89601D 充电 IC** | ✗ 缺 |
| 2 | 0x22 | `aw35615` | USB PD | ✗ 缺 |
| 2 | 0x4e | `rt1711h` | Type-C TCPC | ✓ |

设备 `dumpsys sensorservice` 实际传感器（29 颗全部经 **SSC / sensor DSP** 上报，**不在 AP 侧 i2c 上**）：

```
bmi3x0 Accelerometer / Gyroscope / Gyroscope-Uncalibrated   BOSCH ver:306
ltr578 Ambient Light Sensor                                 Lite-On ver:258
wake_gesture                                                ams
+ 22 颗 qualcomm 合成传感器（gravity / step_detect / tilt / motion_detect …）
```

设备 `/sys/bus/iio/devices/` 只有 6 个 AP 侧 IIO，全是充电/ADC/TypeC，**没有 accel/als**：

```
mm8013c10 | 1c40000.qcom,spmi:...:vadc@3100 | slave_chg | main_chg | nopmi_chg | rt1711h
```

### 0.4 设备固件盘点（**【已核实】**，决定"缺驱动还是缺固件"的关键）

| 路径 | 内容 | 对 mainline 的意义 |
|---|---|---|
| `/vendor/firmware/` | `aw883xx_acf.bin`、`novatek_ts_fw.bin`、`Himax_firmware.bin`、`venus*`、`a6xx_zap*`、`wlan/qca_cld/` | **`aw883xx_acf.bin` 正好是 mainline aw88166 驱动的默认 ACF 名** |
| `/vendor/firmware_mnt/image/` | `adsp.mdt` + `adsp.b00`…`adsp.b20`（192 个文件）、`bdwlan.*`、`modem.*` | **ADSP 固件齐全，只是 split 形式** |
| `/vendor/bt_firmware/image/` | `crbtfw11/20/21.tlv`、`crnv11/20/21.bin`、`apbtfw10/11`、`apnv10/11`、`cmbtfw10-13`、`cmnv10-13` | **`crbtfw21.tlv`+`crnv21.bin` 正是 WCN3990 的 mainline 默认名** |

> 一句话：**蓝牙和音频都不缺固件，缺的是"把固件放到 mainline 认识的名字和路径上"**。音频另外还缺编译开关和 machine driver。

### 0.5 当前 `.config` 的三个"整块缺失"（**【已核实】**）

```
# CONFIG_SOUND is not set          ← 整个 ALSA/ASoC 不存在，音频 0 可能
# CONFIG_MEDIA_SUPPORT is not set  ← 整个 V4L2/media 不存在，摄像头 0 可能
# CONFIG_QCOM_LLCC is not set      ← 无 LLC，影响性能/功耗
```

### 0.6 "显示能用"这件事需要重新定义（**【已核实】两条硬证据**）

用户报告的"GPU / 背光能用"是真的，但**大概率不是通过 DSI + panel 驱动**，理由：

1. **panel compatible 在 mainline 驱动里查不到。** DTS:2428 写 `compatible = "lenovo,p255-inx"`；mainline `panel-novatek-nt36523.c` 的 `of_device_id` 只有 4 个：
   `lenovo,j606f-boe-nt36523w` / `lenovo,tb128fu-boe-nt36523w` / `xiaomi,elish-boe-nt36523` / `xiaomi,elish-csot-nt36523`。
   ⇒ **panel 节点必然绑定失败**，`&mdss_dsi0` 拿不到 panel。

2. **DTS 里另有一条"不依赖 panel 驱动"的通路**：`chosen/framebuffer@5c000000` 的 `simple-framebuffer`，`.config` 里 `CONFIG_DRM_SIMPLEDRM=y`。这条路直接用 ABL 留下的帧缓冲，**不需要 panel 驱动**。

3. **分辨率对不上，进一步印证走的是 ABL 帧缓冲**：设备实测 **1200×1920**（`wm size`），DTS 写 **1200×2000**（`height = 0x7d0`）。若真是 nt36523 驱动在跑，分辨率会由 panel 描述表决定，不会出现这种 80 行偏差。

**这意味着**：
- "能用"= 固定分辨率、无模式设置、亮度只能靠 `ktz8866`（`CONFIG_BACKLIGHT_KTZ8866=y`，独立于 DRM，所以背光确实能调）
- 换分辨率 / 上 Wayland 合成器 / 需要 DSI 命令通道（如屏幕自刷新、部分触摸唤醒）都会撞墙
- 想真正把 DSI 打通，需要二选一：
  - **(a) 复用 tb128 的面板描述**：若 TB331FC 用的是同一块 BOE 屏，把 compatible 改成 `"lenovo,tb128fu-boe-nt36523w", "novatek,nt36523w"` 即可（0.25 人日，先试这个）
  - **(b) 新写 p255-inx 面板描述**：在 `panel-novatek-nt36523.c` 里加一条 `panel_desc`（分辨率 1200×1920、时序、初始化序列需从 Android 侧 DSI 参数取），约 2 ～ 3 人日

**【需上机】** 先用一条命令定性到底走哪条路：

```bash
dmesg | grep -iE "simpledrm|msm_dpu|msm-dsi|nt36523|panel|drm"
ls /sys/class/drm/            # 若只有 card0-DSI-1 且 modes 为空 → simpledrm
cat /sys/class/drm/card0-*/modes
```

> 这一条不在原任务的五个领域里，但**它决定了"已能用"的部分到底有多能用**，所以单列。

---

## 1. 蓝牙

### 1.1 现状证据

**【已核实】DTS 侧 —— 已经接好了，不用改结构**

`sm6225-lenovo-tb331fc.dts:1980-2004`：

```dts
serial@4a8c000 {                       /* uart3, BLSP QUP3 */
    compatible = "qcom,geni-uart";
    interrupts-extended = <0x01 0x00 0x14a 0x04 0x28 0x0b 0x02>;
    pinctrl-names = "default";
    pinctrl-0 = <0x57>;                /* = qup-uart3-active-state */
    status = "okay";

    bluetooth {
        compatible = "qcom,wcn3990-bt";
        vddio-supply  = <0x4c>;
        vddxo-supply  = <0x59>;
        vddrf-supply  = <0xa8>;
        vddch0-supply = <0xa9>;
        max-speed = <0x30d400>;        /* 3,200,000 bps */
        swctrl-gpios = <0x28 0x57 0x00>;   /* tlmm gpio 87 */
    };
};
```

pinmux 核对（DTS:914-944，phandle `0x57`）：`gpio8=CTS / gpio9=RTS / gpio10=TX / gpio11=RX`，`function = "qup3"` —— **正确**。

**【已核实】驱动侧 —— 齐全**

- `drivers/bluetooth/hci_qca.c:2716` → `{ .compatible = "qcom,wcn3990-bt", .data = &qca_soc_data_wcn3990 }`
- `hci_qca.c:2429` → `devm_gpiod_get_optional(&serdev->dev, "swctrl", GPIOD_IN)` ⇒ DT 的 `swctrl-gpios` 名字对得上
- `hci_qca.c:2407-2415` → `qca_init_regulators(...)` 用 `vddio/vddxo/vddrf/vddch0` 四路，与 DTS 提供的四路**数量与名字完全一致**

**【已核实】`.config` 侧 —— 基本够**

```
CONFIG_BT=y
CONFIG_BT_HCIUART=y
CONFIG_BT_HCIUART_SERDEV=y          ← serdev 挂到 geni-uart 必需
CONFIG_BT_HCIUART_H4=y
CONFIG_BT_HCIUART_QCA=y             ← wcn3990-bt 就在这个模块里
CONFIG_BT_QCA=y
CONFIG_SERIAL_DEV_BUS=y
CONFIG_BT_LE is not set             ← ⚠️ 见下
CONFIG_BT_RFCOMM is not set         ← ⚠️ 见下
CONFIG_BT_BNEP is not set           ← ⚠️ 见下
```

### 1.2 缺口归因

**根因只有一个：`/lib/firmware/qca/` 下没有 WCN3990 的 patch + NVM 文件。**

**【已核实】** 代码路径（`drivers/bluetooth/btqca.c`）：

- 驱动先读芯片的 `soc_ver`，算 `rom_ver`（`btqca.c:802-808`）
- **DT 没写 `firmware-name` 时**走默认名（`btqca.c:815-861` 与 `877-936`）：
  ```c
  case QCA_WCN3990:
      snprintf(config.fwname, ..., "qca/crbtfw%02x.tlv", rom_ver);   /* patch */
      snprintf(config.fwname, ..., "qca/crnv%02x%s.bin", rom_ver, variant); /* NVM */
  ```
- 设备上正好有 `crbtfw21.tlv` + `crnv21.bin` ⇒ **`rom_ver == 0x21`**

所以：**不是缺驱动、不是缺 DTS 接线、不是 UART 没通，是固件文件名/路径对不上。**

> 注意 `hci_qca.c:2348` 的 `device_property_read_string_array(..., "firmware-name", ...)`：DTS **没写**，驱动就用上面那套默认名。这是**好事** —— 不用改 DTS 就能生效，只要把文件放对。

### 1.3 具体改法

**Step 1（必做，预计 10 分钟）：拷固件**

```bash
# 在 mainline 根文件系统里，从 Android 只读拷出（不要改设备）
mkdir -p /lib/firmware/qca
adb pull /vendor/bt_firmware/image/crbtfw21.tlv /tmp/
adb pull /vendor/bt_firmware/image/crnv21.bin  /tmp/
cp /tmp/crbtfw21.tlv /lib/firmware/qca/crbtfw21.tlv
cp /tmp/crnv21.bin  /lib/firmware/qca/crnv21.bin
```

> 若 `dmesg` 里出现的 `rom_ver` 不是 `21`（例如 `22`），就把对应 `crbtfw22.tlv`/`crnv22.bin` 放进去；设备上 `cr*` 只有 11/20/21 三组，21 的可能性最高。**以 dmesg 打印的文件名为准，不要猜。**

**Step 2（建议）：补 3 个 `.config` 行**

```diff
-# CONFIG_BT_LE is not set
+CONFIG_BT_LE=y
-# CONFIG_BT_RFCOMM is not set
+CONFIG_BT_RFCOMM=y
-# CONFIG_BT_BNEP is not set
+CONFIG_BT_BNEP=y
```

理由：WCN3990 是 BT 5.x 双模芯片，`BT_LE=n` 时 BlueZ 无法做 LE 扫描/配对，绝大多数现代外设（BLE 键鼠、耳机 LE Audio、手环）直接不可用；`RFCOMM` 影响 SPP/HFP 类 profile。这三行不影响内核能否 probe，但影响"能不能真的连上东西"。

**Step 3（仅在 Step 1 无效时）：显式指定固件名**

如果默认名探测失败，可在 `bluetooth` 节点加（源 DTS 写法，基于 `&uart3`）：

```dts
&uart3 {
	status = "okay";
	bluetooth: bluetooth {
		compatible = "qcom,wcn3990-bt";
		firmware-name = "qcom/sm6225/LENOVO/TB331FC/crbtfw21.tlv";
		/* NVM 名由驱动把扩展名换成 .bin 自动推导（btqca.c:289-303） */
		vddio-supply  = <&pm6125_l9>;
		vddxo-supply  = <&pm6125_l16>;
		vddrf-supply  = <&vreg_l2c_1p3>;   /* TB128 上游是注释掉的，TB331FC 待确认 */
		vddch0-supply = <&vreg_l10c_3p3>;
		max-speed = <3200000>;
		swctrl-gpios = <&tlmm 87 GPIO_ACTIVE_HIGH>;
	};
};
```

（`firmware-name` 只写 patch 那一个文件即可，NVM 由 `qca_get_alt_nvm_file()` 把 `.tlv` 换 `.bin` 得到。）

### 1.4 验证方法

```bash
# 1) 驱动有没有 probe
dmesg | grep -iE "hci_qca|qca|bluetooth|wcn3990"
#    期望看到 "QCA Downloading qca/crbtfw21.tlv" 然后 "QCA Downloading qca/crnv21.bin"

# 2) serdev 有没有绑上
ls -l /sys/bus/serial/devices/
#    期望出现 .../serial0-0 之类，且 driver -> hci_qca

# 3) HCI 设备出现
hciconfig -a          # 或 bluetoothctl list
#    期望 hci0，BD Address 非 00:00:00:00:00:00

# 4) 真能扫到东西（终极判据）
bluetoothctl --timeout 20 scan on
```

失败时的定位顺序（每一步都能把范围砍一半）：

| 现象 | 说明 | 下一步 |
|---|---|---|
| `/sys/bus/serial/devices/` 空 | serdev 没绑 | 查 `dmesg \| grep geni`、确认 `CONFIG_SERIAL_DEV_BUS=y`、确认 `serial@4a8c000 status="okay"` |
| 有 serdev 无 hci0，dmesg 报 `Failed to request file` | 固件路径/名字不对 | 按 dmesg 打印的文件名放文件 |
| 有 hci0 但 `BD Address: 00:00:00:00:00:00` | NVM 里没 MAC | 拷 `crnv21.bin`（NVM 含 BD 地址） |
| 有 hci0，扫描超时无结果 | RF 未上电 / swctrl 极性 | 查 `vddrf`/`vddch0` 稳压器是否真的被 enable；试 `swctrl-gpios` 极性翻转 |

### 1.5 工作量

| 项 | 人日 |
|---|---|
| 拷固件 + 验证 | 0.25 |
| 补 `.config` 三行 + 重编 | 0.25 |
| 若需改 DTS `firmware-name`/稳压器 | 0.5 |
| **合计** | **0.5 ～ 1.0 人日** |

**结论：这是全表性价比最高的一项。** 硬件、驱动、DTS、pinmux、稳压器全部就位，只差两个文件。**【已核实】** 部分占比极高（唯一的不确定性是 `rom_ver` 到底是 0x21 还是别的，dmesg 会直接告诉你）。

---

## 2. 音频（扬声器）

### 2.1 现状证据

**【已核实】DTS 侧 —— codec 节点齐，但整个 sound 卡片不存在**

4 颗 AW88166 分挂两条 i2c（`DTS:1835/1847` 在 `i2c@4a84000`，`DTS:1904/1916` 在 `i2c@4a88000`）：

```dts
speaker@34 {                                    /* i2c@4a84000 */
    compatible = "awinic,aw88166", "awinic,aw883xx_smartpa";
    reg = <0x34>;
    reset-gpios = <0x28 0x55 0x01>;
    interrupts = <0x67 0x08>;
    sound-channel = <0x03>;                     /* ⚠️ 属性名错，见 2.3 */
    #sound-dai-cells = <0x00>;
    firmware-name = "aw883xx_acf.bin";
    status = "okay";
};
/* 另外三颗：i2c@4a84000 的 0x35(ch2)、i2c@4a88000 的 0x34(ch1)、0x35(ch0) */
```

DSP 链路（`DTS:3123-3211`）—— **全部 `status = "okay"`，结构完整**：

```
remoteproc@a400000  compatible = "qcom,sm6115-adsp-pas"   status = okay
  └ glink-edge label = "lpass"  remote-pid = 2
      └ apr  compatible = "qcom,apr-v2"  domain = 4
          ├ service@3  q6core
          ├ service@4  q6afe   └ dais(q6afe-dais) + clock-controller(q6afe-clocks)
          ├ service@7  q6asm   └ dais: dai@0 / dai@1 / dai@2
          └ service@8  q6adm   └ routing(q6adm-routing)
```

LPI pinctrl 控制器存在（`DTS:1198` `qcom,sm6115-lpass-lpi-pinctrl`），但**没有任何 MI2S pin state 定义** —— 引脚还没 mux。

**整个 DTS 里没有 `/ { sound { ... } }` 节点**（节点清单已全量枚举，无 `sound`）。⇒ 没有 machine driver 绑定，声卡不可能注册。

**【已核实】`.config` 侧 —— 致命**

```
# CONFIG_SOUND is not set
```

**整个 ALSA/ASoC 子系统没编进内核。** 这一条单独就足以解释"没有声音"，且优先级高于所有其它音频问题。

**【已核实】驱动侧 —— 全部现成**

| 组件 | mainline 位置 | 结论 |
|---|---|---|
| AW88166 codec | `sound/soc/codecs/aw88166.c`，`compatible = "awinic,aw88166"` / `"awinic,aw883xx_smartpa"` | **DTS 里两个 compatible 都被支持** |
| AW88166 Kconfig | `SND_SOC_AW88166`（selects `SND_SOC_AW88395_LIB`） | 只需打开 |
| ADSP remoteproc | `qcom,sm6115-adsp-pas` 在 `qcom_q6v5_pas.c:1447` | 支持 |
| QDSP6 前端 | `sound/soc/qcom/qdsp6/{q6afe,q6asm,q6adm,q6routing,q6core}.c` | 支持 |
| machine driver | `sound/soc/qcom/` 只有 apq8016/apq8096/sc7180/sc7280/sc8280xp/sdm845/sm8250/x1e80100 | **没有 sm6115/sm6225** ← 唯一的驱动缺口 |

**【已核实】固件侧**

- `/vendor/firmware/aw883xx_acf.bin` 存在。`aw88166.c:1711-1717`：
  ```c
  if (device_property_read_string(dev, "firmware-name", &fw_name) < 0)
      fw_name = AW88166_ACF_FILE;
  ret = request_firmware(&cont, fw_name, dev);
  if (ret && strcmp(fw_name, "aw883xx_acf.bin") != 0) {
      fw_name = "aw883xx_acf.bin";     /* 兜底名正好就是设备上这个文件 */
      ...
  }
  ```
  ⇒ **ACF 不用改名，放 `/lib/firmware/aw883xx_acf.bin` 即可**（或走 `firmware-name` 显式指定）。
- ADSP：设备有 `adsp.mdt` + `adsp.b00`…`adsp.b20`。mainline `mdt_loader.c:50` 的段名规则是
  `sprintf(seg_name + strlen(fw_name) - 3, "b%02d", segment)` —— 即把固件名最后 3 字符换成 `b00`/`b01`/…
  ⇒ **给 `firmware-name = ".../adsp.mdt"` 时，段文件正好叫 `adsp.b00`…，与设备文件名一字不差。**
  而当前 DTS 写的是 `.../TB128FU/adsp.mbn`：**目录错（TB128FU）+ 头部文件名错（设备只有 .mdt，没有 .mbn）**，双重必失败。

### 2.2 缺口归因（按修复顺序排列，四层）

| # | 缺口 | 证据 | 修它需要 |
|---|---|---|---|
| **A1** | `# CONFIG_SOUND is not set` | `.config` | 改 config |
| **A2** | ADSP 固件路径写的是 `TB128FU/adsp.mbn`，设备上只有 `TB331FC/` 下的 `adsp.mdt`+`adsp.b00..b20` | DTS:3135 vs 设备 `ls` | 改 DTS + 拷固件 |
| **A3** | 没有 `/sound` 节点，没有 sm6115 machine driver | DTS 节点清单 + `sound/soc/qcom/` 目录 | **写新驱动** |
| **A4** | 4 颗 AW88166 的 DTS 属性名用的是 Android 私有名 `sound-channel`，mainline 驱动读 `awinic,audio-channel` | `aw88166.c:1853` `of_property_read_u32(np, "awinic,audio-channel", ...)` | 改 DTS |
| **A5** | LPI MI2S 引脚没有 pinmux state | DTS `pinctrl@a7c0000` 无子节点 | 加 pinmux（需确认实际引脚） |

> A1→A2 是"能不能启动 ADSP"，A3→A5 是"ADSP 起来后声音从哪出来"。**建议分两个里程碑做，不要一次上。**

### 2.3 具体改法

#### 里程碑 1：先让 ADSP 起来（不追求出声，1 人日）

```diff
-# CONFIG_SOUND is not set
+CONFIG_SOUND=y
+CONFIG_SND=y
+CONFIG_SND_SOC=y
+CONFIG_SND_SOC_QCOM=y
+CONFIG_SND_SOC_QDSP6=y
+CONFIG_QCOM_APR=y            # 当前是 =m，随内核一起更稳
+CONFIG_QCOM_Q6V5_PAS=y       # 当前是 =m
+CONFIG_QCOM_Q6V5_ADSP=y      # 当前是 =m
```

```bash
# 固件（不改设备，只 pull 到 PC 再推到 mainline rootfs）
mkdir -p /lib/firmware/qcom/sm6225/LENOVO/TB331FC
adb pull /vendor/firmware_mnt/image/ /tmp/fwimg/
cp /tmp/fwimg/image/adsp.mdt /lib/firmware/qcom/sm6225/LENOVO/TB331FC/
cp /tmp/fwimg/image/adsp.b*  /lib/firmware/qcom/sm6225/LENOVO/TB331FC/
cp /vendor/firmware/aw883xx_acf.bin /lib/firmware/     # adb pull 先
```

DTS 修正（源 DTS 写法）：

```diff
-			firmware-name = "qcom/sm6225/LENOVO/TB128FU/adsp.mbn";
+			firmware-name = "qcom/sm6225/LENOVO/TB331FC/adsp.mdt";
```

验证：

```bash
cat /sys/class/remoteproc/remoteproc*/state     # 期望 running
dmesg | grep -iE "adsp|q6v5|remoteproc|glink|apr"
# 期望：adsp started、glink/apr 通道建立、q6afe/q6asm/q6adm probe 成功
```

**里程碑 1 单独就有价值**：ADSP 起来后，`apr`/`q6afe` 会 probe，后面 A3/A5 才有地基。

#### 里程碑 2：最小出声（单颗 amp、单声道、能 `aplay` 一个 wav，3～5 人日）

**(a) 修 A4 —— 属性名**

```diff
-				sound-channel = <0x03>;
+				awinic,audio-channel = <3>;
```

四颗分别 `<3>` / `<2>` / `<1>` / `<0>`（保持现在的通道分配不变）。

**(b) 修 A3 —— 写 machine driver**

`sound/soc/qcom/sm6115.c`（新文件，~250 行，参照 `sound/soc/qcom/sm8250.c` 的骨架，但**不要**照抄它的 wsa883x/wcd938x 链路）：

- `compatible = "lenovo,tb331fc-sndcard"`（或更通用的 `"qcom,sm6115-sndcard"`）
- DAI link 1：`q6asm-dai`（playback，`q6asm.h` 的 `PRIMARY_MI2S_RX`）→ `q6afe-dai`
- DAI link 2：`q6afe-dai`（`PRIMARY_MI2S_RX`）→ `aw88166`（`awinic,aw88166`）
- `SND_SOC_DAILINK_DEFS` + `snd_soc_card` + `devm_snd_soc_register_card`
- 时钟：`q6afe-clocks` 提供 MI2S bit clock

DTS 加：

```dts
/ {
	sound {
		compatible = "lenovo,tb331fc-sndcard";
		model = "TB331FC";
		#address-cells = <1>;
		#size-cells = <0>;

		mm1-dai-link {
			link-name = "MultiMedia1";
			cpu { sound-dai = <&q6asmdai MSM_FRONTEND_DAI_MULTIMEDIA1>; };
		};

		pri-mi2s-playback-dai-link {
			link-name = "Primary MI2S Playback";
			cpu { sound-dai = <&q6afedai PRIMARY_MI2S_RX>; };
			platform { sound-dai = <&q6routing>; };
			codec { sound-dai = <&speaker_top_left>; };   /* 先只接 1 颗 */
		};
	};
};
```

**(c) 修 A5 —— MI2S pinmux**

**【需上机】** 引脚号目前未知。两种取法：

1. 从 vendor 内核 DTS 取（若有）：`git grep -n "mi2s\|lpi_i2s" -- arch/arm64/boot/dts/vendor/qcom/`
2. 设备上读现役 pinmux：
   ```bash
   adb shell 'cat /sys/kernel/debug/pinctrl/*/pinmux-pins' | grep -iE "i2s|mi2s|lpi"
   ```
   LPI 引脚在 SM6225 上映射到 `lpi_tlmm`（`pinctrl@a7c0000`，19 个 pin，`DTS:1205` `gpio-ranges = <0x2a 0x00 0x00 0x13>`）。

补丁形态：

```dts
&lpass_tlmm {
	mi2s_0_active: mi2s-0-active-state {
		/* 待填：clk / ws / d0 / d1，function = "mi2s0" */
		pins = "gpio??";
		function = "mi2s0";
		drive-strength = <8>;
		bias-disable;
	};
};
```

验证：

```bash
cat /proc/asound/cards                 # 期望出现一张 card
aplay -l                               # 期望有 playback device
aplay -D hw:0,0 -f S16_LE -r 48000 -c 2 /tmp/test.wav
dmesg | grep -iE "aw88166|asoc|snd"
```

### 2.4 验证方法（分阶段）

| 阶段 | 判据 | 命令 |
|---|---|---|
| ADSP 活 | `running` | `cat /sys/class/remoteproc/remoteproc*/state` |
| APR 通 | q6afe/q6asm/q6adm 有 platform driver | `ls /sys/bus/apr/devices/` |
| codec probe | 4 个 `aw88166` 有 driver | `ls -l /sys/bus/i2c/devices/0-0034/driver` |
| 声卡注册 | card 出现 | `cat /proc/asound/cards` |
| 出声 | 扬声器响 | `aplay -D hw:0,0 ...` |
| 四路都响 | 分别指定 channel | 逐步把 codec DAI 加进 DAI link |

### 2.5 工作量

| 项 | 人日 |
|---|---|
| A1 `.config` + A2 固件路径 → ADSP running | 1.0 |
| A4 属性名修正 | 0.25 |
| A3 新写 sm6115 machine driver（最小单路） | 3.0 |
| A5 MI2S pinmux（含引脚定位） | 1.0 |
| 扩展到 4 颗 / TDM 通道对齐 | 2.0 ～ 4.0 |
| **合计（最小出声）** | **3 ～ 5 人日** |
| **合计（四扬声器全通）** | **8 ～ 12 人日** |

---

## 3. 电源管理

### 3.1 现状证据

**【已核实】DTS 侧 —— 骨架齐，缺充电 IC**

已有且 okay：`rpmh-regulator`（`regulators-0` + `s6/s7/s8/l1..l24`）、`cpufreq@f521000`（`qcom,sm6115-cpufreq-hw`）、`opp-table`（CPU ×2 cluster + GPU ×11 + QUP + MDSS + DSI）、`power-domain-cpu0..7` + `power-domain-cpu-cluster0/1`、`idle-states`（`cpu-sleep-0-0`/`1-0`、`cluster-sleep-*`）、`thermal-zones`（14 个 zone）、`battery@55`（`mitsumi,mm8013`）、`battery`（`simple-battery`）、`rt1711h`（TypeC）。

**缺**：
- `sc89601d` 充电 IC（设备 i2c 0x6b ×2，DTS 里完全没有）
- `aw35615` USB PD（设备 i2c-2 0x22）
- `pm8008`（设备 i2c 0x08/0x09）
- `# CONFIG_QCOM_LLCC is not set`

**【已核实】`.config` 侧 —— 大部分已开**

```
CONFIG_SUSPEND=y                        CONFIG_PM_GENERIC_DOMAINS=y
CONFIG_PM_GENERIC_DOMAINS_SLEEP=y       CONFIG_PM_GENERIC_DOMAINS_OF=y
CONFIG_CPU_FREQ=y                       CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y
CONFIG_CPUFREQ_DT=y                     CONFIG_CPUFREQ_DT_PLATDEV=y
CONFIG_ARM_QCOM_CPUFREQ_HW=y            CONFIG_ARM_QCOM_CPUFREQ_NVMEM=y
CONFIG_PM_DEVFREQ=y                     CONFIG_DEVFREQ_GOV_SIMPLE_ONDEMAND=y
CONFIG_PM_OPP=y                         CONFIG_QCOM_RPMH=y
CONFIG_QCOM_RPMHPD=y                    CONFIG_REGULATOR_QCOM_RPMH=y
CONFIG_QCOM_TSENS=y                     CONFIG_THERMAL=y / THERMAL_OF=y
CONFIG_CPU_THERMAL=y                    CONFIG_CPU_FREQ_THERMAL=y
CONFIG_POWER_SUPPLY=y                   CONFIG_FUEL_GAUGE_MM8013=y     ← 电量计有了
CONFIG_TYPEC_TCPM=y                     CONFIG_TYPEC_RT1711H=y
CONFIG_TYPEC_MUX_FSA4480=m
# CONFIG_QCOM_LLCC is not set           ← 缺
# CONFIG_CHARGER_MANAGER is not set     ← 缺（充电框架）
# CONFIG_CHARGER_QCOM_SMBB is not set
（没有任何 SC89601x 驱动）
```

**【已核实】设备侧现状（作为"应该长成什么样"的参照）**

```
/sys/class/power_supply/  →  battery  bba  bbc  bms  usb
/sys/devices/system/cpu/cpu0/cpufreq/  →  scaling_cur_freq / scaling_available_frequencies / scaling_governor 全在
/sys/class/thermal/  →  cooling_device0..26+（14 个 thermal zone 对应的 cooling device 都在）
```

### 3.2 缺口归因 —— 把"还得搞搞"拆成 5 个可测项

| # | 可测项 | 现状 | 缺口性质 | 优先级 |
|---|---|---|---|---|
| **P1** | CPU 变频是否工作 | `ARM_QCOM_CPUFREQ_HW=y` + `cpufreq@f521000` + opp-table 齐 | **可能已经能用，只是没测过** | 先测 |
| **P2** | 能否 suspend | `CONFIG_SUSPEND=y`，DTS 有 idle-states | 缺 `qcom,rpmh-rsc` 唤醒配置 / 外设 runtime PM，**大概率挂不住** | 高 |
| **P3** | 待机耗电 | 依赖 P2 | 需 P2 成立后才有意义 | 中 |
| **P4** | 充电是否识别 | **没有 sc89601d 驱动，没有 DTS 节点** | **需要新写驱动** | 中 |
| **P5** | 电量显示 | `mm8013` 驱动 + DTS + config 全齐 | **可能已经能用** | 先测 |

### 3.3 具体改法

#### P1 / P5：先测，别先改（0.25 人日）

```bash
# P1 CPU 变频
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq
cat /sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq
# 压一下看频率是否动
yes > /dev/null & sleep 5; cat /sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq; kill %1

# P5 电量
cat /sys/class/power_supply/*/uevent
```

若 `cpufreq` 目录不存在 → 查 `dmesg | grep -i cpufreq`，多半是 `opp-table` 与 `nvmem-cells`（`qcom,opp-fuse-level`）不匹配，属 DTS 细节。

#### P2：suspend（1 ～ 2 人日，先做"能不能进"再做"能不能醒"）

```bash
cat /sys/power/state                 # 期望含 "mem" 或 "freeze"
cat /sys/power/mem_sleep             # 期望 [s2idle] 或 deep
echo freeze > /sys/power/state       # 先试 freeze（最温和）
echo mem > /sys/power/state          # 再试 mem
```

**【需上机】** 常见失败点与对策：

| 现象 | 原因 | 改法 |
|---|---|---|
| `echo mem` 立刻返回、`dmesg` 有 `PM: Some devices failed to suspend` | 某设备 `-EBUSY` | 按 dmesg 里的 device 名逐个加 `runtime PM` 或 `wakeup` 配置 |
| 挂起后无法唤醒 | `pwrkey` 没设 `wakeup-source` | DTS `pon@800/pwrkey { wakeup-source; }` |
| 挂起即重启 | 稳压器/时钟在 suspend 中被关 | 关键 regulator 加 `regulator-always-on`（先保证能醒，再优化功耗） |
| `mem_sleep` 只有 `s2idle` | 没有 `PSCI SYSTEM_SUSPEND` 或 RPMh sleep 未配 | 查 `psci` 节点 + `rpmhpd` |

#### P4：充电识别（3 ～ 5 人日，唯一需要写驱动的项）

**【已核实】** mainline 里**没有** SC89601D 驱动（`grep -ri sc89601` 全树无命中；`drivers/power/supply/` 里只有 bq25890 / bq25980 / smb2 等）。

三条路，按成本排：

| 方案 | 做法 | 成本 | 结果 |
|---|---|---|---|
| **① 只读电量，不管充电控制**（推荐先做） | 只用 `mm8013`（已有驱动 + DTS + config），`/sys/class/power_supply/` 出 battery，电量能显示；充电状态读不到 | 0 人日 | 桌面能显示电量，插拔充电器不反映 |
| **② 新写 `sc89601d` 驱动** | 参照 `drivers/power/supply/bq25890_charger.c`（同为 I2C 开关充电器，寄存器模型接近），~500 行 + DTS 节点 + `CONFIG_CHARGER_SC89601D` | 3 ～ 5 人日 | 完整 charging/battery 状态 |
| **③ 用 PMIC 侧 | PM6125 的 `adc@3100` + `adc-tm@3500` 已 in DTS，可读 VBUS/电池温度 | 1 人日 | 只能看电压温度，不能看充电状态 |

DTS 节点（方案②，i2c@4a84000 下）：

```dts
&qupv3_i2c0 {          /* = i2c@4a84000 */
	charger@6b {
		compatible = "sc,sc89601d";
		reg = <0x6b>;
		interrupt-parent = <&tlmm>;
		interrupts = <0x67 IRQ_TYPE_EDGE_FALLING>;
		/* 具体属性取决于驱动实现：otg-vbus / charge-current-limit 等 */
	};
};
```

#### 建议的 `.config` 增量

```diff
+CONFIG_QCOM_LLCC=y            # sm6115 有 LLCC，开了对功耗/性能有正面影响
+CONFIG_CHARGER_MANAGER=y      # 若走方案②
+CONFIG_CHARGER_SC89601D=y     # 需先写驱动
```

### 3.4 验证方法（一张表，照抄即用）

```bash
# P1
for c in 0 4; do cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq; done
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors

# P2
cat /sys/power/state; cat /sys/power/mem_sleep
echo freeze > /sys/power/state && dmesg | tail -30
echo mem    > /sys/power/state && dmesg | tail -30
cat /sys/power/suspend_stats/success   # 成功次数
cat /sys/power/suspend_stats/fail      # 失败次数

# P3
# 记录 suspend 前后电量与时间：读 /sys/class/power_supply/*/capacity
# 目标：飞行模式、亮度最低、熄屏，8 小时掉电 < 5%

# P4
cat /sys/class/power_supply/*/uevent
# 期望看到 status=Charging/Discharging、online=1/0、current_now、voltage_now

# P5
cat /sys/class/power_supply/*/capacity
```

### 3.5 工作量

| 项 | 人日 |
|---|---|
| P1 + P5 实测（可能零改动） | 0.25 |
| P2 suspend 打通 | 1 ～ 2 |
| P3 待机耗电调优 | 2 ～ 4 |
| P4 充电（方案① 0 / 方案② 3-5 / 方案③ 1） | 0 ～ 5 |
| `CONFIG_QCOM_LLCC=y` + 回归 | 0.5 |
| **合计** | **1 ～ 4 人日（不含充电驱动）** / **4 ～ 8 人日（含）** |

---

## 4. 摄像头

### 4.1 现状证据

**【已核实】DTS 侧 —— 完全没有摄像头节点**

全量节点枚举后，与 camera 相关的只有 3 个**非功能**节点：

```
DTS:3518  camera-thermal          （thermal zone，纯温度）
DTS:3995  cam_cci0                （pinctrl state，没有对应控制器节点）
DTS:4022  camera_therm_default    （pinctrl state）
DTS:4061  gcc_camss_top_gdsc      （gdsc 电源域引用）
```

**没有 `camss`、没有 `cci`、没有 `csiphy`、没有 sensor / eeprom / actuator 节点。**

`sm6225.dtsi`（81 KB 上游源码）里同样只有 `camera-thermal` 一个 —— 说明 **mainline 从未给 SM6225 写过 CAMSS 支持**。

**【已核实】`.config` 侧 —— 整块关闭**

```
# CONFIG_MEDIA_SUPPORT is not set
（因此 CONFIG_VIDEO_CAMSS / V4L2 / MEDIA_CONTROLLER 全部不可能存在）
```

**【已核实】驱动侧 —— 三个层面都缺**

**(a) camss 不支持 bengal/SM6225**。`drivers/media/platform/qcom/camss/camss.c` 支持的 compatible 全表：

```
qcom,msm8916-camss   qcom,msm8953-camss   qcom,msm8996-camss
qcom,sc7280-camss    qcom,sc8280xp-camss
qcom,sdm660-camss    qcom,sdm670-camss    qcom,sdm845-camss
qcom,sm8250-camss    qcom,sm8550-camss
```

**没有 `qcom,sm6115-camss` / `qcom,sm6225-camss`。**

**(b) 没有 camcc 时钟控制器**。`drivers/clk/qcom/camcc-*.c` 只有 sa8775p / sc7180 / sc7280 / sc8280xp / sdm845 / sm4450 / sm6350 / sm7150 / sm8150 / sm8250 / sm8450 / sm8550 / sm8650 / x1e80100。**没有 `camcc-sm6115.c`**。

**(c) 没有对应 sensor 驱动**。`drivers/media/i2c/` 里 Samsung 只有 `s5k5baf` / `s5k6a3`，**没有 `s5k4h7`**；SmartSens 系列**没有 `sc820cs`**。

**【已核实】设备侧 —— 实际 sensor 型号 = Samsung S5K4H7 ×2（已上机确认，不再是候选）**

决定性回显（`getprop`，设备自报）：

```
vendor.debug.camera.sensor.info : id0 s5k4h7 8M
                                  id1 s5k4h7 8M
vendor.debug.camera.front.info  : elm_lce_s5k4h7_front_ii
vendor.debug.camera.rear.info   : elm_lce_s5k4h7_rear_i
vendor.debug.camera.front.sn    : 8SSC28D951360A004100000
vendor.debug.camera.rear.sn     : 8SSC28D951370A004100000
```

`dumpsys media.camera` 也确认 `Number of camera devices: 2`。

`/vendor/lib64/camera/` 里另有 `elm_sunwin_sc820cs_rear_ii` / `elm_txd_sc820cs_front_i` 两组库，但**本机实际用的是 S5K4H7**（那两组是通用 blob 集里的其它机型分支，与本机无关）。

⇒ **前后双摄均为 Samsung S5K4H7（8MP），mainline 无对应驱动**（`drivers/media/i2c/` 只有 `s5k5baf.c` / `s5k6a3.c`）。

### 4.2 缺口归因

摄像头不是"接线没接"的问题，是**整条栈在 mainline 上不存在**。四层全缺，且**每一层都是独立工程**：

| 层 | 缺口 | 类型 |
|---|---|---|
| L1 | `CONFIG_MEDIA_SUPPORT` 关闭 | config（5 分钟） |
| L2 | 无 `camcc-sm6115` 时钟控制器 | **新写驱动**（含 clock 表逆向，2 ～ 4 周） |
| L3 | camss 无 bengal resources（CSID/VFE/CSIPHY 版本与寄存器基址） | **新写驱动**（4 ～ 8 周） |
| L4 | 无 sensor 驱动：**S5K4H7 ×2（已确认）** + 无 EEPROM 驱动 | **新写驱动**（5 ～ 10 人日，同一颗芯片写一次、挂两个实例） |
| L5 | DTS 全缺（camss / cci / csiphy / sensor / vreg） | 改 DTS（依赖 L2-L4） |

### 4.3 具体改法

**建议：本轮不做。** 若一定要推进，唯一务实的顺序是：

**Step 0（0.5 人日，可立即做）**：只开 `CONFIG_MEDIA_SUPPORT`，拿到 V4L2 框架，为后续所有工作铺路。

```diff
-# CONFIG_MEDIA_SUPPORT is not set
+CONFIG_MEDIA_SUPPORT=y
+CONFIG_MEDIA_CONTROLLER=y
+CONFIG_VIDEO_DEV=y
+CONFIG_V4L2_FWNODE=y
+CONFIG_VIDEO_CAMSS=m        # 编译现有 camss，但 bengal 无 match，不会 probe
```

**Step 1（2 ～ 4 周）**：写 `camcc-sm6115.c`。这是硬门槛 —— 没有摄像头时钟，CSIPHY/CSID/VFE 一个都动不了。取时钟表的方法：设备 `/sys/kernel/debug/clk/clk_summary`（Android 上可读）能拿到 camcc 域全部时钟名与频率，比逆向 ABL 快得多。

**Step 2（4 ～ 8 周）**：给 camss 加 bengal resources。参考 `camss.c` 里最接近的 `sm8250_resources` / `sdm670_resources`（同为 CSID gen2 + VFE 480 系列），把基址、中断、时钟名换成 bengal 的。

**Step 3（1 ～ 2 周）**：sensor 驱动。先确认是 S5K4H7 还是 SC820CS；S5K4H7 有 Android 侧 driver 可参照，SC820CS 更冷门。

**Step 4**：DTS 接线（camss + cci + csiphy + sensor + 供电）。

### 4.4 验证方法

```bash
# L1 之后
ls /dev/video*                        # 期望有 video 节点（camss 不 probe 则无）
dmesg | grep -iE "camss|camcc|csiphy"
cat /sys/kernel/debug/clk/clk_summary | grep -i cam     # L2 完成后
v4l2-ctl --list-devices
media-ctl -p
```

### 4.5 工作量

| 项 | 人日 |
|---|---|
| L1 config 打开 | 0.5 |
| L2 camcc-sm6115 | 10 ～ 20 |
| L3 camss bengal resources | 20 ～ 40 |
| L4 sensor 驱动（S5K4H7 一份，挂前后两个实例）+ EEPROM | 5 ～ 10 |
| L5 DTS | 2 ～ 3 |
| **合计** | **37 ～ 73 人日（约 2 ～ 3.5 人月）** |

**结论：摄像头是这张表里唯一"不建议本轮投入"的项。** 投入产出比极差，且和"能日常用"的目标无关。

---

## 5. 传感器

### 5.1 现状证据

**【已核实】DTS 侧 —— 一个传感器节点都没有**

`sm6225-lenovo-tb331fc.dts` 里与"传感器"沾边的只有：

```dts
DTS:3886  hall-sensor {                    /* 在 gpio-keys 下，是输入按键，不是 IIO */
    label = "Hall Sensor";
    gpios = <0x28 0x42 0x01>;              /* tlmm gpio 66 */
    linux,input-type = <0x05>;             /* EV_SW */
    linux,input-code  = <0x00>;
    wakeup-source;
};
```

**没有 bmi3x0 / bmi323 节点，没有 ltr578 节点，没有任何 i2c 传感器子节点。**

**【已核实】`.config` 侧**

```
CONFIG_IIO=y                    CONFIG_IIO_BUFFER=y
CONFIG_IIO_TRIGGER=y            CONFIG_IIO_KFIFO_BUF=m
# CONFIG_BMI323_I2C is not set  ← 有驱动没开
# CONFIG_BMI323_SPI is not set
# CONFIG_BMI160_I2C is not set  # CONFIG_BMI270_I2C is not set
# CONFIG_BMC150_ACCEL is not set
CONFIG_IIO_ST_LSM6DSX=m        # 不相关的 ST 系列
```

**【已核实】驱动侧 —— 一个有一个没有**

| 芯片 | 设备实测 | mainline 驱动 | 结论 |
|---|---|---|---|
| **BMI3x0**（BOSCH ver 306） | accel + gyro + uncal gyro | `drivers/iio/imu/bmi323/{bmi323_core,bmi323_i2c,bmi323_spi}.c` | **驱动存在**，`CONFIG_BMI323_I2C` 没开 |
| **LTR-578**（Lite-On ver 258） | ALS | `drivers/iio/light/` 只有 `ltr390.c` / `ltr501.c` / `ltrf216a.c` | **没有 LTR-578 驱动，需新写** |
| `wake_gesture`（ams） | 手势唤醒 | 无 | 需新写（低优先级） |
| **AK0991x**（AKM 磁力计） | persist 注册表有 `ak0991x_0.mag` / `.config` / `.fac_cal` | 无（mainline 有 `ak8975.c` 但不含 0991x） | 需新写；dumpsys 未列出 ⇒ 可能未启用 |
| **AW9610x**（Awinic SAR） | persist 注册表有 `aw9610x_0_sar` / `.cali` / `.config` | 无 | 需新写；dumpsys 未列出 ⇒ 可能未启用 |

> 传感器家族比 `dumpsys sensorservice` 显示的更多 —— persist 注册表里还躺着 `ak0991x`（磁力计）与 `aw9610x`（SAR 接近感应）。这两个在当前系统上没被启用，但硬件大概率存在，做传感器项时应一并纳入规划。

**【已核实】最关键的一条：传感器不在 AP 侧总线上**

设备 `/sys/bus/i2c/devices/` 全部 3 条 geni 总线、14 个设备（§0.3 表），**没有 accel、没有 als**。设备 `/sys/bus/iio/devices/` 6 个设备全是充电/ADC/TypeC，**没有 accel/als**。`spi@4a94000` 在 DTS 里 `status = "disabled"` 且无子节点。

⇒ 29 颗传感器全部经 **SSC（Sensor Core / sensor DSP）** 上报，物理上挂在 **ADSP 侧独立的 I2C/SPI 控制器**上，不走 AP 的 QUP。

### 5.2 缺口归因

| # | 缺口 | 性质 |
|---|---|---|
| **S1** | 传感器的物理总线不在 AP 侧 —— 需要先确定 SSC I2C 用的是哪几个 TLMM 引脚，再把它们 mux 到 AP 的某条 QUP I2C | **硬件/引脚级未知，本项目最大未知数** |
| **S2** | `CONFIG_BMI323_I2C` 未开 | config（5 分钟） |
| **S3** | 无 LTR-578 驱动 | **新写驱动** |
| **S4** | DTS 无传感器节点 | 改 DTS（依赖 S1） |

> 注意 S1 的性质：**这不是"没接线"，而是"线接在另一个处理器上"。** 解法只有两条：
> - **改 mux**：把 SSC I2C 的两个 GPIO 从 sensor 功能切到某个 AP QUP 的 i2c 功能。前提是这两个引脚在 TLMM 上可复用（多数情况可以）。
> - **写 SSC 客户端**：让 AP 通过 ADSP 的 QMI/PD 接口取数据（工程量巨大，不建议）。

### 5.3 具体改法

#### Step 1（0.5 人日）：立刻可做，零风险

```diff
-# CONFIG_BMI323_I2C is not set
+CONFIG_BMI323_I2C=m
+CONFIG_BMI323_SPI=m
```

#### Step 2（2 ～ 3 人日，**【需上机】**）：定位 SSC I2C 引脚

> ⚠️ **实测坑**：本机 Android **没有挂 debugfs**（`su -c 'mount | grep debugfs'` 无输出），所以"读 `/sys/kernel/debug/pinctrl/*/pinmux-pins`"这条路**走不通**。别在这上面浪费时间。下面是三条真正可行的路：

```bash
# (a) persist 里的传感器注册表 —— 已实测可读，能拿到芯片家族清单
adb shell 'ls /mnt/vendor/persist/sensors/registry/registry/ | head -40'
#    实测含：bmi3x0_0(.accel/.gyro/.config)、ak0991x_0(.mag)、aw9610x_0(.sar) …

# (b) SSC/ADSP 初始化日志里通常带 i2c 实例号与从地址
adb shell 'dmesg | grep -iE "ssc|sns|sensor.*i2c|i2c.*sensor|slpi" | head -40'

# (c) vendor 内核源码（最可靠）—— 若有 TB331FC 的 vendor kernel 树：
#     git grep -n "i2c\|sensor" -- arch/arm64/boot/dts/vendor/qcom/sm6225*.dtsi
#     找 qcom,i2c-sensor / ssc_i2c / sensor_pin 之类的 pinctrl 定义
```

拿到引脚后，DTS 加（示例，引脚号待填）：

```dts
&qupv3_i2c5 {                    /* 选一条空闲 QUP i2c，需确认引脚可复用 */
	status = "okay";

	accel@68 {                   /* BMI323 I2C 地址 0x68 或 0x69 */
		compatible = "bosch,bmi323";
		reg = <0x68>;
		interrupt-parent = <&tlmm>;
		interrupts = <0x?? IRQ_TYPE_EDGE_RISING>;
		vdd-supply = <&pm6125_l??>;
		vddio-supply = <&pm6125_l??>;
	};

	als@53 {                     /* LTR-578 I2C 地址待确认 */
		compatible = "liteon,ltr578";
		reg = <0x53>;
		interrupt-parent = <&tlmm>;
		interrupts = <0x?? IRQ_TYPE_EDGE_FALLING>;
	};
};
```

#### Step 3（2 ～ 3 人日）：写 LTR-578 驱动

参照 `drivers/iio/light/ltrf216a.c`（同为 Lite-On ALS，I2C，寄存器模型接近），~400 行。需要 datasheet 里的 ALS 增益/积分时间表。

#### Step 4：最小可验证目标

> 任务书要求："`/dev/iio:device*` 出现即可" —— **这个目标对 accel 是可达的（驱动现成），对 ALS 需要先写驱动。**

### 5.4 验证方法

```bash
# 驱动加载
ls /dev/iio:device*
for d in /sys/bus/iio/devices/iio:device*; do echo "$d => $(cat $d/name)"; done
#    期望看到 bmi323 / ltr578

# accel 真的在动
cat /sys/bus/iio/devices/iio:deviceN/in_accel_x_raw
#    倾斜设备，数值应变化

# 用 iio 工具（更直观）
iio_info -u local:
iio_readdev -u local: -s 1000 -b 16 iio:deviceN > /tmp/accel.bin

# ALS
cat /sys/bus/iio/devices/iio:deviceM/in_illuminance_raw
#    遮住/照亮屏幕，数值应变化

# 自动旋转（若接了 iio-sensor-proxy）
monitor-sensor
```

### 5.5 工作量

| 项 | 人日 |
|---|---|
| S2 config 打开 | 0.1 |
| S1 定位 SSC I2C 引脚（含 mux 验证） | 2 ～ 3 |
| DTS 接线 + accel 跑通 | 1 |
| LTR-578 驱动 | 2 ～ 3 |
| wake_gesture（可选） | 2 ～ 3 |
| **合计（accel + ALS）** | **5 ～ 8 人日** |

---

## 6. 总表

| 领域 | 阻塞点（一句话） | 依赖 | 优先级 | 工作量（人日） | 确定性 |
|---|---|---|---|---|---|
| **蓝牙** | `/lib/firmware/qca/` 缺 `crbtfw21.tlv` + `crnv21.bin`；硬件/驱动/DTS/pinmux/稳压器全部就位 | **只缺固件** | **P0** | **0.5 ～ 1** | **极高**（唯一变量是 rom_ver 值，dmesg 直接告知） |
| **音频** | ① `# CONFIG_SOUND is not set` ② ADSP 固件路径写成 `TB128FU/adsp.mbn`（设备只有 `TB331FC/adsp.mdt`）③ 无 sm6115 machine driver ④ codec 属性名 `sound-channel` 应为 `awinic,audio-channel` ⑤ MI2S 无 pinmux | DTS + 驱动 + 固件 + config | **P1** | 3 ～ 5（最小出声）<br>8 ～ 12（四扬声器） | 高（除 ⑤ 引脚待定） |
| **电源管理** | 拆成 5 项：P1 CPU 变频、P5 电量**可能已能用**；P2 suspend 大概率挂不住；P4 充电**无 sc89601d 驱动**；P3 待机耗电依赖 P2 | config + 驱动（仅 P4）+ DTS | **P2** | 1 ～ 4（不含充电）<br>4 ～ 8（含充电驱动） | 中（P1/P5 高，P2 中，P4 需新驱动） |
| **传感器** | 传感器物理上挂在 **SSC/ADSP 侧 I2C**，不在 AP 总线上 —— 需先定位引脚并改 mux；另 LTR-578 无 mainline 驱动 | **DTS(引脚) + 驱动(ALS) + config** | **P3** | 5 ～ 8 | 中低（引脚位置是本项目最大未知） |
| **摄像头** | 整条栈不存在：`MEDIA_SUPPORT` 关闭 + 无 `camcc-sm6115` + camss 不支持 bengal + 无 S5K4H7 驱动（**前后双摄已确认同为 S5K4H7 8MP**）+ DTS 全缺 | **驱动（三层）+ DTS + config** | **P4（不建议本轮做）** | **37 ～ 73** | 低（等于从零写一个平台的摄像头支持） |

### 优先级排序理由

- **P0 蓝牙**：唯一一个"所有基础设施已就位、只差两个文件"的项。0.5 人日换一个完整功能，且验证路径完全确定（dmesg 会直接把缺的文件名打印出来）。
- **P1 音频**：四层缺口里三层是配置/接线，只有 machine driver 需要真写代码。而且可以切成两个独立里程碑（ADSP 起来 → 出声），第一个里程碑 1 人日就有可观测进展。
- **P2 电源**：**先测再改**。P1（CPU 变频）和 P5（电量）很可能已经是好的，不测就改是浪费。真正要写代码的只有充电 IC。
- **P3 传感器**：技术不确定性最高（引脚未知），且"有传感器"对日常使用的边际价值低于音频。
- **P4 摄像头**：唯一一个工作量超过 1 人月的项，且和"能日常用"无关。

---

## 7. 建议的执行顺序（可直接排期）

```
第 1 步（0.5 人日）蓝牙
  ├─ adb pull crbtfw21.tlv / crnv21.bin → /lib/firmware/qca/
  ├─ .config: CONFIG_BT_LE=y / BT_RFCOMM=y / BT_BNEP=y
  └─ 验证：hciconfig -a 出现 hci0 + bluetoothctl scan on 扫到设备
      ↓
第 2 步（1 人日）音频里程碑 1：ADSP 起来
  ├─ .config: CONFIG_SOUND/SND/SND_SOC/SND_SOC_QCOM/SND_SOC_QDSP6=y
  ├─ 拷 adsp.mdt + adsp.b00..b20 → qcom/sm6225/LENOVO/TB331FC/
  ├─ DTS: firmware-name 改成 TB331FC/adsp.mdt
  └─ 验证：/sys/class/remoteproc/*/state = running
      ↓
第 3 步（0.25 人日）电源实测（不改代码）
  ├─ 读 cpufreq / power_supply / suspend_stats
  └─ 产出一张"哪些本来就能用"的清单，再决定第 5 步做什么
      ↓
第 4 步（3 ～ 5 人日）音频里程碑 2：最小出声
  ├─ DTS: sound-channel → awinic,audio-channel
  ├─ 新写 sound/soc/qcom/sm6115.c（单路 DAI link）
  ├─ DTS: /sound 节点 + MI2S pinmux
  └─ 验证：aplay -D hw:0,0 test.wav 出声
      ↓
第 5 步（按第 3 步结论）电源整改
      ↓
第 6 步（5 ～ 8 人日）传感器：先定位 SSC 引脚，再决定是否做
      ↓
第 7 步（不建议）摄像头
```

---

## 8. 已核实 / 需上机验证 一览

### 已核实（有源码、配置或设备回显直接证据）

| # | 结论 |
|---|---|
| 1 | `sm6225-lenovo-tb331fc.dts` 是 dtc 反编译产物（数字 phandle、dtsi 已展开），不是可维护源码 |
| 2 | 该 DTS 的 `model` / `compatible` 仍是 `Lenovo Tab M10 Plus 3rd gen` / `lenovo,tb128` |
| 3 | 该 DTS 的 `firmware-name` 全部指向 `qcom/sm6225/LENOVO/TB128FU/` |
| 4 | TB128 与 TB331FC 的 `msm-id`(0x206/0x10000) 与 `board-id`(0x10022/0x0) 完全相同，不能用它区分机型 |
| 5 | `# CONFIG_SOUND is not set` —— 音频子系统整体缺失 |
| 6 | `# CONFIG_MEDIA_SUPPORT is not set` —— V4L2/media 整体缺失 |
| 7 | 蓝牙 DTS 节点、pinmux(gpio8-11/qup3)、四路稳压器、`swctrl-gpios`、`CONFIG_BT_HCIUART_QCA` 全部就位 |
| 8 | WCN3990 默认固件名为 `qca/crbtfw%02x.tlv` / `qca/crnv%02x%s.bin`（`btqca.c:823-828, 897-905`） |
| 9 | 设备上存在 `crbtfw21.tlv` + `crnv21.bin`，⇒ rom_ver = 0x21 |
| 10 | mainline 有 `aw88166.c`，`compatible` 与 DTS 用的两个字符串完全匹配 |
| 11 | `aw88166.c` 读 `awinic,audio-channel`，DTS 写的是 `sound-channel`（属性名不匹配） |
| 12 | `aw88166.c` 的 ACF 兜底名就是 `aw883xx_acf.bin`，设备上有这个文件 |
| 13 | mainline `sound/soc/qcom/` 无 sm6115/sm6225 machine driver |
| 14 | mainline `camss.c` 支持的 10 个 compatible 里没有 sm6115/sm6225 |
| 15 | mainline 无 `camcc-sm6115.c`；有 `gcc-sm6115.c` / `dispcc-sm6115.c` / `gpucc-sm6115.c` / `lpasscc-sm6115.c` |
| 16 | mainline 无 `s5k4h7` / `sc820cs` sensor 驱动 |
| 17 | `mdt_loader.c:50` 段名规则 = 固件名末 3 字符换 `b%02d`，故 `adsp.mdt` → `adsp.b00..b20` 正好对应设备文件 |
| 18 | `qcom,sm6115-adsp-pas` 在 `qcom_q6v5_pas.c:1447` 有支持 |
| 19 | mainline 有 `mm8013.c`，且 `CONFIG_FUEL_GAUGE_MM8013=y` 已开 |
| 20 | mainline **无** SC89601D 充电驱动（全树 grep 无命中） |
| 21 | 设备 4 颗 AW88166 分挂 i2c-0(0x34,0x35) 与 i2c-1(0x34,0x35)，与 DTS 完全一致 |
| 22 | 设备 AP 侧 i2c 只有 3 条总线 14 个设备，**无 accel / 无 als** |
| 23 | 设备 29 颗传感器全经 SSC 上报（bmi3x0 BOSCH ver306 + ltr578 Lite-On ver258） |
| 24 | mainline 有 `bmi323` 驱动（含 i2c/spi），`CONFIG_BMI323_I2C` 未开 |
| 25 | mainline 无 LTR-578 驱动（只有 ltr390 / ltr501 / ltrf216a） |
| 26 | 设备 `/vendor/firmware_mnt/image/` 有完整 `adsp.mdt` + `adsp.b00..b20` |
| 27 | DTS 里 panel `compatible = "lenovo,p255-inx"`，而 mainline nt36523 面板驱动只支持 j606f-boe / tb128fu-boe / elish-boe / elish-csot |
| 28 | **设备两台摄像头都是 Samsung S5K4H7 8MP**（`vendor.debug.camera.sensor.info` = `id0 s5k4h7 8M` / `id1 s5k4h7 8M`；front=`elm_lce_s5k4h7_front_ii`，rear=`elm_lce_s5k4h7_rear_i`），`dumpsys media.camera` 报 2 个 camera device |
| 29 | **设备真实屏幕 1200×1920，density 320**（`wm size` / `wm density`），而 DTS 的 `simple-framebuffer` 写的是 **1200×2000**（`width=<0x4b0> height=<0x7d0>`），`himax,panel-coords` 也是 `0 1200 0 2000` ⇒ **两处都多了 80 行像素** |

### 需上机验证

| # | 待验证 | 命令 | 为什么重要 |
|---|---|---|---|
| V1 | 当前显示到底走 DRM+DSI 还是 simpledrm | `dmesg \| grep -iE "simpledrm\|msm\|panel\|nt36523"`；`cat /sys/class/drm/card0-*/modes` | DTS 的 panel compatible 不在 nt36523 驱动支持列表里（第 27 条），若真走 simpledrm 则"显示能用"是 ABL 帧缓冲的功劳，换分辨率/改亮度都会受限 |
| V2 | WCN3990 实际 rom_ver | `dmesg \| grep -i "QCA Downloading"` | 决定拷 `crbtfw21` 还是别的 |
| V3 | suspend 是否可行 | `echo mem > /sys/power/state` | P2 的核心判据 |
| V4 | CPU 变频是否已工作 | `cat /sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq` | 可能零改动就可用 |
| V5 | 电量是否已可读 | `cat /sys/class/power_supply/*/uevent` | mm8013 驱动 + config 都齐，可能零改动 |
| ~~V6~~ | ~~摄像头实际 sensor 是 S5K4H7 还是 SC820CS~~ | — | **已上机确认：S5K4H7 ×2，见第 28 条** |
| V7 | SSC I2C 用的是哪几个 TLMM 引脚 | `cat /sys/kernel/debug/pinctrl/*/pinmux-pins` | **传感器项的最大未知数** |
| V8 | MI2S 实际引脚 | 同上 + vendor 内核 DTS | 音频里程碑 2 的前置 |
| V9 | `vddrf` / `vddch0` 对应的稳压器是否正确（phandle 0xa8 / 0xa9） | `dmesg \| grep -i "qca\|regulator"` | BT 射频供电，若错则能 probe 但扫不到设备 |
| ~~V10~~ | ~~面板真实分辨率~~ | — | **已上机确认：1200×1920，与 DTS 的 1200×2000 不符，见第 29 条** |

---

## 9. 附：本报告用到的取证命令（可复现）

```bash
# 设备身份
adb shell cat /proc/device-tree/model
adb shell 'tr -d "\000" < /proc/device-tree/compatible'
adb shell 'od -An -tx1 /proc/device-tree/qcom,board-id'

# i2c 全量 + 名字
adb shell 'for d in /sys/bus/i2c/devices/*-*; do printf "%s %s\n" "$(basename $d)" "$(cat $d/name)"; done'

# 传感器
adb shell dumpsys sensorservice | head -60
adb shell 'ls /sys/bus/iio/devices/; cat /sys/bus/iio/devices/iio:device0/name'

# 电源
adb shell 'ls /sys/class/power_supply/; ls /sys/devices/system/cpu/cpu0/cpufreq/'

# 固件
adb shell 'ls /vendor/firmware/'
adb shell 'ls /vendor/firmware_mnt/image/ | head -25'
adb shell 'ls /vendor/bt_firmware/image/'

# 摄像头
adb shell 'ls /vendor/lib64/camera/ | grep -i elm'
```

PC 侧源码核对用到的抽取命令（7z 必须用正斜杠）：

```powershell
& 'C:\Program Files\7-Zip\7z.exe' x $zip `
  "linux-lenovo-tb331fc-main/drivers/bluetooth/hci_qca.c" `
  "-oE:\rom\work\linux-port-fix\_extract" -y
```

> 注意：`7z l <zip>` 全量列表有 8 万+ 条目会被截断，要用 `7z l <zip> "<子路径通配>"` 定向列。
> 另外 `7z x` 的 `-o` 路径**不要带尾部反斜杠**，内路径**必须用正斜杠**，否则静默抽出 0 个文件。
