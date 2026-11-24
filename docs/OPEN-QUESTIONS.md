# 未解问题清单（OPEN-QUESTIONS）

> 还没答案的问题 + **每个问题具体到命令/实验的验证方法**。
> 编号 `Q-xx`；按"先做哪个"排序：**§1 只读零风险 → §2 单变量实验 → §3 写操作 → §4 需要外部条件 → §5 报告缺口**。
> 风险标记：🟢 只读 · 🟡 改状态但可逆 · 🔴 写分区（有回滚路径）· ⚫ 高风险/不可逆。

**通用前置**（每条实验都适用，→ `dual` FLASH-PLAN §4）：
```
读数一律用：Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_05C6|VID_18D1|VID_17EF' }
槽位三件套：fastboot getvar current-slot / slot-unbootable:a / slot-retry-count:a
每次实验前读一次 retry（每崩一次减 1，到 0 时 ABL 拒启动该槽）；--set-active=a 可重置
```

---

## 1. 只读（🟢 一次 adb 或一次 9008 只读就能定）

### Q-01 解锁态权威到底在哪一侧？（devinfo 是镜像，那真值存哪）

- **为什么重要**：决定"改 `devinfo` 能不能回锁/改状态"是否有意义。当前 `devinfo+0x0D=0` 却 `unlocked: yes`。
- **已知**：`0x13230` 是 `gBS->LocateProtocol(GUID {8E5EFF91-21B6-47D3-AF2B-C15A01E020EC})`，向固件/安全侧问状态；写盘函数幂等只在"值要变"时补写（→ `small` §4.3）。
- **验证**：
  ```powershell
  & $fb oem device-info                      # 期望打印 "Device unlocked: yes"
  & $fb getvar unlocked                      # 期望 yes
  ```
  再 `adb shell su -c 'dd if=/dev/block/by-name/devinfo bs=4096 count=1 | od -A x -t x1z'` 看 `+0x0D` 是否仍为 0。
- **判据**：`oem device-info` 打 `yes` 而 `+0x0D` 是 0 ⇒ "读全局不读分区"成立。
- **若想再进一步**：反汇编 `0x13230` 拿到那个 protocol GUID 的**生产者**（哪个 DXE 模块 `InstallProtocolInterface`），才能确定"权威"落在 XBL 的哪一块 RAM 或哪个 fuse。

### Q-02 `has-slot:recovery` 是 yes 还是 no

- **为什么重要**：决定 recovery 线实验用 `recovery_a` 还是 `recovery_b`（→ `dual` FLASH-PLAN §9-1）。
- **验证**：`fastboot getvar has-slot:recovery`
- **判据**：`yes` ⇒ 有 `recovery_a/b` 两个槽（GPT 里确实两个都在）；`no` ⇒ 只有单槽 `recovery`。

### Q-03 `partition-size:recovery_a/b` 真实值

- **为什么重要**：按原厂镜像推出 96 MiB（100,663,296 B），但没在设备上验证过；决定 OF ramdisk（47.6 MB）塞不塞得下（→ `dual` FLASH-PLAN §9-2）。
- **验证**：`fastboot getvar partition-size:recovery_a`（和 `_b`）

### Q-04 机上 `recovery_a` 是否逐字节等于原厂 `recovery.img`

- **为什么重要**：`recovery_b` 已确认是 ZUI17 内容（`zuidiff` §5.3），`recovery_a` 按指纹是 ZUI16——但指纹方法对大分区只取前 64 MiB（`HEAD64M` 模式）。
- **验证**（需 root，100 MB）：
  ```powershell
  & $adb root
  & $adb shell "dd if=/dev/block/by-name/recovery_a of=/tmp/ra.img bs=1M"
  & $adb shell "sha256sum /tmp/ra.img"
  & $adb pull /tmp/ra.img backup\recovery_a_<stamp>.img
  # 主机再算一次，与设备端、与包内 recovery.img 三方比对
  ```
- **判据**：三方 sha256 相等 ⇒ 原厂；不等 ⇒ 记录差异偏移。

### Q-05 `ro.boot.dtbo_idx` 是否仍为 2

- **为什么重要**：`ro.boot.dtbo_idx=2` 是**历史真机读数**（`work\system-profile\REPORT.md:213`），本轮设备不在线未复读；它决定生效的是哪棵 overlay（entry 2 = KHAJE IDP nopmi，182,701 B）→ `bootgrp` §7-2。
- **验证**：`adb shell getprop ro.boot.dtbo_idx` / `ro.boot.dtb_idx`
- **判据**：= 2 ⇒ 与本轮所有 dtbo 分析前提一致；≠ 2 ⇒ 面板/触摸结论需按实际那棵树重查。

### Q-06 真正在跑的是哪颗触摸

- **为什么重要**：dtbo 里同时存在 `touch@0`（SPI，himax+novatek 双 compatible）、`novatek@62`（I2C）、`synaptics_tcm@20`（I2C），三者 status 不同；`bootgrp` §4.4 明确说"这条别猜"。
- **验证**：`adb shell su -c "dmesg | grep -iE 'hxchipset|nt36|synaptics|novatek'"`
- **判据**：出现 `hxchipset` ⇒ himax 线活（BOE 屏 TDDI `touch@0`，SPI 10 MHz，IRQ GPIO80/RST GPIO86）。

### Q-07 `splash` 分区是否真全零

- **为什么重要**：`splash` 在"可能被一次 Erase-All 清零"的名单里，但本机**能显示 logo**。要确认 logo 到底来自 `splash` 还是 XBL 的显示线程（`EnableDisplayThread=1`）→ `small` §7-4。
- **验证**：
  ```powershell
  & $adb shell su -c 'dd if=/dev/block/by-name/splash bs=4096 count=8 2>/dev/null | od -A x -t x1z'
  ```
- **判据**：前 32 KiB 有内容 ⇒ 未被清；全零而有 logo ⇒ logo 来自 XBL（`SimpleFbDxe`/`DisplayDxe`）。

### Q-08 TEE / hyp 的真机状态复核（6 条命令）

- **为什么重要**：`tee` §6 列的 6 条能把整份报告从"强证据"推到"实测"。
- **验证**：
  ```powershell
  & $adb shell su -c "dmesg | grep -iE 'QSEECOM|qsee_version|qseecom_init'"          # ① 期望 qsee_version = 0x1402000
  & $adb shell su -c "dmesg | grep -iE 'kvm|HYP mode'"                                # ② 期望 HYP mode not available
  & $adb shell su -c "cat /proc/cmdline | tr ' ' '\n' | grep -i kvm"                   # ②' 期望 kvm-arm.mode=protected
  & $adb shell su -c "dmesg | grep -i hyp_region"                                     # ③ 期望 6 MiB nomap non-reusable
  & $adb shell su -c "service list | grep -i keymint; ps -A | grep -i keymint"        # ④ 期望 IKeyMintDevice/default
  & $adb shell su -c "for p in cmnlib_a cmnlib64_a; do echo -n \"\$p \"; dd if=/dev/block/by-name/\$p bs=4096 count=128 2>/dev/null | md5sum; done"   # ⑤ 期望 59071590099d21dd439896592338bf95
  & $adb shell su -c "getprop ro.boot.verifiedbootstate; getprop ro.boot.vbmeta.device_state; getprop ro.boot.flash.locked"  # ⑥ 期望 orange / unlocked / 0
  ```
- **判据**：②若出现 `kvm [1]: HYP mode available` ⇒ `tee` §3 需改写（hyp 未加载）。

### Q-09 900E 为什么走 memory-dump 而不是 EDL（判据表坐实）

- **为什么重要**：这是把"900E 由 panic 引起"从【实测 5/5 相关性】升级为【因果+机制】的唯一缺口，成本一次 `--regions` → `900e` §2.4/§8-1。
- **验证**：
  ```powershell
  python E:\rom\work\tools\auto_900e.py --regions MD_RST_STAT.BIN,MD_PMIC_PON.BIN,MD_PMON_HIS.BIN,MD_SMEMINFO.BIN,MD_SMEM_VER.BIN
  ```
- **判据**：panic 引起 ⇒ `MD_RST_STAT`（`0x45e970d4`/4 B）给"warm reset + WDT/panic 标志"；按键进 EDL ⇒ `MD_PMIC_PON`（`0x45e97000`/8 B）显示按键源，且那次根本不会出现 900E。两边读数不同 = 判据表坐实。

### Q-10 内核态 oops 的符号化栈（10-18 那次 `synchronous external abort` 目前只有一行字）

- **为什么重要**：`[33.053541][T1000] Internal error: synchronous external abort: ffffffff96000210 [#1] PREEMPT SMP` 是唯一抓到过的崩溃原文，指向"读 IO 内存被总线中止"，但没有符号 → `900e` §8-2。
- **验证**：`python auto_900e.py --regions md_KELF_HDR.BIN,md_KCNTXT.BIN,md_KSPERCPU0.BIN,…,md_KSPERCPU7.BIN`
- **判据**：用 `md_KELF_HDR`（`0x4a348000`/28 KiB）里的内核 ELF 把 `md_KCNTXT`（128 KiB）里的 PC 翻成函数名。

### Q-11 `peek`/`poke` 是"这个 programmer 没编进去"还是"表在别处"

- **为什么重要**：只影响"9008 读内存"的可行性判断（当前结论已按"不可用"给出）→ `9008` §6-1。
- **验证**：真机上发一次 `<poke address64="0x40000000" size_in_bytes="4">`（**先备份、先确认目标地址无害**）。
- **判据**：回 `Unsupported command` ⇒ programmer 没编；回 `Poke is disabled on secure boot devices` ⇒ 有代码但被 secure boot 拦。

### Q-12 出厂 GPT 的 LUN4 实际容量（GPT 说 1.48 GB / provision 说 4 GB）

- **为什么重要**：影响备份 GPT 落点判断（→ `9008` §6-4）。
- **验证**：`fh_loader.exe --port=\\.\COM4 --memoryname=ufs --getstorageinfo=1`
- **判据**：`UFS LU Total Blocks` × `bLogicalBlockSize` = 真值；与 `gpt_main4.bin` 的 `AlternateLBA` 对比。可用 `NUM_DISK_SECTORS-5` 绕开。

### Q-13 VIP（签名摘要表）是否被强制

- **为什么重要**：影响未来 `program` 是否必须带签名摘要表（→ `9008` §6-3）。
- **已知反面证据**：本机 `secure: yes` 下用 `0 - no validation` 刷全盘 + 单写 persist 都成功 ⇒ 普通 `program` 路径**不需要**签名摘要表。
- **验证**：`configure AlwaysValidate=1` 后跑一次小 `program`（挑一个空分区，如 `rawdump` 尾部）。
- **判据**：NAK 报 `Authentication of signed hash failed` ⇒ 强制；成功 ⇒ 不强制。

### Q-14 `uefivarstore` 的 `PTBL` 头那 0x38 字节到底是什么

- **为什么重要**：这是"能不能安全追加一条 UEFI 变量"的**唯一真正卡点**（不是权限、不是签名、不是 critical 保护）→ `small` §5.2、`9008` §6-5。
- **验证**（三步，前两步纯离线）：
  1. 只读导出 512 KiB：`python make_xml.py --read --lun 4 --start 362212 --sectors 128 --file uefivarstore.bin`（或 `fh_loader --sendxml=read_uefivar.xml`）
  2. 离线定结构：找 `PTBL` 头（`0x00..0x37`）、`VAR2` 记录链、CRC 字段；用前轮的 `work\woa\bds-chainload\var01.py`/`var02.py` 对照
  3. 在自己的副本上改 → `getsha256digest`/`read` 双重确认 → 才写
- **判据**：能解析出 14 个已知变量（`ConIn`/`ConOut`/`ErrOut`/`SetupMode`/`SecureBoot`/`SignatureSupport`/`VolatileTables`/`VarTableInit`/`RTCInfo`/`RunCycles`/`MemoryOverwriteRequestControl`/`HwErrRec*`/`UefiSecAppLoadAddr`/`UefiSecAppVersion`）⇒ 结构对了。
- **红线**：**没有第 1 步就不要有第 3 步。**

### Q-15 `misc+0x8000` 那 15 B 到底是什么

- **为什么重要**：三条记录（`02 B0 0A 74 56` / `01 0C 11 B5 6A` / `01 "roms"`）落在 32 KiB 边界上，最可能是 ABL 自己的 **FFBM / virtual-A/B 消息暂存**，但未证（→ `small` §3.1/§7-1）。
- **验证**：先备份 1 MiB 全量 → 擦掉那 15 B → 观察：能否开机、能否正常 OTA、能否进 fastbootd、`snapshot-update-status` 是否异常。
- **风险**：🟡（可字节还原）。**除非要修某个具体症状，否则不建议做。**

### Q-16 `-bootloader` 那 11 B 残尾的来历

- **为什么重要**：补回前 8 字节正好是 `bootonce-bootloader`（19 字符，`misc[19]=0` 严丝合缝）；但 ABL 里**没有 `bootonce` 字串** ⇒ ABL 认不出来。要确认它是"出厂如此"还是"某次操作留下的" → `small` §7-2。
- **验证**：9008 全量回刷 544 之后读 `misc` 前 4 KiB。
- **判据**：同样带这 11 B ⇒ 出厂如此；变零 ⇒ 是某次操作留下的。

### Q-17 900E 窗口的长度（决定能不能 `--table-only` 再回来抓）

- **为什么重要**：`auto.log` 只记到"端口在 +0.012 s 被抢到"，**没有窗口关闭时刻的统计**；若要稳定多轮取证，需要知道窗口多长 → `900e` §8-5。
- **验证**：制造一次可控 900E（见 Q-30），然后**不握手**，每 100 ms 用 `Get-PnpDevice -PresentOnly` 记录直到端口消失；重复 3 次。
- **判据**：窗口 T 秒；若 T > 5 s，可以实现"先只取表、再决定抓哪些区域"。

### Q-18 哪些 `*_b` 逻辑分区的 extents 真的是 0（复核 super 元数据）

- **为什么重要**：`ofrec` §0.1/§3.2 说"7 个 `*_b` extents = 0"，但 `work\img-super\REPORT.md` 尚未生成（G1），这条需要官方报告确认。
- **验证**：设备侧 `adb shell su -c "lpdump"`；或离线解析 `super_empty.img` + `super_1..8.img`。
- **判据**：所有 `*_b` 的 `num_extents=0`；LP magic 在 `0x3000`（不是 `0x2000`）。

---

## 2. 单变量实验（🟡/🔴，全部有回滚路径）

### Q-19 ABL 是否接受**外来 ramdisk**进 recovery 分区（recovery 线的生死）

- **为什么重要**：这是 `C-11`（形态没试过）的直接检验，也是全部 recovery 方案里**唯一"最坏情况只是丢掉 recovery 功能"**的选项 → `dual` §5-B1、FLASH-PLAN §3.4。
- **实验设计**（两段，先零风险）：
  ```powershell
  # 段 1（零影响）：b 槽当试验田
  & $fb flash recovery_b $bk\recovery_of_ramdskonly.img
  & $fb reboot-recovery                    # 当前槽是 a ⇒ 按 C-10 预期仍是原厂 recovery
  # 段 2（真验证）：写 a 槽
  & $fb flash recovery_a $bk\recovery_of_ramdskonly.img
  & $fb reboot-recovery
  ```
  镜像制备（离线，不碰设备）：从 `of\v3\vendor_boot_of_tb331fc_v3_split.img` 里切出 OF 那条 lz4 流（`s3_streams.py`），用原厂 `recovery.img` 的头当模板只改 `ramdisk_size`（`kernel_size` 保持 0），`header(4096) ‖ OF_lz4_stream ‖ 零填充` 到 ≤ 100,663,296 B。
  三条离线自检必须先过：`hdr=4` / `kern=0` / `rdsk=OF长度` / `magic=="ANDROID!"` / cpio 里有 `/init` 与 `/system/bin/recovery`。
- **判据**：OF 界面出现 = 成功；仍是原厂 recovery（`adb devices` 显示 `recovery` 但 `adb shell` 崩 = SELinux context 报错）⇒ **C-10 的"当前槽"结论成立**（这正是零风险证伪实验的正结果）；黑屏但 USB 有设备 ⇒ 内核起来了、OF 的 minui 没接管 DRM（`ofrec` §4.4 黑屏三种含义）。
- **回滚**：`restore_recovery.ps1 -Target a`（挑源顺序：设备 dump > `recovery_stock_ZUI17.img` > `recovery_stock_ZUI16.img`）。

### Q-20 BCB 通道本身是否活的（**分水岭**，且零刷机）

- **为什么重要**：通了才值得做 Q-19；不通就把结论改成"本机 recovery 通道整体不可用"，转 b 槽或 boot 里的引导内核 → `dual` §S3。
- **验证**（三选一，推荐 3-a，因为它完全不依赖 Android 是否活着）：
  ```powershell
  & $fb reboot-recovery        # 3-a：ABL 自己写 BCB 再重启（最干净）
  & $adb reboot recovery       # 3-b：Android init 写 BCB
  ```
- **判据**：出现 recovery 界面（原厂"无命令/三角感叹号"或直接进菜单），或至少画面/进入速度与正常启动明显不同；另一条硬证据是 `adb shell getprop sys.boot_completed` 不会变成 1。
- **失败预案**：若全黑/反复重启/回 fastboot ⇒ BCB 可能残留：
  ```powershell
  & $fb flash misc $bk\misc_full.bin    # 字节还原（1 MiB，sha256 45E7A829…）
  & $fb reboot
  ```
  **绝对不要** `fastboot erase misc`（一次抹 1 MiB，会连带毁掉 `misc+0x8000` 的厂商状态）。

### Q-21 b 槽四件到底被 ABL 的哪条判据拒了（20:10 那次 22 s 回 fastboot）

- **为什么重要**：OF 与 mainline Linux 两条线都压在 b 槽上，这条不闭合就都悬着 → `bootgrp` §7-5、`dual` §2.2/§10-5。
- **已知**：约 22 s 自己退回 fastboot、**无 900E** ⇒ 与"ABL 侧失败（镜像被拒/解压失败/boot-error UI 超时 → 复位进 fastboot）"一致，而不是内核 panic（panic → 900E，形态是 USB 整体消失再以 `05C6:900E` 出现）。已排除第 4 条（`--set-active=b` 会把 tries 置满 7）。
- **实验设计**（逐步隔离，每步一个变量）：
  1. 只改 `boot_b`（保留原厂 `vendor_boot_b`/`init_boot_b`/`dtbo_b`）→ `--set-active=b` → 看是否仍 22 s 回 fastboot
  2. 若 1 通过：加 `vendor_boot_b`；再通过：加 `init_boot_b`；再：加 `dtbo_b`
  3. 每步都读 `fastboot getvar all` 存档
- **判据**：哪一步开始失败，就是那一个分区/那一对分区的问题。三类候选：① `boot_b` 内核不是 ABL 能吃下的形态（v4 头/非 gzip/`kaddr` 异常）；② AVB 关系触发"boot error"分支（解锁态**理论**不拦，未证）；③ `dtbo_b` 与内核 DT 不匹配。
- **额外线索**：ABL 有 `Not the single appended DTB` 返回 `0xE` 的硬门（Q-22），若 b 槽 `boot_b` 里带了多棵 appended DTB 就会命中它。

### Q-22 payload 的 appended DTB 是否"恰好一棵"

- **为什么重要**：`0x7fa4 → 0xa520` 是**唯一被打印串明确点名的硬门**（`Not the single appended DTB`，返回 `0x800000000000000E`）→ `abl` §6.2-1、§6.3-a。
- **验证**：payload 的 appended DTB 数改成 **1 / 0 / 2** 各试一次（同一份 payload，只改 DTB 段数量）。
- **判据**：出现 `Not the single appended DTB` ⇒ 命中；另一支是 `Dtb offset goes beyond the image size`（`0x9fae6`）。
- **离线辅助**：`ofkern` §3.3 给了自检命令，期望 `dtb_region=1290690 fdt_magic=0xd00dfeed fdt_totalsize=279505 single=True`。

### Q-23 payload 是否走了 32 位误判分支（**最隐蔽、零日志**）

- **为什么重要**：`0xa270` 拿解压后镜像 `+0x38` 的 4 字节与常量 `0x644d5241` 比较，该常量的内存字节序是 **`41 52 4D 64`（ASCII `"ARMd"`，不是 `"ARM64"`）**。不匹配时静默置 `BootInfo+0xc0 = 1` 后**放行**，按 32 位 ABI 跳（`r0=0,r1=0,r2=Dtb`）→ `abl` §6.3-b。
- **验证**：**改 4 个字节**，把 payload 头 `+0x38` 改成 `41 52 4D 64`（或反过来）。
- **判据**：行为变化即命中。64 位 payload 遇到 32 位 ABI 会立刻异常，**症状与"没跳"极像，且完全没有日志**。

### Q-24 卡在 ABL 还是卡在 SEC（一刀切开 L1~L5 与 L6~L9）

- **为什么重要**：只有走到 `0x8440` 才会打 `Shutting Down UEFI Boot Services: %lu ms`；有这行 ⇒ L1~L5 全排除，问题在 L6~L9 → `abl` §6.3-c。
- **验证**：拿 ABL 日志 —— **UART**（`logfs` 本机为空，C-39 已排除）。
- **判据**：有/无该行。**也可用 BDS 的"按任意键关机"当免费探针**：黑屏后按任意键会关机 ⇒ BDS 已把 ABL 拉起来且 ABL 返回了（问题在 ABL→我们的 SEC）；按键毫无反应 ⇒ 根本没走到 BDS 返回（问题在 SEC 早期或更前）→ `xbl` §6.4-3。

### Q-25 Mu UEFI 到底死在哪一段（**当前最大信息缺口**）

- **为什么重要**：现在"全黑"把三个阶段（ABL 没跳 / shim 跳了但拷挂 / SEC 挂了）混成一个观测。`secmem` §3 明确指出：**这比任何地址猜测都值钱**。
- **验证**（`BootShim.S` 加 6 条指令，风险极低）：
  1. 在 `_Start` **第一条指令前**就往 `0x5C000000` 写一个哨兵色（`movz/movk` 三条，**不依赖栈、不依赖缓存刷新**）
  2. 在 `br x5` 之前再换一种颜色
  3. 三色 = 三段定位
- **判据**：看到色 A 无色 B ⇒ shim 起来了但 `br x5` 之前挂；看到 B 无后续 ⇒ SEC 挂了；两色都没有 ⇒ ABL 根本没跳。
- **纪律**：**在把"哪一段死了"变成两三个像素之前，不要再改地址**（地址已被 `secmem` §2 排除）。

### Q-26 ABL 交接过来的 MMU/缓存状态是什么

- **为什么重要**：SEC 第一件事是 `SecCleanInvalidateDataCacheAll` + `msr SPSel,#1`，然后 `stp` 写 `0x5FF9xxxx`。若 ABL 交过来的 `TTBR0`/`TCR`/`MAIR` 里那段不是 normal-cacheable identity，写栈就 abort；此时 VBAR 还没设（`Sec/AArch64/ModuleEntryPoint.S:47` 才设向量），abort 变成**静默死循环/复位** → `secmem` §3-2。
- **验证**：
  - 静态：反汇编 ABL `0x34810`（它接收 entry 作为参数）与 `BootLinux` 收尾，看是否 `SCTLR_EL1.M` 保持 1、`TTBR0` 是否整套 identity
  - 动态：在 shim 里读 `SCTLR_EL1`/`TTBR0_EL1`，把值写进 framebuffer 像素（或 SMEM）

### Q-27 `kernel_size` 是否等于真实 gzip 流长度

- **为什么重要**：ABL 的 `DecompressImage` 只解 `header.kernel_size` 字节；若 `build_uefi.py` 写小了，zlib 半途失败 → ABL 打印错误、**根本不跳**（同样全黑）→ `secmem` §3-3。
- **验证**（纯离线）：解包 `Mu-tb331fc.img`，取 boot header `+0x08`，与 `0x800..0x800+size` 的 gzip 流实际长度比。
- **判据**：两者相等。

### Q-28 `DXE Heap` 落在 `0x5D000000` 会不会咬人

- **为什么重要**：原厂 cfg 里 `DXE Heap` 是 `0x53F00000 + 0x2800000`；我们（以及 TB128FU）用 `0x5D000000`，而**原厂 tapas 的 `0x5D000000` 是 `LAST LOG`（Reserved，跨重启崩溃日志）**、本仓 tapas 挪到了 `0x63900000`。它不会让 SEC 死，但**一定会在 DXE 起来之后毁掉 LAST LOG / 可能与 ABOOT FV 重叠**，恰好让"静默挂死"永远查不出来 → `secmem` §4.2/§5。
- **验证**：改成 `0x63900000 + 0x2800000`（与 tapas 同思路），同时把 `MemoryMapLib.c` 的 `{"DRAM 0x63900000", …}` 挪到 `0x66100000 + 0x17200000`；冷启动（拔电）vs 热重启对比行为。
- **判据**：`dxe heap` 搬家后若挂死现象**不变**，再次印证 §2 的证伪；若**变了**，说明还有第二层原因。
- **⚠️ 必须在改动前确认** `ArmMmuBaseLib` 在 SEC 阶段建的 identity map 覆盖范围（否则 `0x63900000` 可能没被映射，第一次 `stp` 就 abort —— **症状与现在的挂死一模一样，会让实验假阳性**）。

### Q-29 搬运 UEFI 栈到 `0x7C000000`（可选 A/B 实验，非推荐）

- **为什么重要**：假设已被证伪（C-33），所以这不是修复，而是**一次 A/B**：挂死现象不变 ⇒ 再次印证；变了 ⇒ 还有没看到的第二层原因 → `secmem` §4.1。
- **需要改的 3 处（必须同时改，否则发布的内存地图会说谎）**：
  | 文件（WSL: `/root/woa/uefi-tb128fu/`） | 行 | 现值 → 实验值 |
  |---|---|---|
  | `Platforms/Lenovo/tb331fcPkg/tb331fc.dsc` | 47 | `PcdCPUCoresStackBase\|0x5FF90000` → `\|0x7C000000` |
  | 同上 | 48 | `PcdCPUCorePrimaryStackSize\|0x40000` → 不变 |
  | `…/MemoryMapLib/MemoryMapLib.c` | 54 | `{"UEFI Stack", 0x5FF90000, 0x00040000, …}` → `0x7C000000` |
- **为什么 0x7C000000**：设备 `/proc/iomem` 实测 `63900000-7cbfffff : System RAM`，`0x7C000000+0x40000 = 0x7C040000 < 0x7CC00000`，离所有固件/FW/保留区都远。
- **风险**：① 页表覆盖范围（见 Q-28 的警告）；② 那片 DRAM 在 UEFI 阶段可能还没被 XBL 训练/使能（内核能看到 ≠ UEFI 早期能碰）；③ 若只改 `.dsc` 不改 `MemoryMapLib.c`，DXE 会把栈踩掉（**这次是真的踩内存**）。
- **回滚**：两个文件在工作树里**已经是 modified 状态**，`git checkout` 会连带丢掉未提交的改动 ⇒ **不要用 git 回滚**，用 `.bak-<日期>` 副本。

### Q-30 造一份"已知死因"的 900E 对照样本（校准分析器用）

- **为什么重要**：只在需求是①校准分析器 ②验证 Q-09 那 5 个复位原因区域 ③做 `HELLO_RSP` 各 mode 的响应矩阵时才值得做。**不需要造的场合**：再确认 A17 为什么起不来（已闭合）、想"用 900E 修好设备"（900E 是取证现场，不是维修通道）→ `900e` §5.4。
- **推荐方案 B（最省，20 s 就知道预测对不对）**：用 avbtool 重建一个 **root 故意写错** 的 `vbmeta_system`，只刷这 4 KB。
- **预测必须写死**：刷完重启 **≤5 s** 看到 `05C6:900E`，且转储里出现 `device-mapper: verity: …: data block 0 is corrupted` + `unable to read superblock` + `exitcode=0x00007f00`。
- **反证**：若正常开机到桌面（`ro.boot.veritymode` 仍是 `eio` 但没崩）⇒ 解锁态 ABL 忽略/绕过坏描述符 ⇒ B 路线作废，只能走方案 A（重刷 `product_a.img`，需先 `delete/create`）。
- **回滚**：`fastboot flash vbmeta_system_a` 原厂 4 KB + `--set-active=a` + `reboot`。

---

## 3. 写分区（🔴 有回滚路径）

### Q-31 `misc` 是否在 fastboot 白名单里（零状态变化地测）

- **为什么重要**：`C-15` 已证明 `misc` 只在**锁态表**里、本机已解锁 ⇒ **会被允许**；但这条还没有真机回执 → `dual` §S2。
- **验证**：`fastboot flash misc $bk\misc_full.bin`（写进去的内容与设备现有字节**完全相同**）→ 既不改变任何状态，又回答两个问题：① `misc` 是否受保护；② 回滚通道是否可用。
- **判据**：`Sending 'misc' (1024 KB) OKAY` / `Writing 'misc' OKAY` / `Finished` ⇒ 可写；报 `Flashing is not allowed for Critical Partitions` ⇒ 受保护（那就只能走 `adb reboot recovery` 由 Android init 写）。

### Q-32 B 槽三件到底是谁写进去的（全量回刷中断 vs 事后单刷）

- **为什么重要**：数据上两种解释等价，区别只在"谁写的"，但影响"b 槽能否信任" → `zuidiff` §8-1。
- **验证**：按 `zuidiff` §6.1 全量刷 544，刷完复读 `recovery_b` head64M。
- **判据**：**必须变成 `264aec55…`**（= ZUI16 `recovery.img` 零填充）。若仍是 `e5353d2a…` ⇒ b 槽没写进去，存在"部分分区不写"的结构性问题。
- **配套验收清单**（`zuidiff` §6.4）：`vendor_boot_b` head64M 必须变成 `27832b98…`；`init_boot_b` sha 必须变成 `2d090fb5…`；`vbmeta_system_a` 必须回到原厂 `1e0688b4…`；`persist` 非零字节 > 0。

### Q-33 A17 单变量收尾：真的只需要修 product 的 hashtree 吗

- **为什么重要**：`v4` §5.1 已验证"修 product hashtree 后可复现启动"，但**重启复现性**、A17 下声音/录音/拍照/自动旋转、`imsdaemon` 是否仍每 ~10 s SIGSEGV、GCam/Via 预装都还是"待验"。
- **验证**：按配方重刷三件（`product_FIX.img` 2,999,996,416 B + `vbmeta_system_fix.img` 4,096 B + 保持 `vbmeta_a` 原厂 544 不动）→ **连续重启 ≥2 次**都要起桌面。
- **判据**：`release=17`、`sdk=37`、`sys.boot_completed=1`、`dumpsys sensorservice` = 29/29、`AudioOut_D underruns=0`、`persist` 挂载正常、`ro.boot.veritymode=eio`、`verifiedbootstate=orange`。
- **注意**：若失败，先按 `img-900e\analyze.py` 分类（`init_death_after_mount_failure` / `init_death_mount_silent` / `init_death_before_any_dm` / `kernel_fault` / `hang_watchdog`），别急着换镜像。

### Q-34 当前 `boot_a`/`boot_b` 到底是哪种补丁版

- **为什么重要**：`C-30`/`C-36` 已确认它们**不是任何一版原厂**（两者哈希相同 `667e1723…`），但**是哪一种补丁版**（permissive？ramoops？KSU/APatch？）未知 → `zuidiff` §8-5。
- **验证**：把现机 `boot` 读回来（`adb root` + `dd`），与 `boot-backup-20261024\boot_a.img`、`work\linuximg\vendor_boot_zui16_ramoops.img` 系列、几份实验镜像逐个比；解包看 cmdline 与 ramdisk。
- **判据**：能对上某一份即定；对不上就说明是更晚的一次改写（参考 `03_fp.tsv` 采集时刻）。

### Q-35 `uefivarstore` 写坏的后果（可变可不可变）

- **为什么重要**：`OPTION_VALID`：`VarTableInit` 失败 → 变量退化 volatile，而 cfg 里 `AllowNonPersistentVarsInRetail = 0x1` 会允许它继续跑 ⇒ **多半能开机，但变量全丢**。这条**未验证** → `small` §5.2。
- **验证**（仅在 Q-14 完成、且有自己的副本之后）：写一个只加一条无害变量（例如把 `RTCInfo` 原样重写）的版本。
- **判据**：开机后 `ConIn`/`ConOut` 等 13 个原变量是否仍在（用 Q-14 的读法导出比对）。

---

## 4. 需要外部条件 / 高风险（⚫ 或需要另一台设备）

### Q-36 写坏 `xbl` 之后 PBL 是否必然给出 9008

- **为什么重要**：这是"可救"的唯一前提（`xbl_a/b` 由 PBL 用熔丝根证书验签；失败则 PBL 走自己的 Sahara → 9008 还在）→ `9008` §4.3/§6-6。
- **验证**：**不建议在本机验证**（风险高）。可查同平台（bengal/khaje、TB128FU/tapas）公开案例，或等有第二台机器时做。
- **退一步的证据**：历史 ZUI15 abl 降级（写入成功、读回一致、设备仍能进 fastboot）说明"firehose 不验内容"；而"PBL 载不动 → 9008"这一步目前是【推断】不是【实测】。

### Q-37 `erase` 整 LUN 的触发条件

- **为什么重要**：影响"能不能一键清 `super` 尾部 5.21 GiB（官方包不写不清的部分）" → `9008` §6-2。
- **验证**：`getstorageinfo` 后，挑一个**空分区**（`rawdump`/`logdump`）小范围试 `erase`。
- **判据**：`Erasing the whole disk/LUN %d` 是否出现。

### Q-38 `0x8900()` 的真实语义（它门控 `reboot-recovery`/`reboot-fastboot`/`snapshot-update`）

- **为什么重要**：这决定那三条命令在**锁态**机器上是否存在 → `dual` §10-6。
- **已知**：`0x8900` → `0xfd90` → 用 `"super"` 查分区 ⇒ 至少确定"有动态分区"这个条件；但是否还叠加了"已解锁/允许 OEM 动作"未证（从它门控的三个命令看，可能性压倒性）。
- **验证**：反汇编 `0xfd90` 全文；或实测：锁态设备上 `fastboot reboot-recovery` 是否被拒（本机已解锁，改不了这条）。

### Q-39 对着**另一台同型号未解锁机**做逐分区 sha 对比（唯一干净的黄金参照）

- **为什么重要**：这是区分"出厂就空"与"被一次 Erase-All 清过"的**唯一可靠方法**（`small` §6.3/§6.4-1）。当前 `keystore`/`splash`/`lenovolock`/`lenovocust`(300 MB)/`cdt` 的状态**本轮无法复核**。
- **验证**：按 `work\device-profile\03_fp.tsv` 的方法（分区大小 + `FULL`/`HEAD64M` + 零填充后复算 sha256）在干净机上采一份，与本机逐项比。
- **判据**：本机空、干净机非空 ⇒ 被清过；两台都空 ⇒ 出厂如此。

### Q-40 ABL 跳转前到底有没有 `ExitBootServices`（BootShim 的唯一真风险）

- **为什么重要**：若 ABL 跳转后仍会用到 Runtime Services（`VariableDxe`/`ResetRuntimeDxe`/`CapsuleRuntimeDxe` 的代码或数据可能落在 `0x5FC00000–0x5FE20400`），BootShim 一覆盖就会在下一次 `SetVariable/ResetSystem` 时炸。**这是 C-34 里唯一"只有上机/抓内存才能定"的问题** → `xbl` §6.3 风险 A。
- **验证**（三条，从便宜到贵）：
  - **V3（静态）**：在 `LinuxLoader.efi` 里搜 `ExitBootServices`/`gBS`/`gRT` 的引用，看跳 kernel 前是否还有 runtime 调用
  - **V1（只读）**：9008 只读 dump `0x5FC00000`，与 `xbl.img` 的 ph16 逐字节比对 —— 若仍等于 ph16 ⇒ ABL 没动过这段；若已是别的内容 ⇒ 已被复用
  - **V2（A/B）**：把 FD 基址挪到 `0x5D000000`（原厂 cfg 里这段是**空白**）或 `0x5E000000`，重编重刷一次 —— 若换基址就出图 ⇒ 冲突点在 `0x5FC00000` 窗口
- **倾向判断（明确标为判断）**：`xbl` §6.3 认为 **V1 大概率显示"仍等于 ph16"**，所以"覆盖 XBL UEFI"多半不是三版全黑的根因；真要找，仍应回到 SEC 早期（Q-25/Q-26）。

### Q-41 BDS 对"非可移除 FAT 卷上的 `BOOTAA64.EFI`"会不会自动启动

- **为什么重要**：这是"被 BDS 当 `BOOTAA64.EFI` 加载"这条形态（`xbl` §6.4-1）能否成立的**唯一未定点**。BDS 确实有活代码（`0xd21c` 打开该文件，`0xd4a8–0xd4c4` 校验 `Machine==0xAA64` + `Subsystem==0x0A`）会枚举 SimpleFileSystem 卷自动建引导项；现成 FAT16 载体是 `modem_a`（180 MB / 141 MB 空闲）→ `small` §5.3-2。
- **未知**：默认流程会不会把"非可移除卷"排在 `DefaultBDSBootApp` **之前**。
- **验证**：先解决"怎么进菜单"已被否定（C-05），所以只能反汇编 `0x10818` 那条"标准引导项流程"分支，看 `BootOrder`/`Boot####` 的枚举是否包含非可移除卷，以及它与 `LaunchAppFromGuidedFv` 的先后。

### Q-42 `QcomChargerApp` 的可达性（能否人为进充电界面）

- **为什么重要**：`xbl` §8-5 明确列为未证。若能人为进，可作为一个"确认 BDS 走到了哪一步"的额外探针。
- **验证**：反汇编 `0x30D0`（判充电/off-mode-charging 的那个函数），逐条追它的输入来源（PMIC 状态？`ChargerExDxe` 的 protocol？`0x69960()` 那种 bootmode?）；实机侧可用 `fastboot oem enable-charger-screen` / `off-mode-charge` 配合观察。

### Q-43 `SecurityFlag = 0xC4` 各位的运行时含义

- **为什么重要**：`xbl` §8-6 明确列为未证。已知 bit0=0（SecBoot）、bit2=1（CommonMbnLoad）、bit6=1（LoadSecApp）、bit7=1（LoadKeymaster）。但 `VariableServicesFlag=0` 却存在 `VariableDxe`，说明**位语义可能与字面不完全一致**，需要 QCOM 文档才能定。
- **验证**：反汇编 SEC 里读 `SecurityFlag` 的所有点（在 xbl 的 SEC TE 里搜该字面量附近），看每个 bit 各自门控什么。

---

## 5. 报告缺口（进行中，出来后需回填 `PANORAMA.md`）

| # | 缺什么 | 现状 | 回填到哪 |
|---|---|---|---|
| **G1** | `work\img-super\REPORT.md` | 目录有 17 个脚本（`avb2.py`/`avb_parse.py`/`chain_check.py`/`probe_ext4.py`/`verify_verity.py`/`enum.sh`/`pass2..11.sh`）+ `raw\`（`00_features.txt`、`10_vendor_vintf.txt`、`11_vendor_hw.txt`、`12_vendor_buildprop.txt`、`13_vendor_tree.txt` 162 KB），**无 REPORT.md** | `PANORAMA.md` §4.5（super 与逻辑分区）、§2.2 的 super 长度口径；Q-18 |
| **G2** | `work\img-firmware\REPORT.md` | 目录有 `bootextract.py`/`bootparse.py`/`fatls.py`/`fdtparse.py`/`gpt_dump.py`(+`gpt_lun4.txt` 10.8 KB)/`cpiols.py`/`ext4info.py`/`ls_modem.txt`(18.9 KB)/`ls_bt.txt`/`ls_dsp.txt` 等，**无 REPORT.md** | `PANORAMA.md` 应新增"固件链（modem/dsp/adsp/bt）"一节 |
| **G3** | `work\research-gh-20261124\REPORT.md` | 只有 `MANIFEST-downloads.tsv`（9,143 B）+ 抓取树（`issues\` 6 篇、`Mu-Silicium-main\`、`sapphiren\Status.md` 4,509 行、`topaz-woa\`、`OpenABL\README.md`、`UniXNU-xun\README.md`、`UEFI-xun\README.md` 0 字节），**无 REPORT.md** | `PANORAMA.md` §5.3-6（GitHub 横向结论） |
| **G4** | 900E 抓取覆盖面 | 6 份转储里 `race_20261113_113918` 只有表没抢到日志（`no_log`）；`md_KELF_HDR.BIN`/`md_KCNTXT.BIN` 从未抓过 | Q-09/Q-10 |
| **G5** | `abt.elf` 的容器格式（ELF 头 + 证书链，字符串区疑似压缩/加密） | `9008` §6-7：影响静态逆向 ABL 的可行性。注意本仓已有**解包后的** `Z17_9e21fd93_lz_f536d559_PE32_at_0xb4.bin`（970,752 B）可用，但**解包器本身**没沉淀成文档 | `abl` 的复现节；新增一个"从 `abl.img` 到内层 PE"的步骤 |

---

## 6. 一张"先做什么"的顺序表

| 顺序 | 做什么 | 成本 | 门槛 | 能定什么 |
|---|---|---|---|---|
| 1 | **Q-20** `fastboot reboot-recovery` | 1 秒，零刷机 | 设备进 fastboot | recovery 通道是否活（**分水岭**） |
| 2 | **Q-02/Q-03** 两条 `getvar` | 1 秒 | 同上 | recovery 线用哪个槽、塞不塞得下 |
| 3 | **Q-19 段 1** 刷 `recovery_b` | 1 分钟，零影响 | Q-20 通 | C-10「当前槽」结论的零风险证伪 |
| 4 | **Q-25** 三个哨兵色 | 改 6 条指令 + 一次编译 | 编译环境 | WoA 线"哪一段死了"（**最大信息缺口**） |
| 5 | **Q-01** `oem device-info` + `devinfo` 回读 | 只读 | 设备在 Android | 解锁权威在哪一侧 |
| 6 | **Q-23** 改 4 个字节验 32 位分支 | 一次刷 boot | 设备进 fastboot | ABL 是否静默按 32 位跳 |
| 7 | **Q-22** appended DTB 数 1/0/2 | 三次刷 boot | 同上 | 是否命中唯一被点名的硬门 |
| 8 | **Q-08** TEE/hyp 6 条 | 只读 | 设备在 Android | 把 `tee` 从强证据推到实测 |
| 9 | **Q-09/Q-10** 900E 补抓区域 | 一次 900E | 设备能进 900E | 900E 成因机制 + oops 符号化 |
| 10 | **Q-28** DXE Heap 搬到 `0x63900000` | 一句改动 + 一次编译 | 编译环境 | 是不是"第二次启动才挂"类问题的根源；至少修掉一个确定会咬人的错 |

---

*本清单与 [`PANORAMA.md`](PANORAMA.md) §7 的 O/E/W/G 编号对应（O↔§1、E↔§2、W↔§3、G↔§5）。*
