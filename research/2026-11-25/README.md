# 2026-11-25 本轮研究报告索引

> 这一轮（2026-11-25）共 **17 个主题目录 / 18 份报告**，全部是**只读取证的离线研究**：
> 大部分报告明确标注「未刷机」「未写任何镜像」；涉及真机的部分只做到 `adb` 只读采集与镜像离线解析。
> 所有脚本从原始工作目录 `E:\rom\work\` 原样搬入，**未改动逻辑**（唯一改动是一处凭据脱敏，见文末「安全处理」）。
>
> 大文件（`.img` / `.zip` / `.apk` / `.cpio` / `.dtb`、>5 MB 的转储）**一律没有上传**，清单见文末「未上传」。

## 目录

```
research/2026-11-25/
├─ boot-chain/          ABL 与启动链的边界（距上限多少、能不能绕、怎么观测）
│  ├─ abl-limit/            ABL ramdisk 总量上限的地址级精算
│  ├─ trojan-kernel/        「把 UEFI 伪装成真内核」三条路线的判决
│  ├─ sentinel/             v9 三色哨兵（屏幕颜色 = 死在哪一段）
│  └─ ch-probe/             paint proof：用真内核验证观测通道本身
├─ kernel/              内核侧可行性
│  ├─ overclock/            超频不可行（CPU LUT 顶格 / GPU 1260 上限 / 内存由 RPMh 定）
│  ├─ kernel-research/      真 mainline 调研（v6.0 最差、我们手上的树就是 mainline）
│  ├─ kernel-re/            原厂 5.15 内核逆向（本轮只有产物，无报告）
│  └─ linux-boot/           mainline 启动包 + 914 KB 最小 initramfs
├─ recovery/            recovery 三条线（自己拼 / 定位卡 logo / 瘦身 / 重编）
│  ├─ rec-direction/        方向定案：原厂骨架 + OF 用户态
│  ├─ of-pipeline/          最小化实验设计（6 个镜像阶梯刷）+ pstore 发现
│  ├─ of-slim/              OF ramdisk 瘦身（zstd 13.26 MB）
│  └─ of-rebuild/           用源码重编一个能进 14.5 MB 的 TWRP/OF
├─ system-surgery/      在系统内部动手术 / 拆镜像
│  ├─ pkg-installer/        澎湃4 安装器：去联网、去安全检测（零改 APK 路线的由来）
│  └─ img-analysis/         四份镜像分析里的三份（img-firmware / img-boot-group / img-zui-diff）
└─ housekeeping/        工作盘自身的整理
   ├─ disk-cleanup/         E:\rom 磁盘分析（79% 占用在 rom 之外）
   └─ dir-tidy/             根目录 61 项 → 30 项
```

---

## 1. boot-chain —— 启动链的边界

| 主题 | 一句话结论 | 文件 |
|---|---|---|
| **ABL ramdisk 上限** | 上限是 **`89,120,768 − image_size`**（地址级），不是拍脑袋的经验值；设备 9008 回读的 `abl_a` 与包内 `abl.elf` 二进制同一性已闭环，所以这些地址就是**正在跑的那份代码** | [REPORT.md](boot-chain/abl-limit/REPORT.md) · [scripts/](boot-chain/abl-limit/scripts) |
| **木马内核三路线** | 机械层面拿不到任何东西：ABL 交接给「真内核」和交接给我们的 payload 是**同一条 `blr x8`、同一组寄存器**；⇒ **A 机械不可行 / B 不可行 / C 严格劣于 A**，真正有价值的是把数据面差异钉死（新发现：v1 头 + gzip 时 `LoadDtb` 兜底路径算出的地址恒定早一个 `PageSize`） | [REPORT.md](boot-chain/trojan-kernel/REPORT.md) |
| **v9 三色哨兵** | 把「哪一段死了」变成两三个像素：shim 阶段涂 **RED**、`br x5` 前改 **GREEN**、SEC 第一条 C 语句盖 **BLUE**；屏幕剩哪种颜色就是那一段死了。**不动任何地址**，镜像已离线逐字节校验 | [REPORT.md](boot-chain/sentinel/REPORT.md) · [v9-sentinel.patch](boot-chain/sentinel/v9-sentinel.patch) · [scripts/](boot-chain/sentinel/scripts) · [logs/](boot-chain/sentinel/logs) |
| **观测通道验证（paint proof）** | 把确定能开机的 A17 内核入口 `code1` 改成 `b` 到内核尾部 168 字节桩（关 MMU → 涂满 15 MiB 红 → 恢复 SCTLR → 跳回 `primary_entry`）：**「能进 Android」本身就成了「桩跑过了」的证据**。屏幕变红⇒通道有效（v9 全黑=ABL 没走到 `blr`）；屏幕不变⇒之前「卡 logo = 载荷没执行」的结论全部作废 | [REPORT.md](boot-chain/ch-probe/REPORT.md) · [scripts/](boot-chain/ch-probe/scripts) · [out/](boot-chain/ch-probe/out) |

## 2. kernel —— 内核侧

| 主题 | 一句话结论 | 文件 |
|---|---|---|
| **超频可行性** | **这台机器没有「超频」空间，只有「解锁/钉频/温控」空间**：大簇 2.8032 GHz、小簇 1.9008 GHz 已是 CPU LUT 全部有效项（LUT 在硬件寄存器里，DT 上根本没有 CPU `opp-table`）；GPU bin0 顶档 **1260 MHz 就是本颗芯片最高档**，DT 写更高会被 `gpucc-khaje.ko` 的时钟表夹回 1260；内存频率由 RPMh 定，内核侧改不了 | [REPORT.md](kernel/overclock/REPORT.md) · [scripts/](kernel/overclock/scripts) |
| **真 mainline 调研** | **「真 6.0」是最差选项不是最好选项**：`v6.0` 里根本没有 bengal/SM6115/SM6225 任何支持（`sm6115.dtsi`/`dispcc-sm6115.c` 全 404），SM6115 系第一次进 mainline 是 **v6.2**；mainline 从来没有 `sm6225.dtsi`（上游只有 `sm6115.dtsi`），我们手上那份是社区 out-of-tree 文件 ⇒ **现有树即 mainline**。报告还含实测编译计时 | [REPORT.md](kernel/kernel-research/REPORT.md) · [scripts/](kernel/kernel-research/scripts) |
| **原厂 5.15 内核逆向** | 本轮该目录**只产出产物、没有报告**（报告缺口已记入 `docs/OPEN-QUESTIONS.md` 类待办）：`a17-ikconfig.txt` 是从 A17 内核提取的完整 `.config`（6610 行，clang 17.0.4 / LLD，`5.15.167-android13`），`strings-key.txt` 是按主题分节的 kernel blob 字符串索引（文件偏移 == VMA `0xffffffc008000000` 起点），`kallsyms.py` 是只靠 raw blob + stdlib 抽压缩 kallsyms 表的独立解析器 | [out/](kernel/kernel-re/out) · [README](kernel/kernel-re/README.md) |
| **mainline 启动包** | 给出 5 种装机形态的优先级：**A3（`boot_a`=内核 + `vendor_boot_a`=DTB+cmdline + `init_boot_a`=我们的 initramfs）最稳**（ABL 反汇编：ramdisk 段 C 恒执行且取 init_boot，段 A 空则无拼接）；A 为正式用法；C（UEFI/BDS）当前不可行是因为**缺固件不是缺 FAT 支持**。附带 914 KB 最小 initramfs | [REPORT.md](kernel/linux-boot/REPORT.md) · [scripts/](kernel/linux-boot/scripts) · [out/](kernel/linux-boot/out) |

## 3. recovery —— 三条线

| 主题 | 一句话结论 | 文件 |
|---|---|---|
| **方向定案（rec-direction）** | **方向 A：留原厂 ZUI16 ramdisk 骨架（`init`/`ueventd`/rc/USB/sepolicy 一个不动），只换 TWRP 用户态**。硬证据三条：hybrid 的 `recovery` 依赖闭包 94 ELF/23.37 MiB **缺 0 个库**、10,014 条未定义符号里 strong-unresolved 只有 10 个且与 baseline 逐个相同；「OF 的 init 与 recovery 强耦合」被证伪（两边是同一份 AOSP recovery `init.rc` 的两个版本）；`printk` 抬到 8 让 init 日志进 ttyMSM0 → pstore，卡 logo 从此有日志 | [PLAN.md](recovery/rec-direction/PLAN.md) · [REPORT-TO-LEAD.md](recovery/rec-direction/REPORT-TO-LEAD.md) · [scripts/run_dirA.ps1](recovery/rec-direction/scripts/run_dirA.ps1) · [out/patch/](recovery/rec-direction/out/patch) |
| **卡 logo 定位实验（of-pipeline）** | 我们的打包/压缩**已被证明与原厂比特级等同**（`lz4 -l -12` 重压原厂 cpio 与原厂 ramdisk sha256 相同）⇒ 卡 logo 不可能是「压错了」，六个镜像阶梯刷一遍就能把原因锁死在三选一（内核没解开 / 解开了 OF init 死 / init 活但显示初始化死）。本轮另一收获：**pstore 可用** | [REPORT.md](recovery/of-pipeline/REPORT.md) · [RESULTS.md](recovery/of-pipeline/RESULTS.md) · [scripts/run_experiments.ps1](recovery/of-pipeline/scripts/run_experiments.ps1) |
| **OF ramdisk 瘦身（of-slim）** | **lz4 做不到 14.5 MB（地板 15.02 MB 且已残废），zstd 做到 13.26 MB 且功能接近完整**（UI/主题 + fs 工具 + 动态分区 + adbd + fastbootd + 触摸固件，余量 1,313,252 B）；中文版 14.22 MB 余 354 KB。zstd 不是赌博——这台机器的内核自己带着可用 zstd 配置 | [报告_of-recovery-瘦身.md](recovery/of-slim/报告_of-recovery-瘦身.md) |
| **最小 TWRP 重编（of-rebuild）** | 用源码重编后的尺寸全部实测：**lz4 11.8 MB（极简）～ 14.40 MB（全功能，余 0.17 MB），推荐档 13.67 MB（余 0.91 MB）**，gzip 同配置 11.70 MB，zstd 8.26 MB；关键节省项 **`TW_INCLUDE_CRYPTO` 省 4.49 MB**。方案文档，未执行 `repo sync` | [PLAN.md](recovery/of-rebuild/PLAN.md) |

## 4. system-surgery —— 系统内部手术与拆镜像

| 主题 | 一句话结论 | 文件 |
|---|---|---|
| **澎湃4 安装器去联网/去安全检测** | 安装器 = `com.miui.packageinstaller`，**能提取、能分析，但「改 APK 重签」必然破坏平台签名 ⇒ 退回方案 1：零改 APK、运行期屏蔽**（iptables + 设置开关，真机验证过并当场删掉测试规则）。产物：`block-installer.sh` / `rollback-installer.sh` / KSU 模块 | [REPORT.md](system-surgery/pkg-installer/REPORT.md) · [out/](system-surgery/pkg-installer/out) |
| **固件链分析（img-firmware）** | **`modem_a` 那个 180 MiB FAT16 不是「基带分区」，而是 ADSP+CDSP+MODEM+WLAN 固件的唯一载体**（`ADSP.MDT`+35 分片、`CDSP.MDT`+10、`MODEM.MDT`+21、`WLANMDSP.MBN`、39 个 `BDWLAN*`）；`dsp_a` 是 ext4 只装用户态 `.so`；`bluetooth_a` 只有 1 MiB。三块都运行时 ro、**都不在 AVB 描述符里**、官方 erase 都不擦。用它当 EFI 探针载体物理上安全，但要先过「FAT 逻辑扇区 4096 B」和「只能离线改 + 9008 回刷」两道 | [REPORT.md](system-surgery/img-analysis/img-firmware/REPORT.md) · [out/](system-surgery/img-analysis/img-firmware/out) |
| **启动镜像组（img-boot-group）** | ① 「init_boot 尺寸不符」是误判（`2,011,136` 是镜像大小不是 ramdisk 长度，哈希与 `vbmeta_a` 逐字节一致）；② **真正破 AVB 的只有 `boot`**（43,098,112 B 的「仅内核」重打包 + 3.7 MB 原厂残留字节，实测与声明 MISMATCH），`verifiedbootstate=orange` 是解锁态正常值；③ `dtbo` 不是几片小补丁而是 **45 棵完整板级 overlay 树**，本机生效的是 entry 2「KHAJE IDP nopmi」；④ **panel/touch 参数全部只在 dtbo 里**，base DTB 一个都没有 | [REPORT.md](system-surgery/img-analysis/img-boot-group/REPORT.md) · [out/](system-surgery/img-analysis/img-boot-group/out) · [scripts/](system-surgery/img-analysis/img-boot-group/scripts) |
| **ZUI16 ⟷ ZUI17 逐项对比（img-zui-diff）** | ZUI16.0.544 = A14/SDK34/内核 5.15.123，ZUI17(17.0.460/ZUXOS 1.1.10.460) = **A14→A15 平台换代**（内核跳 26 个 LTS、240 个模块重建、SELinux 与 init 换新，**recovery 流程逻辑零改动**）。本机 **固件基线 = ZUI16.0.544**：49 个可比槽位 37 个精确等于 ZUI16、仅 3 个等于 ZUI17（全在 **B 槽**：`init_boot_b`/`vendor_boot_b`/`recovery_b`）⇒ 兜底包只用 544 EDL 全量包，别拿 ZUI17 补 | [REPORT.md](system-surgery/img-analysis/img-zui-diff/REPORT.md) · [tables.md](system-surgery/img-analysis/img-zui-diff/tables.md) · [scripts/](system-surgery/img-analysis/img-zui-diff/scripts) |

## 5. housekeeping —— 工作盘自身

| 主题 | 一句话结论 | 文件 |
|---|---|---|
| **磁盘分析（disk-cleanup）** | **E: 不是被刷机工作盘吃满的**：`E:\rom` 只有 93.24 GiB，而 E: 已用 436.9 GiB ⇒ **79% 占用在 `E:\rom` 之外**（WSL `ext4.vhdx` 38.5 GB「虚胖」+ pagefile 8 GB + 游戏/工具链）。rom 内部的真问题是**同一套 6.5 GB 的 A17 镜像存了 7 份 + 2 个 zip ≈ 43 GB**（其中 `work\a17dump\` 是回滚底牌，不要删） | [REPORT.md](housekeeping/disk-cleanup/REPORT.md) · [evidence/](housekeeping/disk-cleanup/evidence) |
| **根目录整理（dir-tidy）** | 根目录 **61 项（17 目录 + 44 文件）→ 30 项（18 目录 + 12 文件）**，32 个散落文件移入 `E:\rom\_archive\`，**0 删除、0 目录移动、0 sha 漂移、undo 双向实测**。附一处事实纠正：任务书说的 `rom_audit_*.txt`/`*.rar` 在 `release\` 不在根目录 | [REPORT.md](housekeeping/dir-tidy/REPORT.md) · [scripts/](housekeeping/dir-tidy/scripts) |

---

## 未上传（刻意略过）

| 项 | 原因 |
|---|---|
| 所有 `.img` / `.zip` / `.apk` / `.rar` / `.cpio(.gz)` / `.dtb` / `.ko` / `.bin` / `.cpio` 产物 | 二进制镜像与构建产物，不放仓库（如 `linux-boot/out/*.img`、`of-pipeline/out/exp2a_mintel.img`、`overclock/dtbo_a.img`、`img-zui-diff/work/*.cpio`、`kernel-re` 的 `System.map` 类大转储） |
| `img-boot-group/dtbo_extract/`（45 组 `.dtb`+`.dts`，约 7 MB） | 纯派生产物，`img-boot-group` 的 `tools/` 脚本可原地重生成 |
| `overclock/device_dump*.txt`、`device_config.txt`（合计 ~470 KB） | 原始 `adb` 转储，结论已在 REPORT 表格化 |
| `pkg-installer/out/evidence/manifest.xmltree.txt`（98 KB）等大证据 | 保留体积更小的签名/badging/URL 证据；jadx 全量反编译（5040 个 java）从不上传 |
| `work\jadx\sources`、`evidence` 里 >5 MB 的文件 | 按纪律跳过 |
| **`img-super`** | 本轮该目录**没有 REPORT.md**（只有 `avb2.py`/`chain_check.py`/`verify_verity.py` 等脚本），故未建目录；AVB/verity 的结论已并入 `img-boot-group` 与 `docs/PANORAMA.md` |

## 安全处理

- 入库前对**全仓**（排除 `.git`）grep 了 `ghp_[A-Za-z0-9]{16,}`、`github_pat_`、`PRIVATE KEY`、`BEGIN RSA|OPENSSH|EC`、`AKIA…`、以及 PAT 字面量 `rVnP9qwg` ⇒ **0 命中**。
- **发现并修掉一处真实泄露**：`kernel/kernel-research/scripts/probe_gh*.ps1`（11 个文件）原来把 GitHub PAT **硬编码**在 `$tok = 'ghp_…'` 里。入库版本已改为 `$tok = $env:GH_TOKEN` 并在行尾注明原因。
  ⚠️ 原始文件 `E:\rom\work\kernel-research\probe_gh*.ps1` 里那个字面量**仍然存在**，且该 token 已在本地脚本中出现过 —— **建议把那个 PAT 直接吊销重签**，不要只依赖仓库侧脱敏。
