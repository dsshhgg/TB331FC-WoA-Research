# TB331FC 设备档案 · 硬件与分区全貌

> 设备：联想小新 Pad 2024 **TB331FC**（代号 `khaje`，SoC `SM6225-AD` / bengal）
> 采集：2026-11-24 13:12–13:50 (Asia/Shanghai)，adb serial `5e367954`，KSU root
> **全程只读**：只用 `dd` 读分区头部/前 64 MiB、读 sysfs / `/proc/device-tree` / `/proc` / `getprop` / `dmesg`；
> 未写任何分区、未 reboot、未进 bootloader / fastbootd / 9008。

---

## 0. 采集时的设备状态（读后面所有结论前必看）

| 项 | 值 | 证据 |
|---|---|---|
| 运行中系统 | 澎湃 **HyperOS 4.0 / Android 17 (SDK 37)** | `getprop ro.build.version.release` = `17`，`ro.build.version.sdk` = `37` |
| 系统指纹 | `Lenovo/miproduct_yupei/TB331FC:17/CP2A.260605.016/OS4.0.5.0.XPZCNXM` | `ro.build.fingerprint` |
| 构建标识 | `CP2A.260605.016 by dsshhgg` | `ro.build.display.id` |
| vendor 侧 | 仍是**原厂 ZUI 16.0.544** | `ro.vendor.build.fingerprint` = `Lenovo/TB331FC_PRC/TB331FC:14/UKQ1.230917.001/ZUI_16.0.544_241115_PRC` |
| 当前槽位 | `_a` | `ro.boot.slot_suffix=_a`；`lpdump` → `Current slot: _a` |
| AVB 状态 | **orange / eio**（verity 降级） | `ro.boot.verifiedbootstate=orange`，`ro.boot.veritymode=eio` |
| 内核 | `5.15` GKI（`android13-5.15` 线），cmdline 含 `msm_drm.dsi_display0=qcom,mdss_dsi_panel_p255_hx83102j_fhd_video` | `/proc/cmdline` |

**两条采集环境事实，会影响后续任何实验的可比性：**

1. **会话期间设备自动重启 2 次**。两次都在 uptime 归零后被重新连上（13:25 时 `uptime=57.43s`，13:47 时 `78.47s`），
   `ro.boot.bootreason=bootloader`，adbd 中断 2–4 分钟后自行恢复。→ 这台机器当前 A17 状态**不稳定**，
   任何长时间采集脚本都必须能断点续采（本次共 6 个采集脚本，其中 3 个被打断：`collect_hw3` 在递归 `find` 上卡死、
   `collect_hw5` / `collect_hw6` 撞上重启，最后都改成更小的定向脚本重跑）。
2. **设备系统时间比真实时间慢约 30 天**（`date` = `Sun Oct 25 17:56:59 CST 2026`，真实 = 2026-11-24 13:47）。
   用设备侧时间戳做先后判断会错。

## 1. 一页纸

| 项 | 值 |
|---|---|
| SoC | Qualcomm **SM6225-AD**（bengal / Snapdragon 685），8 核 |
| DT model | `Qualcomm Technologies, Inc. KHAJE IDP nopmi` |
| DT compatible | `qcom,khaje-idp` / `qcom,khaje` / `qcom,idp` |
| qcom,board-id | `0x00010022` |
| qcom,msm-id | `0x00000206` `0x00010000` |
| 内存 | 5,778,924 kB ≈ **5.51 GiB 可用**（6 GB 物理） |
| 存储 | **SAMSUNG KLUDG2R1DE-B0F1**，rev 0100，128 GB，**6 个 LUN，逻辑扇区 4096 B** |
| 屏幕 | **1200×1920，90 Hz**，DSI video mode，单 DSI link |
| 面板 | **BOE p255 + Himax HX83102J**（`qcom,mdss_dsi_panel_p255_hx83102j_fhd_video`） |
| 触摸 | **Himax**（`himax-touchscreen` + `himax-stylus`），**SPI** @0x4A80000 CS0，10 MHz |
| 背光 | I2C 背光 IC `bkl-bl@11`（i2c-0），max 4095 |
| 电池 | **MITSUMI**，design 7,040,000 µAh（7040 mAh），循环 277 次 |
| 充电 | **SouthChip SC89601D** 主/从双充（i2c-1 0x6B master / i2c-0 0x6B slave），`qcom,nopmi-chg` 框架 |
| 电量计 | **Mitsumi MM8013C**（i2c-1 0x55） |
| Type-C | **Richtek RT1711H**（i2c-3 0x4E，TCPC `type_c_port0`）+ **Awinic AW35615**（i2c-3 0x22）+ **FSA4480**（i2c-0 0x42，模拟音频切换） |
| 音频 | **WCD937x**（bolero）+ **2× AW883xx** 智能 PA（i2c-0/1 0x34、0x35）；`bengal-asoc-snd`；ADSP `remoteproc-adsp@ab00000` |
| 无线 | 集成 **`qcom,icnss@C800000`**（bengal 内置 WCN）+ **`bt_wcn3990`**（compatible `qcom,wcn3990`）+ SLIMbus `slim@a5c0000`；`persist.vendor.qcom.bluetooth.soc=cherokee` |
| 传感器 | **29 颗**：BOSCH **BMI3x0**（加速度/陀螺，含 uncalibrated）、Lite-On **LTR578**（环境光）、ams `wake_gesture` |
| 摄像头 | **Samsung S5K4H7 8 MP** ×2（后 `elm_lce_s5k4h7_rear_i` 带 AF+闪光灯 / 前 `elm_lce_s5k4h7_front_ii`） |
| 指纹 | **无**（`/sys/class/sensors` 无指纹节点，DT 无指纹 compatible；只有 virtual fingerprint APEX） |
| 按键 | `gpio_keys`：`vol_up`（KEY_VOLUMEUP=115）、`hall_key`（EV_SW / SW_LID=0，霍尔盖/磁吸检测）；电源键走 `qpnp_pon`（PM6125 PON） |

## 2. 分区全表

来源：`ls -l /dev/block/by-name/` + `blockdev --getsize64`，共 **91** 个分区（另有 6 个整盘别名 `sda..sdf`）。
LUN / 起始扇区 / GPT 属性来自厂商 `gpt_main0..5.bin`（见 §2.4）。

### 2.1 按 LUN 分组

#### LUN0 `sda` — 盘容量 115.1 GiB，逻辑扇区 4096 B，14 个分区

| # | 分区名 | 设备节点 | 大小(字节) | 大小 | 起始 LBA | GPT 属性 | 标记 |
|---|---|---|---|---|---|---|---|
| 1 | `ssd` | `/dev/block/sda1` | 8192 | 8.00 KiB | 6 | `0x0000000000000000` |  |
| 2 | `persist` | `/dev/block/sda2` | 33554432 | 32.00 MiB | 8 | `0x0000000000000000` |  |
| 3 | `misc` | `/dev/block/sda3` | 1048576 | 1.00 MiB | 8200 | `0x0000000000000000` |  |
| 4 | `keystore` | `/dev/block/sda4` | 524288 | 512.0 KiB | 8456 | `0x0000000000000000` |  |
| 5 | `oemowninfo` | `/dev/block/sda5` | 1048576 | 1.00 MiB | 8584 | `0x1000000000000000` | RO |
| 6 | `lenovolock` | `/dev/block/sda6` | 524288 | 512.0 KiB | 8840 | `0x0000000000000000` |  |
| 7 | `lenovocust` | `/dev/block/sda7` | 314572800 | 300.0 MiB | 8968 | `0x0000000000000000` |  |
| 8 | `lenovoraw` | `/dev/block/sda8` | 16777216 | 16.00 MiB | 85768 | `0x0000000000000000` |  |
| 9 | `frp` | `/dev/block/sda9` | 524288 | 512.0 KiB | 89864 | `0x0000000000000000` |  |
| 10 | `super` | `/dev/block/sda10` | 12884901888 | 12.00 GiB | 89992 | `0x0000000000000000` |  |
| 11 | `vbmeta_system_a` | `/dev/block/sda11` | 65536 | 64.00 KiB | 3235720 | `0x1000000000000000` | A/B RO |
| 12 | `vbmeta_system_b` | `/dev/block/sda12` | 65536 | 64.00 KiB | 3235736 | `0x1000000000000000` | A/B RO |
| 13 | `metadata` | `/dev/block/sda13` | 67108864 | 64.00 MiB | 3235752 | `0x0000000000000000` |  |
| 14 | `userdata` | `/dev/block/sda14` | 110251814912 | 102.7 GiB | 3252136 | `0x0000000000000000` |  |

#### LUN1 `sdb` — 盘容量 8.00 MiB，逻辑扇区 4096 B，2 个分区

| # | 分区名 | 设备节点 | 大小(字节) | 大小 | 起始 LBA | GPT 属性 | 标记 |
|---|---|---|---|---|---|---|---|
| 1 | `xbl_a` | `/dev/block/sdb1` | 3670016 | 3.50 MiB | 6 | `0x1000000000000000` | A/B RO |
| 2 | `xbl_config_a` | `/dev/block/sdb2` | 131072 | 128.0 KiB | 902 | `0x0000000000000000` | A/B |

#### LUN2 `sdc` — 盘容量 8.00 MiB，逻辑扇区 4096 B，2 个分区

| # | 分区名 | 设备节点 | 大小(字节) | 大小 | 起始 LBA | GPT 属性 | 标记 |
|---|---|---|---|---|---|---|---|
| 1 | `xbl_b` | `/dev/block/sdc1` | 3670016 | 3.50 MiB | 6 | `0x1000000000000000` | A/B RO |
| 2 | `xbl_config_b` | `/dev/block/sdc2` | 131072 | 128.0 KiB | 902 | `0x0000000000000000` | A/B |

#### LUN3 `sdd` — 盘容量 32.00 MiB，逻辑扇区 4096 B，3 个分区

| # | 分区名 | 设备节点 | 大小(字节) | 大小 | 起始 LBA | GPT 属性 | 标记 |
|---|---|---|---|---|---|---|---|
| 1 | `ALIGN_TO_128K_1` | `/dev/block/sdd1` | 106496 | 104.0 KiB | 6 | `0x1000000000000000` | RO |
| 2 | `cdt` | `/dev/block/sdd2` | 131072 | 128.0 KiB | 32 | `0x1000000000000000` | RO |
| 3 | `ddr` | `/dev/block/sdd3` | 1048576 | 1.00 MiB | 64 | `0x1000000000000000` | RO |

#### LUN4 `sde` — 盘容量 4.00 GiB，逻辑扇区 4096 B，65 个分区

| # | 分区名 | 设备节点 | 大小(字节) | 大小 | 起始 LBA | GPT 属性 | 标记 |
|---|---|---|---|---|---|---|---|
| 1 | `rpm_a` | `/dev/block/sde1` | 524288 | 512.0 KiB | 6 | `0x1000000000000000` | A/B RO |
| 2 | `tz_a` | `/dev/block/sde2` | 4194304 | 4.00 MiB | 134 | `0x1000000000000000` | A/B RO |
| 3 | `hyp_a` | `/dev/block/sde3` | 524288 | 512.0 KiB | 1158 | `0x0000000000000000` | A/B |
| 4 | `modem_a` | `/dev/block/sde4` | 188743680 | 180.0 MiB | 1286 | `0x1000000000000000` | A/B RO |
| 5 | `bluetooth_a` | `/dev/block/sde5` | 1048576 | 1.00 MiB | 47366 | `0x1000000000000000` | A/B RO |
| 6 | `mdtpsecapp_a` | `/dev/block/sde6` | 4194304 | 4.00 MiB | 47622 | `0x1000000000000000` | A/B RO |
| 7 | `mdtp_a` | `/dev/block/sde7` | 33554432 | 32.00 MiB | 48646 | `0x1000000000000000` | A/B RO |
| 8 | `abl_a` | `/dev/block/sde8` | 1048576 | 1.00 MiB | 56838 | `0x1000000000000000` | A/B RO |
| 9 | `dsp_a` | `/dev/block/sde9` | 33554432 | 32.00 MiB | 57094 | `0x1000000000000000` | A/B RO |
| 10 | `keymaster_a` | `/dev/block/sde10` | 524288 | 512.0 KiB | 65286 | `0x1000000000000000` | A/B RO |
| 11 | `boot_a` | `/dev/block/sde11` | 100663296 | 96.00 MiB | 65414 | `0x0000000000000000` | A/B |
| 12 | `cmnlib_a` | `/dev/block/sde12` | 524288 | 512.0 KiB | 89990 | `0x1000000000000000` | A/B RO |
| 13 | `cmnlib64_a` | `/dev/block/sde13` | 524288 | 512.0 KiB | 90118 | `0x1000000000000000` | A/B RO |
| 14 | `devcfg_a` | `/dev/block/sde14` | 131072 | 128.0 KiB | 90246 | `0x0000000000000000` | A/B |
| 15 | `qupfw_a` | `/dev/block/sde15` | 65536 | 64.00 KiB | 90278 | `0x0000000000000000` | A/B |
| 16 | `vbmeta_a` | `/dev/block/sde16` | 65536 | 64.00 KiB | 90294 | `0x1000000000000000` | A/B RO |
| 17 | `dtbo_a` | `/dev/block/sde17` | 25165824 | 24.00 MiB | 90310 | `0x0000000000000000` | A/B |
| 18 | `imagefv_a` | `/dev/block/sde18` | 2097152 | 2.00 MiB | 96454 | `0x0000000000000001` | A/B REQ |
| 19 | `uefisecapp_a` | `/dev/block/sde19` | 2097152 | 2.00 MiB | 96966 | `0x0000000000000000` | A/B |
| 20 | `featenabler_a` | `/dev/block/sde20` | 131072 | 128.0 KiB | 97478 | `0x0000000000000000` | A/B |
| 21 | `multiimgoem_a` | `/dev/block/sde21` | 32768 | 32.00 KiB | 97510 | `0x1000000000000000` | A/B RO |
| 22 | `init_boot_a` | `/dev/block/sde22` | 8388608 | 8.00 MiB | 97518 | `0x0000000000000000` | A/B |
| 23 | `recovery_a` | `/dev/block/sde23` | 104857600 | 100.0 MiB | 99566 | `0x1000000000000000` | A/B RO |
| 24 | `vendor_boot_a` | `/dev/block/sde24` | 100663296 | 96.00 MiB | 125166 | `0x0000000000000000` | A/B |
| 25 | `rpm_b` | `/dev/block/sde25` | 524288 | 512.0 KiB | 149742 | `0x0000000000000000` | A/B |
| 26 | `tz_b` | `/dev/block/sde26` | 4194304 | 4.00 MiB | 149870 | `0x0000000000000000` | A/B |
| 27 | `hyp_b` | `/dev/block/sde27` | 524288 | 512.0 KiB | 150894 | `0x0000000000000000` | A/B |
| 28 | `modem_b` | `/dev/block/sde28` | 188743680 | 180.0 MiB | 151022 | `0x1000000000000000` | A/B RO |
| 29 | `bluetooth_b` | `/dev/block/sde29` | 1048576 | 1.00 MiB | 197102 | `0x1000000000000000` | A/B RO |
| 30 | `mdtpsecapp_b` | `/dev/block/sde30` | 4194304 | 4.00 MiB | 197358 | `0x1000000000000000` | A/B RO |
| 31 | `mdtp_b` | `/dev/block/sde31` | 33554432 | 32.00 MiB | 198382 | `0x1000000000000000` | A/B RO |
| 32 | `abl_b` | `/dev/block/sde32` | 1048576 | 1.00 MiB | 206574 | `0x1000000000000000` | A/B RO |
| 33 | `dsp_b` | `/dev/block/sde33` | 33554432 | 32.00 MiB | 206830 | `0x1000000000000000` | A/B RO |
| 34 | `keymaster_b` | `/dev/block/sde34` | 524288 | 512.0 KiB | 215022 | `0x1000000000000000` | A/B RO |
| 35 | `boot_b` | `/dev/block/sde35` | 100663296 | 96.00 MiB | 215150 | `0x0000000000000000` | A/B |
| 36 | `cmnlib_b` | `/dev/block/sde36` | 524288 | 512.0 KiB | 239726 | `0x1000000000000000` | A/B RO |
| 37 | `cmnlib64_b` | `/dev/block/sde37` | 524288 | 512.0 KiB | 239854 | `0x1000000000000000` | A/B RO |
| 38 | `devcfg_b` | `/dev/block/sde38` | 131072 | 128.0 KiB | 239982 | `0x0000000000000000` | A/B |
| 39 | `qupfw_b` | `/dev/block/sde39` | 65536 | 64.00 KiB | 240014 | `0x0000000000000000` | A/B |
| 40 | `vbmeta_b` | `/dev/block/sde40` | 65536 | 64.00 KiB | 240030 | `0x1000000000000000` | A/B RO |
| 41 | `dtbo_b` | `/dev/block/sde41` | 25165824 | 24.00 MiB | 240046 | `0x0000000000000000` | A/B |
| 42 | `featenabler_b` | `/dev/block/sde42` | 131072 | 128.0 KiB | 246190 | `0x0000000000000000` | A/B |
| 43 | `imagefv_b` | `/dev/block/sde43` | 2097152 | 2.00 MiB | 246222 | `0x0000000000000001` | A/B REQ |
| 44 | `uefisecapp_b` | `/dev/block/sde44` | 2097152 | 2.00 MiB | 246734 | `0x0000000000000000` | A/B |
| 45 | `multiimgoem_b` | `/dev/block/sde45` | 32768 | 32.00 KiB | 247246 | `0x1000000000000000` | A/B RO |
| 46 | `recovery_b` | `/dev/block/sde46` | 104857600 | 100.0 MiB | 247254 | `0x1000000000000000` | A/B RO |
| 47 | `vendor_boot_b` | `/dev/block/sde47` | 100663296 | 96.00 MiB | 272854 | `0x0000000000000000` | A/B |
| 48 | `init_boot_b` | `/dev/block/sde48` | 8388608 | 8.00 MiB | 297430 | `0x0000000000000000` | A/B |
| 49 | `devinfo` | `/dev/block/sde49` | 4096 | 4.00 KiB | 299478 | `0x1000000000000000` | RO |
| 50 | `dip` | `/dev/block/sde50` | 1048576 | 1.00 MiB | 299479 | `0x1000000000000000` | RO |
| 51 | `apdp` | `/dev/block/sde51` | 262144 | 256.0 KiB | 299735 | `0x0000000000000000` |  |
| 52 | `spunvm` | `/dev/block/sde52` | 8388608 | 8.00 MiB | 299799 | `0x0000000000000000` |  |
| 53 | `splash` | `/dev/block/sde53` | 34226176 | 32.64 MiB | 301847 | `0x0000000000000000` |  |
| 54 | `limits` | `/dev/block/sde54` | 4096 | 4.00 KiB | 310203 | `0x1000000000000000` | RO |
| 55 | `toolsfv` | `/dev/block/sde55` | 1048576 | 1.00 MiB | 310204 | `0x1000000000000000` | RO |
| 56 | `logfs` | `/dev/block/sde56` | 8388608 | 8.00 MiB | 310460 | `0x0000000000000000` |  |
| 57 | `cateloader` | `/dev/block/sde57` | 2097152 | 2.00 MiB | 312508 | `0x0000000000000000` |  |
| 58 | `rawdump` | `/dev/block/sde58` | 134217728 | 128.0 MiB | 313020 | `0x0000000000000000` |  |
| 59 | `logdump` | `/dev/block/sde59` | 67108864 | 64.00 MiB | 345788 | `0x0000000000000000` |  |
| 60 | `storsec` | `/dev/block/sde60` | 131072 | 128.0 KiB | 362172 | `0x1000000000000000` | RO |
| 61 | `multiimgqti` | `/dev/block/sde61` | 32768 | 32.00 KiB | 362204 | `0x1000000000000000` | RO |
| 62 | `uefivarstore` | `/dev/block/sde62` | 524288 | 512.0 KiB | 362212 | `0x1000000000000000` | RO |
| 63 | `secdata` | `/dev/block/sde63` | 28672 | 28.00 KiB | 362340 | `0x1000000000000000` | RO |
| 64 | `catefv` | `/dev/block/sde64` | 524288 | 512.0 KiB | 362347 | `0x1000000000000000` | RO |
| 65 | `catecontentfv` | `/dev/block/sde65` | 1048576 | 1.00 MiB | 362475 | `0x1000000000000000` | RO |

#### LUN5 `sdf` — 盘容量 32.00 MiB，逻辑扇区 4096 B，5 个分区

| # | 分区名 | 设备节点 | 大小(字节) | 大小 | 起始 LBA | GPT 属性 | 标记 |
|---|---|---|---|---|---|---|---|
| 1 | `ALIGN_TO_128K_2` | `/dev/block/sdf1` | 106496 | 104.0 KiB | 6 | `0x1000000000000000` | RO |
| 2 | `modemst1` | `/dev/block/sdf2` | 2097152 | 2.00 MiB | 32 | `0x0000000000000000` |  |
| 3 | `modemst2` | `/dev/block/sdf3` | 2097152 | 2.00 MiB | 544 | `0x0000000000000000` |  |
| 4 | `fsg` | `/dev/block/sdf4` | 2097152 | 2.00 MiB | 1056 | `0x1000000000000000` | RO |
| 5 | `fsc` | `/dev/block/sdf5` | 131072 | 128.0 KiB | 1568 | `0x0000000000000000` |  |

**标记含义**：`A/B` = 有 `_a`/`_b` 双槽；`RO` = GPT 属性 bit60（UEFI 规范 read-only）；
`REQ` = GPT 属性 bit0（required partition）。

### 2.2 A/B 成对清单（28 组）

`abl`、`bluetooth`、`boot`、`cmnlib`、`cmnlib64`、`devcfg`、`dsp`、`dtbo`、`featenabler`、`hyp`、`imagefv`、`init_boot`、`keymaster`、`mdtp`、`mdtpsecapp`、`modem`、`multiimgoem`、`qupfw`、`recovery`、`rpm`、`tz`、`uefisecapp`、`vbmeta`、`vbmeta_system`、`vendor_boot`、`xbl`、`xbl_config`

单槽（无 `_a/_b`）：`ALIGN_TO_128K_1`、`ALIGN_TO_128K_2`、`apdp`、`catecontentfv`、`catefv`、`cateloader`、`cdt`、`ddr`、`devinfo`、`dip`、`frp`、`fsc`、`fsg`、`keystore`、`lenovocust`、`lenovolock`、`lenovoraw`、`limits`、`logdump`、`logfs`、`metadata`、`misc`、`modemst1`、`modemst2`、`multiimgqti`、`oemowninfo`、`persist`、`rawdump`、`secdata`、`splash`、`spunvm`、`ssd`、`storsec`、`super`、`toolsfv`、`uefivarstore`、`userdata`

### 2.3 super 里的逻辑分区（`lpdump`）

super = `/dev/block/sda10`，**12.00 GiB**（12 GiB），metadata 版本 10.2，`Header flags: virtual_ab_device`。

| 逻辑分区 | 组 | 属性 | 扇区数 | 大小 | 实际 extents |
|---|---|---|---|---|---|
| `odm_a` | qti_dynamic_partitions_a | readonly | 2768 | 1.35 MiB | 0..2767@super+2048 |
| `odm_b` | qti_dynamic_partitions_b | readonly | 0 | 0 B | **空（0 长度）** |
| `product_b` | qti_dynamic_partitions_b | readonly | 0 | 0 B | **空（0 长度）** |
| `system_b` | qti_dynamic_partitions_b | readonly | 0 | 0 B | **空（0 长度）** |
| `system_dlkm_a` | qti_dynamic_partitions_a | readonly | 856 | 428.0 KiB | 0..855@super+11898880 |
| `system_dlkm_b` | qti_dynamic_partitions_b | readonly | 0 | 0 B | **空（0 长度）** |
| `system_ext_b` | qti_dynamic_partitions_b | readonly | 0 | 0 B | **空（0 长度）** |
| `vendor_a` | qti_dynamic_partitions_a | readonly | 1330616 | 649.7 MiB | 0..1330615@super+12800000 |
| `vendor_b` | qti_dynamic_partitions_b | readonly | 0 | 0 B | **空（0 长度）** |
| `vendor_dlkm_a` | qti_dynamic_partitions_a | readonly | 115104 | 56.20 MiB | 0..115103@super+14131200 |
| `vendor_dlkm_b` | qti_dynamic_partitions_b | readonly | 0 | 0 B | **空（0 长度）** |
| `system_a` | default | none | 3417968 | 1.63 GiB | 0..3417967@super+5120 |
| `system_ext_a` | default | none | 3027336 | 1.44 GiB | 0..2615295@super+9283584；2615296..3027335@super+11899904 |
| `product_a` | default | none | 5859368 | 2.79 GiB | 0..5859367@super+3423232 |

- **7 个 `_a` 逻辑分区有实体**，**7 个 `_b` 逻辑分区全部 0 长度**（只有表项，没有 extents）。
- `system_ext_a` 是**两段不连续** extent（9283584..11898880 + 11899904..12311944），是历史 resize 留下的碎片。
- super 内最高用到扇区 14246304 → 已用 **6.79 GiB / 12.00 GiB**，剩余约 **5.21 GiB** 未分配。
- 组上限：`qti_dynamic_partitions_a/b` = 12,876,513,280 B；`default` = 0（不限）。

### 2.4 设备实测 vs 出厂 GPT 交叉核对

出厂 GPT 取自 `E:\rom\TB331FC\刷机包\TB331FC_ZUI_16.0.544\image\gpt_main0..5.bin`。

**核对结果：设备实测大小与出厂 GPT 逐项一致（0 差异），但有一处必须知道的坑：**

| LUN | 出厂 GPT 里的 `last_usable` / `userdata` 末扇区 | 设备实测 | 说明 |
|---|---|---|---|
| 0 | `last_usable=3252135`，`userdata` 末扇区 3252135（**大小算出来是 0**） | userdata = 110,251,814,912 B | `gpt_main0.bin` 是**模板**；`patch0.xml` 在刷机时把 `userdata` 末扇区和 `last_usable` 改成 `NUM_DISK_SECTORS-6` |
| 1–5 | 与设备一致 | 一致 | 无需 patch |

`patch0.xml` 原文（决定性证据）：

```xml
<patch SECTOR_SIZE_IN_BYTES="4096" byte_offset="1704" filename="gpt_main0.bin"
       physical_partition_number="0" size_in_bytes="8" start_sector="2"
       value="NUM_DISK_SECTORS-6."
       what="Update last partition 14 'userdata' with actual size in Primary Header."/>
```

→ **推论**：直接拿 `gpt_main0.bin` 去算 userdata 大小会得到 0；`sda` 实际是 30,169,088 个 4096 B 扇区（115.1 GiB）。

另一个必须知道的点：**6 个 LUN 的逻辑扇区都是 4096 B**（`/sys/block/sd*/queue/logical_block_size` = 4096）。
所以 `gpt_main*.bin` 里 `EFI PART` 出现在偏移 4096 而不是 512，任何按 512 解析的 GPT 工具都会读错（本次第一版解析脚本就踩了这个坑）。

### 2.5 分类标注汇总

**逻辑分区（super 派生，出现在 `/dev/block/mapper/`）**：

`odm_a`、`odm_b`、`product_a`、`product_b`、`system_a`、`system_b`、`system_dlkm_a`、`system_dlkm_b`、`system_ext_a`、`system_ext_b`、`vendor_a`、`vendor_b`、`vendor_dlkm_a`、`vendor_dlkm_b`

外加 25 个 APEX 的 dm 设备（`com.android.*`）+ `userdata` 的 dm（`dm-swapfile` 6 GiB）+ 7 个 `*-verity` 设备。完整清单见 `02_part_dump.txt` 的 `### MAPPER_LS`。

**GPT read-only（bit60）标记的 46 个分区** —— 这是设备自己给出的、机器可读的「受保护分区」集合：

`ALIGN_TO_128K_1`、`ALIGN_TO_128K_2`、`abl_a`、`abl_b`、`bluetooth_a`、`bluetooth_b`、`catecontentfv`、`catefv`、`cdt`、`cmnlib64_a`、`cmnlib64_b`、`cmnlib_a`、`cmnlib_b`、`ddr`、`devinfo`、`dip`、`dsp_a`、`dsp_b`、`fsg`、`keymaster_a`、`keymaster_b`、`limits`、`mdtp_a`、`mdtp_b`、`mdtpsecapp_a`、`mdtpsecapp_b`、`modem_a`、`modem_b`、`multiimgoem_a`、`multiimgoem_b`、`multiimgqti`、`oemowninfo`、`recovery_a`、`recovery_b`、`rpm_a`、`secdata`、`storsec`、`toolsfv`、`tz_a`、`uefivarstore`、`vbmeta_a`、`vbmeta_b`、`vbmeta_system_a`、`vbmeta_system_b`、`xbl_a`、`xbl_b`

**Critical Partition（fastboot 禁刷，只能 9008）**：本机只读手段**无法**从 ABL 里直接读出该清单
（`abl_zui16_padded.img` 与设备 `abl_a` 的 sha256 **完全相同** = `22eaf506…43a4`，但整镜像可打印字符占比仅 8.6%，
`critical` 字串在 ASCII/UTF-16 两种编码下都命中 0 次；里面能抓到的是证书链 `Elm Attestation CA` / `Lenovo` / `QUALCOMM`）。
因此这一项按**既有真机实测记录**记录，不作为本次新证据：

| 分区 | 结论 | 依据 |
|---|---|---|
| `xbl_a` / `xbl_b` | Critical，fastboot 拒刷，只能 9008 | 历史实测记录（skill 知识库）；本次佐证：xbl 独占 LUN1/LUN2，且 GPT 属性 bit60 置位 |
| `abl_a` / `abl_b` | Critical，同上 | 同上；本次佐证：GPT 属性 bit60 置位 |

其余 bit60 分区（tz/hyp/modem/dsp/keymaster/cmnlib/cmnlib64/rpm/devcfg/qupfw/uefisecapp/featenabler/multiimgoem/storsec/secdata/devinfo/limits/toolsfv/cdt/ddr/fsg/ALIGN_TO_128K_*/vbmeta*/recovery*/mdtp*/bluetooth*/cate*/oemowninfo/uefivarstore/dip）
是否被 ABL 判为 critical **无法确定**（未做刷写实测，也不允许做）。

## 3. 关键分区内容指纹

方法：`dd if=/dev/block/by-name/<p> bs=4096 count=1` 取头部 4 KiB → `od -A x -t x1` 存证 + `sha256sum`；
整分区 ≤ 64 MiB 时算**全分区** sha256，否则算**前 64 MiB** sha256（表里 `采样` 列写明）。
**完整 4 KiB 十六进制头部**见 `07_heads_hexdump.txt`（1.27 MB，逐分区 `offset  hex  |ascii|`）。

| 分区 | 大小 | 采样 | sha256 | 头部 4 KiB sha256 | 格式判定 |
|---|---|---|---|---|---|
| `xbl_a` | 3.50 MiB | 全量 | `d3d65fab9c539f04a39721005a0e2add8c760e743e1aff645562a5f02bc39a2a` | `2c7535dd0af904439bcf0488c12feebefb69222fd4bfa9124791b41eb5d8424f` | ELF64（\x7fELF@0；e_type=2, e_machine=0xb7） |
| `abl_a` | 1.00 MiB | 全量 | `22eaf506d8c80e5c287ae23ddb918a92a0979ff9e93ef82d1c51a2fdf98143a4` | `75a13f43acac7f72c1f41005cf21dea2fa51235a97a1aa1c4af1ce0ad752818c` | ELF32（\x7fELF@0；e_type=2, e_machine=0x28） |
| `uefisecapp_a` | 2.00 MiB | 全量 | `7241d28a39135f9bb46559ad32308b144fbbd1263f5505bd3f242febb63c463d` | `e580dff272620a402c27a2027e19d5af697f42ae9d6f8838e734d4a03c4b4712` | ELF64（\x7fELF@0；e_type=3, e_machine=0xb7） |
| `imagefv_a` | 2.00 MiB | 全量 | `646baf6c6a6417875abfea047969eff6ae45cab84cd36176f3999e083c447161` | `938a93599b12ec22576cb18a8d90494dcd201fa0cd0fe9b320bdcdf2233e38aa` | ELF32（\x7fELF@0；e_type=2, e_machine=0x28） |
| `toolsfv` | 1.00 MiB | 全量 | `30e14955ebf1352266dc2ff8067e68104607e750abb9d3b36582b8af909fcb58` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `boot_a` | 96.00 MiB | 前 64 MiB | `667e1723c6abce50e2e2e4a6aaa8f4ef6a4b998d61a2871ee30d06320e35cbc8` | `04340f1336997c8b6ce3fd6e6dd2300dfff829dce054f0abe83bd5d998828923` | Android boot image v4（'ANDROID!'@0；kernel=43092480, ramdisk=0） |
| `init_boot_a` | 8.00 MiB | 全量 | `2d090fb59244cf3cf55b95478b98234f4a27615fd1c63220e685f76ae79bb01b` | `b7f64d75b13551d67d0acfd52859f7b94658ed0ca887bbf74912a2ec1dc4cb8c` | Android boot image v4（'ANDROID!'@0；kernel=0, ramdisk=2005893） |
| `vendor_boot_a` | 96.00 MiB | 前 64 MiB | `27832b98b00ec00d95d51e8d25e37fbbc482526802d238cff2c18e8384cf7733` | `68364fd72c919c9d12034f804736706d379cc8c0b7a7539177a911a47255a3a0` | Android vendor_boot v4（'VNDRBOOT'@0；page=4096） |
| `dtbo_a` | 24.00 MiB | 全量 | `ac8fc83d0818aaf7154b790398020b8cc62de9a8310c7d329a45a08980ad0c09` | `0177570b510607cc6ed022f0c971ef2cfe5788a7e05527ef3148fe5fc182ced4` | Qualcomm DTBO table（magic 0xd7b7ab1e@0） |
| `vbmeta_a` | 64.00 KiB | 全量 | `9466f0e8e95a55a0ca25504a01cdd87672557ef0fb6130c16a6fde78055223ec` | `7740d22d041e7a3b671dfcccbef69a9a0c1662a1ff5f454c0adb513cf0a0d21f` | AVB vbmeta（'AVB0'@0；libavb 1.0） |
| `vbmeta_system_a` | 64.00 KiB | 全量 | `cea948ea538c84b1d77289ac2db473077dc293764282dd84530d677efbb86643` | `c19995669eecacdfb495235e7ce5d9439830eb087a33ad4b07fb2952d96f48fd` | AVB vbmeta（'AVB0'@0；libavb 1.0） |
| `super` | 12.00 GiB | 前 64 MiB | `306a7f9daee0c6593d0ac862aa66790da74f38c542a1ccff0be8d9af5aae43a2` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `misc` | 1.00 MiB | 全量 | `45e7a8290d5011ca1c1590e57d35dc8e5349ab6bbf9fb0cf9600860b4b8187fc` | `9a0cf4176ce232cb0dccf8e0362ce1d8c2aab5c57a70168e565ae3b17c368b9e` | `bootloader_message`（偏移 8 = '-bootloader'；misc 结构） |
| `devinfo` | 4.00 KiB | 全量 | `7d6a4855f19d498a092ff0ffb44a69e114cd915d4d49acb2640035cf70e854ed` | `7d6a4855f19d498a092ff0ffb44a69e114cd915d4d49acb2640035cf70e854ed` | Qualcomm `device_info`（'ANDROID-BOOT!'@0；非零字节 14 个：0x00、0x01、0x02、0x03、0x04、0x05、0x06、0x07） |
| `persist` | 32.00 MiB | 全量 | `15cd820c821921551503d79df02239c15b409726750c3c620ba6edde770e4ca5` | `d859a7582639a3fb5e785ce53c0a101105b96584d2a3faba60c62f1d4265024e` | ext4（magic 0x53ef@0x438） |
| `modem_a` | 180.0 MiB | 前 64 MiB | `bbe4cbd55b028960c6bf700ae283115c0f0951105d87fe2f23b7b014fc891e72` | `1370c89c08aad6f0b1d3777f5d786a052c78ca8fbbd482521407d63f310dc849` | FAT12/16/32（引导扇区/OEM 串） |
| `tz_a` | 4.00 MiB | 全量 | `43de2f0c6e3b08372139edf0d3e984737bef22191f2476e94c5211523407420e` | `41cc872de2599b96d4899428d08de804fbfe758604be6ed006deaa7c66e9ff65` | ELF64（\x7fELF@0；e_type=2, e_machine=0xb7） |
| `hyp_a` | 512.0 KiB | 全量 | `c52db25e00b7773296e376294c50733a936fbc37d622a0acdbaa648428b206e1` | `1835c8d0a1d8e1c322d3fe1aba4fd6ed53881df8b768bdbcbf17654f365d6867` | ELF64（\x7fELF@0；e_type=2, e_machine=0xb7） |
| `devcfg_a` | 128.0 KiB | 全量 | `4af9275ce85f0c80f9512acfdf7879acd0543594da029460e203ca9c899f4a60` | `25f8e85785fb59e779c2b5bee263f1999439de43877a873464a648b4dbb768b9` | ELF64（\x7fELF@0；e_type=2, e_machine=0xb7） |
| `keymaster_a` | 512.0 KiB | 全量 | `b71c4171584af07a990d8a03fe86d47ca2ea71af133016a092739fb82f65961b` | `e54a47dedc696a21243c1f276dbc85075392068dc39d5fd5427e1aee29ebdb74` | ELF64（\x7fELF@0；e_type=3, e_machine=0xb7） |
| `featenabler_a` | 128.0 KiB | 全量 | `9ddea24fa0739c4057848cf1f14449004db590b88443c3dd8fb6b64fd4592e35` | `8c3c7ae76f89632737f81e889ca0b9f947dab244a5154b0845f0391edda6a0c7` | ELF64（\x7fELF@0；e_type=3, e_machine=0xb7） |
| `logfs` | 8.00 MiB | 全量 | `b8b5ac87f3d954404fc7ecbdd9ee3b5b0cf5691e5006e6ec55db4c899ff61220` | `a2d1e16bc22fe5bb92d5a22208708101adbd507727b73b2aba74b37ad02c0b52` | FAT12/16/32（引导扇区/OEM 串） |
| `logdump` | 64.00 MiB | 全量 | `3b6a07d0d404fab4e23b6d34bc6696a6a312dd92821332385e5af7c01c421351` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `fsc` | 128.0 KiB | 全量 | `fa43239bcee7b97ca62f007cc68487560a39e19f74f3dde7486db3f98df8e471` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `fsg` | 2.00 MiB | 全量 | `5647f05ec18958947d32874eeb788fa396a05d0bab7c1b71f112ceb7e9b31eee` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `modemst1` | 2.00 MiB | 全量 | `efb7a2581b57da3b2bac15b08574a13be4cf8de2350f826f1cdf937641170692` | `7fe515b5b5848bd426a3829df835abb6497e809345b4f3c6326062c50845ea7c` | 未识别（无已知 magic；前 16B=1000000003000000d801000028b375c2） |
| `modemst2` | 2.00 MiB | 全量 | `c57fbd5f93fd9d7a272d98f681bf85a37fff9ede4c884ef51639aeb83d324310` | `d6198ebfa4006be896c2c84646f600b91d10361234ed7d353ec7100fe6de9501` | 未识别（无已知 magic；前 16B=1100000003000000d801000000029c01） |
| `multiimgoem_a` | 32.00 KiB | 全量 | `786caaeeb724caf15a0d11251c366e85e9a06cf013ccde336f2090939efc9a2b` | `c571a0b1dad5a9f08228f19b1b05950b8a18fc514b02138fad38b9c0201b549a` | ELF32（\x7fELF@0；e_type=0, e_machine=0x28） |
| `qupfw_a` | 64.00 KiB | 全量 | `888d3e1d0ab5dae63a2b5492ba19f403c1b8ab4c30da2bb45d169e1fc1f9bc2f` | `f74d1ff94977d1f50ad3a85e0f4a2c812c8fbe5c02d63999daf3c36b7fd83e98` | ELF32（\x7fELF@0；e_type=2, e_machine=0xa4） |
| `dsp_a` | 32.00 MiB | 全量 | `e6dff50c4becc20edf98810a97c00784757de7554ac6bba0d58445abd42dea16` | `bf7c12c6179bbb12a88856f5c579873abf7fdb22e8195d5e16035605dd6c7a26` | ext4（magic 0x53ef@0x438） |
| `bluetooth_a` | 1.00 MiB | 全量 | `730560ac51504cabb36c701c3ab2e4f74f604ba7e7b38d4973a48280c306317f` | `2e03162d5101269627392fecb2afecaf491e1e29c8e10878271647c32926750b` | FAT12/16/32（引导扇区/OEM 串） |
| `rpm_a` | 512.0 KiB | 全量 | `45dabac5959f3667af51f313e66f0c0545931c80440d01ae2a972591a9d1e59e` | `85f8453993ef31cc1d2ff5f7ec047b797ced60d6f673777fb8cb73ba156d1f8b` | ELF32（\x7fELF@0；e_type=2, e_machine=0x28） |
| `cmnlib_a` | 512.0 KiB | 全量 | `07854d2fef297a06ba81685e660c332de36d5d18d546927d30daad6d7fda1541` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `cmnlib64_a` | 512.0 KiB | 全量 | `07854d2fef297a06ba81685e660c332de36d5d18d546927d30daad6d7fda1541` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `cdt` | 128.0 KiB | 全量 | `fa43239bcee7b97ca62f007cc68487560a39e19f74f3dde7486db3f98df8e471` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `ddr` | 1.00 MiB | 全量 | `5db5789d0cc5b42efea3bb8428da4d5f4c6bb93bcf55429896ef252ef0292a79` | `77c071b3343c264eefcda125779149bf6a327d5a78af6d9add8d5c6a6684f87a` | 未识别（无已知 magic；前 16B=000000000b0012008813000000000f00） |
| `dip` | 1.00 MiB | 全量 | `30e14955ebf1352266dc2ff8067e68104607e750abb9d3b36582b8af909fcb58` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `apdp` | 256.0 KiB | 全量 | `51be585e1c723bbe57717fd27cfbcf018d36359c2b7d27023b9e8f0ff38cdd45` | `d59ec550a0559b57c06fcdf4096bdb9597c1003e2616b2f1ac485c905fdbb8f9` | ELF64（\x7fELF@0；e_type=0, e_machine=0x28） |
| `spunvm` | 8.00 MiB | 全量 | `2daeb1f36095b44b318410b3f4e8b5d989dcc7bb023d1426c492dab0a3053e74` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `splash` | 32.64 MiB | 全量 | `efd199079045b4bad342bb57fa6f8ddebbe6fb086ee425b29de38d80443d7a6e` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `limits` | 4.00 KiB | 全量 | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `storsec` | 128.0 KiB | 全量 | `edeea784d93e57607dd197d5d10b9496bcf4aaaf0f3cace39061cfbe22ec0596` | `530da94fc60ea9f28b0f7d65f15b3d74293b14df1fe4d05c2f58f6f5fec4c0d0` | ELF64（\x7fELF@0；e_type=3, e_machine=0xb7） |
| `secdata` | 28.00 KiB | 全量 | `fc44a8d803d7fb664d0c0cf753175c023518bf1c0a1adc2c40440b2ba451cc7b` | `dddd5bd8b1d1b2817f526b0e522370d6f74db39fb653f3459a606c27b5f045e7` | ELF64（\x7fELF@0；e_type=0, e_machine=0x28） |
| `uefivarstore` | 512.0 KiB | 全量 | `9feb32a025fa1f4355dd8802535d69644b26c1ece3882a36d1c6abc73dc1baa0` | `f6148e4a6c1e4d2e3847f97efef13206fac9ca2f28ae483383ab0372b0445c8d` | 未识别（无已知 magic；前 16B=5054424c000100007d00000003000000） |
| `cateloader` | 2.00 MiB | 全量 | `5647f05ec18958947d32874eeb788fa396a05d0bab7c1b71f112ceb7e9b31eee` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `catefv` | 512.0 KiB | 全量 | `07854d2fef297a06ba81685e660c332de36d5d18d546927d30daad6d7fda1541` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `catecontentfv` | 1.00 MiB | 全量 | `30e14955ebf1352266dc2ff8067e68104607e750abb9d3b36582b8af909fcb58` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `rawdump` | 128.0 MiB | 前 64 MiB | `4ed1a02bafc87ad37253d9cf951816b7ba9191cb11799bd0d17ea9eee323eeb6` | `5138b0b2594cf43787b5bbb8f8a66cc4d0348df145aedf3c68e2bcf34ac943d5` | 未识别（无已知 magic；前 16B=5261775f446d70210010000001000000） |
| `recovery_a` | 100.0 MiB | 前 64 MiB | `264aec551474f3e4fbea9131325eac6a3e6b94d560afc50078f1062ecde22d73` | `0079bea12a0498c0e811fa927b70c77d87d95843a3053b0c42cfbd73903e280e` | Android boot image v4（'ANDROID!'@0；kernel=0, ramdisk=14572954） |
| `keystore` | 512.0 KiB | 全量 | `07854d2fef297a06ba81685e660c332de36d5d18d546927d30daad6d7fda1541` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `oemowninfo` | 1.00 MiB | 全量 | `69d27531a6884dbfd809a8c0329388b50f608667572f488c15bf3f95ad512e6b` | `81c3f6ad4a0a0212d28f14ca1dd18c110655bfeb4fd155f976f62cc3c2448e42` | 未识别（无已知 magic；前 16B=00000000000000000000000000000000） |
| `lenovolock` | 512.0 KiB | 全量 | `07854d2fef297a06ba81685e660c332de36d5d18d546927d30daad6d7fda1541` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `lenovoraw` | 16.00 MiB | 全量 | `080acf35a507ac9849cfcba47dc2ad83e01b75663a516279c8b9d243b719643e` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `lenovocust` | 300.0 MiB | 前 64 MiB | `3b6a07d0d404fab4e23b6d34bc6696a6a312dd92821332385e5af7c01c421351` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `frp` | 512.0 KiB | 全量 | `cf274201cd91474d10aa4d1c8a6536cc1039a3241017e93ef76955c1d44e7abf` | `3a2bd34d0ee810da8b3224d91766323665a2acb82277768f829785049655e188` | 未识别（无已知 magic；前 16B=d764f4c12c37e37ca42f55b62f649350） |
| `ssd` | 8.00 KiB | 全量 | `9f1dcbc35c350d6027f98be0f5c8b43b42ca52b7604459c0c42be3aa88913d47` | `ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7` | 前 4KB 全 0x00 |
| `metadata` | 64.00 MiB | 全量 | `8b6292def080e336b4f7a2431a12d2ff5251f1feb6164b408470f41a4735a2ee` | `c9a5560463e4bbe9961e2dce9eaa5bc3ef066a429b514b6f95949267cbfe3ea9` | f2fs（magic 0xF2F52010@0x400） |

### 3.1 请求清单里「设备上不存在」的分区（重要）

| 请求的分区 | 实际 |
|---|---|
| `uefi_a` | **不存在**。设备上只有 `uefisecapp_a/_b`（2 MiB ELF64，`e_type=3` DYN）与 `uefivarstore`（512 KiB，magic `PTBL`） |
| `aop_a` | **不存在**。SM6225 没有 AOP 子系统 |
| `shrm_a` / `cpucp_a` / `spuservice_a` / `soccp_*` | **不存在**。这些是 SM8250/SM7325 一级才有的分区 |
| `countrycode` | **不存在**。WiFi 国家码在 `persist` / `oemowninfo` 里，不单独开分区 |

### 3.2 整分区全零的分区（25 个）

判定方式：`sha256(整分区) == sha256(N 个 0x00)`。

| 分区 | 大小 | 说明 |
|---|---|---|
| `toolsfv` | 1.00 MiB | UEFI 工具 FV，本机未使用 |
| `logdump` | 64.00 MiB | Qualcomm logdump（崩溃时由 bootloader 写），当前空 |
| `fsc` | 128.0 KiB | modem 文件系统缓存，空 |
| `fsg` | 2.00 MiB | modem FSG（EFS 备份），空 —— EFS 实际在 modemst1/modemst2 |
| `multiimgqti` | 32.00 KiB | QTI 多镜像配置，空 |
| `cmnlib_a` | 512.0 KiB | **TEE cmnlib 全零**（见 §5 结论） |
| `cmnlib_b` | 512.0 KiB | 同上 |
| `cmnlib64_a` | 512.0 KiB | **TEE cmnlib64 全零** |
| `cmnlib64_b` | 512.0 KiB | 同上 |
| `mdtp_a` | 32.00 MiB | ModemDebugTransport，空 |
| `mdtp_b` | 32.00 MiB | 同上 |
| `mdtpsecapp_a` | 4.00 MiB | 同上 |
| `mdtpsecapp_b` | 4.00 MiB | 同上 |
| `cdt` | 128.0 KiB | Core Dump Table，空（cfg 走 ddr 分区） |
| `dip` | 1.00 MiB | DIP，空 |
| `spunvm` | 8.00 MiB | SPU VM 固件，空 |
| `splash` | 32.64 MiB | 开机 LOGO 分区，**全零** —— 开机画面不在 splash（走 `imagefv`/ABL 内置） |
| `limits` | 4.00 KiB | thermal/限流配置，空 |
| `cateloader` | 2.00 MiB | Cate loader，空 |
| `catefv` | 512.0 KiB | Cate FV，空 |
| `catecontentfv` | 1.00 MiB | Cate content FV，空 |
| `keystore` | 512.0 KiB | 空（keystore 走 TEE/keymaster） |
| `lenovolock` | 512.0 KiB | **联想锁分区全零** —— 解锁状态不在这个分区里 |
| `lenovoraw` | 16.00 MiB | 联想 raw 分区，空 |
| `ssd` | 8.00 KiB | 8 KiB，空 |

> `super` 只有**前 4 KiB 全零**（lp metadata 从偏移 4096 起），整体非零。
> `lenovocust`（300 MiB）**前 64 MiB 全零**：它的「前 64 MiB sha256」= `3b6a07d0…`，
> 与 64 MiB 全零分区 `logdump` 的全分区 sha256 完全相同 → 联想的定制分区实际是空的，300 MiB 白占。

## 4. 硬件清单

### 4.1 SoC / 平台

| 项 | 值 | 证据 |
|---|---|---|
| `/proc/device-tree/model` | `Qualcomm Technologies, Inc. KHAJE IDP nopmi` | `dt_scalar.txt` |
| `/proc/device-tree/compatible` | `qcom,khaje-idp` `qcom,khaje` `qcom,idp` | 同上 |
| `qcom,board-id` | `0x00010022`（DT 大端 u32 数组） | `od -A n -t x4` → `22000100 00000000` |
| `qcom,msm-id` | `0x00000206`, `0x00010000` | → `06020000 00000100` |
| `ro.board.platform` | `bengal` | getprop |
| `ro.soc.model` / `ro.soc.manufacturer` | `SM6225` / `QTI` | getprop |
| CPU | 8 核；`CPU implementer 0x51`(Qualcomm)、`part 0x801`(Cortex-A73)、`variant 0xa`、`revision 4` | `/proc/cpuinfo` |
| GPU / 图形 | Adreno（`ro.hardware.egl=adreno`，`ro.hardware.vulkan=adreno`，`ro.opengles.version=196610` = 3.2） | getprop |

### 4.2 内存

| 项 | 值 | 证据 |
|---|---|---|
| MemTotal | 5,778,924 kB ≈ 5.51 GiB | `/proc/meminfo` |
| MemAvailable | 2,647,112 kB | 同上 |
| DDR 型号 | **无法确定** —— 无 SPD/`ddr_type` 属性（`ro.boot.ddr_type` 为空）；`ddr` 分区仅 1 MiB 且内容为训练参数 | `ddr` 分区头部 = `00000000 0b001200 88130000 …`（0x1200=4608, 0x1388=5000 → DDR 训练频点表） |
| DDR 容量编码 | `ddr` 分区首字 = 0，第 2 字 0x1200、第 3 字 0x1388 | 同上 |

`/proc/iomem` 里与硬件相关的可用区间（节选，完整见 `hw/iomem.txt`）：

```
00400000-00ffffff : 400000.pinctrl pinctrl@400000
01c0a000-01c2ffff : spmi-0 cnfg
03f00000-03f9ffff : spmi-0 intr
04784000-04784fff : 4784000.sdhci hc
04804000-04806fff : 4804000.ufshc ufs_mem
04807000-04807dff : 4807000.ufsphy_mem phy_mem
04810000-04817fff : 4804000.ufshc ufs_ice
04a84000-04a87fff : 4a84000.i2c i2c@4a84000
04a88000-04a8bfff : 4a88000.i2c i2c@4a88000
04a94000-04a97fff : 4a94000.i2c i2c@4a94000
04ac0000-04ac1fff : 4ac0000.qcom,qupv3_0_geni_se qcom,qupv3_0_geni_se@4ac0000
04e0c100-04e0dfff : 4e00000.dwc3 dwc3@4e00000
059a0000-059affff : 59a0000.kgsl-smmu base
```

### 4.3 存储（UFS）

| 项 | 值 | 证据 |
|---|---|---|
| 控制器 | `4804000.ufshc`（host0），PHY `4807000.ufsphy_mem`，ICE `4804000.ufshc ufs_ice` | `/proc/iomem` |
| 型号 | **SAMSUNG KLUDG2R1DE-B0F1** rev `0100` | `/sys/class/scsi_device/0:0:0:{0..5}/device/model` |
| 容量 | 128 GB（LUN0 = 115.1 GiB） | `blockdev --getsize64 /dev/block/sda` |
| 逻辑扇区 | **4096 B**（全部 6 个 LUN） | `/sys/block/sd*/queue/logical_block_size` |
| physical_block_size | 4096 | 同上 |
| rotational | 0 | 同上 |

**LUN 布局**：

| LUN | 节点 | 容量 | 用途 | 分区数 |
|---|---|---|---|---|
| 0 | `sda` | 115.1 GiB | 主数据：super / userdata / persist / metadata / vbmeta_system | 14 |
| 1 | `sdb` | 8.00 MiB | `xbl_a` + `xbl_config_a` | 2 |
| 2 | `sdc` | 8.00 MiB | `xbl_b` + `xbl_config_b` | 2 |
| 3 | `sdd` | 32.00 MiB | `ALIGN_TO_128K_1` / `cdt` / `ddr` | 3 |
| 4 | `sde` | 4.00 GiB | 全部 boot 链固件（xbl 除外） | 65 |
| 5 | `sdf` | 32.00 MiB | `ALIGN_TO_128K_2` / `modemst1/2` / `fsg` / `fsc` | 5 |

> 注意：LUN1/LUN2 各只有 8 MiB，却要放 3.5 MiB 的 xbl —— 这也是 `xbl` 被单独隔离在独立 LUN 的原因（保护启动链）。

### 4.4 显示

| 项 | 值 | 证据 |
|---|---|---|
| 分辨率 | **1200 × 1920** | `wm size` = `Physical size: 1200x1920`；面板 DT `qcom,mdss-dsi-panel-width=1200`、`-height=1920` |
| 密度 | 物理 320 dpi（`ro.sf.lcd_density=320`）；`vendor.display.lcd_density=240` | `wm density` / getprop |
| 刷新率 | **90 Hz** | 面板 DT `qcom,mdss-dsi-panel-framerate=0x5A=90` |
| 模式 | DSI **video mode**（`qcom,mdss-dsi-panel-type=dsi_video_mode`），DSC 开启（`qcom,mdss-dsc-slice-width=0x258=600`, `slice-height=0x14=20`） | 面板 DT |
| DSI 通道 | **1 条**（`card0-DSI-1`、`sde-conn-0-DSI-1`），控制器 `qcom,mdss_dsi_ctrl0@5e94000`（`dsi-ctrl-hw-v2.4`），PHY `qcom,mdss_dsi_phy0@5e94400`（`dsi-phy-v4.1`） | `/sys/class/drm/` + DT |
| **活动面板** | **`qcom,mdss_dsi_panel_p255_hx83102j_fhd_video`** —— 名称 `hx83102j video mode dsi boe panel` | **`/proc/cmdline` 里 `msm_drm.dsi_display0=qcom,mdss_dsi_panel_p255_hx83102j_fhd_video`（决定性）** |
| 备选面板（DT 里有、本机未用） | `..._p255_inx_fhd_video`（`nt36523n ... inx panel`）、`..._p255_csot_fhd_video`（`nt36523n ... csot panel`）、`..._td4330_truly_v2_video/cmd`、`..._nt36672e_fhd_plus_{90,120}hz_video`、`..._sim_video` | DT 节点 + `qcom,dsi-default-panel` |
| 背光 IC | **`bkl-bl@11`**（i2c-0 地址 0x11，compatible `bkl,bkl-bl`），`bl_ctrl_dcs` 走 DCS 亮度命令，`bl-max-level=0xFFF=4095` | DT + `/sys/class/backlight/bkl-bl/max_brightness=4095` |
| 面板供电 | `dsi_panel_pwr_supply_no_labibb`（**无 LAB/IBB**，只有 `vddio` 一路） | DT |
| 面板时序（p255_hx83102j, timing@0） | hfp=0xB9=185, hbp=0x28=40, hpw=0x14=20, vfp=0x76=118, vbp=0x0C=12, vpw=0x08=8 | DT |

### 4.5 触摸

| 项 | 值 | 证据 |
|---|---|---|
| 驱动 | **Himax**：`/proc/bus/input/devices` 里 `himax-touchscreen`（input2）+ `himax-stylus`（input3） | `input_devices.txt` |
| DT 节点 | `/soc/qcom,qupv3_0_geni_se@4ac0000/spi@4a80000/touch@0`，`compatible = himax,hxcommon` + `novatek,NVT-ts-spi`，`status=ok` | DT |
| **总线** | **SPI**，控制器 `spi@4a80000`（QUPV3_0 SE，`qcom,spi-geni`，寄存器基址 0x4A80000），**CS0**（`reg=<0>`），`spi-max-frequency=0x00989680`=**10 MHz** | DT + `/proc/iomem` `04a80000` 段 |
| **中断 GPIO** | `himax,irq-gpio = <&tlmm 0x50 0x01>` → **GPIO 80**，flags 1 | DT（大端解码） |
| **复位 GPIO** | `himax,rst-gpio = <&tlmm 0x56 0x02>` → **GPIO 86**，flags 2 | 同上 |
| 坐标 | `himax,panel-coords` = `himax,display-coords` = `<0 0x2EE0 0 0x4B00>` → `<0, 12000, 0, 19200>`（屏幕坐标 ×10） | DT |
| 笔支持 | `novatek,pen-support` 存在；`himax-stylus` input 设备在跑 → **支持主动笔** | DT + input |
| 备选触摸（未用） | `novatek@62`（i2c-1，`novatek,NVT-ts`，**`status=disabled`**）、`synaptics_tcm@20`（i2c-1） | DT |

> 提示：`init_boot` ramdisk 里的 `lib/firmware/novatek_ts_fw.bin`（196,608 B）虽然叫 novatek，
> 但本机实际触摸 IC 是 Himax；修补 init_boot 时丢了它仍会导致触控异常（历史实测），说明 HAL 会统一加载该固件路径。

### 4.6 电池 / 充电 / Type-C

| 项 | 值 | 证据 |
|---|---|---|
| 电池 | `manufacturer=MITSUMI ELECTRIC`，`technology=Li-ion`，`charge_full_design=7,040,000 µAh`（7040 mAh），`cycle_count=277` | `/sys/class/power_supply/battery` |
| 电量计（fuel gauge） | **Mitsumi MM8013C**，`i2c-1` 地址 **0x55**，compatible `mm8013c10`，节点 `bms` | DT + `/sys/class/power_supply/bms` |
| 充电 IC | **SouthChip SC89601D**（兼容 `upm,upm6910d`），**主/从双充**：`sc8960x_master@6b` 在 **i2c-1**，`sc8960x_slave@6b` 在 **i2c-0**；框架节点 `soc/nopmi_chg`（`qcom,nopmi-chg`） | DT + `/sys/class/power_supply/{bba,bbc}` 的 `manufacturer=SouthChip` |
| JEITA | `nopmi_chg` 里 8 段温度阈值 + 对应 `fcc/iterm/cv` 全表（`temp_tn1..t4`） | DT |
| 快充 | `dumpsys battery`：`Max charging current 1500000`（1.5 A）、`Max charging voltage 12000000`（12 V）→ 18 W 档 | `battery_dump.txt` |
| Type-C PD | **Richtek RT1711H**，`i2c-3` 地址 **0x4E**，compatible `richtek,rt1711h`，`rt-tcpc,name=type_c_port0`，`role_def=5`，中断 GPIO `0x5D`=93 | DT |
| Type-C OVP/开关 | **Awinic AW35615**，`i2c-3` 地址 **0x22** | DT |
| Type-C 模拟音频切换 | **FSA4480**，`i2c-0` 地址 **0x42**，compatible `qcom,fsa4480-i2c` | DT |
| USB | `dwc3@4e00000`（`/proc/iomem` 0x04e0c100-0x04e0dfff），当前 `USB_CDP` | iomem + power_supply/usb |

### 4.7 音频

| 项 | 值 | 证据 |
|---|---|---|
| 声卡 | `bengal-idp-snd-card`（`compatible=qcom,bengal-asoc-snd`），`/proc/asound/cards` = `0 [bengalidpsndcar]` | `asound.txt` |
| Codec | **WCD937x**（`qcom,wcd937x-codec`，bolero 框架：`rx-macro@a600000` / `tx-macro@a620000` / `va-macro@a730000`） | DT |
| 智能 PA | **2× Awinic AW883xx**（`awinic,aw883xx_smartpa`），i2c-0 与 i2c-1 上各有 `@34`、`@35` → **立体声双 SPK** | DT |
| WSA | `wsa881x-i2c-codec@0e/@44` 节点存在，但 `vendor.audio.feature.wsa.enable=false` → **未使用** | DT + getprop |
| ADSP | `remoteproc-adsp@ab00000`，`glink-edge/qcom,gpr`，`q6prm`，`audio-pkt` | DT |
| DSP 分区 | `/vendor/dsp` ← `/dev/block/sde9`（`dsp_a`，ext4） | `/proc/mounts` |
| 耳机检测 | `bengal-idp-snd-card Headset Jack`（input4，SW=d4）+ `Button Jack`（input5） | input_devices |

### 4.8 无线（WiFi / BT）

| 项 | 值 | 证据 |
|---|---|---|
| WiFi | **SoC 内置** `qcom,icnss@C800000`（compatible `qcom,icnss`），`ipa_smmu_wlan`，接口 `wlan0` | DT + getprop |
| 蓝牙 | `bt_wcn3990`（compatible `qcom,wcn3990`）；`persist.vendor.qcom.bluetooth.soc=cherokee`；`ro.bluetooth.library_name=libbluetooth_qti.so` | DT + getprop |
| BT 音频通道 | SLIMbus `slim@a5c0000`（`qcom,slim-ngd-v1.5.0`）→ `btfmslim-driver`（`slim217,221`） | DT + `/proc/asound/pcm` 的 `btfm_bt_sco_*` |
| 固件 | `/vendor/firmware_mnt` ← `modem_a`(sde4, vfat)；`/vendor/bt_firmware` ← `bluetooth_a`(sde5, vfat) | `/proc/mounts` |
| WiFi MAC | `qca_cld3_wlan.wifiaddr=` **为空**（cmdline） | `/proc/cmdline` |

### 4.9 传感器（29 颗，全部 running）

| 器件 | 厂商 | 提供的 sensor | 证据 |
|---|---|---|---|
| **BMI3x0** | BOSCH (ver 306) | accelerometer、gyroscope、两者的 uncalibrated，各分 non-wakeup/wakeup | `dumpsys sensorservice` |
| **LTR578** | Lite-On (ver 258) | `android.sensor.light`（环境光），non-wakeup/wakeup | 同上 |
| **ams** | ams | `wake_gesture`（抬手亮屏） | 同上 |
| qualcomm（算法层） | qualcomm | gravity、linear_acceleration、game_rotation_vector、significant_motion、step_detector、step_counter、tilt_detector、device_orientation、stationary_detect、motion_detect | 同上 |

> `/sys/class/sensors/` 在 A17 上**不存在**（旧 ZUI 才有），传感器只能从 `dumpsys sensorservice` 取。
> **无磁力计、无距离传感器**（平板定位）。

### 4.10 摄像头

| 项 | 值 | 证据 |
|---|---|---|
| 后摄 | **Samsung S5K4H7 8 MP**，模组 `elm_lce_s5k4h7_rear_i`，SN `8SSC28D951370A004100000` | `vendor.debug.camera.rear.info` / `.sn` |
| 前摄 | **Samsung S5K4H7 8 MP**，模组 `elm_lce_s5k4h7_front_ii`，SN `8SSC28D951360A004100000` | `vendor.debug.camera.front.info` / `.sn` |
| CCI | `qcom,cci0`（`qcom,cci-v1.2`），子节点 `cam-sensor0`、`cam-sensor1`、`eeprom0`、`eeprom1`、`actuator0`、`camera-flash@1`、`camera-flash@2` | DT |
| HAL | `vendor.camera-provider-2-4` running；`ro.vendor.config.lgsi.camerainfo=Lgsi-Common-Camera` | getprop |

### 4.11 按键 / GPIO / 霍尔

| 项 | 值 | 证据 |
|---|---|---|
| `gpio_keys` 节点 | `/soc/gpio_keys`，`compatible=gpio-keys`，`label=gpio-keys` | DT |
| `vol_up` | `label=volume_up`，`linux,code=0x73=115`（**KEY_VOLUMEUP**），`linux,input-type=0x01`（EV_KEY），`debounce-interval=15`，`gpio-key,wakeup` | DT |
| `hall_key` | `label=hall_key`，`linux,input-type=0x05`（**EV_SW**），`linux,code=0`（**SW_LID**），`debounce-interval=15`，`gpio-key,wakeup` | DT |
| 音量减 / 电源 | **DT 里没有独立节点**；音量减与电源由 PM6125 **PON** 处理 —— `qpnp_pon`（input0，`/soc/1c40000.qcom,spmi/spmi-0/0-00/…/qcom,power-on@800`） | `input_devices.txt` |
| 输入设备汇总 | `qpnp_pon`(input0) / `gpio-keys`(input1) / `himax-touchscreen`(input2) / `himax-stylus`(input3) / `Headset Jack`(input4) / `Button Jack`(input5) | 同上 |
| 其它 IC | `qcom,pm8008@8`/`@9`（i2c-0，摄像头/显示 LDO）、`awinic@64`（`awinic,aw2016_led` LED 驱动，i2c-0）、`nq@28`（`qcom,sn-nci` NFC，i2c-0） | DT |

## 5. 关键结论（对「能不能刷、能刷什么」有影响）

### 5.1 vbmeta 覆盖范围：哪些分区受 AVB 保护，哪些不受

用 `avbtool info_image` 解析设备上的 4 个 vbmeta（完整输出见 `06_avbtool.txt`）：

| vbmeta | 大小 | 公钥 sha1 | 算法 | release string | 描述符 |
|---|---|---|---|---|---|
| `vbmeta_a` | 64 KiB（内容 256+576+6080） | `2597c218aae470a130f61162feaae70afd97f011` | SHA256_RSA**4096** | `avbtool 1.2.0` | chain→`vbmeta_system`(rsa2048 `cdbb7717…`) + 5 个 hash + 4 个 hashtree + 一批 prop |
| `vbmeta_b` | 同上，**与 `vbmeta_a` 逐字节相同** | 同上 | 同上 | 同上 | 同上 |
| `vbmeta_system_a` | 64 KiB（内容 256+320+1344） | `cdbb77177f731920bbe0a0f94f84d9038ae0617d` | SHA256_RSA**2048** | `avbtool 1.3.0` | 3 个 hashtree：`product` / `system` / `system_ext` |
| `vbmeta_system_b` | 64 KiB（内容 256+320+2432） | 同上 | 同上 | `avbtool 1.2.0` | 3 个 hashtree（**FEC 开启、尺寸是原厂 5.4 GB 那套**） |

**`vbmeta_a` 里的 hash 描述符**（直接哈希，非链式）：

| 分区 | 声明 Image Size | 说明 |
|---|---|---|
| `boot` | 46,841,856 | 哈希，flags=0 |
| `dtbo` | 3,500,977 | 哈希 |
| `init_boot` | 2,011,136 | 哈希，salt `6cb9fac0…` |
| `recovery` | 14,577,664 | 哈希 |
| `vendor_boot` | 12,939,264 | 哈希 |

**`vbmeta_a` 里的 hashtree 描述符**（dm-verity，FEC roots=2）：

| 分区 | 声明 Image Size |
|---|---|
| `odm` | 1,310,720 |
| `system_dlkm` | 352,256 |
| `vendor` | 670,437,376 |
| `vendor_dlkm` | 57,925,632 |

**通过 `vbmeta_system` 间接保护**：`system` / `product` / `system_ext`。

#### → 结论：**没有 vbmeta 描述符保护**的分区

下面这些分区在 `vbmeta_a` / `vbmeta_b` / `vbmeta_system_a` / `vbmeta_system_b` 四个镜像里**都没有任何描述符**：

| 类别 | 分区 |
|---|---|
| 启动链固件（本来就不做 AVB，靠 ABL 自己的签名校验） | `xbl_a/_b`、`xbl_config_a/_b`、`abl_a/_b`、`tz_a/_b`、`hyp_a/_b`、`devcfg_a/_b`、`keymaster_a/_b`、`cmnlib_a/_b`、`cmnlib64_a/_b`、`rpm_a/_b`、`qupfw_a/_b`、`uefisecapp_a/_b`、`featenabler_a/_b`、`imagefv_a/_b`、`multiimgoem_a/_b`、`apdp`、`devcfg`、`secdata`、`storsec`、`uefivarstore`、`multiimgqti` |
| 调制解调 / DSP | `modem_a/_b`、`dsp_a/_b`、`bluetooth_a/_b`、`mdtp_a/_b`、`mdtpsecapp_a/_b`、`modemst1`、`modemst2`、`fsg`、`fsc` |
| **刷机常改的、且不受 AVB 管的分区** | **`misc`**、**`devinfo`**、**`persist`**、**`metadata`**、**`userdata`**、**`frp`**、**`super`（本身）**、`logfs`、`logdump`、`rawdump`、`splash`、`cdt`、`ddr`、`dip`、`spunvm`、`limits`、`toolsfv`、`cateloader`、`catefv`、`catecontentfv`、`keystore`、`oemowninfo`、`lenovolock`、`lenovocust`、`lenovoraw`、`ssd` |

**这对刷机意味着什么**（按影响排序）：

1. **改 `init_boot` / `boot` / `vendor_boot` / `dtbo` / `recovery` 一定会破 AVB**（它们在 `vbmeta_a` 里有 hash 描述符）。
   当前设备 `init_boot_a` 的 ramdisk_size = 2,005,893，而 `vbmeta_a` 声明的是 2,011,136 → **已经在破 AVB 的状态下运行**（`verifiedbootstate=orange`、`veritymode=eio` 就是证据）。
2. **改 `super` 里的逻辑分区要同时管 `vbmeta_system_a`**（`system`/`product`/`system_ext` 是 hashtree，改了数据不重算 root digest 就会 dm-verity 失败）。
   这正是 2026-11-13 那次 `product_D.img` hashtree 与自身数据不符导致 panic/900E 的同一机制。
3. **`misc` / `devinfo` / `persist` / `metadata` / `frp` / `userdata` 完全不受 AVB 管**：
   - `persist` 全零会同时丢声音+录音+BT MAC（历史实证），而官方包 `rawprogram0.xml` 里 persist 的 `filename=""`，**刷官方包永远不写它**。
   - `devinfo` 只有 4 KiB：内容是 `ANDROID-BOOT!` + 全零，**唯一非零字节在偏移 `0x90` = `0x01`**。
     按 Qualcomm `device_info` 结构 `is_unlocked` 应在偏移 `0x10`，那里是 **0**。
     → 这台机器的「已解锁」状态**不在 devinfo 的 `is_unlocked` 字段**里（`lenovolock` / `keystore` 也全零），
     具体由哪块介质/哪一位承载**无法确定**（只读手段查不出，且不能做刷写实验）。
   - `misc` 1 MiB 里只有 11 个非零字节：偏移 8 起是 ASCII `-bootloader`，即标准 `bootloader_message` 结构。

### 5.2 A/B 双槽：b 槽物理齐全，但**逻辑分区全空 → b 槽不可启动**

#### 5.2.1 物理分区 a/b 比对

对每个 A/B 分区比较：大小、sha256（≤64 MiB 全量，>64 MiB 取前 64 MiB + 末 4 KiB）。

| A/B 基名 | a 大小 | b 大小 | 内容是否相同 | 说明 |
|---|---|---|---|---|
| `abl` | 1.00 MiB | 1.00 MiB | **相同** | 逐字节一致 |
| `bluetooth` | 1.00 MiB | 1.00 MiB | **相同** | 逐字节一致 |
| `boot` | 96.00 MiB | 96.00 MiB | **相同** | 逐字节一致 |
| `cmnlib` | 512.0 KiB | 512.0 KiB | **相同** | 逐字节一致 |
| `cmnlib64` | 512.0 KiB | 512.0 KiB | **相同** | 逐字节一致 |
| `devcfg` | 128.0 KiB | 128.0 KiB | **相同** | 逐字节一致 |
| `dsp` | 32.00 MiB | 32.00 MiB | **相同** | 逐字节一致 |
| `dtbo` | 24.00 MiB | 24.00 MiB | **相同** | 逐字节一致 |
| `featenabler` | 128.0 KiB | 128.0 KiB | **相同** | 逐字节一致 |
| `hyp` | 512.0 KiB | 512.0 KiB | **相同** | 逐字节一致 |
| `imagefv` | 2.00 MiB | 2.00 MiB | **相同** | 逐字节一致 |
| `init_boot` | 8.00 MiB | 8.00 MiB | **不同** | **大小相同但内容不同**（全分区 sha256 比对） |
| `keymaster` | 512.0 KiB | 512.0 KiB | **相同** | 逐字节一致 |
| `mdtp` | 32.00 MiB | 32.00 MiB | **相同** | 逐字节一致 |
| `mdtpsecapp` | 4.00 MiB | 4.00 MiB | **相同** | 逐字节一致 |
| `modem` | 180.0 MiB | 180.0 MiB | **相同** | 逐字节一致 |
| `multiimgoem` | 32.00 KiB | 32.00 KiB | **相同** | 逐字节一致 |
| `qupfw` | 64.00 KiB | 64.00 KiB | **相同** | 逐字节一致 |
| `recovery` | 100.0 MiB | 100.0 MiB | **不同** | **大小相同但内容不同**（前 64 MiB + 末 4 KiB 双点比对） |
| `rpm` | 512.0 KiB | 512.0 KiB | **相同** | 逐字节一致 |
| `tz` | 4.00 MiB | 4.00 MiB | **相同** | 逐字节一致 |
| `uefisecapp` | 2.00 MiB | 2.00 MiB | **相同** | 逐字节一致 |
| `vbmeta` | 64.00 KiB | 64.00 KiB | **相同** | 逐字节一致 |
| `vbmeta_system` | 64.00 KiB | 64.00 KiB | **不同** | **大小相同但内容不同**（全分区 sha256 比对） |
| `vendor_boot` | 96.00 MiB | 96.00 MiB | **不同** | **大小相同但内容不同**（前 64 MiB + 末 4 KiB 双点比对） |
| `xbl` | 3.50 MiB | 3.50 MiB | **相同** | 逐字节一致 |
| `xbl_config` | 128.0 KiB | 128.0 KiB | **相同** | 逐字节一致 |

汇总：**23 组 a/b 内容完全一致**，**4 组不同**（`init_boot`、`vendor_boot`、`recovery`、`vbmeta_system`）。

> 也就是说：**b 槽的物理分区不是空的、也不是残缺的**，除了 4 组之外都和 a 槽逐字节相同。
> 唯一「大小相同但内容不同」的 4 组，正好是历次实验改过的分区。

#### 5.2.2 真正的 b 槽问题：super 里 7 个 `_b` 逻辑分区全是 0 长度

`lpdump` 明确列出 `odm_b`、`product_b`、`system_b`、`system_dlkm_b`、`system_ext_b`、`vendor_b`、`vendor_dlkm_b` **全部 `Extents:` 为空**。

而 `vbmeta_system_b` 是**原厂 ZUI 16 那一份**，它声明的分区尺寸是：

| 分区 | `vbmeta_system_b` 声明 | super 里 `_b` 实际 |
|---|---|---|
| `system` | 5,406,855,168 B（含 FEC） | **0 B** |
| `product` | 584,949,760 B | **0 B** |
| `system_ext` | 452,763,648 B | **0 B** |

→ **b 槽不可启动**：`vbmeta_system_b` 描述的三个 hashtree 分区在 super 里根本不存在，
`dm-verity` 无从建立，init 会在挂载 `system` 时失败。切到 b 槽必然起不来。

这也解释了历史现象：为什么「成对回滚槽位」时只能刷回 a 槽内容，而不能指望 b 槽当备份。

### 5.3 super 元数据：能腾多少空间、动过哪里

| 项 | 值 |
|---|---|
| super 分区 | 12,884,901,888 B（12 GiB），起始扇区 2048，`Flags: none` |
| metadata | version 10.2，1384 B / 上限 65536 B，**3 个 slot**，`Header flags: virtual_ab_device` |
| 当前 slot | `_a`；`Boot indicator: booting from unknown slot`；快照状态 `Update state: none` |
| 已用 | 最高扇区 14,246,304 → **6.79 GiB** |
| 空闲 | **约 5.21 GiB**（碎片化：分区之间有 6 处空隙） |

**super 内的空隙明细**（扇区，按 512 B/扇区）：

| 空隙 | 扇区范围 | 大小 |
|---|---|---|
| #1 | 4816 .. 5119 | 152.0 KiB |
| #2 | 3423088 .. 3423231 | 72.00 KiB |
| #3 | 9282600 .. 9283583 | 492.0 KiB |
| #4 | 11899736 .. 11899903 | 84.00 KiB |
| #5 | 12311944 .. 12799999 | 238.3 MiB |
| #6 | 14130616 .. 14131199 | 292.0 KiB |


**`_a` 逻辑分区实际尺寸（可据此规划 resize）**：

| 逻辑分区 | 大小 | 扇区 |
|---|---|---|
| `odm_a` | 1.35 MiB | 2768 |
| `system_dlkm_a` | 428.0 KiB | 856 |
| `vendor_a` | 649.7 MiB | 1330616 |
| `vendor_dlkm_a` | 56.20 MiB | 115104 |
| `system_a` | 1.63 GiB | 3417968 |
| `system_ext_a` | 1.44 GiB | 3027336 |
| `product_a` | 2.79 GiB | 5859368 |

对照 `vbmeta_system_a` 声明的 Image Size（数据段，不含 hashtree）：

| 分区 | vbmeta_system_a 声明 | super 里实际 | 差 |
|---|---|---|---|
| `product` | 2.71 GiB | 2.79 GiB | 实际 = 声明 + 90001408 B（= hashtree 预留 + 对齐余量） |
| `system` | 1.58 GiB | 1.63 GiB | 实际 = 声明 + 52502528 B（= hashtree 预留 + 对齐余量） |
| `system_ext` | 1.40 GiB | 1.44 GiB | 实际 = 声明 + 46501888 B（= hashtree 预留 + 对齐余量） |

> 一致性校验通过：`vbmeta_system_a` 声明的 `product` Image Size 2,909,995,008 + Tree Size 22,921,216 = 2,932,916,224，
> 小于分区实际 2,999,996,416 → **footer 位置合法**，说明当前 a 槽的 vbmeta 与分区尺寸是自洽的（能开机）。

### 5.4 其它对刷机/移植有影响的观察

1. **`init_boot_a` 与 `init_boot_b` 大小相同但内容不同**（ramdisk 2,005,893 vs 2,005,872），且都 ≠ `vbmeta_a` 声明的 2,011,136。
   → a/b 两侧都被改过（KSU 修补痕迹），不能靠「b 槽是原厂」来当回滚底牌。
2. **25 个分区整块全零**，其中 `cmnlib_a/_b`、`cmnlib64_a/_b`（TEE 关键库）全零而系统仍能正常运行 ——
   说明这台机器的 keymaster/TEE 走的是别处（`keymaster_a` 有内容，`/vendor/firmware` 有 TEE 应用），
   **但反过来说明：拿「分区非空」当「分区健康」的判据在这台机器上不成立**（与 persist 全零那次同源的教训）。
3. **`splash`（34 MB）全零** —— 开机 LOGO 不从这个分区出，改 splash 不会有任何视觉变化。
4. **`lenovolock`（512 KiB）全零** —— 联想自己的锁状态分区是空的。`devinfo`（4 KiB）也只有 magic + 一个 `0x01` 字节，
   `is_unlocked` 字段（偏移 0x10）为 0。**「已解锁」这件事在设备上找不到一个直接的字节级证据**，只能从
   `ro.boot.verifiedbootstate=orange` 反推。
5. **`keystore` 分区全零**，但 `ro.boot.verifiedbootstate=orange` 说明设备已解锁 —— 再次印证解锁标志不在 keystore/lenovolock。
6. **6 个 LUN 全是 4096 B 逻辑扇区**：任何按 512 B 解析 GPT / 计算 `start_sector` 的脚本都会错位。
   `rawprogram0.xml` 里 `SECTOR_SIZE_IN_BYTES="4096"`，`fh_loader` 必须带 `--memoryname=ufs` 且 XML 里的 `SECTOR_SIZE_IN_BYTES` 不能被改。
7. **`super` 里 `system_ext_a` 是两段不连续 extent** —— 以后 `resize` / `delete` / `create` 逻辑分区前先 `lpdump` 确认，
   不要假设逻辑分区连续。
8. **设备每 ~20 分钟自动重启一次**（本次会话 2 次），重启后 `ro.boot.bootreason=bootloader`。
   任何刷写/取证流程都要假设「设备随时会掉」，脚本必须幂等 + 可续跑。

## 6. 中间产物索引（同目录）

| 文件 | 内容 |
|---|---|
| `REPORT.md` | 本报告 |
| `01_byname_ls.txt` | `/dev/block/by-name/` 原始 `ls -l` |
| `02_part_dump.txt` | 分区表 + mapper + **完整 lpdump** + `/proc/mounts` + 整盘大小（原始输出） |
| `03_fp.tsv` | 全分区 sha256 / 头部 4 KiB sha256 原始表 |
| `04_analyze.txt` | 全零分区判定 + 格式判定（脚本输出） |
| `05_gpt.txt` | 6 个 LUN 的出厂 GPT 解析结果 |
| `06_avbtool.txt` | 4 个 vbmeta 的 `avbtool info_image` 完整输出 |
| `07_heads_hexdump.txt` | **62 个分区的前 4 KiB 十六进制头部**（1.27 MB，`offset  hex  |ascii|`）；未覆盖的是 b 槽孪生分区与 <4 KiB 的小配置分区 |
| `08_tail.txt` | 大分区末 4 KiB sha256（A/B 比对用） |
| `09_abl_scan.txt` | ABL 镜像扫描（找 critical 清单的失败记录） |
| `10_stats.txt` / `11_byname.tsv` | 统计与规整后的分区表 |
| `head/`、`hw/h4k/` | 头部 4 KiB 的 od 文本 / 原始二进制 |
| `hw/`、`hw2/`、`hw4/`、`hw5/` | 硬件采集原始输出（getprop、DT、dmesg、sysfs 等） |
| `*.sh` / `*.py` | 全部采集与分析脚本（可直接重跑） |

---

**未能确定的三项**（按「查不到就写无法确定」的要求）：

1. **ABL 的 Critical Partition 清单** —— 只读手段读不出（见 §2.5）。
2. **DDR 型号/容量编码** —— 无 SPD、无 `ddr_type` 属性，`ddr` 分区只有训练参数。
3. **`super` 末尾 4 KiB 的 sha256** —— toybox `dd` 在 3,145,727 块的大偏移 `skip` 上返回 0 字节（`e3b0c442…` = 空输入哈希）。
   该区域按 `lpdump` 推断应为未分配的空白，但**未取到字节级证据**。

