# E:\rom 磁盘分析报告（2026-11-25）

- 生成时间：2026-11-25 18:5x (+08:00)
- 执行者：磁盘分析子代理（**只读**，未删任何文件）
- 工具/证据：`Get-PSDrive`、`fsutil volume diskfree`、`fsutil hardlink list`、`compact /q`、自写单遍扫描器 `scan_all.py`（100,187 文件 / 93.24 GiB 全量枚举，152 s）、`scan_shard.py`（E: 其余顶层目录）、`zipfile` 读中央目录、`du`/`df` in WSL
- 原始数据：`scan-all.txt`（E:\rom 全量：一级/二级/三级目录体积+文件数、>500 MB 文件、973 个 reparse 点、0 个枚举错误）、`scan-e-part1.txt` / `shard-*.txt`（E: 其它顶层目录）、`du-crelocate.txt`

---

## 0. 一句话结论

**E: 不是被「刷机工作盘」吃满的。** E:\rom 全部只有 **93.24 GiB**，而 E: 已用 **436.9 GiB** —— 也就是说 **79% 的占用在 `E:\rom` 之外**（WSL 的 `ext4.vhdx` 38.5 + pagefile 8.0 + 一堆游戏/开发工具链/下载）。

`E:\rom` 内部真正的问题不是「新工作目录变大」，而是**同一套 6.5 GB 的 A17 镜像在盘上存了 7 份 + 2 个 zip，合计约 43 GB**：

| 副本 | 路径 | 体积 | 性质 |
|---|---|---|---|
| ① 底牌 | `work\a17dump\` | 5.961 | **不要删**（回滚底牌） |
| ② v3 目录 | `release\…_v3\images\` | 5.961 | 与 v4 逐字节同一套 |
| ③ v4 目录 | `release\…_v4\images\` | 5.961 | **当前真值** |
| ④ kit 成品 | `work\kit-baked\out\` | 5.961 | 改过的（5 模块已融进镜像） |
| ⑤ kit 复现 | `work\kit-baked\out_repro\` | 5.961 | 可复现性证明件 |
| ⑥ kit 中间 | `work\kit-baked\work\` | 7.561 | 4 张中间大图 + 脚本 |
| ⑦ v3 zip | `release\…_v3.zip` | 2.898 | v3 的 11-24 19:58 快照 |
| ⑧ v4 zip | `release\…_v4.zip` | 2.837 | v4 的可分发单文件 |

点名那批「近期新增大件」里，**只有 `kit-baked` 是真大件（19.53 GiB）**；`of-pipeline`(0.487)、`of-slim`(0.486)、`linux-boot`(0.092)、`woa\ch-probe`(0.080)、`of-rebuild`(0.001) 加起来 **1.15 GiB**，且都带 `REPORT.md`、今天 07:36–14:18 还在写 —— 不能整体动。

---

## 1. 各盘剩余空间

| 盘 | 总 | 已用 | **空闲** |
|---|---|---|---|
| C: | 111.48 GiB | 79.82 GiB | **31.67 GiB** |
| D: | 55.59 GiB | 38.29 GiB | **17.30 GiB** |
| **E:** | **465.45 GiB** | **436.90 GiB** | **28.71 GiB**（`fsutil volume diskfree` 精确值 30,616,305,664 B = 28.51 GiB） |

> `Get-PSDrive` 与 `fsutil` 差 0.2 GiB，是本机别的会话在持续写入的正常抖动（不是读数错误）。**报告收尾时（18:32）`fsutil` 再测一次是 30,289,055,744 B = 28.2 GiB**，10 分钟又少 0.3 GB —— 这块盘此刻仍被别的会话在吃。

E: 的 436.9 GiB 去向（已核实部分）：

| 项 | 体积 | 证据 |
|---|---|---|
| `E:\rom\`（本盘刷机工作区，全量枚举） | **93.24 GiB** / 100,187 文件 | `scan-all.txt` |
| `E:\WSL\ub\ext4.vhdx` | **38.48 GiB** | 文件实体 41,315,991,552 B |
| `E:\pagefile.sys` | **8.00 GiB** | 初始 8192 / 最大 16384 MB |
| `E:\CRelocate\`（dot-jdks/msys64/gradle/flutter/rustup/…开发工具链重定位目录） | 未跑完（见 §7） | 单目录枚举极慢 |
| 其它（游戏/下载/归档/各项目） | 见 §7 部分结果 | `shard-*.txt` |

**没有 VSS 影子副本**（`vssadmin list shadowstorage` = No items found），`$RECYCLE.BIN` 只有 0.015 GiB —— 这两项这次不是元凶。

---

## 2. `E:\rom` 一级目录（全量枚举）

| 一级目录 | GiB | 文件数 | 一句话 |
|---|---|---|---|
| `work\` | **45.774** | 96,568 | 全部工作产物，`kit-baked` 一家占 19.53 |
| `release\` | **20.193** | 2,054 | v3/v4 两套目录 + 两个 zip + TEMP |
| `TB331FC\` | **12.160** | 202 | 原厂 ZUI16.544 包（zip 4.44 + 解压目录 7.38） |
| `yupei-ota_full-OS4.0.5.0.XPZCNXM…\` | **9.241** | 7 | 移植输入源 `payload.bin` |
| `extracted\` | **5.610** | 240 | 救砖 GSI kit |
| `logs\` / `session_dump\` / `session_logs_extract\` / `$dir` / `$out` | 0.059+0.054+0.052+0.051+0.018 | 296 | 会话与 EDL 日志 |
| `tools\` `liquid-glass\` `docs\` `.workbuddy-ai\` `TB331FC-OrangeFox\` `scripts\` `backup\` | < 0.01 | — | 小件 |
| 根目录散落 .md/.zip/.py/.log | ~0.04 | — | 6 个 dsh-session-*.zip ~20 MB 等 |
| **合计** | **93.24 GiB** | **100,187** | |

> 注：`backup\` 是空目录（0 文件）。`$dir`/`$out` 是上个会话留下的临时解包目录。

## 3. Top 20 目录（按 GB 排序，已去重：只列最细粒度）

（同名分区的表，`GB` 实为 GiB。为避免父子重复计数，父目录只要有子目录占其 >90% 就到子目录为止。）

| # | 目录 | GiB | 文件数 | 是什么 |
|---|---|---|---|---|
| 1 | `work\kit-baked\work` | **7.561** | 59 | 4 张中间大图（product/system/system_repro/system_ext）+ 一堆 .sh/.py |
| 2 | `TB331FC\刷机包\TB331FC_ZUI_16.0.544` | **7.378** | 178 | 原厂包**解压目录**（34 个 .img） |
| 3 | `release\…_v4\images` | **5.961** | 8 | v4 成品 6 镜像 |
| 4 | `release\…_v3\images` | **5.961** | 8 | v3 成品 6 镜像（与 v4 同一套） |
| 5 | `work\a17dump` | **5.961** | 7 | 回滚底牌（boot/product/system/system_ext/vbmeta×2 + SUMS） |
| 6 | `work\kit-baked\out` | **5.961** | 6 | 已刷进设备的改动镜像 |
| 7 | `work\kit-baked\out_repro` | **5.961** | 6 | 同一条流水线重跑一遍的复现件 |
| 8 | `extracted\GSI_Kit\05_镜像` | **5.592** | 5 | GSI `system_a_完全自包含.img` 5.53 |
| 9 | `work\woa\win` | **3.960** | 74 | Win11 22H2 ARM64 UUP 全套 61 文件（已 sha256 校验） |
| 10 | `release\tmp\DiagOutputDir` | **2.076** | 161 | **RD 客户端 ETL 追踪日志**（不是 9008 转储！见 §5.6） |
| 11 | `work\vendor\lenovo` | 0.774 | 3,049 | vendor 解包 |
| 12 | `work\fix-hyperos\dpi-and-formfactor` | 0.573 | 54,835 | **正在进行的形态修复，别动** |
| 13 | `work\apk` | 0.517 | 2 | `GCam_MGC_8.8.224…apk` 527 MB + 1 |
| 14 | `work\zui17_images` | 0.445 | 30 | 原厂全分区镜像（回滚用） |
| 15 | `work\of-slim\work` | 0.434 | 3,924 | OF 瘦身实验的 rootfs 解包树（可重解） |
| 16 | `work\of-pipeline\work` | 0.409 | 4,775 | OF 流水线实验的 rootfs 解包树（可重解） |
| 17 | `work\dual-boot\backup` | 0.384 | 5 | 双启动实验备份 |
| 18 | `work\a17_diag\sysui_overflow` | 0.357 | 358 | SystemUI overlay 工程 + 71 个 RRO apk |
| 19 | `work\ZUI15-extract\images` | 0.322 | 25 | ZUI15 解析镜像 |
| 20 | `work\zui16_flash\image` | 0.318 | 62 | ZUI16 刷机镜像 |

（`TB331FC\刷机包` 一级是 11.821 GiB = 解压目录 7.378 + 官方 zip 4.443；`release\` 一级 20.193 = v3 6.098 + v4 6.098 + tmp 2.261 + v3.zip 2.898 + v4.zip 2.837 + 零碎。）

---

## 4. >500 MB 单文件清单（E:\rom，共 34 个）

| GiB | 路径 | 最后修改 | 是什么 |
|---|---|---|---|
| 9.241 | `yupei-ota_full-OS4.0.5.0.XPZCNXM…\payload.bin` | 2009-01-01（包内时间戳） | 澎湃 OS 4.0.5 OTA 载荷，**移植输入源** |
| 5.396 | `extracted\GSI_Kit\05_镜像\GSI\system_a_完全自包含.img` | 2026-09-19 | 救砖 GSI 自包含系统镜像 |
| 5.116 | `TB331FC\刷机包\…ZUI_16.0.544\image\super_4.img` | 2024-11-15 | 原厂 super 最大子镜像（占原包 76%） |
| 4.443 | `TB331FC\刷机包\TB331FC_CN_OPEN_USER_Q00016_T_ZUI_16.0.544.zip` | 2025-12-13 | 官方原厂刷机包（deflate 0.603） |
| 2.898 | `release\…_v3.zip` | 2026-11-24 19:58 | v3 快照包（45 条目 / 解压 6.53 GB） |
| 2.837 | `release\…_v4.zip` | 2026-11-25 02:02 | v4 快照包（79 条目 / 解压 6.55 GB） |
| 2.794 ×7 | `work\_prod_data.img`(11-20)、`work\kit-baked\work\product.img`(14:11)、`work\kit-baked\out_repro\product_a.img`(14:05)、`work\kit-baked\out\product_a.img`(14:11)、`work\a17dump\product_a.img`(11-23)、`release\…_v4\images\product_a.img`、`release\…_v3\images\product_a.img` | — | **同一分区 7 份**（前 5 份总 13.97 GiB） |
| 1.630 ×7 | `work\kit-baked\work\system.img`、`work\kit-baked\work\system_repro.img`、`out_repro\system_a.img`、`out\system_a.img`、`a17dump\system_a.img`、`_v4\images\system_a.img`、`_v3\images\system_a.img` | — | 同上 |
| 1.444 ×6 | `work\kit-baked\work\system_ext.img`、`out_repro\system_ext_a.img`、`out\system_ext_a.img`、`a17dump\system_ext_a.img`、`_v4\images\system_ext_a.img`、`_v3\images\system_ext_a.img` | — | 同上 |
| 0.903 | `work\woa\win\UUPs\Windows11.0-KB5066793-arm64.psf` | 11-21 23:06 | Win11 UUP 补丁 |
| 0.746 | `work\tools\hyperos4_system_avb.img.gz` | 10-14 | 带 AVB 的 system 压缩镜像（工具输入） |
| 0.746 | `work\woa\win\UUPs\Microsoft-Windows-Client-Desktop-Required-Package.ESD` | 11-21 | Win11 UUP |
| 0.701 | `work\tools\gsi_trebledroid_a15_vanilla.img.xz` | 10-16 | GSI 压缩包（工具输入） |
| 0.634 | `TB331FC\刷机包\…ZUI_16.0.544\image\super_7.img` | — | 原厂 super 子镜像 |
| 0.600 | `work\woa\win\UUPs\professional_en-us.esd` | — | Win11 专业版 ESD |
| 0.554 | `TB331FC\刷机包\…ZUI_16.0.544\image\super_3.img` | — | 原厂 super 子镜像 |
| 0.514 | `work\apk\GCam_MGC_8.8.224_A11_V14a_MGC.apk` | 10-26 | GCam |

（`boot_a.img` 96 MB、两个 vbmeta 各 64 KB 不在 500 MB 门槛内，但同样有 5 份以上副本。）

---

## 5. 分类判定（点名项逐条）

图例：**可删** = 删了不丢任何不可再生内容；**谨慎** = 有价值但可权衡；**不要删** = 硬边界或仍在用。

### 5.1 `work\kit-baked\` —— 19.53 GiB（**这是本轮最大单个可回收项**）

先说结论：**这个目录的"净产出"只有 6.0 GiB（`out\`），其余 13.5 GiB 是中间件与复现件。**

`kit-baked` 是今天 13:47–14:18 做的「把 5 个 KSU 模块融进镜像」的工程，自带 `REPORT.md`（581 行，结论齐全）。

| 子目录 | GiB | 内容 | 判定 | 理由 |
|---|---|---|---|---|
| `out\` | 5.961 | 6 个交付镜像（3 张改过 + boot_a/vbmeta 两个原样搬入） | **谨慎（留这一份）** | 已刷进设备并验过 AVB（`avbtool verify_image` + 独立 python 重算 hashtree 三处一致 + e2fsck clean）。**留它是为了「想复刷/复位」时有现成输入**；真要删，`rebake.ps1` 15 分钟能重算（但产出 sha256 会变，`flash_baked.ps1` 的白名单会拦——需要同步改脚本顶部的 `$Images` 表） |
| `out_repro\` | 5.961 | 同一条流水线在 14:05 重跑一遍的产物 | **可删（推荐）** | 它的存在意义就是「证明能复现」。REPORT.md §2 已用**原厂镜像回环逐字节证明**了 AVB 参数正确（`vbmeta_system` rebuilt = `CEA948EA…6643` 与原件相同）；§8.1 也诚实说明：加了时间戳钉扎后两次重跑才一致。**证据已经落进报告，`out_repro` 只是那份证明的物证** —— 想留就压缩归档，不值得占 6 GiB |
| `work\` | 7.561 | `product.img`(2.794)+`system.img`(1.630)+`system_repro.img`(1.630)+`system_ext.img`(1.444) + 20 个 .sh/.py/.log | **可删（推荐）** | 这 4 张大图是 avbtool 加 hashtree 页脚的中间物。**`out\` 里那 3 张（mtime 与 work 里同秒：14:11:51 / 14:11:30 / 14:11:38）就是它们的拷贝**，同一套数据；`system_repro.img`(13:31) 是被取代的第一次试做。删掉后只剩脚本 63 KB。**保留**：`REPORT.md`、全部 `.py/.sh`、`dryrun.txt`、`rebake*.log` |
| `payload\`+`verify\` | 0.046 | 5 个注入载荷（fw.apk、plat.cil、build.prop、xml、rc） | **谨慎** | 只有 46 MB，是「注入什么进镜像」的物证，删了要重跑 `build_payload.py` 并从 work 里的解包树里取。太小，不值得动 |

> **一个必须说清的风险**：`out\` 的三张镜像里已经融进了 `hyperos4_developer_fix` / `xbt_continuity_fix` / `xbt_recents_proxy` / `zz_density320` / `lenovo_pen_enable` 五项。如果这 5 个模块还要继续演进（改 plat_sepolicy.cil、换 framework-res.apk），那 `out\` 就是「一次性」的 —— 按下一版重算。**这正是它适合进「可整体删除的临时目录」的理由**（见 §6）。
>
> 顺带：`out\` 里 `boot_a.img` 与 `vbmeta_a.img` 是**原样搬入未改动**（REPORT 表里写明 "未改动"），跟 `a17dump` 同哈希 —— 这 2 个只有 96 MB，不影响判断。

### 5.2 `release\…_v4\`(6.098) vs `_v4.zip`(2.837)；`_v3\`(6.098) 与 `_v3.zip`(2.898) 还在不在

**四件都在。** 实测：

| 项 | 大小 | 时间 | 内容 |
|---|---|---|---|
| `_v3\` | 6,098 GiB / 65 文件 | 目录 11-24 19:36，README 22:22 | 6 镜像 + rollback + edl + ksu_modules + 5 个 .bat |
| `_v3.zip` | 2.898 GiB (3,111,615,993 B) | 11-24 19:58 | **合法 zip**，45 条目、解压 6,526,454,856 B、前缀 `…_v3/` |
| `_v4\` | 6.098 GiB / 66 文件 | 11-24 23:10 建，README 改到 11-25 01:28 | 同上 + `selftest.bat` + `edl\SECTORS.txt`/`rawprogram_*.xml` |
| `_v4.zip` | 2.837 GiB (3,046,558,012 B) | 11-25 02:02 | **合法 zip**，79 条目、解压 6,547,715,606 B、前缀 `…_v4/` |

**v4 与 v4.zip 是不是重复？—— 是「同一份内容的两种形态」，不是字节重复。**
zip 里 79 条目 = v4 目录那 66 个文件 + 目录结构，解压后 6.55 GB ≈ 目录 6.098 GiB。**留目录就够用（能直接刷、能改壳子）；zip 只是「发给别人一个文件」的载体。**

**v3 与 v4 是不是重复？—— 镜像部分是「同一套」，壳子不是。**

| 证据 | 结果 |
|---|---|
| `_v3\images\SHA256SUMS.txt` vs `_v4\images\SHA256SUMS.txt` **文件哈希** | **`7D016967F5776BD13C8BCFBA18BE07211EC4976AEE68C19C798A22A2F804A1F6` 完全相同** |
| 6 个镜像的字节数 | 逐一相等（product 2,999,996,416 / system 1,749,999,616 / system_ext 1,549,996,032 / boot 100,663,296 / vbmeta×2 65,536） |
| 6 个镜像的 mtime | **逐一相同**（product 11-23 23:09:34、system 23:07:04…）→ 是复制而来，不是重算 |
| 顶层 `SHA256SUMS.txt` | **不同**（v3 `302AC0C1…` / v4 `0FAEFC8D…`，3570 vs 3298 B）→ 因为壳子文件变了 |
| 壳子差异 | v4 的 5 个 .bat 全部重写（`01_全量刷入.bat` 43,753 vs 26,975）、README 21,932 vs 15,647、多 `selftest.bat`(19,702) + `edl\` 两个文件 |

**结论与建议**：

| 项 | 判定 | 理由 / 代价 |
|---|---|---|
| `_v4\` | **不要删** | 当前唯一真值，01:28 还在更新 |
| `_v4.zip` | **谨慎** | 要「发一个文件给别人」就留；纯备份可删。**注意它是 02:02 的快照，而 README 01:28 之后若再改就过期** —— 作为备份本来就不牢靠 |
| `_v3\` | **可删（推荐，省 6.098）** | 镜像与 v4 同哈希同时间戳，壳子是被 v4 取代的旧版（旧 .bat 逻辑可能已经错） —— 但**`release\..._v3\images` 在指令的硬边界里，所以这条我只给结论，请 lead 拍板** |
| `_v3.zip` | **可删（推荐，省 2.898）** | 11-24 19:58 的过期快照，v4.zip 已取代它；要分发也是分发 v4 |

> 若 v4 已确认是正式版：删 `_v3\`+`_v3.zip`+`_v4.zip` = **11.83 GiB**，一个镜像字节都不丢。

### 5.3 `work\a17dump\`（5.961 GiB / 7 文件）—— **不要删**

| 文件 | 字节 | SHA256 |
|---|---|---|
| `boot_a.img` | 100,663,296 | `2510b098380a573a40ee6600aa9124ced06a047c14c21e6bf7cd596fbbc3c14b` |
| `vbmeta_a.img` | 65,536 | `9466f0e8e95a55a0ca25504a01cdd87672557ef0fb6130c16a6fde78055223ec` |
| `vbmeta_system_a.img` | 65,536 | `cea948ea538c84b1d77289ac2db473077dc293764282dd84530d677efbb86643` |
| `system_a.img` | 1,749,999,616 | `e92fa9c1…ad45` |
| `system_ext_a.img` | 1,549,996,032 | `f6e953c4…7320` |
| `product_a.img` | 2,999,641,6（见注） | `f46c5580…b996` |
| `SHA256SUMS.txt` | 490 | 与 v3/v4 的 `images\SHA256SUMS.txt` **内容完全一致**（只是行序不同） |

注：`product_a.img` 实际字节 = 2,999,996,416（上表排版误差，以 `SIZES.txt` 为准）。**硬边界，不动。**

### 5.4 `work\woa\out\` 的实验镜像 —— 已基本清空，只剩 6.85 MB

- `woa\out\` 现有 4 个文件：`Mu-tb331fc-probe-single.img`、`Mu-tb331fc-v7-heap639.img`、`Mu-tb331fc-v8-hobsfalse.img`、`SILICIUM_UEFI.fd`（3 MB，UEFI 固件本体=输入）
- 上一轮（11-24 第三轮）已删掉 33 个旧 Mu 件（514.3 MiB，含 5 个 96 MB 的 boot_a 变体）
- **判定：留着（0.007 GiB，没有回收意义）**

**但 `work\woa\` 现在的大头换了地方**：`work\woa\win\` = **3.960 GiB**，是 11-21 下载的 **Win11 22H2 (22621.6060) ARM64 Professional en-us 完整 UUP 文件集**（61/61 文件，全量 sha256 校验通过，`_DONE.txt` 已落）。

- **判定：谨慎**。它是 WOA 侧线的**输入**，而下一步「UUP→ISO 转换」**没做**（`REPORT.md §3 未完成项` 第一条）。
- 可删性：随时能重下（官方 CDN ~20 MB/s，脚本已写好 `uup\uup_download.ps1`，踩过的 3 个 bug 也记进报告了），但重下要 1–2 小时。
- 若 WOA 侧线暂时不做：**先删这 3.96 GiB 是合理的**（重下成本可控），但要 lead 点头。

### 5.5 `work\of*\out\` 的实验镜像 —— 都很小，不是元凶

| 目录 | 总量 | `out\` | `work\`（解包树，可重解） | 判定 |
|---|---|---|---|---|
| `work\of\` | 0.303（v3 独占 0.302） | — | — | 留着（v3 是现行 OF 产物，`of\v3\*.img` 硬边界） |
| `work\of-pipeline\` | 0.487 / 4,790 f | 0.077 | 0.409 / 4,775 f | `work\` 可删（rootfs 解包树）；其余留 |
| `work\of-slim\` | 0.486 / 3,929 f | 0.053 | 0.434 / 3,924 f | 同上 |
| `work\of-rebuild\` | 0.001 / 25 f | ~0 | ~0 | 留着（只有脚本与 PLAN.md） |
| `work\linux-boot\` | 0.092 / 30 f | 0.089 | `build\` 0.003 | 留着（linux 启动实验的交付物） |
| `work\woa\ch-probe\` | 0.080 / 10 f | — | — | 留着（`REPORT.md` + 探针盘） |

- **合计可回收 ≈ 0.85 GiB**（两个 `work\` 解包树）。所有这 6 个目录**今天 07:36–14:18 还在写**，且都带 `REPORT.md`/`PLAN.md` —— 整体删等于丢结论。
- 注：`of-pipeline\work\of_root\` 里有 525 个 reparse 点、`of-slim` 183 个、`vendor\lenovo` 265 个（解出来的 Android rootfs 里的符号链接，无体积）。

### 5.6 `%TEMP%` = `E:\rom\release\tmp` —— 2.261 GiB / 1,808 文件

**确认：本机 `%TEMP%`/`%TMP%` 就是 `E:\rom\release\tmp`**（用户级环境变量写死；机器级仍是 `C:\Windows\TEMP`）。所以这里装的很杂：

| 子项 | GB | 文件 | 时间 | 是什么 | 判定 |
|---|---|---|---|---|---|
| **`DiagOutputDir\`** | **2.076** | 161 | 11-22 22:44（最后写入 11-25 12:33） | **`RdClientAutoTrace-WppAutoTrace-*.etl` 97 KB–100 MB ×161 —— 这是 Windows「远程桌面客户端(RD Client)」自动追踪日志，不是 9008 转储！** | **可删（推荐，省 2.08）**。上一轮报告把它当成「9008 diag 转储」是误判。放 3 天了，纯追踪垃圾；**但它还会继续长**（见 §6 防复发第 3 条） |
| `dsh-subprocess-3R4QZm` | 0.055 | 35 | 11-25 13:44 | 本会话引擎子进程的临时产物 | 谨慎（可能有活进程在用；按 mtime >1 天再清） |
| `av2_orig` / `av2_jt` | 0.059 | 1,001 | 11-25 01:35–01:39 | 音视频素材解包残留 | 谨慎 |
| `de.fabmax.physx-jni` / `.cache` / `lwjglAdministrator` / `PCL` / `Steam++` / `XiaomiClipboard` / `node-compile-cache` | 0.021 | ~150 | 11-22 ~ 11-25 | 各类应用的临时缓存 | 可删（都是可再生的缓存，但收益小） |
| `dsh-spill-*` / `dsh-workspace-changes-*` | 0.007 | ~200 | 11-25 18:09+ | **当前正在写的** | 不要删 |

- **不要整目录删**：TEMP 现在还在被本机多个进程使用（18:16 还有新文件）。
- **可回收：`DiagOutputDir\` 单独删 2.076 GiB**，另外 0.08 GiB 是缓存级零碎。

### 5.7 其它「点名但不在清单里」的发现

| 项 | 体积 | 判定 | 理由 |
|---|---|---|---|
| `work\_prod_data.img`（`work\` 根下） | **2.794** | **可删（推荐）** | 11-20 的 product 数据段中间物，`a17dump\product_a.img` 是它的成品版本；kit-baked 的 `truncate.py` 也能从 `v4\images` 重新切出来 |
| `TB331FC\刷机包\TB331FC_ZUI_16.0.544\`（解压目录） | **7.378 / 178 文件** | **谨慎（可省 7.38，但有代价）** | 与官方 zip（4.443）是同一份：目录**多** 5 个小件（`image\restore_min.xml`、`vb_dtb.dtb`、`vb_ramdisk.cpio`、`tool\port_trace.txt`、**`tool\prog_firehose_sm6225_ddr.elf`**）。**删前必须先把这 5 个单独拷出来**，否则丢 firehose loader。上一轮已实测 7z 整包只省 2.7–3.0 GiB，不划算；正确做法是留 zip + 留 5 个小件 |
| `work\tools\hyperos4_system_avb.img.gz` + `gsi_trebledroid_a15_vanilla.img.xz` | 1.447 | 谨慎 | 是工具链的输入样本；两者都能从网盘重下，但下载地址未必在文档里 |
| `work\apk\GCam…apk` | 0.517 | 谨慎 | 装机用的 GCam，删了要重找 |
| `work\vendor\lenovo` | 0.774 / 3,049 | 谨慎 | vendor 解包，是否还有引用未逐个核 |
| `work\fix-hyperos\` | 0.836 / 55,902 | **不要删** | 11-24 22:12 还在改（`dpi-and-formfactor` 单占 0.573 / 54,835 文件） |
| `work\sysui_verify_dec` + `sysui_verify2_dec` | 0.182 / 18,748 | 可删 | 反编译树，同级 apk 都在（上一轮 B6 结论不变） |
| `work\logs` / `work\forensics_900e` | 0.672 / 0.168 | 归档而非删 | 建议 `7z a -mx=9` 压成几十 MB |
| `work\dual-boot\` | 0.623 / 27（`backup` 0.384 + `out` 0.239） | 谨慎 | 11-25 06:46 的新实验 |
| `work\a17_diag\` | 1.222 / 644 | 谨慎 | 11-25 01:34 已瘦身过（11 万小文件已清），剩下的 apk/img/jar 是真值 |
| `work\zui16_flash\image` / `ZUI15-extract\images` | 0.640 | 谨慎 | 原厂镜像残留，确认 `zui17_images` 不够用才删 |
| `E:\BNZ.6af959d2b347050\…lavender_images_V12.5.7.0…tar`（**E: 盘顶，不在 rom**） | **5.444** | 谨慎（提醒 lead） | 红米 9 (lavender) MIUI 12.5.7 fastboot 包；**E: 顶还有一份同名解包目录 `E:\lavender_images_V12.5.7.0…`（2021 年）**，疑似重复，与 TB331FC 主线无关 |

---

## 6. 防复发建议

### 6.1 先把「一次性产物」集中到一个可整体删除的目录

现状问题：一次性中间件散落在 `kit-baked\work`、`release\tmp\DiagOutputDir`、`work\_prod_data.img`、`_v3\images`、`work\of-slim\work`、`work\of-pipeline\work` 六处，每次清理都要逐个人肉判断。建议改成：

```
E:\rom\work\_ephemeral\           ← 唯一允许「整体 rm -r」的目录，且约定不放进任何不可再生内容
├─ kit-<date>\                    kit-baked 式的 rebake 中间件（work\ 里的大图、out_repro\）
├─ of-<date>\                     OF 实验的 rootfs 解包树（of-slim\work、of-pipeline\work）
├─ tmp\                           临时解包/试用件
└─ README.txt                     写清「本目录内任何东西都可删」+ 谁在写
```

配套三条硬约定（这才是防复发的关键）：

1. **交付件一律只留一份**。规矩写成：「一个产物只在一个 `out\` 目录里存在，`images\` 不复制、不复刻」。v3/v4 那种「整套镜像复制一份到新版本目录」的做法是这次 6 GiB 白占的直接原因 —— **应该只复制壳子（.bat/README/edl），`images\` 用硬链接 `mklink /H` 指向唯一真值**（同卷、零额外空间，实测本报告就在用 `fsutil hardlink list` 验证是否硬链接过）。当时 `_v3\images` 与 `_v4\images` 大小/mtime 全一致却各占 5.96 GiB —— 用硬链接本可只占一份。
2. **zip 不要留过期快照**。约定：`release\*.zip` 只在「要发出去」的当天生成，发完就删，或者由 `release\_dist\` 统一管理并只保留最新一代。
3. **`out\` 带版本号，旧代进 `_ephemeral`**。例如 `work\_ephemeral\kit-20261125\out\`，而不是把上一代留在 `work\kit-baked\out_repro\`。

### 6.2 该定期清的目录（按性价比排序）

| 优先级 | 目标 | 现在能回收 | 频率 | 备注 |
|---|---|---|---|---|
| P0 | `work\kit-baked\out_repro\` + `work\kit-baked\work\` 的 4 张大图 | **13.46 GiB** | 一次性 | 结论文档已落 `REPORT.md` |
| P0 | `work\_prod_data.img` | **2.79 GiB** | 一次性 | 成品在 `a17dump` |
| P0 | `release\tmp\DiagOutputDir\` | **2.08 GiB** | **每月**（会自动长） | 见下方第 3 条，光删还会再长 |
| P1 | `release\…_v3\` + `_v3.zip`（+`_v4.zip`） | **8.99（+2.84）GiB** | 一次性 | 需 lead 点头（`_v3\images` 在硬边界内） |
| P1 | `work\woa\win\`（UUP 全套） | **3.96 GiB** | 视 WOA 侧线 | 可重下 |
| P2 | `work\of-slim\work` + `work\of-pipeline\work` | 0.85 GiB | 每次实验后 | rootfs 解包树 |
| P2 | `work\sysui_verify{,_2}_dec\` | 0.18 GiB | 一次性 | apk 都在 |
| P2 | `work\logs\` + `work\forensics_900e\` | 0.84 GiB | 每季度 | 压缩归档，别删 |
| P3 | `TB331FC\刷机包\…ZUI_16.0.544\`（先备份 5 个小件） | 7.38 GiB | 一次性 | 有 zip 在，救砖前解压即可 |
| P3 | `work\tools\` 两个大下载样本 | 1.45 GiB | 确认无引用后 | 上一轮标记「需逐个看」 |

### 6.3 三条「机制级」防复发（比删文件更重要）

1. **杀掉 RD Client 的自动追踪（这是新发现的隐形漏点）**。`release\tmp\DiagOutputDir` 里 161 个 `RdClientAutoTrace-WppAutoTrace-*.etl`、每天长 8–15 个 × 100 MB = **每天 1 GB 级**，且因为 `%TEMP%` 被指到 E: 盘，全落在刷机盘上。做法：
   - 在 `%TEMP%` 换成别的盘之前，至少加一条计划任务每月清 `DiagOutputDir`；
   - 或按微软文档关掉 RD Client 的 WPP auto-trace（注册表/组策略项），从源头不再生成。
2. **把 `%TEMP%` 移出 `E:\rom`**。目前它指向 `E:\rom\release\tmp`，等于**所有程序的所有临时文件都写在刷机工作盘里**，还让 `release\` 这个交付目录看起来「莫名变大」。建议：设回 `C:\Users\Administrator\AppData\Local\Temp`（或在 D:/E: 单开 `E:\temp`）。这条只动环境变量，不动文件。
3. **E: 盘整体不是 rom 的问题**（见 §0/§1）：若目标是「让 E: 空出来」，光清 `E:\rom` 最多拿回 ~45 GiB；想大幅缓解得看 `E:\CRelocate\`（开发工具链重定位目录，dot-jdks/msys64/gradle/flutter/rustup/mcreator/local-npm-cache/Downloads）、`E:\WSL\ub\ext4.vhdx`（38.5，内部只用 17.5 → **虚胖 20.9 GiB 未回收**）、`E:\pagefile.sys`（8.0）这三块。

---

## 7. E: 其余部分（rom 之外）


> 这块**没有跑完**：E: 上 `E:\CRelocate\`（开发工具链重定位）与若干树有 10 万级小文件，加上本机同时有 4 个 `DeepSeekRuntime` 会话在抢盘（实测 E: 顺序读只有 0.9–3 MB/s、队列长度 8；一个 4,042 文件的小目录 `D_backup` 要 189 s），大目录单次枚举 >10 分钟。**已完成的实测见下表，未测的明确标注。**

已实测（GiB，均为本轮枚举）：

| 目录 | GiB | 文件数 | 备注 |
|---|---|---|---|
| `pagefile.sys` | **8.000** | 1 | 系统页面文件（初始 8192 / 最大 16384 MB，不是垃圾） |
| `steam\` | **7.631** | 14,901 | Steam 库（213.8 s 扫完） |
| `tbfw\` | **7.977** | 33 | 联想固件/刷机材料，33 个文件、单件大 |
| `BNZ.6af959d2b347050\` | 5.444 | 1 | **红米9 `lavender_images_V12.5.7.0…_8b85782ef6.tar`**（单文件） |
| `lavender_images_V12.5.7.0.QFGCNXM_20211109.0000.00_10.0_cn\` | 5.444 | 51 | **与上一行是同一份 MIUI 包的「解压目录」**（名字只差 `_8b85782ef6.tar`）→ **疑似 5.44 GiB 重复**，与 TB331FC 主线无关 |
| `driver-backup-20261108\` | 4.105 | 1,017 | NVIDIA 驱动备份；**`E:\CRelocate\driver-backup-20261108` 是第二份同名目录** |
| `rbr\`（junction → `E:\分析\apkwork\ben10appwork`） | 1.905 | 61,716 | **⚠ 这是 junction，数据实际在 `E:\分析` 下 —— 不能与 `分析\` 相加**（`rb`、`rborig`、`chongci-android` 同族） |
| `archive-2026-11-22T170135+0800\` + 同名 `.zip` | 1.455 + 1.096 | 1,918 / 1 | **同一份归档的目录 + 压缩两种形态** → 可省 1.1 GiB |
| `D_backup\` | 0.646 | 4,042 | 备份目录 |
| `build_kami\` | 0.603 | 23 | |
| `AstrBot\` | 0.501 | 34,851 | |
| `Earth3 ver0.21fix\` | 0.375 | 587 | |
| `minecraft-numen-1.21.1\` | 0.228 | 3,338 | |
| `QQMusicCache\` | 0.168 | 165 | 纯缓存，可清 |
| `MiBandStudio\` `Cache\` `dnaout\` `dna_build\` `b1img\` `Bin\` `Modelbench\` `.pnpm-store\` `_patch\` `_xjar\` `Motrix-1.8.19-x64.exe` | 约 0.8 | — | 零碎 |
| **已测合计（不含 junction、不含 pagefile）** | **≈ 36.6 GiB** | — | |

未测（4 个 shard 在跑但没跑完）：`分析\`、`类\`、`汇总\`、`CRelocate\`、`学习冲刺\`、`特摄英雄修复计划\`、`软件\`、`dump\`、`mv\`、`片\`、`纳米\`、`WSL\`（已知 38.48）、其余小件。

### 7.1 未完成部分的诚实说明

- 我起了 4 个并行 shard 扫描（`scan_shard.py N 4`）。第二版比第一版快很多`archive-2026-11-22…` 1.455 GiB / 1,918 文件从分钟级降到 0.1 s），但 `E:\CRelocate\`（12 个子项：dot-jdks / dot-mcreator / dot-rustup / dot-workbuddy-ai / Downloads / driver-backup / flutter / gradle-9.6.1 / GradleHome / jdk-17 / Local-npm-cache / msys64）单它一家的枚举就超过 10 分钟。
- **已测到的 `CRelocate` 子项**：`Downloads` 2.331 GiB / 1 文件（一个 2.3 GB 的单个文件）、`GradleHome` 2.395 GiB / 10,234 文件 → 合计 4.73 GiB，**该目录至少 5 GiB 起**。
- 结论不必等它：**E: 已用 436.9 GiB − rom 93.24 − vhdx 38.48 − pagefile 8.00 = 297.2 GiB 在 `E:\rom` 之外的普通目录里**。这一条足以说明「E: 快满不是刷机盘的锅」。
- 要补完（挑空闲时段，单进程 30–40 分钟能出全表）：
  ```powershell
  cd E:\rom\work\disk-cleanup-2026-11-25
  0..3 | ForEach-Object { Start-Process python "scan_shard.py $_ 4" }
  ```
  结果写进 `shard-N.txt`。**注意 `rbr`/`rb`/`rborig`/`chongci-android` 是 junction，别和 `分析\`/`学习冲刺\` 重复相加。**

---

## 8. WSL 侧

| 项 | 实测（今天） | 结论 |
|---|---|---|
| 发行版 | `ub` (WSL2, BasePath `E:\WSL\ub`)；`Ubuntu` 也仍注册着（上一轮判定为空壳） | — |
| **vhdx 实体** | `E:\WSL\ub\ext4.vhdx` = **41,315,991,552 B = 38.479 GiB**（mtime **2026-11-25 18:04:42**，一直在写） | 没 compact 过 |
| **vhdx 内部已用** | `df -B1` → **18,727,702,528 B = 17.44 GiB**（两次取样 18,754,064,384 / 18,727,702,528） | 上一轮删完是 17.06，只涨 0.38 |
| **虚胖（已删未回收）** | **≈ 21.04 GiB**（38.479 − 17.44） | **上一轮 §8.5 的 compact 从未执行** —— 这 21 GiB 仍然锁在 vhdx 里，不跑 compact 一分都拿不到 |
| `/root/linux-tb331fc` | **1,713,770,305 B = 1.596 GiB**（本轮实测，247 s） | 比上一轮删完 `.o` 后的 1.82 GiB 又小了 0.22 GiB（`/root/kbuild-clean` 与 `kbtest-*.log` 说明今天 12:38–13:09 又编过一轮）。`Image`/`vmlinux`/`.config` 是交付物，**别删** |
| `/root/woa` | **7,170,553,769 B = 6.68 GiB**（本轮实测） | 里面 `converter` 4.15 GiB（**全机唯一一份 Win11 ARM64 ISO**）+ `uefi-tb128fu` 2.40 GiB。**别删** |
| `/root/audit` / `/root/fit` | 62,950,751 B = 60 MiB / 29,500,068 B = 28.1 MiB | 小，不动 |
| `/root/owrt` | **已不存在**（`du` 无输出）→ 上一轮的整目录删除生效，`owrt-salvage\`(17.8 MiB) 留在 E: | 已清 |
| `/root` 其余 | `du` 前四项合计 8.36 GiB，而 `/` 已用 17.44 → 约 9 GiB 在 `/root/fw`(11-25 02:35)、`/root/kbuild-clean`、`kbtest-*.log`、系统本体与 docker 层 | 未逐项测 |
| **`/root` 侧结论** | vhdx 实体 38.479 GiB 恒定没涨；内部用量从 17.06 → 17.44 GiB（+0.38） | **没有「再次虚胖」** —— 是上一轮的 20.9 GiB 从来没回收过 |

**WSL 侧唯一有价值的动作仍然是那条**：`wsl --shutdown` → `diskpart compact`（或 `Optimize-VHD -Mode Full`）→ 约 **20.9 GiB** 还给 E:。命令与风险清单在上一轮报告 §8.5，本轮我没有执行（只读纪律）。

---

## 9. 诚实声明

**已证明（可复算）**
- `E:\rom` 全量：100,187 文件 / 100,116,649,640 B / 93.24 GiB，枚举 152 s，**0 个枚举错误**；973 个 reparse 点全部是解包出来的 Android rootfs 符号链接（0 体积），且 `E:\rom` 内**没有任何 junction 目录**（数据不会藏在链接后面）。
- E: 精确用量 `fsutil`：Total 499,775,442,944 / Used 469,138,563,072 / Free 30,616,305,664 B。
- `_v3\images\SHA256SUMS.txt` 与 `_v4\images\SHA256SUMS.txt` **文件哈希相同**（7D016967…）；6 个镜像的字节数与 mtime 逐一相同；顶层 `SHA256SUMS.txt` 不同（302AC0C1… vs 0FAEFC8D…）。
- 两个 zip 都是**合法 zip**（`zipfile` 能读中央目录）：v3.zip 45 条目 / 解压 6,526,454,856 B；v4.zip 79 条目 / 解压 6,547,715,606 B。
- `kit-baked\out`、`out_repro`、`work`、`a17dump`、`v3\images`、`v4\images` 里的镜像**没有任何硬链接**（`fsutil hardlink list` 每个只列出自身一条）→ 6-7 份是**真实占用**，不是引用计数造成的假象。同理 `compact /q` 显示 `_v3\images`、`_v4\images` 都是 `0 compressed, ratio 1.0`，不是 NTFS 压缩/稀疏。
- `%TEMP%` = `E:\rom\release\tmp`（用户级环境变量），`DiagOutputDir` 里是 161 个 `RdClientAutoTrace-WppAutoTrace-*.etl`（RD 客户端追踪日志）。
- WSL `df -B1` 与 vhdx 实体字节数；vhdx mtime 18:04:42（正在写）。
- 没有 VSS 影子副本；`$RECYCLE.BIN` 0.015 GiB；`E:\pagefile.sys` 8.00 GiB。

**没证明 / 没做的**
- **本报告 §0–§9 是「只读分析轮」的结论，全程没有删除任何文件**；实际删除记录见 **§10**（19:07 之后按 lead「清」的指令执行）。
- **没有重算镜像 SHA256**：v3/v4/a17dump/kit-baked 之间「同一套镜像」的判断是**清单级 + 字节数 + mtime + 无硬链接**的复合证据，不是逐字节哈希（6 张 × 3 GB 在 0.9–3 MB/s 的盘上要 1–2 小时，且会和别的会话抢 IO）。**若要升级为「已证明」，用 `certutil -hashfile` 跑 `_v4\images\*.img` 6 次即可（空闲时段 5–8 分钟）**，与 `_v4\images\SHA256SUMS.txt` 对照。
- **`kit-baked\out` 与 `work\` 里 4 张大图是否逐字节相同没算哈希**：依据是「字节数相等 + mtime 同秒（14:11:51/14:11:30/14:11:38）+ REPORT.md 记录的流水线步骤」。置信度高，但不是哈希证明。**（这 4 张大图已在 §10 删除，`out\` 保留。）**
- **E: 其余目录未测全**（§7.1 已逐条列出已完成/未完成的项）。
- `/root/linux-tb331fc` 与 `/root/woa` 的当前体积见 §8 表（已实测 1.596 / 6.68 GiB）。
- 本报告撰写期间别的会话仍在写 E:（`Get-PSDrive` 与 `fsutil` 差 0.2 GiB 就是这个），所以**任何跨时刻的空间差都不能当作释放量**。

---

## 10. 本轮实际删除（2026-11-25 19:07–19:10，lead 回「清」后执行）

**授权链**：§0–§9 只给清单 → lead 回复「清」→ 按报告里「建议先删哪些」那张表的 **5 条实删**（不含标注为「可选」的 `_v4.zip`，也不含标注「要你拍板、有取舍」的 `woa\win` / `TB331FC` 解压目录 / OF 解包树）。
逐项日志：`free-space.log`（时间戳 + 精确字节 + 删前删后空闲）。

### 10.1 已删（7 项，合计 **27.48 GiB**）

| # | 路径 | 字节 | GiB | 删后 |
|---|---|---|---|---|
| 1 | `work\kit-baked\out_repro\`（6 文件） | 6,400,786,432 | 5.961 | 已不存在 |
| 2 | `work\kit-baked\work\product.img` | 2,999,996,416 | 2.794 | 已不存在 |
| 3 | `work\kit-baked\work\system.img` | 1,749,999,616 | 1.630 | 已不存在 |
| 4 | `work\kit-baked\work\system_ext.img` | 1,549,996,032 | 1.444 | 已不存在 |
| 5 | `work\kit-baked\work\system_repro.img` | 1,749,999,616 | 1.630 | 已不存在 |
| 6 | `work\_prod_data.img` | 2,999,996,416 | 2.794 | 已不存在 |
| 7 | `release\…_v3.zip` | 3,111,615,993 | 2.898 | 已不存在 |
| 8 | `release\…_v3\`（65 文件） | 6,547,633,424 | 6.098 | 已不存在 |
| 9 | `release\tmp\DiagOutputDir\*.etl`（**167 个**，>3 分钟未写的） | 2,393,374,720 | 2.230 | 剩 6 个正在写的（0.019 GiB） |

**小计 8,049,991,680 + 6,400,786,432 + 2,999,996,416 + 3,111,615,993 + 6,547,633,424 + 2,393,374,720 = 29,503,398,665 B = 27.48 GiB**
（表里编号 1–9 是 9 行，其中 2–5 是同一次 `work\` 删除的 4 个文件，实为 7 个「项」）

### 10.2 空间实测（用 `Win32_LogicalDisk.FreeSpace`，不跨时刻相减做结论）

| 时刻 | E: 空闲 | 说明 |
|---|---|---|
| 19:06:51 | 29,966,393,344 B = **27.90 GiB** | 基线（`fsutil` 报告同一值） |
| 19:07:37 | 47,412,891,648 B = **44.16 GiB** | 删完第 1 批（6 项，16.253 GiB，与字节数之和**完全吻合**） |
| 19:07:52 | 57,072,259,072 B = **53.15 GiB** | 删完 v3 那对（+8.996 GiB，同样精确吻合） |
| 19:09:38 | — | 删 167 个 .etl（+2.22 GiB） |
| 19:10 之后 | **≈ 55.3 GiB** | 期间别的会话仍在写，读数为净效果 |

**净结果：E: 空闲 27.9 → 55.3 GiB，净增约 27.4 GiB**（与删除量 27.48 GiB 吻合；差额是并发写入）。

### 10.3 删前删后的保护性核查（全部 OK，一个字节没动）

| 项 | 结果 |
|---|---|
| `work\a17dump\` 7 个文件 | **全部存在且字节数逐一相符**（boot_a 100,663,296 / vbmeta 65,536 ×2 / system_a 1,749,999,616 / system_ext_a 1,549,996,032 / product_a 2,999,996,416 / SHA256SUMS 490） |
| `release\…_v4\images\` 6 镜像 + `SHA256SUMS.txt`(3,570) + `_v4\` 整目录 | **全部存在，字节数未变**（66 文件 / 6.098 GiB） |
| `release\…_v4.zip` | 存在 3,046,558,012 B（**没删**，见 §10.4） |
| `work\kit-baked\out\` 6 镜像 | **全部存在**（product 2,999,996,416 / system 1,749,999,616 / system_ext 1,549,996,032 / boot 100,663,296 / vbmeta 65,536 ×2） |
| `work\kit-baked\` 的 `rebake.ps1`(9,027) `flash_baked.ps1`(7,633) `build_payload.py` `surgery.sh` `verify.sh` `truncate.py` `REPORT.md`(28,121) | 全部保留（默认参数即可重算整套镜像） |
| `work\kit-baked\work\` 的脚本/日志/`cil`/`dump`/`labels`/`repro_vbmeta_system.img`/`vbmeta_system_a.img`/`_pk2048.bin` | 全部保留（该目录从 7.561 GiB 降到 **0.13 GiB**） |
| `work\of\v3\` 三个 v3 img | 存在（90,726,400 / 60,567,552 / 43,098,112） |
| `work\linux-build\out\Image-6.14.0-rc5-tb331fc` | 存在 38,959,616 B |
| `extracted\GSI_Kit\05_镜像`、`yupei…\payload.bin`(9,922,252,710)、`release\BDS-EFI-Probe\`、`.workbuddy-ai\memory\` | 全部存在 |

### 10.4 ⚠ 执行期间发现的两件事（lead 需要知道）

1. **`release\TB331FC_HyperOS4_A17_FullKit_v5\` 正在被另一个会话生成**（目录 19:03:18 出现，19:17 时已 6 文件 / 5.961 GiB）。它的 `images\product_a/system_a/system_ext_a` 的 mtime 是 **14:11:51 / 14:11:30 / 14:11:38 —— 正是 `kit-baked\out\` 那三张改造镜像的时间戳**，也就是**有人在把「已刷进设备」的那套 baked 镜像正式升格成 v5 成品包**。
   - 这正好验证了删 `out_repro` 与 `work\*.img` 的判断：**`out\` 还在，而且正在被复制成 v5**，一份都没丢。
   - **`_v4.zip` 我没删**（2.837 GiB）：v4 即将被 v5 取代，理论上它也过期了，但「要不要留一个可分发单文件」需要 lead 拍板 —— 说一句「删 v4.zip」即可再省 2.84 GiB。
   - 我全程**没有碰** `release\…_v5\`。
2. **`DiagOutputDir` 在 19:07:25 自己长出了一个 `RdClientAutoTrace\` 子目录**（`msrdc` PID 13172 正在运行并持续写 trace）。所以这次只删了 167 个 >3 分钟未写的 `.etl`，**留下 6 个正在写的**。这条**必然复发**：只要 `%TEMP%` 还在 E: 且 RD Client 的 WPP auto-trace 没关，每天会长回 ~1 GB。机制性解法见 §6.3 第 1、2 条。

### 10.5 还没动、等 lead 明确点头的（约 14.5 GiB）

| 项 | GiB | 为什么需要一个明确指令 |
|---|---|---|
| `release\…_v4.zip` | 2.84 | 唯一「可分发单文件」；v5 出来后就是过期快照 |
| `TB331FC\刷机包\…ZUI_16.0.544\`（解压目录） | 7.38 | 救砖底牌的第二种形态。删前**必须先拷出 5 个小件**（`image\restore_min.xml`、`vb_dtb.dtb`、`vb_ramdisk.cpio`、`tool\port_trace.txt`、**`tool\prog_firehose_sm6225_ddr.elf`**），且以后救砖要先解压 3–5 分钟 |
| `work\woa\win\`（Win11 ARM64 UUP 全套） | 3.96 | WOA 侧线的输入，UUP→ISO 一步还没做；重下要 1–2 小时（脚本在，可复跑） |
| `work\of-slim\work\` + `work\of-pipeline\work\` | 0.85 | rootfs 解包树，可重解；但两个实验今天还在写 |

**WSL 侧（不动，需要停机）**：`ext4.vhdx` 虚胖 **21.04 GiB** 仍在里面，跑 `wsl --shutdown` + `diskpart compact` 才能还给 E:。这一步会杀掉 WSL 里所有会话（dockerd/containerd/容器/supervisord/relay6199.py），**必须 lead 挑时间自己执行**，命令在 `disk-cleanup-2026-11-24\REPORT.md` §8.5。
