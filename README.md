# TB331FC (联想小新 Pad 2024 / khaje) — Windows on ARM 移植研究快照

## 先读这三份（本轮整合产出）

| 文档 | 内容 | 什么时候看 |
|---|---|---|
| **[docs/PANORAMA.md](docs/PANORAMA.md)** | **全景机制文档**：硬件 → 分区全表 → 启动链（PBL→XBL→ABL→Linux）→ 各镜像职责 → 三条目标线现状与阻塞 → 已证伪清单 → 待验证清单。**每条结论都标出处（报告 + 地址/偏移）** | 想一次搞清这台机器怎么起来的、现在卡在哪 |
| [docs/CORRECTIONS.md](docs/CORRECTIONS.md) | **43 条旧结论的更正**：「旧说法 → 现证据 → 正确结论」。含 SEC 栈踩 XBL、FD 基址覆盖致命、cmnlib 全零、900E=9008、ABL 用 recovery_a、devinfo 解锁位、misc+2048 槽元数据、fastboot erase misc 被 critical 拦 等 | 动手前先查这里，避免重复已证伪的路 |
| [docs/OPEN-QUESTIONS.md](docs/OPEN-QUESTIONS.md) | **43 条未解问题 + 每条的具体验证命令/实验设计**（只读 → 单变量 → 写分区 → 需外部条件 → 报告缺口），附「先做什么」顺序表 | 想推进但不知道下一步做什么 |

> 三份文档的结论都**只读整合自本仓库与本地研究报告**，未刷机、未连设备（2026-11-25）。

## 这台机器是什么

| 项 | 值 |
|---|---|
| 型号 | Lenovo Xiaoxin Pad 2024 / **TB331FC** |
| 代号 | **khaje** |
| SoC | **SM6225-AD（骁龙 685，bengal 平台）** |
| 存储 | **UFS**（三星 KLUDG2R1DE，128 GB，6 个 LUN，4096B 逻辑扇区） |
| 屏幕 | BOE p255 / Himax **HX83102J**，1200×1920@90Hz |
| 内存 | 6 GB（DRAM 至 `0x1BFFFFFFF`） |
| 槽位 | A/B（super 为 `virtual_ab_device`，`*_b` 逻辑分区全 0 长度） |
| 当前系统 | HyperOS4 / A17（`CP2A.260605.016 by dsshhgg`），解锁，`verifiedbootstate=orange` |

## 目标

让这台机器**启动 Windows on ARM** —— 具体路径是自编一份 UEFI 固件，装进 boot 分区，由 ABL 跳转执行。

## 现在卡在哪（一句话）

> **ABL 确实跳进了我们的 payload（`fastboot continue` 后设备离开 fastboot），但设备随后卡在 logo、USB 静默、且永不复位。**
> 所有镜像层面的变量都已排除（见 [docs/tried-and-failed.md](docs/tried-and-failed.md)），剩下的怀疑点集中在 **SEC 阶段与 XBL 运行时的内存冲突**（见 [docs/sec-memory.md](docs/sec-memory.md)）。

## 目录

| 路径 | 内容 |
|---|---|
| `docs/PANORAMA.md` | ★ **全景机制文档**（本文顶部「先读这三份」） |
| `docs/CORRECTIONS.md` | ★ **43 条旧结论更正** |
| `docs/OPEN-QUESTIONS.md` | ★ **43 条未解问题 + 验证方法** |
| `docs/abl-dtb-root-cause.md` | **最有价值的单项发现**：ABL 要求「内核之后最多一棵 FDT」，否则返回 status 14 且永不跳转 |
| `docs/tried-and-failed.md` | 所有试过并失败的 UEFI 配置（9 条），以及每条的现象 |
| `docs/bootchain.md` | PBL→XBL→ABL→Linux 的真实结构；UEFI 固件在 `xbl` 里而不是 `abl` 里 |
| `docs/device-profile.md` | 分区表要点、25 个全零分区、b 槽是假备份 |
| `docs/system-profile.md` | A17 系统 + A13 vendor 拼装、模块三处来源、dm-verity eio |
| `docs/of-recovery.md` | OrangeFox 的 MODE=2 约束；显示只能走 DRM；触摸只缺 `hxchipset.ko` |
| `docs/linux-port.md` | mainline Linux 6.14 的 5 项缺口与已完成的补丁（已编出可刷内核） |
| `docs/rescue-matrix.md` | 救砖矩阵；三个最危险操作；9008 扇区表 |
| `docs/flashkit-audit.md` | 刷机包 v2 的 6 个 P0 缺陷与 v3 的修法 |
| `docs/sec-memory.md` | SEC 栈/临时区与 XBL 运行时可能的重叠分析 |
| `patches/acpi/` | TB331FC 专用 DSDT（保留 UFS0 = `ACPI\QCOM24A5`）+ SSDT |
| `patches/otg/` | OTG 供电驱动（SC89601D + FSA4480 + RT1711H，三颗芯片三条 I2C） |
| `patches/kernel/` | mainline Linux 的 `.config` 与 DTS 改动 |
| `probe/` | 三个探针：MMU-off 涂屏、看门狗复位、BDS EFI 应用 |

## 复现前提（重要）

- **解锁状态**是硬前提：ABL 在解锁态打印 `State: Unlocked, AvbSlotVerify returned %a, continue boot` 并跳过 AVB
- **只动 boot 分区**（`boot_a` 原厂 sha256 `2510b098380a573a40ee6600aa9124ced06a047c14c21e6bf7cd596fbbc3c14b`），任何时候都能一条命令刷回
- **不要动 `xbl` / `abl`**：fastboot 层对 24 个 critical 分区硬拦，9008 层零保护，写坏没有软件通道

## 免责

所有内容来自一次真实设备上的实验记录。失败的尝试如实保留，包括我们自己的误判（例如把「跨设备服务崩溃」误判为 TEE 问题、把「设备自发重启」误判为硬件问题——实际那两次重启是研究者自己 `adb reboot` 造成的）。引用前请先核对 `docs/` 内的证据链。