# TB331FC（khaje / SM6225-AD / 骁龙 685 / bengal）超频可行性报告

> 取证时间：2026-11-25 18:00–18:50（设备在线、只读）
> 设备：`TB331FC`，`ro.board.platform=bengal`，`ro.soc.model=SM6225`，`ro.soc.manufacturer=QTI`
> 内核：`5.15.167-android13-5.15.167_r00-dirty #1 SMP PREEMPT Sun Aug 9 16:49:46 UTC 2026`
> 编译：clang 17.0.4 + LLD 17.0.4；`CONFIG_CFI_CLANG=y`、`CONFIG_LTO_CLANG_FULL=y`、`CONFIG_MODULE_SIG=y`（`SIG_FORCE` 未开）
> 本次全部操作：`cat` / `od` / `find` / `dd`（只读）、`adb pull`、一次 90 s 纯 CPU 负载采样。**没有写过任何 sysfs 值，没有刷任何分区。**

---

## 0. 一句话结论

**这台机器没有"超频"空间，只有"解锁 / 钉频 / 温控"空间。**

| 方向 | 能否超 | 依据（本机实测，不是猜） |
|---|---|---|
| **CPU** | ❌ 不能。已在芯片最高档 | 大簇 2.8032 GHz / 小簇 1.9008 GHz 已是 LUT 全部有效项；`scaling_max_freq` 已等于 `cpuinfo_max_freq`；LUT 在硬件寄存器里，DT 上根本没有 CPU 的 `opp-table` |
| **GPU** | ⚠️ 只能在 1260 MHz 以内"选档"，超不上去 | 厂商 DT 的 bin0 顶档 **1260 MHz 已是本颗芯片最高档**；时钟源 `gpucc-khaje.ko` 里写死的频率表最大也是 1260 MHz → DT 写更高频率会被时钟驱动夹回 1260 |
| **内存（LPDDR4X）** | ❌ 不能，也没接口 | `ddr-freq-table` 最高 ≈2092 MHz（≈LPDDR4X-4266，已到颗粒额定）；DDR 时钟由 bootloader/RPMh 决定，kernel 侧只有带宽投票（`qcom,bus-freq`） |
| **A 层（纯软件）** | ✅ 可做，但**收益≈0** | 出厂状态已无任何限制：最大频=硬件最大、`thermal_pwrlevel=0`、GPU `max_freq=1260`、`core_ctl` 关闭。压测 90 s 全核钉在 2.8 GHz、温度 90 ℃ / 限值 110 ℃ 也没掉频 ⇒ 没有"被压住"的性能可以释放 |

**给 lead 的直答**：
1. **能超吗？** 不能。CPU 已顶格、GPU 顶格就是 1260 MHz、内存到颗粒额定；三个方向都没有真实余量。
2. **A 层能白拿多少？** 约 **0（上限个位数 %）**。能做的是钉 GPU 顶档、把 CPU 最小频拉高（省 ramp 延迟）——对**平均帧 / 跑分**几乎不可见，代价是常驻功耗与发热明显上升。**不建议为跑分或日常去改。**
3. **B 层值不值得做？** **不值得**。DT 能改的两处（GPU 频率、电压档）都被"时钟表写死在 vendor 模块里"卡住：改频率表要重编 `gpucc-khaje.ko`（无公开源码），改完还得重打 `vendor_boot`（11.6 MB lz4 ramdisk + 1.29 MB dtb，且被 vbmeta 哈希覆盖）。收益 0、风险高。

---

## 1. 当前频率表实况（实测）

### 1.1 CPU（`qcom-cpufreq-hw`，governor = `walt`）

| 簇 | policy | 核 | 能力值 | 可用频率（kHz，实测 `scaling_available_frequencies`） | `cpuinfo_min/max` | `scaling_min/max` | 当前 |
|---|---|---|---|---|---|---|---|
| 小簇 A53×4 | `policy0` | cpu0-3 | 433 | 300000 / 691200 / 940800 / 1190400 / 1516800 / 1804800 / **1900800** | 300000 / **1900800** | 691200 / **1900800** | 1900800 |
| 大簇 A73×4 | `policy4` | cpu4-7 | 1024 | 300000 / 806400 / 1056000 / 1344000 / 1766400 / 2208000 / 2400000 / 2592000 / **2803200** | 300000 / **2803200** | 1056000 / **2803200** | 2803200 |

- `scaling_driver = qcom-cpufreq-hw`；`scaling_available_governors = ondemand userspace walt conservative powersave performance schedutil`
- `scaling_boost_frequencies` **为空**（没有额外 boost 档可开）
- CPU 频率表的真正来源是 **硬件 LUT 寄存器**，不是 DT：

  ```
  /sys/firmware/devicetree/base/soc/qcom,cpufreq-hw
      compatible = "qcom,cpufreq-hw"
      reg = <0xf521000 0x1000 0xf523000 0x1000>      ← freq-domain0 / freq-domain1
      qcom,max-lut-entries = <0x0c>                  ← 12 行 LUT
  /sys/firmware/devicetree/base/cpus/cpu@0 … cpu@3    → qcom,freq-domain = <&cpufreq-hw 0>
                                   cpu@100…103       → qcom,freq-domain = <&cpufreq-hw 1>
  ```

  `/cpus/*` 下**没有任何 `operating-points-v2` / `opp-hz`**；`/proc/config.gz` 里 `# CONFIG_ARM_QCOM_CPUFREQ_HW is not set`（驱动是 vendor 模块 `qcom-cpufreq-hw.ko`，在 `vendor_boot` ramdisk 内）。
- 驱动行为（与主线 `drivers/cpufreq/qcom-cpufreq-hw.c` 同构）：`qcom_cpufreq_hw_read_lut()` 逐个读 `reg_freq_lut / reg_volt_lut` 生成 OPP；DT 有表就先全禁用再用 LUT 交叉校验，DT 没表就直接用 LUT。**⇒ 改 DT 不可能"加频率点"，这是硬件表。**
- 当前 perf-state（只读寄存器 dump，`/sys/kernel/qcom-cpufreq-hw/print_cpufreq_debug_regs`）：
  `FREQUENCY DOMAIN 0 PERF_STATE_DESIRED: 0x6`（第 7 项 = 1900800，顶档）
  `FREQUENCY DOMAIN 1 PERF_STATE_DESIRED: 0x8`（第 9 项 = 2803200，顶档）
- 调度侧：`core_ctl enable=0`（`min_cpus=1 / max_cpus=4` 但**未生效**）；`msm_performance` 的 `cpu_min_freq` 全 0、`cpu_max_freq` 全 INT_MAX（**当前没有外部限频**）。`core_ctl global_state` 里 CPU5 / CPU7 `Paused: 1` 是 WALT 的 sync-pause 记账，不是真的下线（`/sys/devices/system/cpu/online = 0-7`，`cpuinfo_cur_freq` 正常）。

### 1.2 GPU（`msm_kgsl`，vendor 模块；devfreq governor `msm-adreno-tz`）

| 参数 | 值 |
|---|---|
| `gpu_model` | `Adreno610v2`（`qcom,chipid = <0x06010001>`） |
| 频率表 | `1260 / 1114 / 1025 / 785 / 600 / 465 / 320` MHz（7 档，`gpu_available_frequencies` = `devfreq/available_frequencies`） |
| `num_pwrlevels` / `max_pwrlevel` / `min_pwrlevel` / `default_pwrlevel` | 7 / 0 / 6 / 6 |
| `thermal_pwrlevel` | **0**（= 没有热限档） |
| `min_clock_mhz` / `max_clock_mhz` | 320 / **1260** |
| `devfreq min/max/cur` | 320 MHz / **1260 MHz** / 320 MHz（空闲） |
| 可用 governor | **只有** `msm-adreno-tz` |

DT 里有两套 GPU 表，**只有 kgsl 生效的那套是真的**：

1. `gpu-opp-table`（给 DRM/MSM 用的，`opp-hz` 320…980，`opp-microvolt` = 64/128/192/256/320/384/416/448 的 **RPMh 档位号**）→ 本机 `CONFIG_DRM_MSM` 未编进 GKI、kgsl 是 vendor 模块，**这张表没人用**。
2. `qcom,kgsl-3d0@5900000/qcom,gpu-pwrlevel-bins/qcom,gpu-pwrlevels-{0..4}`：按 nvmem `speed_bin` 选 bin，本机是 **bin0**（`qcom,speed-bin = <0x00>`）。bin0 各档：

| pwrlevel | 频率 | `qcom,level`（RPMh 档位） | 对应 mainline 宏 |
|---|---|---|---|
| @0 | **1260 MHz** | `0x1a0` = **416** | `RPM_SMD_LEVEL_TURBO_NO_CPR` |
| @1 | 1114 MHz | 416 | 同上 |
| @2 | 1025 MHz | `0x180` = 384 | `LEVEL_TURBO` |
| @3 | 785 MHz | `0x100` = 256 | `LEVEL_NOM` |
| @4 | 600 MHz | `0xc0` = 192 | `LEVEL_SVS_PLUS` |
| @5 | 465 MHz | `0x80` = 128 | `LEVEL_SVS` |
| @6 | 320 MHz | `0x40` = 64 | `LEVEL_LOW_SVS` |
| @7 | 0（占位） | 64 | — |

其他 bin：`0xeb`→顶 1114、`0xd8`→顶 1025、`0x9d`→顶 745、`0x7f`→顶 600。**本机取 bin0，已是最好的一档。**

**GPU 时钟源（决定性证据）**：`/lib/modules/gpucc-khaje.ko` 里固化的 `freq_tbl` 只有
`320 / 465 / 600 / 785 / 820 / 980 / 1025 / 1114 / 1260 MHz`
（主线 `drivers/clk/qcom/gpucc-sm6225.c` 的表是 320…1114 且含 745/900/950 —— **厂商表与主线表不同**）。
`clk_rcg2` 只能选出表内档位，**DT 里写 1300 / 1400 MHz 也会被夹回 1260**。

### 1.3 电压 / 稳压器（谁真正决定"能不能再高"）

- 本机 CPU / GPU 的 VDD 走 **RPMh level 接口**，不是微伏：

```
regulator.1  pm6125_s3_level          enabled  level=256   range 16..512
regulator.2  pm6125_s3_floor_level    disabled             16..512
regulator.4  pm6125_s5_level          disabled             16..512
regulator.11 pm6125_l2_level          disabled             16..512
regulator.12 pm6125_l3_level          disabled             16..512
regulator.44 gpu_cx_gdsc / 45 gpu_gx_gdsc   （GDSC 开关域，空闲时 disabled）
```

- level 型稳压器的 `min_microvolts / max_microvolts` 显示的是 **level 号（16..512）**，不是 mV —— 所以"把 `regulator-max-microvolt` 调大"在这里**没有对应概念**。
- LUT 里的电压编码（`LUT_VOLT * 1000` 微伏）**只读取不到**：`print_cpufreq_debug_regs` 只 dump `PERF_STATE_DESIRED / CYCLE_CNTR / PSTATE_STATUS`；`qcom-cpufreq-hw-debug.ko` 的 `cpufreq_hwregs_show` 是只读 sysfs 属性，没有 LUT 写入口。
- 关键量化：**档位上限 512** 里，最高实用户是 416（`TURBO_NO_CPR`），448（`TURBO_HIGH`）、512（`BINNING`）在 mainline 宏里存在但没人引用 ⇒ 就算硬塞更高档，也是"没有标定过的电压"。

### 1.4 温控（这决定了"超了会不会烧"）

`/sys/class/thermal/` 共 **25 个 zone**（+ 36 个 cooling device）。**确实没有 `thermal_message`**（小米/澎湃那套用户态温控不存在），但**内核侧有完整 trip + LMH**：

| zone | 类型 | trip（均 passive） | 挂的 cooling device |
|---|---|---|---|
| 7–10 | `cpu-1-0..3` | 110 / 115 / 125 / 125 ℃（4 档） | `cpufreq-cpu4`（max_state=8）、`thermal-pause`、`pause-cpu*`、`lmh-cpu-vdd0` |
| 11–13 | `cpuss-0..2` | 110 / 115 / 125 / 125 ℃ | 同上 + `qti_cpufreq_cdev` |
| 16 | `gpu` | **95 / 100 / 100 / 115 / 125 ℃（5 档）** | `devfreq-5900000.qcom,kgsl-3d0`（max_state=6） |
| 1 | `mapss` | 115 / 125 ℃ | — |
| 0, 2–6, 14, 15, 17–24 | `pm6125-tz / cdsp-hvx / wlan / camera / video / mdm / display / xo-therm / pa-therm0 / quiet-therm / charger_therm / bms / battery …` | 多数两档 | 各自 cdev |

- 另有 `bcl_soc.ko`、`bcl_pmic5.ko`（电池电流限流）、`lmh_cpu_vdd_cdev`（硬件 LMH 直接压频，绕过 governor）—— **这些就是"烧不起来"的保险**，但也意味着热到一定程度它会自己降频，超频收益会被吃掉。
- 关键旁证：`/sys/class/kgsl/kgsl-3d0/thermal_pwrlevel = 0`、`throttling = 0`、`temp = 0`（kgsl 自己没在限），GPU zone 目前 34.7 ℃。

### 1.5 本机负载实测（90 s，8 条 busy loop，只读采样）

| t(s) | policy0 | policy4 | gpu | cpu-1-3 | cpuss-0 | gpu_z | mapss | 电池 |
|---|---|---|---|---|---|---|---|---|
| 0 | 1900800 | 2803200 | 320 MHz | 52.1 ℃ | 51.3 ℃ | 35.5 ℃ | 45.5 ℃ | 4.144 V / -180 mA |
| 10 | 1900800 | 2803200 | 320 MHz | 85.3 ℃ | 89.9 ℃ | 57.9 ℃ | 77.6 ℃ | 4.085 V / **-1015 mA** |
| 30 | 1900800 | 2803200 | 320 MHz | 91.1 ℃ | 88.4 ℃ | 62.1 ℃ | 79.1 ℃ | 4.084 V / -992 mA |
| 60 | 1900800 | 2803200 | 320 MHz | 88.4 ℃ | 90.3 ℃ | 62.9 ℃ | 79.1 ℃ | 4.09 V / -818 mA |
| 90 | 1900800 | 2803200 | 320 MHz | 89.6 ℃ | 89.9 ℃ | 62.9 ℃ | 79.1 ℃ | 4.086 V / -832 mA |

- **全程没有任何降频**：两个簇钉在最大频，`PERF_STATE_DESIRED` 一直是 6 / 8；`time_in_state` 显示大簇 2.8 GHz 累计从 ~74.9 s 涨到 146.8 s（+72 s，等于 4 核 × 90 s 满档）。
- 稳态温度 **90 ℃ / 限值 110 ℃（CPU）**、**63 ℃ / 限值 95 ℃（GPU）**，还有 20–30 ℃ 余量。
- 整机功耗 ≈ 4.09 V × 0.85 A ≈ **3.5 W**（纯 CPU 满载），电池包温度只升到 26.5 ℃。
- **这条实测的含义**：出厂状态既没限频、也没触发热降频 ⇒ A 层"解除限制"类操作**拿不到任何性能**。

---

## 2. 分区事实（改哪里、能不能改）

本机的启动镜像分工很反直觉，务必按这张表操作：

| 分区 | 大小 | 内容（实测） | 与"超频"的关系 |
|---|---|---|---|
| `boot_a` | 96 MiB | `ANDROID!` **header v4，无 ramdisk、无 DTB**，只有 GKI `Image` | 社区内核 `yxyyds666/TB331FC-Kernel` 只改这里（CI 用 `scripts/repack.py` 换 kernel 段） |
| `vendor_boot_a` | 100 MiB | vendor ramdisk **11,628,676 B（lz4-legacy，magic `0x02214C18`）**，内含 `/lib/modules/qcom-cpufreq-hw.ko`、`gpucc-khaje.ko`、`msm_kgsl.ko`、`qcom-dcvs.ko`、`lmh_cpu_vdd_cdev.ko` 等；**dtb 段 1,290,690 B**（`d00dfeed`，就是含 GPU pwrlevel 的基座 DTB） | **GPU 频率表在这里**；CPU 频率驱动的模块也在这里 |
| `dtbo_a` | 24 MiB | 自定义 magic `0xd7b7ab1e`（AVB 1.0 stub），**45 个 overlay**（khaje / khajeg / khajep / khajeq 的 ATP / IDP / QRD 各变体）。本机 overlay = `offset 0x1fcdd`，`qcom,board-id = <0x10022 0x00>`、`qcom,msm-id = <0x206 0x10000>`，`model = "Qualcomm Technologies, Inc. KHAJE IDP nopmi"` | overlay 只做板级微调，**不含 GPU 频率表** |
| `vbmeta_a` | 8 KiB（stock 544） | `SHA256_RSA4096`，hash 描述符覆盖：`boot / dtbo / init_boot / recovery / vendor_boot / odm / system_dlkm / vendor / vendor_dlkm`，外加 chain→`vbmeta_system` | **`dtbo` 与 `vendor_boot` 都被 vbmeta 哈希覆盖** |

> 结论：**任何"改 DTS"的动作都不是只改一个文本文件** —— GPU 表在 `vendor_boot` 的 dtb 段，改完必须重打 `vendor_boot.img`（ramdisk 段保留、dtb 段替换、头部 `dtb_size` 同步），并且因为被 vbmeta 哈希覆盖，要么同步更新 `vbmeta_a`，要么接受 AVB 红/橙态。

现成工具（本机已有，可直接用）：
- `E:\rom\work\tools\unpack_vendor_boot.py` / `repack_vendor_boot.py`
- `E:\rom\work\img-boot-group\tools\dtbo.py`（dtbo 打包 / 解包，magic `0xd7b7ab1e`）
- `E:\rom\work\img-boot-group\dtbo_extract\vendor_boot_base.dts`（**已解好的基座 DTS，352,956 B**，GPU 表在 6506–6590 行）

---

## 3. 三层可行性与预期收益

### A 层 · 纯软件（不重编内核）—— **可行但没收益**

| 想干的事 | 现状 | 能做吗 | 真实收益 |
|---|---|---|---|
| 提高 CPU `scaling_max_freq` | 已 = `cpuinfo_max_freq`（1900800 / 2803200） | 写了也没用（会被 hardware max 夹回） | **0** |
| 换 governor → `performance` | 现状 `walt`，压测下已全程顶档 | 可（写 `scaling_governor`） | **≈0**，反而空闲也顶档，续航变差 |
| 提高 `scaling_min_freq`（大簇 1056→2803） | 可以 | 可 | 只省 ramp 延迟；跑分 +1–3%（误差级），待机功耗明显上升 |
| `walt/boost`、`hispeed_freq`、`target_load` | `boost=0`、`hispeed_freq=1344000`、`hispeed_load=90` | 可 | UI 轻微跟手，不可量化 |
| GPU 钉顶档（`devfreq/min_freq=1260000000` 或 `kgsl min_pwrlevel=0`） | `min_freq=320`、`min_pwrlevel=6` | **可，且是唯一有意义的 A 层动作** | 游戏/掉帧场景**稳定性**小幅改善（ramp 延迟 ~80 ms 消除）；`gpu_clock_stats` 已显示 1260 MHz 累计占比很高 ⇒ 平均帧提升很小 |
| 关温控（`thermal_zone*/mode=disabled` / 清 trip） | trips 95–125 ℃，实测最高 90 ℃ | 可，但**不该做** | **0**（压测都没碰到 trip），只丢掉保险 |
| 关 `msm_performance` / `bcl` | 两者当前都没在限 | — | **0** |
| 改 `core_ctl`（enable=0→1，min_cpus=4） | 当前关闭、全 8 核在线 | 可 | **0**，甚至负收益（调度抖动） |

**A 层结论**：能改的开关一大把，**但没有一个是"被压住的性能"**。唯一值得保留的是"游戏时把 GPU 钉到 1260"这一条，属于调优不属于超频。

### B 层 · 设备树（改 `opp-table`）—— **技术上可做，收益为 0，风险高**

| 想改的表 | 位置 | 改完会怎样 |
|---|---|---|
| `gpu-opp-table`（DRM 用的那张，`opp-hz` 320–980） | `vendor_boot_base.dts` 的 `soc/gpu-opp-table` | **没人用**：kgsl 是 vendor 模块（`modinfo` 指向 `/vendor/lib/modules/msm_kgsl.ko`），GKI 里 `CONFIG_DRM_MSM is not set`。改了不生效 |
| `qcom,gpu-pwrlevels-0/qcom,gpu-pwrlevel@0/qcom,gpu-freq`（真表） | `vendor_boot_base.dts:6518-6525`（`qcom,gpu-freq = <0x4b1a1300>` = 1260 MHz） | 写 **≤1260** 只是降档；写 **>1260**（如 1400）→ `gpucc-khaje.ko` 的 `freq_tbl` 里没有 → `clk_rcg2` 夹回 1260 → **不生效**，还白冒一次开机失败风险 |
| 把 `qcom,level` 从 416 提到 448 / 512（想"给更高电压"） | 同上 `qcom,level` 字段 | 448/512 档在 mainline 宏里存在但**没有任何频率点标定过**；拿不到额外性能，只会改电压/功耗曲线 |
| `cpufreq_hw` 加频率点 | **DT 里没有 `cpu-opp-table`**，`qcom,max-lut-entries = <0x0c>` 只是"读 12 行" | LUT 在 SoC 寄存器里（`0xf521000 / 0xf523000`），**DT 无法新增频率**。这条路不存在 |
| `ddr-freq-table` / `qcom,bus-table-ddr` | `soc/ddr-freq-table`（≈200 / 547 / 768 / 1017 / 1555 / 1804 / 2092 MHz）、`qcom,kgsl-3d0@5900000/qcom,bus-table-ddr` | 只影响带宽投票；DDR 时钟由 bootloader / RPMh 决定，**改 DT 不改变实际 DDR 频率** |

**如果非要试 B 层（不推荐）**，最小闭环是：
1. 用 `unpack_vendor_boot.py` 拆 `vendor_boot_a`，用 `dtc` 把 dtb 段反编译 → 改 `qcom,gpu-pwrlevels-0/...@0/qcom,gpu-freq`；
2. `dtc -I dts -O dtb` 重编（注意 `#address-cells / #size-cells`、`reg` 不能动），`repack_vendor_boot.py` 回填（**dtb 段长度变了必须同步头里的 `dtb_size`**）；
3. `fastboot flash vendor_boot_a`（在 a 槽时）→ 同时准备 `vbmeta_a`（AVB hash 描述符要重算，否则红/橙态）；
4. 观察 `cat /sys/class/kgsl/kgsl-3d0/freq_table_mhz`、`devfreq/available_frequencies` 是否出现新档 —— **大概率看不到**（时钟源夹死）。

风险等级：**高**（`vendor_boot` 是启动关键分区，坏了直接 900E；它还同时装着 11.6 MB 的 vendor 模块 ramdisk，打错一次等于丢全部 vendor 模块）。

### C 层 · 内核代码 —— **没有可行路径（硬件表 + 无源码）**

| 组件 | 在哪 | 要改什么 | 现实障碍 |
|---|---|---|---|
| CPU 频率表 | `qcom-cpufreq-hw.ko`（在 `vendor_boot` ramdisk） | 让驱动在 LUT 之外"造"频率点 | LUT 是 XBL 写好的硬件表（12 行，9 行有效）；驱动只能读不能写。要"造点"必须直接 poke LUT 寄存器（无 `/dev/mem` 访问、无 debugfs 写接口）—— **等于改 SoC 内部状态，没有任何公开先例** |
| GPU 频率表 | `gpucc-khaje.ko`（同上） | 往 `freq_tbl` 里加 1300 / 1400 MHz + 对应 PLL 配置 | **没有公开的 khaje/bengal `gpucc` 厂商源码**；GKI 那份表只到 1114，且 `P_GPU_CC_PLL0/1` 的分频与 alpha 配置要精确匹配，否则时钟锁不上 → 白屏 / 900E |
| GPU 电压/档位 | kgsl + RPMh | 新增档位 | 电压只有"档位号"，没有 mV 表；448/512 档未标定 |
| GKI 内核本体 | `boot_a` | — | 改内核**改变不了**上面两张硬件表；`CFI_CLANG + LTO` 下交叉改 CFI 调用点极易踩 `CFI failure` |

**C 层结论**：**不建议做**。要动就必须同时具备（a）msm-5.15 khaje/bengal 的 vendor 内核源码，（b）vendor 模块重编工具链与 vermagic（本机 `msm_kgsl.ko` 的 vermagic 是 `5.15.74-ga0aa332d6eec-dirty`，与 GKI `5.15.167-android13…` 不一致，说明这些模块是厂商侧另一套树编的），（c）重打 `vendor_boot` ramdisk 的能力。三样都不具备。

---

## 4. 社区先例（查到什么就说什么）

- **GitHub 仓库检索**（`api.github.com/search/repositories`，2026-11-25）：
  `sm6225 overclock` / `bengal overclock` / `Adreno 610 overclock` / `sd680 overclock` / `khaje overclock` / `sm6225 gpu overclock` → **命中 0 个仓库**。
- 相关的 SM6225 社区内核（都不是超频项目，只是定制/优化）：
  - `ChicKernel/device_xiaomi_gemstones-kernel`（Redmi Note 12/13 4G，sm6225 5.15 树）
  - `chkndrp/device_xiaomi_sm6225ad-recovery`（**SM6225-AD**，tapas/topaz/sapphire/creek 的 TWRP/OFRP/PBRP device tree）
  - `mi-sdm680/android_kernel_xiaomi_sm6225`（spes/spesn）
  - 本机在用的 `yxyyds666/TB331FC-Kernel`（纯 GKI 5.15.167 + KSU + SusFS，**不含任何频率表改动**，CI 只替换 `boot` 的 kernel 段）
- ⚠️ **本次 `web_search` 不可用**（route 报 "answered without running a search"；Bing / DuckDuckGo 均被反爬 / 拦截），所以 **XDA / 4pda 的帖子没能检索**。这不是"没有先例"的证明，只能说"GitHub 上没有以超频为主题的 SM6225 / bengal 项目"。
- 已知 SoC 常识（供判断，不是本机实测）：骁龙 680/685 这类入门 SoC 的 CPU/GPU 频率点由出厂 fuse/LUT 决定，社区所谓 "OC 内核" 绝大多数是**解锁温控 + 改 governor + 提最小频**（即本报告的 A 层），真正改频率表的极少，且集中在可换 PLL 的老平台（如 660 / 845）。

---

## 5. 推荐做法（只做 A 层，且只做"钉 GPU 顶档"这一条）

> ⚠️ 以下命令**本次没有执行**（纪律：不写 sysfs）。给 lead 决定是否要跑。全部 `echo` 到 sysfs，重启即失效。

### 5.1 安全边界（先立规矩）

- **核心只写 GPU 的 2 个节点**：`kgsl-3d0/min_pwrlevel`、`kgsl-3d0/devfreq/min_freq`（CPU `scaling_min_freq` 仅在跑分时作为可选实验）。
- **不要**碰 `thermal_zone*/mode`、trip、`bcl`、`scaling_max_freq`、任何 `opp` 相关。
- 单次实验 ≤ 15 分钟，跑完立刻回滚。
- 温度红线：**GPU zone > 80 ℃ 或 CPU zone > 95 ℃ 立即停**（限值 95 / 110，留 15 ℃ 余量）。
- 电池：实验期间保持 ≥ 40%，别边充边满负荷。

### 5.2 命令（逐条可 copy）

```bash
# 0) 记录基线（回滚用）
adb shell su -c 'cat /sys/class/kgsl/kgsl-3d0/min_pwrlevel /sys/class/kgsl/kgsl-3d0/devfreq/min_freq'
#   基线应为: 6 / 320000000

# 1) 钉 GPU 顶档（1260 MHz）
adb shell su -c 'echo 0 > /sys/class/kgsl/kgsl-3d0/min_pwrlevel'
adb shell su -c 'echo 1260000000 > /sys/class/kgsl/kgsl-3d0/devfreq/min_freq'

# 2) 确认生效
adb shell su -c 'cat /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq /sys/class/kgsl/kgsl-3d0/clock_mhz'
#   期望: 1260000000 / 1260

# 3) （可选）跑分时把大簇最小频抬高，省 ramp
adb shell su -c 'echo 2803200 > /sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq'

# 4) 回滚（重要）
adb shell su -c 'echo 6 > /sys/class/kgsl/kgsl-3d0/min_pwrlevel'
adb shell su -c 'echo 320000000 > /sys/class/kgsl/kgsl-3d0/devfreq/min_freq'
adb shell su -c 'echo 1056000 > /sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq'
```

### 5.3 观察指标（判断"到底有没有用"）

```bash
# GPU 是否真的钉住 / 有没有被热限
cat /sys/class/kgsl/kgsl-3d0/clock_mhz          # 期望长期 1260
cat /sys/class/kgsl/kgsl-3d0/gpu_clock_stats    # 第一列(1260)应快速增长
cat /sys/class/kgsl/kgsl-3d0/thermal_pwrlevel   # 变了说明热限介入

# CPU 是否降频
cat /sys/devices/system/cpu/cpufreq/policy4/scaling_cur_freq
cat /sys/devices/system/cpu/cpufreq/policy4/stats/time_in_state

# 温度 / 功耗
for z in 7 9 11 16; do echo "zone$z $(cat /sys/class/thermal/thermal_zone$z/type) $(cat /sys/class/thermal/thermal_zone$z/temp)"; done
cat /sys/class/power_supply/battery/voltage_now /sys/class/power_supply/battery/current_now /sys/class/power_supply/battery/temp
```

---

## 6. 实测方法（不上机也能先把方法定死）

### 6.1 压测工具

| 工具 | 装法 / 注意 | 用途 |
|---|---|---|
| `stress-ng` | 需要 aarch64 静态二进制（`stress-ng --cpu 8 --cpu-method matrixprod`、`--vm 1 --vm-bytes 1G`）；设备没有，需从 Termux 或交叉编译推到 `/data/local/tmp` | CPU 满载、内存带宽 |
| `sbc-bench.sh` | Thomas Kaiser 脚本，需要 `gcc` / `sysbench`，**在 Android 上跑不全**，只取其中 `7z b` / `openssl` 子项 | 快速稳定性 |
| **Geekbench 6 / 5** | Play 版或 APK | 单核 / 多核 + Compute（OpenCL/Vulkan），**跨版本可比** |
| **3DMark (Android)** | `Wild Life` / `Sling Shot`，看 **stability（20 min loop 的稳定性百分比）** | GPU 持续性能与降频曲线 |
| `Antutu` | 只当参考，**不同版本不可比** | 整机热设计上限 |
| `fps` 观测 | `dumpsys SurfaceFlinger --latency`、`dumpsys gfxinfo`，或游戏内 fps | 真实收益（不是跑分） |

**推荐组合（时间成本最低）**：`3DMark Wild Life Stress Test`（20 次循环）+ `Geekbench 6 Compute`；两者都能给出"第 1 次 vs 第 20 次"的衰减曲线。

### 6.2 温度 / 功耗采样（本次已验证可用的脚本形态）

```bash
while :; do
  echo "$(date +%T) cpu0=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq)" \
       "cpu4=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_cur_freq)" \
       "gpu=$(cat /sys/class/devfreq/5900000.qcom,kgsl-3d0/cur_freq)" \
       "cpu=$(cat /sys/class/thermal/thermal_zone7/temp)" \
       "cpuss=$(cat /sys/class/thermal/thermal_zone11/temp)" \
       "gpu_t=$(cat /sys/class/thermal/thermal_zone16/temp)" \
       "batt=$(cat /sys/class/power_supply/battery/current_now)uA/$(cat /sys/class/power_supply/battery/voltage_now)uV"
  sleep 10
done
```

- 功耗近似：`P ≈ voltage_now × current_now`（负值表示放电），本机纯 CPU 满载 ≈ 3.5 W。
- 频点占比：`policyX/stats/time_in_state`（内核自己累计，最权威）；GPU 用 `gpu_clock_stats`（7 个数对应 7 档）。

### 6.3 稳定性判据（"多久不崩算通过"）

| 层级 | 判据 | 建议门槛 |
|---|---|---|
| 短测 | 30 min 满载不重启、不 panic，`dmesg` 无 `CFI failure / Oops / watchdog` | **必须过** |
| 中测 | 2 h「压测 + 亮屏 + WiFi」混合，无 soft reboot，`/sys/kernel/oops_count` 为 0 | 至少 1 次 |
| 长测 | 24 h 日常使用（含待机），无随机重启、无掉电异常 | 想要"可发布"才需要 |
| 数据判据 | 20 次 3DMark 循环 stability ≥ 85%，末次分数 ≥ 首次 70% | 低于此说明**就是热降频**，不是超频 |
| 降频检测 | 采样里 `scaling_cur_freq` 跌到非最大档 → 记一次降频；`thermal_pwrlevel != 0` → kgsl 已限 | 出现即视为"没白拿" |

**注意**：崩溃形态要会分辨 —— `900E`（`05C6:900E`）是内核 panic 后的 crash dump（本机有 `E:\rom\work\tools\auto_900e.py` 可读转储）；`9008` 是 EDL；`18D1:D00D` 是 ABL 拒绝启动。

---

## 7. 风险与回滚

### 7.1 回滚资产（已核实存在 + 哈希）

| 分区 / 文件 | 路径 | SHA256（前 16 位） |
|---|---|---|
| `boot_a`（stock 544） | `E:\rom\work\kit-baked\out\boot_a.img`（= `E:\rom\work\a17dump\boot_a.img`） | **`2510B098380A573A`** ← lead 说的 `2510b098…` 就是这份 |
| `boot_a`（原厂包内） | `E:\rom\TB331FC\刷机包\TB331FC_ZUI_16.0.544\image\boot.img` | 使用前现算 |
| `boot_a`（另一份备份） | `E:\rom\work\boot-backup-20261008\bk\boot_a.img` / `E:\rom\extracted\GSI_Kit\05_镜像\boot\boot_a_原始.img` | `0B4701274BAAB52A`（同一份） |
| `dtbo_a` | `E:\rom\work\of\v3\stock\dtbo_a.bin` | `AC8FC83D0818AAF7154B7903` |
| `vendor_boot_a` | `E:\rom\work\of\v3\stock\vendor_boot_a.bin` | `D526C77B243C5277FD6FB715` |
| 每日快照 | `E:\rom\work\boot-backup-20261024\`（`boot_a` / `dtbo_a` / `vendor_boot_a`） | `3C3A276724771ACA`（boot_a） |

回滚命令（a 槽）：

```bash
fastboot --set-active=a
fastboot flash boot_a        E:\rom\work\kit-baked\out\boot_a.img
fastboot flash dtbo_a        E:\rom\work\of\v3\stock\dtbo_a.bin
fastboot flash vendor_boot_a E:\rom\work\of\v3\stock\vendor_boot_a.bin
fastboot reboot
```

（`vendor_boot` / `dtbo` 被 `vbmeta_a` 哈希覆盖；stock 组合回滚时 3 个分区一齐回到 stock 即可一致。）

### 7.2 不可逆 / 高危

| 操作 | 后果 | 可逆性 |
|---|---|---|
| 往 LUT / CPR 寄存器写频率或电压（devmem、自编模块） | 电压-频率失配 → **SoC 锁死 / 瞬时烧毁**；CPR 校准数据在 efuse，烧了就废 | ❌ **不可逆** |
| 改 `qcom,level` 到 448 / 512 并长期高负载 | 超出 PMIC 标定范围，PMIC 可能进保护或损伤 | ⚠️ 硬件级不可逆风险 |
| 关 `thermal_zone*/mode`、清 trip、拔 `bcl` / `lmh` 模块 | 失去唯一的热保险；本机没有 `thermal_message` 用户态补偿 | 软件可逆，**但过热时已经来不及** |
| 改 `vendor_boot` 的 dtb / ramdisk 且 `dtb_size` 不同步 | ABL 找不到 DTB 或找不到模块 → 卡 logo、`900E` | ✅ 可刷回，但要能进 fastboot；若连带 vbmeta 坏了可能只能 9008 |
| 改 `abl` / `xbl` / `xbl_config` | fastboot 禁刷，只能 9008；刷错变砖 | ❌ 极难 |
| 回锁 bootloader | 非官方回锁**极大概率变砖**（skill 已列为禁止） | ❌ |

### 7.3 本机特殊雷区（skill 已验证，别踩）

1. **不要注入非空 boot cmdline**（高通 ABL 缺陷，实机验证不开机）。
2. **启动链必须成套**：`boot / init_boot / vendor_boot / vbmeta / dtbo` 混搭 = 900E。
3. 一次只改一个分区，改完确认能开机再动下一个。
4. `persist` 分区（32 MB）官方刷机永远不写（`rawprogram0.xml` 里 `filename=""`）；动 `vendor_boot` 前先确认 persist 正常（`cat /proc/mounts | grep persist` 有输出）。

---

## 8. 明确"不建议做"清单（及原因）

| 不做 | 原因（一句话） |
|---|---|
| ❌ 改 DT 加 GPU 更高频点（1300 / 1400…） | `gpucc-khaje.ko` 时钟表只到 1260，会被夹回，**白改** |
| ❌ 改 DT 加 CPU 频率点 | DT 里根本没有 CPU OPP 表，频率在硬件 LUT 里，**无入口** |
| ❌ 重编内核"解锁"频率 | 换 GKI `Image` 改不了 vendor 模块里的表与 LUT；还会破坏 CFI / KMI 一致性 |
| ❌ 反编译或改 `gpucc-khaje.ko`、`qcom-cpufreq-hw.ko` | 需要厂商源码与 vermagic（本机 `msm_kgsl.ko` vermagic 是 `5.15.74-ga0aa332d6eec`，不是 GKI 那套），重编后无法保证与其余 vendor 模块兼容 |
| ❌ 关温控 / 清 trip / 拔 `bcl`、`lmh` | 实测压测都没到 trip，**关掉不涨性能**，只丢保险；本机没有 `thermal_message` 兜底 |
| ❌ 改 DDR 相关 DT | DDR 时钟由 bootloader / RPMh 决定，kernel 只有带宽投票 |
| ❌ 用 `performance` governor 常驻 | 空闲也顶档，续航骤降，收益≈0 |
| ❌ 为"跑分提升"去做 A 层 | 已实测：出厂就无限制、压测无降频，**A 层天花板个位数百分点** |

---

## 9. 遗留未验证项（写清楚，别当结论用）

1. **LUT 的电压编码没读到**：`print_cpufreq_debug_regs` 只给 `PERF_STATE_DESIRED / CYCLE_CNTR / PSTATE_STATUS`；要读 12 行 LUT 的 `freq / volt` 需要**写一次** `/sys/kernel/qcom-cpufreq-hw/print_cpufreq_debug_regs`（写 `1` 触发 dmesg dump），本次按纪律没写。若 lead 允许，这一条能拿到 CPU 每档真实电压码。
2. **`vendor_boot` ramdisk 里的模块清单是 `lz4 -d` 解到 `/tmp/vb_ramdisk.cpio` 后 grep 得到的**（`lz4` 报 `Error 53`，但解出 33 MB 内容、`.ko` 路径齐全）；正式重打包前应改用完整 `unpack_vendor_boot.py` 复核。
3. **XDA / 4pda 先例没检索到**（`web_search` 本次不可用）。GitHub 侧只有"0 命中"这一条证据。
4. **GPU 1260 MHz 是否已被 ACD / CPR 实际降频**：`acd = 0`、`throttling = 0`，但 ACD 状态要持续观察才准，本次只取单点。
5. **小簇 1900.8 MHz 是否为 fuse 上限**：`max-lut-entries = 12`，小簇只用 7 项；寄存器里理论上还有 5 行，但按驱动逻辑（重复项判表尾）它们不是有效频率点。

---

## 10. 附：本次取证命令速查（可复现）

```bash
# CPU 表 / governor / 限值
for d in /sys/devices/system/cpu/cpufreq/policy0 /sys/devices/system/cpu/cpufreq/policy4; do
  cat $d/scaling_driver $d/scaling_governor $d/scaling_available_frequencies \
      $d/cpuinfo_min_freq $d/cpuinfo_max_freq $d/scaling_min_freq $d/scaling_max_freq
done

# GPU 表 / 功耗档
cat /sys/class/kgsl/kgsl-3d0/gpu_model /sys/class/kgsl/kgsl-3d0/freq_table_mhz \
    /sys/class/kgsl/kgsl-3d0/num_pwrlevels /sys/class/kgsl/kgsl-3d0/max_pwrlevel \
    /sys/class/kgsl/kgsl-3d0/min_pwrlevel /sys/class/kgsl/kgsl-3d0/thermal_pwrlevel
cat /sys/class/devfreq/5900000.qcom,kgsl-3d0/available_frequencies \
    /sys/class/devfreq/5900000.qcom,kgsl-3d0/governor \
    /sys/class/devfreq/5900000.qcom,kgsl-3d0/min_freq \
    /sys/class/devfreq/5900000.qcom,kgsl-3d0/max_freq

# DT 里的 GPU 频表（基座 DTB 在 vendor_boot）
cat /sys/firmware/devicetree/base/soc/qcom,kgsl-3d0@5900000/qcom,gpu-pwrlevel-bins/qcom,gpu-pwrlevels-0/qcom,gpu-pwrlevel@0/qcom,gpu-freq

# 温度 / 温控
for z in /sys/class/thermal/thermal_zone*; do echo "$z $(cat $z/type) $(cat $z/temp)"; done
cat /sys/class/thermal/thermal_zone16/trip_point_*_temp /sys/class/thermal/thermal_zone16/trip_point_*_type

# 稳压器（level 型 vs 微伏型）
for r in /sys/class/regulator/regulator.*; do echo "$r $(cat $r/name) $(cat $r/state) $(cat $r/microvolts)"; done
```

**证据文件**（都在 `E:\rom\work\overclock\`）：
`device_dump.txt`（CPU / GPU / thermal / battery）、`device_dump2.txt`（DT 顶层 + 内核参数）、`device_dump4.txt`（kgsl DT 节点）、`device_dump5.txt`（pwrlevel bins 十六进制）、`device_dump6.txt`（模块 / trip）、`device_dump7.txt`（core_ctl / walt / msm_perf）、`device_config.txt`（`/proc/config.gz` 全量）、`dtbo_a.img`（dtbo 分区镜像）、`gpucc-khaje.ko`、`qcom-cpufreq-hw-debug.ko`。
基座 DTS：`E:\rom\work\img-boot-group\dtbo_extract\vendor_boot_base.dts`。
