# TB331FC 刷机包制作规范 + 现有 v2 包审计

- 对象：`E:\rom\release\TB331FC_HyperOS4_A17_FullKit_v2.zip`（3,070,666,012 B / 20 条目 / 解压 6,402,223,479 B）
- 设备：TB331FC / `khaje` / SM6225-AD，adb `5e367954`，当前跑 A17（`release=17`、`sdk=37`、`ro.boot.slot_suffix=_a`、`verifiedbootstate=orange`、`veritymode=eio`）
- 日期：2026-11-24
- 性质：**全程只读**。解压只在 `E:\rom\work\flashkit-spec\extract\` 进行，`release\` 目录未改动；设备侧只做过 `getprop` / `blockdev --getsize64` / `su -c ls`，**未刷机、未写分区、未 reboot**。
- 证据标注：【实测】本次亲自跑出来的字节级结果 ·【实证】本机历史真机记录（引用时标来源） ·【推断】由证据推演 ·【未证】明确没验过

---

## 0. 一句话结论

**现有 v2 包「镜像是对的，包装是错的」：六个镜像的哈希、大小、AVB 哈希树三项全对（这是能开机的最强证据），但包缺 `tools\` 导致 01/04/05 三个脚本第一步就退出，而且包里没有任何 `/data` 侧收尾件——就算刷进去也只是「能开机」，不是「能用」。**

三句话展开：

1. **刷不动**：`tools\` 目录在 zip 里不存在。`01_全量刷入.bat` 第 7–8 行硬编码 `%~dp0tools\adb.exe` / `fastboot.exe`，第 26–33 行缺任一即 `goto :fail`；`04` 第 24–27 行同样；`05` 第 46 行调用 `tools\edl_reset.py`，而**这个文件在整个 `E:\rom` 下已经不存在**（全盘搜索 0 命中）——05 不是"补个文件"能救，得重写。只有 `02`（记录 COM 口）和 `03`（EDL 写 vbmeta）能独立跑。
2. **刷出来也不能用**：包内 `system_a.img` 的 `framework-res.apk` 里 `config_recentsComponentName` **仍是 `com.android.launcher3/com.android.quickstep.RecentsActivity`**（实测 resources.arsc 命中 1 次，修复值 `com.miui.home/...` 命中 0 次）→ 刷完小白条/全面屏手势回到失效态；`system_ext_a.img` 的 `continuity_sdk_app.xml` **仍指向 `continuity-sdk-stub.jar` 空桩** → 互传/通话流转不可用；`/system/build.prop` 仍是 `ro.build.flavor=missi-user` → 机型身份没对齐；密度修复在 vendor 侧属性 + KSU 模块，包里没有 → 回到 436dp 手机布局。这些修复全都活在 `/data`（KSU 模块 + `service.d`），**zip 里一个都没有**。
3. **有一条硬约束没有任何脚本提**：本包 `images\vbmeta_a.img` 是**原厂 544 的 8 KB vbmeta**（后面补 57,344 个 0 到 64 KB），它的 boot 哈希描述符算的是**原厂 boot**（salt+前 46,841,856 B 的 sha256 = `ad970718…`，我复算一致）；而包内 `boot_a.img` 是 100,663,296 B 的 KSU 内核，前 46,841,856 B 的 salted 哈希是 `89013232…`，**对不上**。⇒ 只有在解锁态（`orange`）下 ABL 跳过校验才开得起来。锁机刷 = 直接不开机且没有 fastboot 退路。`01` 里**没有一行 `getvar unlocked`**。

### P0 清单（会让用户刷失败或刷完不可用）

| # | P0 项 | 后果 | 证据 |
|---|---|---|---|
| **P0-1** | 包内缺 `tools\`（adb.exe / fastboot.exe / edl_reset.py） | 01、04、05 三个脚本直接退出；只有 02/03 可用 | zip 条目表 20 条无 `tools/`；01 L7-8/L26-33；04 L24-27；05 L46 |
| **P0-2** | `vbmeta_a` 与 `boot_a` 不是一对 AVB，且脚本不校验解锁 | 锁机刷入必不开机；解锁机刷入"侥幸能开" | `avbtool info_image` + 复算：声明 `ad970718…`（= 原厂 boot），实机 `89013232…` |
| **P0-3** | 不处理 A/B 槽位：硬编码 `_a`，不读 `current-slot`、不 `--set-active` | 设备在 b 槽时刷完重启回到 b 槽旧系统，用户以为"刷失败"或"没变化" | 01 全文无 `current-slot` / `set-active`，6 个分区名全写死 `_a` |
| **P0-4** | 不清 userdata、也不提示 | 从 ZUI 16（A14）首次刷 A17，FBE 密钥不匹配 → 卡加密失败/开机循环 | 01 全文无 `-w`、无 `erase userdata`、无提示 |
| **P0-5** | 包里没有 `/data` 侧收尾件 | 刷完是 436dp 手机布局 + 手势失效 + 互传空桩 + `missi` 身份 + 无 KSU 管理器 | 见 §3.5（逐条实测证据） |

---

## 1. 审计范围与方法

| 项 | 做法 | 是否只读 |
|---|---|---|
| 包结构 | `System.IO.Compression` 读中央目录，逐条列出 | ✅ |
| 解压 | 解到 `E:\rom\work\flashkit-spec\extract\`（18 文件 / 6,402,223,479 B，与 `REBUILD.md` 记录的合计字节数一致） | ✅ 只写 work 区 |
| 哈希 | 6 个镜像流式复算 sha256，与包内 `images\SHA256SUMS.txt` 逐条比对 | ✅ |
| 分区大小 | 设备侧 `blockdev --getsize64`（boot_a / vbmeta_a / vbmeta_system_a / boot_b / vbmeta_b）；逻辑分区用整分区 `dd` dump 的长度 | ✅ 只读查询 |
| AVB | `work\tools\avbtool.py info_image` 解 vbmeta_a / vbmeta_system_a 全部描述符；`work\tools\verify_hashtree.py` 的算法自己重实现一遍（`audit_image.py`，一次读盘同时算 sha256 + 哈希树） | ✅ 纯离线 |
| 镜像内容 | WSL `ub` 的 `debugfs` 只读打开 ext4：读 `/system/build.prop`、`/system/framework/framework-res.apk`、`/etc/permissions/continuity_sdk_app.xml` | ✅ 只读 |
| 脚本 | 5 个 .bat 从 GBK 解码后逐行走读；`work\tools\scan_bat.py` 做结构静态检查 | ✅ 未执行 |
| 9008 表 | 与官方 `TB331FC_ZUI_16.0.544\image\rawprogram{0,4}.xml` 逐字段核对 | ✅ |

**没做**：`fastboot getvar`（要 reboot，越界）、真机刷写、`7z t`（`REBUILD.md` 已做过，结果转引）。

---

## 2. 现状审计

### 2.1 包结构（20 条目 = 2 目录 + 18 文件）

```
01_全量刷入.bat              6,480      ← 依赖 tools\adb.exe / tools\fastboot.exe（缺）
02_进入9008.bat              1,428      ← 只记录 COM 口
03_9008刷入.bat              4,099      ← EDL 写 vbmeta（自足）
04_adb自动进入9008.bat       5,542      ← 依赖 tools\adb.exe（缺）
05_900E退出.bat              2,239      ← 依赖 tools\edl_reset.py + Python（都缺）
edl\fh_loader.exe                    561,152
edl\prog_firehose_sm6225_ddr.elf     670,608
edl\QSaharaServer.exe                176,128
edl\rawprogram_vbmeta_a.xml              340
edl\rawprogram_vbmeta_system_a.xml       349
edl\vbmeta_stock_544.img               8,192
images\boot_a.img                100,663,296
images\product_a.img           2,999,996,416
images\system_a.img            1,749,999,616
images\system_ext_a.img        1,549,996,032
images\vbmeta_a.img                   65,536
images\vbmeta_system_a.img            65,536
images\SHA256SUMS.txt                    490
```

**没有** `tools\`、`rollback\`、`scripts\`、`ksu_modules\`。原因可追：`REBUILD.md` §4 的打包命令是

```
7z a -tzip ...v2.zip *.bat edl images -mx1 -mmt4 -y
```

——**只显式列了 `*.bat edl images`**。打包那一刻起，其它目录就注定不在包里。（原始目录 `release\TB331FC_HyperOS4_A17_FlashKit\` 现已不存在，我 `Test-Path` 过。）

### 2.2 哈希与字节数（【实测】6/6 全对）

| 镜像 | 字节 | 复算 sha256 | 清单 | 结论 |
|---|---:|---|---|---|
| `boot_a.img` | 100,663,296 | `2510b098380a573a40ee6600aa9124ced06a047c14c21e6bf7cd596fbbc3c14b` | 同 | ✅ |
| `product_a.img` | 2,999,996,416 | `f46c5580e647d6a4f44d972a9db9e3b1be1b1b93ae132f357a3476eda9dab996` | 同 | ✅ |
| `system_a.img` | 1,749,999,616 | `e92fa9c1a090c583e83634a5deb16664873ab268f09cf4fd657cc642015dad45` | 同 | ✅ |
| `system_ext_a.img` | 1,549,996,032 | `f6e953c4ca31d05257e236deb2edf5ceeadf678eacd71cb8b11f9e7e80197320` | 同 | ✅ |
| `vbmeta_a.img` | 65,536 | `9466f0e8e95a55a0ca25504a01cdd87672557ef0fb6130c16a6fde78055223ec` | 同 | ✅ |
| `vbmeta_system_a.img` | 65,536 | `cea948ea538c84b1d77289ac2db473077dc293764282dd84530d677efbb86643` | 同 | ✅ |

`images\SHA256SUMS.txt`：490 B、6 行、`<sha256>` + **两个空格** + 文件名、CRLF、末尾无多余行（多一个空行，`for /f` 会跳过）。格式与 `01` 的 `for /f "tokens=1,2"` + `certutil` 逻辑兼容。

### 2.3 镜像大小 vs 实际分区大小（【实测】6/6 匹配）

| 镜像 | 镜像字节 | 分区实际大小 | 来源 |
|---|---:|---:|---|
| `boot_a.img` | 100,663,296 | **100,663,296** | `blockdev --getsize64 /dev/block/by-name/boot_a` |
| `vbmeta_a.img` | 65,536 | **65,536** | 同上（`vbmeta_a`） |
| `vbmeta_system_a.img` | 65,536 | **65,536** | 同上（`vbmeta_system_a`） |
| `system_a.img` | 1,749,999,616 | 1,749,999,616 | 整分区 `dd` 长度（`work\a17dump\`，与包内哈希一致） |
| `product_a.img` | 2,999,996,416 | 2,999,996,416 | 同上 |
| `system_ext_a.img` | 1,549,996,032 | 1,549,996,032 | 同上 |

顺带确认：`boot_b` = 100,663,296、`vbmeta_b` = 65,536，两槽几何相同。
逻辑分区的 `blockdev` 复核**没做成**——查询到一半设备 USB 掉线（本机高发，见 §8），所以逻辑分区尺寸以"整分区 dump 的长度"为准；这三张镜像本来就是按分区全长的 dump，长度即分区尺寸。

### 2.4 AVB 一致性（本包最强的一项，也是最容易被误判的一项）

#### 2.4.1 `vbmeta_a.img` = 原厂 544，逐字节

```
kit images\vbmeta_a.img   65,536 B
stock 544 image\vbmeta.img 8,192 B
前 8,192 B 逐字节相同 = True
8,192 之后非零字节 = 0
```

`avbtool info_image`（【实测】）：

| 字段 | 值 |
|---|---|
| Algorithm | `SHA256_RSA4096` |
| Public key (sha1) | `2597c218aae470a130f61162feaae70afd97f011` |
| Flags / Rollback Index | 0 / 0 |
| Release String | `avbtool 1.2.0` |
| Chain → `vbmeta_system` | 公钥 sha1 **`cdbb77177f731920bbe0a0f94f84d9038ae0617d`**，rollback index location 2 |
| Hash 描述符 | boot / dtbo / init_boot / recovery / vendor_boot（salt `0b8f7e2f…`） |
| Hashtree 描述符 | odm / system_dlkm / vendor / vendor_dlkm（salt `2e7e7a71…`，FEC 2 roots） |

链公钥 `cdbb7717…` 与 `vbmeta_system_a` 自己的公钥一致 → **链是通的**。

#### 2.4.2 但 boot 描述符描述的不是包内的 boot（【实测】决定性）

```
vbmeta_a 里 boot 描述符：Image Size 46,841,856  salt 0b8f7e2f…  Digest ad970718ab11fdbf…
salted sha256(包内 boot_a.img 前 46,841,856 B)        = 89013232fa91fa39bfb722484dec8bf5ce852c550a8fd0bb30e02391ed273990
salted sha256(原厂 544 boot.img 前 46,841,856 B)      = ad970718ab11fdbf7331b8a084809ab71d90da233d577ee7024079e43f21e3e5  ← 完全一致
```

⇒ `vbmeta_a` 描述的是**原厂 544 的 boot**，包内 `boot_a.img` 是 100,663,296 B 的 KSU 内核（前 43,098,112 B 的 sha256 = `b943b3bd…`，与 `work\of\REPORT_v2.md` 记录的 `boot_tb331fc_v2_kernel_only.img` 完全一致）。

**为什么现在能开机**：`work\woa\abl-cmd-surface\REPORT.md` §3.3 已静态证明本机 ABL 在解锁态走 `Device is unlocked, Skipping boot verification`（串 `@0xaaa52`）。设备侧 `ro.boot.verifiedbootstate=orange`、`veritymode=eio` 与之吻合。
**为什么这是缺陷**：它把"必须已解锁"变成了一条隐式前提，而 `01` 从头到尾没检查 `unlocked`。

#### 2.4.3 `vbmeta_system_a` 与三张系统镜像**完全自洽**（【实测】这是能开机的最强证据）

`vbmeta_system_a.img`：`SHA256_RSA2048`、公钥 `cdbb7717…`、flags 0、rollback 0、release `avbtool 1.3.0`，三条 hashtree 描述符（**FEC 0**，因为 `avbtool --do_not_generate_fec`）。

我把 dm-verity 根哈希独立重算了一遍（`audit_image.py`：block 4096 / sha256 / salt 前缀 / 128 叉归约）：

| 分区 | data_size | tree_size（声明） | tree_size（算） | 声明 root | **重算 root** | 结论 |
|---|---:|---:|---:|---|---|---|
| product | 2,909,995,008 | 22,921,216 | 5,551+44+1 块 = 22,921,216 | `02c25fcf…` | **`02c25fcf…`** | ✅ 一致 |
| system | 1,697,497,088 | 13,373,440 | 3,238+26+1 块 = 13,373,440 | `971e7bb1…` | **`971e7bb1…`** | ✅ 一致 |
| system_ext | 1,503,494,144 | 11,845,632 | 2,868+23+1 块 = 11,845,632 | `fef554f2…` | **`fef554f2…`** | ✅ 一致 |

镜像内部布局也对得上：`data_size + tree_size` 恰好等于 AVB footer 里的 `vbmeta_offset`（例：system 1,697,497,088 + 13,373,440 = 1,710,870,528 = footer 声明值）。

> 这条为什么值得单独说：2026-11-13 那次"同一套镜像一次能起、一次必崩"的根因就是 `product_D.img` 的 hashtree 与自身数据不符（声明 `832596f2…`，重算 `0bcedeb0…`）→ `dm-13: data block 0 is corrupted` → init 被 kill → 900E。**v2 包把那个坑修掉了**，这是它真正值钱的地方。

### 2.5 9008 侧资产（【实测】与官方 544 包同源）

| 文件 | 结论 |
|---|---|
| `edl\prog_firehose_sm6225_ddr.elf` 670,608 B | sha256 `26FBA9B7E64EAD8346CA387FE06F2D77BAD8104B5C0DEAA0FA9B249CD36F0930`，与 `544\tool\prog_firehose_sm6225_ddr.elf` **逐字节相同** |
| `edl\vbmeta_stock_544.img` 8,192 B | sha256 `52ECB456EF3E5D82A05C8473CB90414BA90496EF7B41E155C1F9928389DE8F66`，与 `544\image\vbmeta.img` **逐字节相同** |
| `edl\fh_loader.exe` 561,152 B / `QSaharaServer.exe` 176,128 B | 大小与 `544\tool\` 内同名文件一致（未逐字节比对哈希） |

两个 `rawprogram_*.xml` 的 LUN / start_sector 与官方 `rawprogram0.xml`（vbmeta_system_a）、`rawprogram4.xml`（vbmeta_a）**逐字段一致**，见 §4.6.2 的表。

> **一处容易被误判成 bug 的地方**：`rawprogram_vbmeta_a.xml` 声明 `num_partition_sectors="16"`（64 KB），而 `vbmeta_stock_544.img` 只有 8,192 B。这**不是缺陷**——官方 `rawprogram4.xml` 就是这么写的（`filename="vbmeta.img"` + 16 扇区）。kit 是忠实复刻。但要注意它**从未被真机执行过**（见 §2.6 的 04 走读）。

### 2.6 五个 .bat 逻辑走读

#### `01_全量刷入.bat`（248 行，6,480 B）

| 步 | 做什么 | 失败如何处理 | 幂等/回滚 |
|---|---|---|---|
| L1-5 | `chcp 936` / `cd /d %~dp0` / 设 `ADB` `FB` `IMG` `KSU` `TMPF` | — | — |
| `[1/6]` L19-35 | 6 个镜像存在性 + `tools\adb.exe` + `tools\fastboot.exe` 存在性 | 缺任一 → 打印文件名 → `goto :fail` | 幂等（只读检查） |
| `[2/6]` L37-49 | **问**用户"是否校验 SHA256"，输 `y` 才 `call :verifyall` | 校验失败 → 提示"重新解压" → `:fail` | **默认跳过**（回车即跳过） |
| `[3/6]` L51-68 | 90 次 × 2 s 轮询 `adb get-state` / `fastboot devices`，记 `STATE` | 都没有 → 打印进 bootloader 指引 → `:fail` | 幂等 |
| `[4/6]` L70-111 | adb 态则 `reboot bootloader`；`call :waitfb`；若在 fastbootd（`is-userspace: yes`）则退回；`getvar product` 校验 TB331FC/khaje | 型号不符 → 允许输 `YES` 继续（**无硬拦**）；进不了 fastboot → `:fail` | 幂等 |
| — L107-110 | `flash boot_a` → `flash vbmeta_a` | 任一失败 → `:fail` | 可重跑；**未做回滚** |
| `[5/6]` L113-132 | `reboot fastboot` → `call :waitfbd`（60×2 s）→ `flash system_a` → `system_ext_a` → `product_a` → `vbmeta_system_a` | 进不了 fastbootd → 一句"请确认 boot 与 vbmeta 已刷入" → `:fail` | 可重跑 |
| `[6/6]` L134-151 | `reboot`；96 次 × 5 s 等 `sys.boot_completed` | 超时**只警告**（"首次开机较慢属正常"），不判失败、不回退 | — |
| L153-162 | 若开机成功且存在 `ksu_modules\mi_os_ver.sh`，`adb push` + `su -c` 装进 `/data/adb/service.d` | 目录不存在 → "跳过"（**包里没有这个目录，所以永远跳过**） | — |
| `:verifyall` L173-187 | 读 `SHA256SUMS.txt`，逐行 `call :checkhash`，`BAD` 计数 | `BAD≠0` → `exit /b 1` | — |
| `:checkhash` L189-201 | `certutil -hashfile` 取第 2 行、去空格、与清单 `/i` 比对 | 不等 → 计数 +1 | — |
| `:flash` L225-238 | `fastboot flash %1 %IMG%\%1.img` → 输出落 `_flash.tmp` → `type` → `findstr "FAILED"/"error:"` | 命中 → 删临时文件、`exit /b 1` | 用完即删，**不留日志** |
| `:fail` L240-248 | 统一出口 | `pause` + `exit /b 1` | — |

**关键缺口**（详见 §3）：无 `getvar unlocked`、无 `getvar current-slot`、无 `--set-active`、无 `getvar partition-size`、无 `-w`、无日志落盘、型号不符可强行继续、`:flash` 不看 `errorlevel`（只看输出关键字）。

#### `02_进入9008.bat`（58 行，1,428 B）

只做一件事：读/问 COM 口 → 正则校验 `COM[0-9]+` → 写 `last_com.txt`。**不检测设备是否真在 9008**（`pnputil` 都没调），也不下发任何东西。设计意图明确（"只记录"），但用户体验上像"没反应"。失败处理：格式不对 → `goto :done`（`exit /b 0`，**用成功码退出**）。

#### `03_9008刷入.bat`（146 行，4,099 B）

| 步 | 做什么 | 失败处理 |
|---|---|---|
| L21-44 | COM 口（手填或沿用 `last_com.txt`）+ 格式校验 + 写回 | 无端口/格式错 → `:done` |
| L46-71 | 选 1=`vbmeta_system_a`（LUN 0 / sector 3235720，镜像取 `images\`）或 2=`vbmeta_a`（LUN 4 / sector 90294，镜像取 `edl\vbmeta_stock_544.img`） | 非法输入 → `:done` |
| L73-93 | 4 个文件存在性 + 打印镜像字节数/目标 LUN/扇区 | 缺 → `:done` |
| L95-100 | 二次确认（输 `n` 取消） | — |
| L102-116 | `QSaharaServer.exe -p \\.\COMx -s 13:prog_firehose_sm6225_ddr.elf` | `QSERR≠0` → 打印三条常见原因 + 手动进 9008 步骤 → `:done` |
| L118-136 | `fh_loader.exe --port=\\.\COMx --sendxml=... --search_path=... --noprompt --noreset --memoryname=ufs --zlpawarehost=1`，输出落 `_edl.tmp` | `findstr "fail"/"FAIL"/"error"/"ERROR"` 命中 → "把输出发给作者"；否则打印"写入完毕" |

缺口：**不校验 GPT**（扇区写死）；**无回读校验**（`readbackverify="false"`）；判据是关键字而非退出码；`--noreset` 后不自动复位（与 04 不一致）。

#### `04_adb自动进入9008.bat`（188 行，5,542 B）

`[1/4]` 用 `adb devices` 找设备（取第一台 `device` 态）→ `getprop ro.product.device` 校验（不符可输 `YES` 继续）→ `adb reboot edl`，失败则依次退 `su -c "reboot edl"`、`shell reboot edl`。
`[3/4]` `pnputil /enum-devices /connected` 抓 `VID_05C6` 行的第 3 token → `reg query ...\Device Parameters /v PortName` 取 COM 口，最多 60 次重试。
`[4/4]` Sahara → fh_loader 写入（同 03）→ `fh_loader --reset` 复位。

> `记忆 §9.5` 说"04 已真机端到端验证"。**要打折看**：那次设备已挂起，Sahara 直接失败，脚本按设计报错退出——所以"验证"覆盖的是**到 Sahara 失败为止**的链路，**fh_loader 的写入分支从未被真机执行过**。因此 8 KB 镜像 vs 16 扇区声明的组合、以及写入后是否需要复位，都还是【未证】。

#### `05_900E退出.bat`（84 行，2,239 B）

`where python` → 缺则报错退出；`python -c "import serial"` 失败则 `pip install pyserial`（**联网自动装包**）→ `python "%TOOLS%\edl_reset.py" --to fastboot|system --wait 60|180` → 按返回码 0/2/4 分支解释。

两个问题：① `tools\edl_reset.py` **不存在**（全盘搜索 0 命中），而脚本**没有存在性检查** → Python 以"文件不存在"退出（返回码 2）→ 脚本会把"缺文件"误报成"**没找到 900E/9008 设备**"，误导性极强；② 依赖 Python + pyserial + 联网，与"纯 bat"的交付约定冲突。

### 2.7 编码与结构静态检查（【实测】全过）

| 文件 | 字节 | CRLF | 裸 LF | BOM | scan_bat.py |
|---|---:|---:|---:|---|---|
| 01_全量刷入.bat | 6,480 | 248 | 0 | 无 | ok |
| 02_进入9008.bat | 1,428 | 58 | 0 | 无 | ok |
| 03_9008刷入.bat | 4,099 | 146 | 0 | 无 | ok |
| 04_adb自动进入9008.bat | 5,542 | 188 | 0 | 无 | ok |
| 05_900E退出.bat | 2,239 | 84 | 0 | 无 | ok |

**5/5 clean**：GBK + CRLF + 无 BOM，没有未转义的 `)` / `&`，没有裸 LF。这一项是达标的，改进版脚本也必须保持（`scan_bat.py` 已作为强制检查步骤写进规范 §4.7.4）。

---

## 3. 缺陷清单

优先级定义：**P0 = 会让用户刷失败 / 刷完不可用**；**P1 = 影响体验或排障**；**P2 = 锦上添花**。

| ID | 级别 | 缺陷 | 证据 | 影响 |
|---|---|---|---|---|
| D-01 | **P0** | 包内无 `tools\`：`adb.exe` / `fastboot.exe` / `edl_reset.py` 全缺 | zip 20 条目；01 L7-8/L26-33；04 L24-27；05 L46 | 01/04/05 三个脚本第一步即退出；`edl_reset.py` 全盘已无副本，05 需重写 |
| D-02 | **P0** | `vbmeta_a` 描述原厂 boot，与包内 KSU `boot_a` 不配对；脚本不检查 `unlocked` | §2.4.2 复算 | 锁机刷入必不开机；解锁机属"靠 ABL 跳过校验" |
| D-03 | **P0** | A/B 槽位不处理 | 01 无 `current-slot`/`set-active`，分区名写死 `_a` | 设备在 b 槽时刷完无效（回到旧系统） |
| D-04 | **P0** | 不清 userdata、不提示 | 01 无 `-w` | ZUI→A17 首次刷入卡加密/开机循环 |
| D-05 | **P0** | 无 `/data` 侧收尾件（密度/手势/互传/GMS/身份/imsdaemon/KSU 管理器） | §3.5 逐条实测 | 刷完"能开机但不能用" |
| D-06 | P1 | 不核对分区大小 | 01 无 `getvar partition-size` | 镜像大于分区时刷到一半失败，用户不知为什么 |
| D-07 | P1 | 哈希校验默认跳过 | 01 L37-48 回车即跳过 | 镜像损坏会一路刷到底 |
| D-08 | P1 | 无日志落盘 | 01 `_flash.tmp` 用完即删 | 出事无法复盘；远程排障只能靠用户截图 |
| D-09 | P1 | 型号不符可"输 YES 继续" | 01 L101-104；04 L85-90 | 最容易变砖的路径没有硬拦 |
| D-10 | P1 | fastbootd 失败无回退无指引 | 01 L117-121 | 设备卡在 fastbootd 时用户无从下手 |
| D-11 | P1 | 03/04 硬编码 LUN/扇区，不校验 GPT，写入后不回读 | 03 L58-60；XML `readbackverify="false"` | GPT 被改过的机器会写错位置 |
| D-12 | P1 | EDL 写入判据是关键字 grep，不看退出码 | 03 L127-135；04 L165-173（取了 `FHER` 只打印） | 失败可能被判成功 |
| D-13 | P1 | 无回滚镜像 | zip 无 `rollback\` | 刷坏后只能靠用户自己找原厂包 |
| D-14 | P2 | 01 引用不存在的 `ksu_modules\mi_os_ver.sh` | 01 L154-161 | 静默跳过，用户以为装过了 |
| D-15 | P2 | 02 只记 COM 口，不验证设备 | 02 全文 | 用户以为"进了 9008"其实没有 |
| D-16 | P2 | 03 `--noreset` 后不复位 | 03 L123 | 与 04 行为不一致，用户困惑 |
| D-17 | P2 | 未加 `-s <serial>`，多设备即失败 | 01/04 全文 | 本机现在就有 2 台无线 adb 设备，实测会报 `more than one device` |
| D-18 | P2 | "刷写成功"只看 `sys.boot_completed` | 01 L134-151 | 布局/手势/root 坏了也算成功 |

### 3.5 D-05 的逐条实测证据（这是本报告最重要的负面结论）

包内三张镜像 = 设备分区的**整段 dump**，所以镜像内容 = 11-23 那天设备上的原始字节。而 11-17～11-18 那些"修好才像话"的改动，**全部落在 `/data`**（KSU 模块 + `service.d`），不在任何分区镜像里。

| 修复项 | 落地位置 | 包内实测 | 刷完后果 |
|---|---|---|---|
| 全面屏手势/小白条 | KSU 模块 `xbt_module3.zip` bind-mount `framework-res-fixed2.apk` | `system_a.img` 里 `framework-res.apk` 的 resources.arsc：`com.android.launcher3/com.android.quickstep.RecentsActivity` **命中 1 次**；`com.miui.home/com.miui.home.launcher.LauncherActivityCompat` **命中 0 次** | 手势回到失效态（`LauncherProxyService isConnected=false`） |
| 平板形态 320dpi | KSU 模块 `zz_density320`（`resetprop`） | `/system/build.prop` 里**没有** `ro.sf.lcd_density`（实测无该键；实际值由 vendor/odm 侧提供，而包不刷 vendor/odm） | 回到 440dpi / 436dp → 手机布局 |
| 互传/通话流转 | KSU 模块 `xbt_continuity_v1.zip` | `system_ext_a.img:/etc/permissions/continuity_sdk_app.xml` 仍指向 `file="/system_ext/framework/continuity-sdk-stub.jar"` | 类存在但全 `return null` → 互传/通话流转不可用 |
| 机型身份 `missi` → `TB331FC/yupei/miproduct` | `service.d/_boot_fix.sh`（`resetprop`） | `/system/build.prop`：`ro.build.flavor=missi-user` | 机型身份仍是小米内部测试平台代号 |
| imsdaemon 崩溃循环 | 同上 `service.d` | 不在镜像内 | 每 ~10 s 一次 SIGSEGV 循环（WiFi-only 无 modem，属死代码但会刷日志/耗电） |
| GMS（`gsf`） | `/data` 侧装回 | 不在镜像内 | GMS 双进程不可用 |
| 「设备内部出现问题」弹窗 | `settings put global hide_error_dialogs 1` | 不在镜像内 | 每次开机弹窗 |
| KSU 管理器 APK | `/data`（清数据即丢） | 不在镜像内 | 有 root 但没管理器（`su` 可用，`ksud` 在） |

> 换句话说：**这个包复刻的是"分区"，不是"那台能用的机器"**。用户刷完会得到一台能开机、但界面是手机布局、手势失效、互传不可用的 A17。

---

## 4. 刷机包制作规范（可落地版）

### 4.1 目录结构

```
TB331FC_HyperOS4_A17_FullKit_v3/
├─ 01_全量刷入.bat            主流程（见 §6 骨架）
├─ 02_进入9008.bat            只做引导 + 端口探测（必须真探测，不能只记）
├─ 03_9008刷入.bat            EDL 写 vbmeta（自足，不依赖 tools\）
├─ 04_adb自动进入9008.bat     全自动进 EDL + 写 vbmeta
├─ 05_900E退出.bat            发 Sahara RESET_REQ 回 fastboot
├─ README.txt                 一页纸：红线 + 三步 + 排错表
├─ MANIFEST.json              机器可读清单（人/工具读，bat 不读）
├─ images/                    分区镜像 + 校验清单
│   ├─ boot_a.img  vbmeta_a.img  vbmeta_system_a.img
│   ├─ system_a.img  system_ext_a.img  product_a.img
│   ├─ SHA256SUMS.txt         <sha256>␠␠<name>，CRLF，6 行
│   └─ SIZES.txt              <name>␠<bytes>，CRLF
├─ edl/                       9008 兜底
│   ├─ prog_firehose_sm6225_ddr.elf
│   ├─ fh_loader.exe  QSaharaServer.exe
│   ├─ rawprogram_vbmeta_a.xml  rawprogram_vbmeta_system_a.xml
│   ├─ vbmeta_stock_544.img
│   └─ SECTORS.txt            §4.6.2 的扇区表（给人和脚本共用）
├─ tools/                     ★ v2 缺的就是这个
│   ├─ adb.exe  AdbWinApi.dll  AdbWinUsbApi.dll
│   ├─ fastboot.exe
│   └─ edl_reset.py           （仅 05 需要；若不发 Python 就别发 05）
├─ rollback/                  回滚件（强烈建议）
│   ├─ boot_a_stock544.img  vbmeta_a_stock544.img
│   └─ 回滚说明.txt
└─ ksu_modules/               /data 侧收尾（见 §4.8）
    ├─ zz_density320.zip  xbt_module3.zip  xbt_continuity_v1.zip
    └─ _boot_fix.sh
```

**打包命令必须显式列全目录**（v2 的事故根因）：

```
"C:\Program Files\7-Zip\7z.exe" a -tzip <out>.zip *.bat *.txt edl images tools rollback ksu_modules -mx1 -mmt4 -y
```

打包后**必须**做两件事：① `7z t` 全量 CRC；② 从 zip 里抽出每个镜像逐个复算 sha256（`REBUILD.md` 的 `verify_zip.py` 可复用）。并记录 `size + mtime` 基线——历史上出过"磁盘写满导致 zip 截断"（`TB331FC_HyperOS4_A17_FullKit.zip` 至今 2,033,188,864 B 且无中央目录）。

### 4.2 清单文件格式

**`images/SHA256SUMS.txt`**（GNU coreutils 风格，`certutil`/`sha256sum` 双向兼容）

```
<64 hex lowercase><空格><空格><filename>\r\n     ← 6 行，最后一行也有 CRLF
```

**`images/SIZES.txt`**（十进制字节，便于 bat 用 `%%~zA` 直接字符串比对）

```
boot_a.img 100663296
vbmeta_a.img 65536
...
```

**`MANIFEST.json`**（可选，给人和工具；bat 不解析）

```json
{
  "kit": "TB331FC_HyperOS4_A17_FullKit", "version": "v3",
  "built": "2026-11-24T13:00:00+08:00",
  "target": { "product": ["TB331FC","khaje"], "soc": "SM6225-AD", "abi": "arm64-v8a" },
  "requires": { "bootloader": "unlocked", "slot_policy": "flash_current_slot", "wipe": "required_on_cross_rom" },
  "images": [
    {"name":"boot_a.img","partition":"boot","bytes":100663296,"sha256":"2510b098...",
     "stage":"bootloader","avb":"not_paired_with_vbmeta_a","note":"KSU kernel"}
  ],
  "edl": { "firehose":"prog_firehose_sm6225_ddr.elf","fh_loader":"fh_loader.exe",
           "sectors":"SECTORS.txt","memoryname":"ufs" }
}
```

### 4.3 必备校验（型号 / 大小 / 哈希 三重 + 两条本机特有）

#### 4.3.1 型号
- `fastboot getvar product` ∈ {`TB331FC`, `khaje`}；不符**硬停**，不提供"继续"。
- adb 侧对照 `ro.product.device`。
- 顺带记 `getvar serialno` / `ufs_sn`（解锁申请要用，且能确认"刷的是哪台"）。

#### 4.3.2 解锁状态（本机强制）
- `fastboot getvar unlocked` 必须 `yes`；否则硬停。
- 理由见 §2.4.2：本包 boot 与 vbmeta 不是一对 AVB。
- 若将来把 vbmeta_a 重签成"描述 KSU boot"的版本，这条可以降为警告——但那时要同步更新 `boot` 描述符的 `Image Size` 与 digest。

#### 4.3.3 槽位
- `fastboot getvar current-slot` → `a`/`b` → 所有分区名拼 `<name>_<slot>`。
- **镜像文件名固定 `_a`（内容与槽位无关），目标分区名随槽位**。这一点要写进 README，否则用户会去找 `system_b.img`。
- 不建议脚本自行 `--set-active`（切槽会改变下次启动目标，属副作用）。

#### 4.3.4 哈希与大小
- 哈希：**强制**，不提供跳过；`certutil -hashfile` 逐条比对，任一条不符即停。
- 大小：
  - **物理分区**（boot / vbmeta / vbmeta_system，值 < 2³¹）：`getvar partition-size:<name>_<slot>` 与期望十六进制精确比对。
  - **逻辑分区**（system / system_ext / product，3 GB 级）：`set /a` 是 32 位，3,000,000,000 会溢出 → 纯 bat 做不了精确数值比较。规范的做法是：**打印** getvar 值与镜像字节数，**由 `fastboot flash` 自身的报错兜底**（`Not enough space to resize partition` / `Failed to write partition`）。若确实需要精确预判，只有两条路：引入 PowerShell，或接受"靠 fastboot 报错"。（这是"纯 bat"约束的直接代价，必须写进规范而不是假装做到了。）

#### 4.3.5 引导链一致性（本机特有，建议在 PC 侧预检）
发布前用 `avbtool info_image` 把 `vbmeta_a` / `vbmeta_system_a` 的描述符 dump 出来，与镜像逐个对：

```
python avbtool.py info_image --image images\vbmeta_system_a.img
# 对每条 Hashtree descriptor：Image Size / Tree Size / Salt / Root Digest 必须与镜像自洽
python <kit>\audit_image.py images\system_a.img --expect-root 971e7bb1... --data-size 1697497088 --tree-offset 1697497088
```

自洽 = 声明的 root 等于从数据重算的 root。**只有声明对声明一致是不够的**（11-13 那次就是"两处 digest 都写 832596f2，但数据不是那个 832596f2"）。

### 4.4 刷写顺序

#### 4.4.1 两个阶段，不要混
| 阶段 | 能刷什么 | 判据 | 备注 |
|---|---|---|---|
| **bootloader（ABL）** | 物理分区：`boot` `vbmeta` `init_boot` `dtbo` `vendor_boot` `recovery` | `getvar is-userspace` = `no` | 24 个 critical 分区（`abl` `xbl` `tz` `devinfo` `frp` …）**被 ABL 硬拦**，只能 9008 |
| **fastbootd** | super 里的逻辑分区：`system` `system_ext` `product` `vendor` `odm` `vendor_dlkm` `system_dlkm` | `getvar is-userspace` = `yes` | 进 fastbootd 靠 `fastboot reboot fastboot`，而它依赖 **boot + vbmeta 可用** |

#### 4.4.2 先 vbmeta 还是先 boot？
**同一阶段内没有物理依赖，但必须"成对、同一次会话内"完成；推荐顺序 `boot` → `vbmeta`（vbmeta 在后）。**

理由：
1. 解锁态下 ABL 跳过 AVB，谁先谁后结果一样（`abl-cmd-surface\REPORT.md` §3.3）。
2. 若将来回锁/加固，vbmeta 描述的是 boot 的哈希，**vbmeta 必须最后写**才能保证"写进去的 vbmeta 与已落盘的 boot 一致"。
3. 反过来的风险：先写 vbmeta、再写 boot 失败 → 分区里是"新 vbmeta + 旧 boot"，比"新 boot + 旧 vbmeta"更难解释。所以 boot 先。
4. 两者之间**禁止 reboot**：ABL 在两次 flash 之间不会校验，但中途掉电会留下半套。

#### 4.4.3 动态分区怎么刷
1. `fastboot reboot fastboot` → 等 `is-userspace: yes`（最多 120 s）。
2. 逐个 `fastboot flash <name>_<slot> images\<name>_a.img`。
3. 镜像大于当前逻辑分区时，fastbootd 会尝试 resize；失败会报 `Not enough space to resize partition`。此时手工：
   ```
   fastboot delete-logical-partition product_a
   fastboot create-logical-partition product_a 2999996416
   fastboot flash product_a images\product_a.img
   ```
   腾空间顺序（本机实测经验）：**先缩 `product`/`system_ext`，再扩 `system`**。super 总容量 12 GB，本包三张合计 6.3 GB，正常够。
4. **`vbmeta_system` 必须最后刷**：它是三张逻辑分区哈希树的"开关"，重启前必须与三张新镜像同批落盘。

#### 4.4.4 重启前的最后一道
- 确认 `vbmeta_system_a` 已刷（它声明 system/system_ext/product 的 root digest）。
- 若清了 userdata：`fastboot -w`（会同时清 `metadata`）。
- `fastboot reboot`，首启耐心 5–10 分钟。

### 4.5 失败处理

#### 4.5.1 每步的判据（两条都要，主次分明）
1. **退出码**为主：`%ERRORLEVEL%` ≠ 0 即失败（fastboot 失败一律非 0）。
2. **输出关键字**为辅：`FAILED` / `error:` / `cannot load` / `Invalid sparse`。
3. 两者都过才算成功。**不要只用关键字**（fh_loader 的输出里 `error` 可能出现在非致命行），**也不要只看退出码**（部分 fh_loader 版本失败也返回 0）。

#### 4.5.2 常见错误与处置

| fastboot 报错 | 根因 | 处置 |
|---|---|---|
| `Flashing is not allowed for Critical Partitions` | 该分区在 ABL 的 24 条 critical 白名单里（`abl` `xbl` `tz` `devinfo` `frp` `secdata` …） | fastboot 无解，只能 9008（`fh_loader`） |
| `Flashing is not allowed in Lock State` | 未解锁 | 先走官方解锁流程（`flash unlock sn.img` + `oem unlock-go`） |
| `Not enough space to resize partition` | super 里空间不足 | 先删/缩其它逻辑分区（§4.4.3） |
| `Partition not found` / `Invalid partition name` | 分区名或槽位后缀错 | 用 `getvar current-slot` 重新拼名 |
| `error: cannot load 'x.img': No such file or directory` | 文件缺失/路径含中文 | 工作目录改纯 ASCII（本机历史坑） |
| `FAILED (remote: 'unknown command')` | 该命令在本机 ABL **未注册**：`boot` / `flashing unlock` / `flash`（无冒号） | 换等效路径：`flash boot` + `continue` |
| `FAILED (Write to device failed (no link))` | USB 掉线（本机高发） | 换线/换口/关 USB hub；重跑（幂等） |
| `fastbootd` 进不去（`is-userspace` 恒 `no`） | boot 或 vbmeta 坏了 | 回 bootloader 重刷 boot+vbmeta；仍不行走 9008 |
| 设备变 `05C6:900E` | 内核 panic 后的 Qualcomm memory dump | **先退出到 fastboot**（`05` 发 Sahara RESET_REQ），900E 状态下什么都刷不进去 |

#### 4.5.3 自动回退到 a 槽
**时机**：`reboot` 后 10 分钟仍无 `sys.boot_completed=1`，且设备仍在 adb/fastboot。
**动作**：`fastboot --set-active=<另一槽>` → `fastboot reboot`，日志记录"已回退，刷入的槽内容保留便于取证"。
**不做**：不回刷镜像（保留现场），不自动清数据（不可逆）。

#### 4.5.4 什么时候进 9008
| 状态 | USB ID | 能否 fh_loader | 第一步 |
|---|---|---|---|
| 正常 Android | 见 adb | — | `adb reboot edl`（本机曾报 `unknown command`，也试 `su -c "reboot edl"`） |
| fastboot（ABL） | `18D1:D00D` | ❌ | 能刷物理分区，不必进 9008 |
| **9008** | `05C6:9008` | ✅ | 标准 EDL，Sahara + Firehose |
| **900E** | `05C6:900E` | ❌（Sahara 卡 memory_debug） | 先发 `SAHARA_RESET_REQ` 回 fastboot |

**进 9008 的物理操作**：先充电 20 分钟（0% 极易掉线）→ 长按电源 15–30 s 关机 → **同时按住 音量+ 与 音量−** → 插 USB → 听到"叮"后松开。失败可放余电 1 分钟重试。

### 4.6 9008 兜底

#### 4.6.1 需要哪些文件
| 类别 | 文件 | 说明 |
|---|---|---|
| Firehose | `prog_firehose_sm6225_ddr.elf`（670,608 B） | 本机专用；`lite` 版（670,480 B）也可试 |
| 传输 | `fh_loader.exe`（561,152 B）、`QSaharaServer.exe`（176,128 B） | QPST 附带；`fh_loader` 是真正的写入器 |
| 分区表 | `rawprogram0..5.xml` + `patch0..5.xml` | LUN 0–5；`patch*.xml` 负责 GPT 修补 |
| GPT | `gpt_main*.bin` / `gpt_backup*.bin` | 仅在 GPT 被破坏时用；**不要随手写** |
| 镜像 | 各物理分区镜像；`super_*.img` 用于 super 切片 | 见 §4.6.3 |
| 扇区表 | §4.6.2 | 单分区救砖时手写 `rawprogram` 用 |

#### 4.6.2 扇区偏移表（【实测】与官方 `rawprogram0.xml` / `rawprogram4.xml` 逐字段一致）

| 分区 | LUN | start_sector | 字节偏移 | 扇区数 | 大小 |
|---|---:|---:|---|---:|---:|
| `vbmeta_system_a` | 0 | 3,235,720 | `0x315F88000` | 16 | 64 KB |
| `vbmeta_a` | 4 | 90,294 | `0x160B6000` | 16 | 64 KB |
| `boot_a` | 4 | 65,414 | `0x0FF86000` | 24,576 | 96 MB |
| `dtbo_a` | 4 | 90,310 | `0x160C6000` | 6,144 | 24 MB |
| `init_boot_a` | 4 | 97,518 | `0x17CEE000` | 2,048 | 8 MB |
| `boot_b` | 4 | 215,150 | `0x3486E000` | 24,576 | 96 MB |
| `vbmeta_b` | 4 | 240,030 | `0x3A99E000` | 16 | 64 KB |
| `dtbo_b` | 4 | 240,046 | `0x3A9AE000` | 6,144 | 24 MB |
| `recovery_b` | 4 | 247,254 | `0x3C5D6000` | 25,600 | 100 MB |
| `vendor_boot_b` | 4 | 272,854 | `0x429D6000` | 24,576 | 96 MB |
| `init_boot_b` | 4 | 297,430 | `0x489D6000` | 2,048 | 8 MB |

（`recovery_b` / `vendor_boot_b` / `init_boot_b` 在官方 XML 里 `filename=""`，即只定义几何、不写内容。）

单分区救砖的 XML 模板（本包 `edl\rawprogram_vbmeta_system_a.xml` 就是这个形状）：

```xml
<program SECTOR_SIZE_IN_BYTES="4096" file_sector_offset="0"
         filename="vbmeta_system_a.img" label="vbmeta_system_a"
         num_partition_sectors="16" physical_partition_number="0"
         readbackverify="false" size_in_KB="64.0" sparse="false"
         start_byte_hex="0x315F88000" start_sector="3235720" />
```

调用（注意三个坑）：

```
fh_loader.exe --port=\\.\COM5 --sendxml=rawprogram_vbmeta_system_a.xml ^
              --search_path="<镜像目录>" --memoryname=ufs --zlpawarehost=1 ^
              --noprompt --noreset
```
- 端口必须写 `\\.\COM5`，裸 `COM5` 会警告；
- **`--memoryname=ufs` 漏了必失败**（上次失败真因）；
- 只有 `--sendxml`，读也是 `--sendxml`（XML 里用 `<read>` 元素）；工作目录用纯 ASCII。

#### 4.6.3 设备不亮屏也能刷的原理与边界
- **能**：9008 下 Sahara + Firehose 只依赖 USB 枚举（`05C6:9008`），不需要屏、不需要系统、不需要 fastboot。
- **能刷什么**：任何物理分区，包括 fastboot 拦不住的 critical 分区（`abl`/`xbl`/`tz`）。
- **刷不了什么**：`super` 里的逻辑分区——9008 只认物理扇区。要么整块写 `super`（`super_empty.img` + `super_*.img` 切片），要么刷回物理镜像后靠 fastbootd。
- **两个红线**：
  1. **严禁勾"全部格式化"**（QFIL）——丢 IMEI / SN / 校准数据。
  2. **`persist` 在官方 `rawprogram0.xml` 里是 `filename=""`**（`label="persist" start_sector="8"`，32 MB，LUN 0）→ **官方刷机永远不写 persist**。persist 全零会导致"声音+录音同时消失、BT MAC 变 null"，只能手工 `fh_loader` 单刷 `persist.img` 修复。

#### 4.6.4 本包 9008 能力的现状
只能写两个 vbmeta。对"vbmeta 写坏不开机"够用（这正是 `03`/`04` 的设计目标，`03` 的提示语也如实说了）。**但不是完整兜底**：boot 写坏、super 脏、GPT 坏都救不了。规范要求：完整包应附 `SECTORS.txt` + 至少 `boot_a` / `vbmeta_a` / `vbmeta_system_a` 三个单分区 `rawprogram`，并在 README 里写明"更重的救援请用官方 544 全量包"。

### 4.7 用户交互

#### 4.7.1 编码与文件格式（硬要求）
- **GBK + CRLF + 无 BOM**；首行 `@echo off` + `chcp 936 >nul`。
- 纯 `.bat`，不引入 `.ps1`（用户明确拒绝）；不依赖 Python（除 05 这类确实需要的，且必须在 README 里前置声明）。
- 中文提示；专有名词保留原文（`fastbootd`、`vbmeta`、`super`）。

#### 4.7.2 危险操作的二次确认
| 操作 | 确认方式 |
|---|---|
| 开始刷写 | 列出"将写入的分区 + 槽位"，要求输入 `YES` |
| 清 userdata / metadata | 要求输入 `ERASE`（只按回车=跳过） |
| 型号不符 | **不给继续选项**，直接中止 |
| 未解锁 | **不给继续选项**，直接中止 |
| 9008 写入 | 列出 `镜像 / LUN / start_sector / 字节数`，输 `n` 取消 |

#### 4.7.3 日志落盘
- 路径：`logs\flash.log`；重跑前把上一份改名 `logs\flash_prev.log`（不删，便于对比两次刷写）。
- 每行 `[HH:MM:SS] 文本`；**每条 fastboot/fh_loader 命令的完整输出都追加进去**（`type out.txt` 到屏幕 + `>>log`）。
- 失败时打印"停在阶段 N / 失败步骤 / 回滚命令 / 日志路径"。
- 不要在日志里写 `&` `|` `^` `)` 等字符（cmd 会截断）——用中文标点代替。

#### 4.7.4 静态检查（发布前必跑）
```
python E:\rom\work\tools\scan_bat.py <kit目录>
```
检查：未转义的 `)`（会提前闭合 `if (...)`）、echo 里的裸 `&`、裸 LF、UTF-8 BOM、制表符/行尾空格。**5/5 clean 才算过。**

已知的四个 cmd 坑（本项目实测踩过，写进规范避免复发）：
1. `&` 绝不能经过 `set` 变量（USB 实例 ID `USB\VID_05C6&PID_9008\...` 会被拆成命令分隔符）→ 让 `%%J` 直接嵌在 `for /f` 的命令串里。
2. `for /l` 块里的 `for /f` 会被二次解析 → 用 `goto` 重试循环代替。
3. `echo "!VAR!"` 同样会泄漏 `&`。
4. `echo` 里的裸 `)` 会切断 `if (...)` 块 → 必须写 `^)`。

#### 4.7.5 进度可读性
阶段号固定 `[n/7]`，每步一行结论（`OK` / `FAIL` + 原因），失败立即停并打印"已完成到哪一步"。

### 4.8 `/data` 侧收尾（本机特有，必须写进规范）

**原则：分区镜像负责"能开机"，`/data` 负责"能用"。两者必须一起发，否则等于交付半成品。**

| 修复项 | 落地形态 | 不做会怎样 |
|---|---|---|
| 密度 320（平板形态） | KSU 模块 `zz_density320`（`post-fs-data.sh` 里 `resetprop`） | 436dp → 手机布局 |
| 全面屏手势/小白条 | KSU 模块 bind-mount 修好的 `framework-res.apk` | 手势失效 |
| 互传/通话流转 | KSU 模块改 `continuity_sdk_app.xml` 指向 `LyraSdkSpp.apk` | 空桩，功能全废 |
| 机型身份 / imsdaemon | `service.d/_boot_fix.sh`（`resetprop` + 停 `imsdaemon`） | `missi` 身份 + 崩溃循环 |
| GMS | `/data` 侧装回 `gsf` | GMS 不可用 |
| 错误弹窗 | `settings put global hide_error_dialogs 1` | 每次开机弹窗 |
| KSU 管理器 | 预装进 `product_a.img` 的 `/product/app/`（未收口）或首次开机脚本 `pm install` | 有 root 没界面 |

**建议实现**：把上表做成 `ksu_modules/` + 一个 `首次开机.bat`（`adb push` 模块 → `ksud module install` → `reboot`）。这样"刷完 = 可用"，而且模块可单独回滚。

---

## 5. 差距清单（规范 vs 现有 v2）

| # | 规范要求 | 现状 | 结论 | 优先级 |
|---|---|---|---|---|
| 1 | 目录含 `tools\` | 无 | **缺失** | **P0** |
| 2 | 型号核对（硬拦） | 有，但可"输 YES 继续" | **建议改进** | P1 |
| 3 | 解锁状态核对 | 无 | **缺失** | **P0** |
| 4 | 槽位核对 + 分区名随槽位 | 无（写死 `_a`） | **缺失** | **P0** |
| 5 | 哈希清单 + 强制校验 | 清单有、格式对、默认跳过 | **建议改进** | P1 |
| 6 | 镜像大小 vs 分区大小 | 无 | **缺失** | P1 |
| 7 | 镜像大小 vs 清单字节数 | 无（清单里只有哈希） | **建议改进** | P2 |
| 8 | 引导链一致性（vbmeta ↔ 镜像） | 发布时未做；但**结果自洽**（§2.4.3） | **已满足**（侥幸） | — |
| 9 | 刷写顺序（两阶段） | 正确（ABL 刷 boot/vbmeta → fastbootd 刷三张 + vbmeta_system） | **已满足** | — |
| 10 | vbmeta_system 最后刷 | 是（`01` L124-131 顺序正确） | **已满足** | — |
| 11 | 逐分区刷 + 失败即停 | 是 | **已满足** | — |
| 12 | 失败判据（退出码 + 关键字） | 只有关键字 | **建议改进** | P1 |
| 13 | 自动回退 a 槽 | 无（只警告"首次开机较慢"） | **缺失** | P1 |
| 14 | 清 userdata（跨 ROM） | 无 | **缺失** | **P0** |
| 15 | 日志落盘 | 无（临时文件用完即删） | **缺失** | P1 |
| 16 | 危险操作二次确认 | 仅哈希询问 + 型号可绕过 | **建议改进** | P1 |
| 17 | 9008 兜底（firehose + rawprogram + 扇区表） | 有 vbmeta 两条 + firehose + fh_loader | **部分满足** | P1（补 boot/扇区表） |
| 18 | 9008 资产来源可信 | 与官方 544 包逐字节同源 | **已满足** | — |
| 19 | 扇区偏移正确 | 与官方 XML 逐字段一致 | **已满足** | — |
| 20 | 9008 写入后回读校验 | 无（`readbackverify="false"`） | **缺失** | P2 |
| 21 | 9008 自动认口 | 04 有（`pnputil`+`reg query`） | **已满足** | — |
| 22 | 900E 退出能力 | 有 05，但依赖缺失的 `edl_reset.py` + Python | **缺失**（需重写） | **P0**（脚本不可用） |
| 23 | 回滚镜像随包 | 无 | **缺失** | P1 |
| 24 | `/data` 侧收尾件随包 | 无 | **缺失** | **P0** |
| 25 | 编码/结构（GBK+CRLF+无 BOM+无 `)`/`&`） | 5/5 全过 | **已满足** | — |
| 26 | 打包列全目录 + 打包后校验 | 只列 `*.bat edl images`；打包后做过 7z t + 哈希 | **建议改进**（列目录这一项） | P1 |
| 27 | 多设备时 `-s <serial>` | 无 | **缺失** | P2 |
| 28 | 刷完功能自检（密度/手势/root） | 无 | **缺失** | P2 |
| 29 | README（一页纸红线 + 排错表） | 无 | **缺失** | P1 |
| 30 | 未在真机执行过的分支要标注 | 04 的写入分支从未真机跑过，但文档写成"已端到端验证" | **建议改进** | P1 |

**汇总**：已满足 8 项、缺失 14 项、建议改进 8 项。其中 P0 共 6 项（1/3/4/14/22/24），**这 6 项不修，这个包不能交付给用户**。

---

## 6. 附：改进版脚本骨架

文件：`01_全量刷入_v3骨架.bat`（16,235 B / 545 行，GBK + CRLF + 无 BOM，`scan_bat.py` 1/1 clean，**未在真机执行**）。

结构与 v2 的对应关系：

| 骨架阶段 | 做了什么 | 修掉的缺陷 |
|---|---|---|
| `[1/7]` 环境自检 | 缺 `tools\adb.exe`/`fastboot.exe` 时给出**具体修法**（复制 platform-tools 的哪几个文件） | D-01 |
| `[2/7]` 哈希 + 字节数 | **强制**校验，6 行清单必须齐；任一失败即停 | D-07 |
| `[3/7]` 设备身份 | 型号硬拦；**`getvar unlocked` 硬拦**；`getvar current-slot` → `SUF`/`OTHER` | D-02 / D-03 / D-09 |
| `[4/7]` 分区尺寸 | 物理分区 `set /a` 精确比对（`0x6000000` 等）；逻辑分区打印 + 依赖 fastboot 报错 | D-06 |
| `[5/7]` 二次确认 | 列出将写的分区与槽位，输 `YES` | D-16 |
| `[6/7]` bootloader 阶段 | `flash vbmeta` → `flash boot`（成对、失败即停、输出入日志） | D-12 |
| `[7/7]` fastbootd 阶段 | `system` → `system_ext` → `product` → `vbmeta_system`（最后） | — |
| 清数据 | 输 `ERASE` 才 `fastboot -w`，默认跳过 | D-04 |
| 重启等待 | 120×5 s 等 `sys.boot_completed` | — |
| 失败回退 | 超时 → 若在 fastboot 则 `--set-active=<另一槽>` + reboot；若不在则给 9008 三步指引 | D-13 |
| `:log` | 每行 `[时间]`，同时上屏与落 `logs\flash.log`，重跑前改名为 `flash_prev.log` | D-08 |
| 全局 | 所有 adb/fastboot 调用带 `-s <serial>` | D-17 |

**几处刻意的取舍（都在脚本注释里写了原因）**：

1. **逻辑分区不做精确数值比较**。`cmd` 的 `set /a` 是 32 位有符号，`3,000,000,000` 直接溢出；`if 3000000000 LSS ...` 同样不可靠。所以骨架里物理分区用 `set /a` 精确比对（`0x6000000` / `0x10000` 都在 32 位内），逻辑分区只打印并由 `fastboot flash` 自身报错兜底。要在纯 bat 里做精确比较，只能绕（例如按字符串截断到 MB 再比），那会让"差 1 字节也算过"，不如明说做不到。
2. **不自动 `--set-active`**。切槽是副作用，会改变下次启动目标；只在"开机超时"这一条失败路径上作为回退动作。
3. **镜像文件名固定 `_a`，目标分区名随槽位**。包内只有 `_a` 镜像，但内容与槽位无关，所以 b 槽也用同一份。
4. **不自动 resize 逻辑分区**。`delete-logical-partition` 是不可逆操作，交给用户按提示手工做（脚本打印确切命令）。
5. **不执行**。按任务要求只交付骨架；`[6/7]` 之后的所有分支都未经真机验证，这一点写在文件头。

静态自检（本次已做）：`goto`/`call` 目标 16 个全部可解析、无悬空标签、无未使用标签；`scan_bat.py` clean。

---

## 7. 复现命令（全部只读）

```powershell
# 1 解包到 work 区（不动 release）
#    见 _decoded\ 下的 GBK→UTF-8 副本；原 bat 仍在 extract\
Get-ChildItem -LiteralPath 'E:\rom\work\flashkit-spec\extract' -Recurse -File |
  Measure-Object Length -Sum            # 18 文件 / 6,402,223,479 B

# 2 哈希 + 哈希树自检（一次读盘同时算两样）
python E:\rom\work\flashkit-spec\audit_image.py `
  E:\rom\work\flashkit-spec\extract\images\system_a.img `
  --expect-sha e92fa9c1a090c583e83634a5deb16664873ab268f09cf4fd657cc642015dad45 `
  --data-size 1697497088 --tree-offset 1697497088 --tree-size 13373440 `
  --expect-root 971e7bb18f7f2a5c3c409e6e633282abfecc8ef4aa25ede805bc2718240ba024

# 3 vbmeta 描述符
python E:\rom\work\tools\avbtool.py info_image --image E:\rom\work\flashkit-spec\extract\images\vbmeta_a.img
python E:\rom\work\tools\avbtool.py info_image --image E:\rom\work\flashkit-spec\extract\images\vbmeta_system_a.img

# 4 镜像内容（WSL 只读）
wsl -d ub -u root -- bash -lc 'debugfs -R "cat /system/build.prop" /mnt/e/rom/work/flashkit-spec/extract/images/system_a.img'

# 5 脚本结构
python E:\rom\work\tools\scan_bat.py E:\rom\work\flashkit-spec\extract
python E:\rom\work\tools\scan_bat.py E:\rom\work\flashkit-spec\01_全量刷入_v3骨架.bat
```

日志：`E:\rom\work\flashkit-spec\audit_images.log`（三张镜像的完整审计输出）。

---

## 8. 边界与未做

1. **没刷机**。全部结论来自离线字节分析与设备只读查询；"刷了能不能开机"由 AVB 自洽性推断，不是真机验证。
2. **`fastboot getvar` 没做**（需 reboot）。所以 `partition-size` / `unlocked` / `current-slot` 的真机回显是【未证】，骨架里的写法依据是 `abl-cmd-surface\REPORT.md` §5 的静态变量表。
3. **设备 USB 掉线**：`blockdev --getsize64` 只取到 `boot_a` / `vbmeta_a` / `vbmeta_system_a` / `boot_b` / `vbmeta_b` 五项，逻辑分区三项没取到（改由整分区 dump 长度代替）。本机 USB 不稳是已知问题（记忆 §0）。
4. **`tools\edl_reset.py` 已不可恢复**：全盘 `Get-ChildItem -Recurse -Filter edl_reset.py` 0 命中，`release\TB331FC_HyperOS4_A17_FlashKit\` 目录也已不存在。05 要恢复功能只能按 `work\tools\auto_900e.py` 的思路重写一个纯 bat 版（用 `mode`/串口发送字节）或改回发 05 的 Python 依赖并在 README 前置声明。
5. **没验 `fh_loader` 的 8 KB/16 扇区行为**：需要一台真机在 9008 下试。官方 QFIL 包也是这个组合，风险低但【未证】。
6. **没评估**"把 vbmeta_a 重签成描述 KSU boot"的可行性（那样就能锁机启动）。技术上可行（`avbtool add_hash_footer` + `make_vbmeta_image` 的配方在记忆 §9.5 里有，私钥 `work\tools\testkey_rsa4096.pem` 本地就有），但会改动发布套件，属新工作，不在本次审计范围。
7. `_decoded\` 里是从 GBK 转出的 UTF-8 副本（只为便于阅读），**原文件未改**；`extract\` 保持 zip 原样。
