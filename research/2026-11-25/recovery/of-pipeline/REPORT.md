# OF recovery 卡 logo 定位：最小化实验设计与离线产物

生成时间：2026-11-25 12:5x (+08:00)
工作目录：`E:\rom\work\of-pipeline\`
**本次没有刷机**（设备当前卡 logo，需人工按电源）。只产出镜像 + 脚本 + 判读表。
只写过 `E:\rom\work\of-pipeline\`；`work\dual-boot\backup\`、`work\of-slim\`、`work\of\` 只读。

---

## 〇、一句话结论

**我们的打包/压缩方法已被证明与原厂比特级等同**（`lz4 -l -12` 重压原厂 cpio 得到的字节流与原厂 ramdisk **完全一致**，sha256 相同），
所以「OF 卡 logo」不可能是"我们压错了/包错了"这类问题留给猜测——**六个镜像按阶梯刷一遍，就能把原因锁死在三选一**：
① 内核侧根本没解开 initramfs（格式/尺寸/内存），② 解开了但 OF 的 init 死了，③ init 活着但 OF 的 recovery 死在显示初始化。

---

## 一、新增的硬证据（本轮离线得出，之前没人算过）

### 1.1 我们的 lz4 与原厂同一条流水线（比特级）

```
原厂 recovery_a.bin 偏移 4096 起 14,572,954 B 的 ramdisk
   lz4 解压 → cpio 30,172,672 B, sha256 7ed699243dbd598e397a4e483f51f126463ace63ee3bea72650edb3dd64536ab, 472 条目
   用本机 lz4 -l -12 重新压缩 → 14,572,954 B
   与原厂流逐字节比较 → **完全相同**（sha256 4c3fd399da0c08918bf1fdb44fa8e41ccf499e355de67c3ed10b376640e6a55b）
```

含义：原厂就是用 `lz4 -l -12`（legacy frame）打的包，我们的工具链与它等价。
→ **实验 1 的问题从"我们的包对不对"降级成"内容换了还认不认"，这是能一次刷机回答的。**

### 1.2 原厂 recovery 镜像的真实结构（之前没人拆开）

| 项 | 值 |
|---|---|
| 分区容量（`recovery_a.bin` 全量 dump） | 104,857,600 B（100 MiB） |
| 厂商刷机包 `image/recovery.img` | **100,663,296 B（96 MiB）** |
| 头部 | `ANDROID!` + v4，`kernel_size=0`，`ramdisk_size=14,572,954` |
| `os_version` 字段 | **0**（不是我们之前写的 `0x1c0001a3`） |
| `header_size` | 1584，`signature_size`(@1580)=0，`page_size` 字段=0（隐含 4096） |
| cmdline 区（44..1580） | **全零** |
| ramdisk | 4096 起 14,572,954 B，lz4 legacy `02 21 4c 18` |
| **AVB** | 14,577,664 处有 `AVB0` vbmeta（141 B 非零），96 MiB 末尾（100,663,232）有 `AVBf` footer |

推论与本次取舍：原厂镜像是 AVB 签过的，我们的镜像**不带 AVB**。
OF 13 MB 那几次现象是"卡 logo"而不是"10 秒退回 fastboot" ⇒ **ABL 没有因为 AVB 不符而拒绝**，
所以本轮所有镜像继续按"不带 AVB"出（这与 lead 之前刷 OF 的条件一致，不引入新变量）。
> 若某次实验出现"10 秒回 fastboot"，那是尺寸/形态问题，不是 AVB——AVB 不符在解锁机上不拦。

### 1.3 这台内核到底支持什么（从 `boot.img` 内嵌 IKCONFIG 直接读出，6949 行）

```
CONFIG_RD_GZIP=y    CONFIG_RD_LZ4=y    CONFIG_RD_ZSTD=y     （无 XZ/LZMA/BZIP2）
CONFIG_FB is not set                      ← ★ 没有 fbdev，/dev/graphics/fb0 永远不存在
CONFIG_DEVTMPFS is not set                ← ★ 没有 devtmpfs，/dev 必须由 ueventd/mdev 建
CONFIG_PSTORE=y CONFIG_PSTORE_RAM=y CONFIG_PSTORE_CONSOLE=y
CONFIG_USB_CONFIGFS=y CONFIG_USB_CONFIGFS_F_FS=y CONFIG_USB_F_FS=y CONFIG_USB_DWC3_QCOM=y
CONFIG_SECURITY_SELINUX=y
```

并且设备树里**本来就有 ramoops**，cmdline 本来就带串口控制台：

```
[0.000000] OF: reserved mem: 0x00000001bfe00000..0x00000001bfffffff (2048 KiB) ramoops_region
[0.158809] pstore: Registered ramoops as persistent store backend
Kernel command line: ... console=ttyMSM0,115200n8 ... video=vfb:640x400,bpp=32,memsize=3072000 ...
```

**这是本轮最重要的作战条件**：任何一次 recovery 挂死，**下一次启动都能从 `/sys/fs/pstore/console-ramoops-0` 读到上一轮的控制台**，
不需要串口、不需要 adb 在坏的那一台上。脚本第 6 步（`-CollectPstore`）已经把它自动化：
回滚 → 进原厂 recovery → `adb shell cat /sys/fs/pstore/console-ramoops-0` → 落盘 `logs\pstore_*.txt`。
→ 从这一轮开始，"卡 logo"不再是无信息事件，它是**有日志可读的事件**。

### 1.4 OF 内容的静态审计（已经把一些假设排掉）

| 检查 | 结果 |
|---|---|
| OF slim 里 `init` 的 DT_NEEDED 闭包 | 34 个 ELF / 8.24 MiB，**缺 0 个** |
| `system/bin/recovery` 闭包 | 97 个 ELF / 23.35 MiB，**缺 0 个** |
| `system/bin/adbd` 闭包 | 16 个 ELF / 6.65 MiB，**缺 0 个** |
| 所以"缺 `/vendor/lib64` 的库 → linker 起不来" | ❌ 对 slim 不成立（slim 甚至把 `libdrm` 编进了 `libminuitwrp.so`，无需外部 .so） |
| `init` 是否认识 TWRP 内建命令 `install_keyring` | ✅ 认识（`strings system/bin/init` 命中 1 次），rc 不会解析失败 |
| `service recovery` 有没有被声明 | ✅ 有（在 `init.recovery.service.rc`，被 `init.rc` 用 `import` 显式导入，不依赖 `ro.hardware`） |
| slim 删了 `system/bin/logd`，但 `init.recovery.logd.rc` 仍 `start logd` | ⚠️ 非致命，但**OF 没有 logcat** |
| `twrp.flags` 引用的分区名 | ⚠️ `cust` / `logo` 在本机 GPT 里**不存在**（本机叫 `lenovocust` / `splash`）；`modem`/`dsp` 之类的 slotselect 名字是对的 |
| OF 的身份属性 | ⚠️ 仍是 topaz 派生：`ro.build.product=topaz`、`ro.display.series=Redmi Note 12 4G`、`sdk=32`；但 `recovery.fstab` 已按 TB331FC 重写（文件里有 v3 注释、pin 了 `*_a` 逻辑分区） |

---

## 二、实验 1：验证"我们能自己造一个能启动的 recovery ramdisk"

全部镜像**逐字节复制原厂 4096 B 头**，只改 `ramdisk_size`（`os_version` 保持原厂的 0，不再自己编），
ramdisk 之后补零到 4096 页边界。

| # | 镜像 | 内容 | ramdisk_size | vs 14,572,954 | 想证明什么 |
|---|---|---|---|---|---|
| 1a | `exp1a_stock_clone.img` | 原厂 ramdisk **原样字节** | 14,572,954 | ±0 | 控制组：与 `recovery_a.bin[0:14577664]` **逐字节相同**（已断言相等）。它要是不启动，说明刷写路径坏了，后面全部作废 |
| 1b | `exp1b_hello_lz4.img` | 原厂 cpio **+`/hello.txt`**，我们用 `lz4 -l -12` 重压 | 14,573,096 | **+142** | 我们能不能改内容还照样启动 |
| 1c | `exp1c_zstd_stock.img` | 原厂 cpio 原样，`zstd -19` | 8,129,498 | −6,443,456 | **zstd 这条 initramfs 路径到底通不通** |
| 1d | `exp1d_gzip_stock.img` | 原厂 cpio 原样，`gzip -9` | 12,517,651 | −2,055,303 | gzip 同上（1c 的保险丝） |

`hello.txt` 的插法：**不重新序列化已有条目**，只在 `TRAILER!!!` 之前把新记录拼进去，
所以 472 个原条目的字节、inode、mtime、权限全部原封不动（已在脚本里断言）。

### 判读（这一列就是本轮的核心逻辑）

| 1a | 1b | 1c | 结论 |
|---|---|---|---|
| 进原厂 recovery | 进原厂 recovery | 进 | **打包、cpio 手术、lz4、zstd、gzip 全部无辜** → 原因 100% 在 OF 内容 → 直接做实验 2/3 |
| 进 | 进 | **卡 logo** | zstd 在**这条启动路径**上不通（尽管内核配置说有）。那 OF 的 zstd 版失败就被解释了；OF 的 gzip 版若也卡，则说明不只 zstd → 再刷 1d |
| 进 | **卡 logo** | — | 我们改内容的方式有问题（cpio 手术/头部字段），与 OF 无关。差别只剩 142 字节，重点查 ABL 的尺寸阈值到底是不是"等于原厂大小" |
| **卡 logo / 回 fastboot** | — | — | 刷写路径本身不成立（分区名、槽位、misc BCB）；先解决这个，别做后面任何实验 |

> 1b 比原厂大 **142 B**。如果它退回 fastboot，那说明 ABL 的上限精确到原厂字节数，
> 这时用 `exp2c`（−280 KB）继续即可，不必再改 1b。

---

## 三、实验 2：把 adb / 日志拿回来（三个镜像）

### 2a `exp2a_mintel.img` —— 我们自己写的最小 init（4.95 MB，lz4）

不使用 Android init、不用 property service，只要三件事：挂 proc/sys/dev、建 `/dev`、起 adbd。

- `/init` = `/sbin/busybox sh` 脚本（**静态** busybox，取自 OF ramdisk 的 `sbin/busybox`，1,498,688 B，`statically linked`）
- 内核没有 devtmpfs，所以 `/dev` 是 tmpfs + `busybox mdev -s`（从 sysfs 反建节点）+ 兜底 `mknod`
- USB：`configfs` 建 `g1`（idVendor 0x18D1 / idProduct 0xD00D）→ `functions/ffs.adb` →
  `mount -t functionfs adb /dev/usb-ffs/adb` → 起 `adbd` → 等 ep0/ep1 → 写 UDC
- `/system/bin/sh` 软链到 busybox（adbd 的 `SHELL_PATH` 是 `/system/bin/sh`，否则 `adb shell` 不可用）
- 每 10 秒往 `/dev/kmsg` 打心跳（→ ttyMSM0 → pstore），这样"它活到第几秒"可回读

**adbd 的动态库闭包（`readelf -d` 逐层追，全部取自原厂 ramdisk，共 16 个文件 / 6.26 MiB 库 + linker）**：

| 文件 | 字节 | 来源 |
|---|---|---|
| `system/bin/adbd` | 2,178,568 | 原厂 |
| `system/bin/linker64` | 1,797,120 | 原厂（interp，非 DT_NEEDED） |
| `system/lib64/libc.so` | 1,052,504 | |
| `system/lib64/libcrypto.so` | 1,302,624 | adbd 直接 NEEDED |
| `system/lib64/libc++.so` | 709,208 | |
| `system/lib64/libbase.so` | 247,032 | |
| `system/lib64/liblog.so` | 66,376 | |
| `system/lib64/libselinux.so` | 105,112 | |
| `system/lib64/libm.so` | 225,048 | |
| `system/lib64/libdl.so` | 13,728 | |
| `system/lib64/libadbd_auth.so` | 255,040 | |
| `system/lib64/libadbd_fs.so` | 32,024 | |
| `system/lib64/ld-android.so` | 9,392 | |
| `system/lib64/libpcre2.so` | 360,464 | （libselinux 拖进来的） |
| `system/lib64/libpackagelistparser.so` | 10,632 | |
| `system/etc/ld.config.txt` | 238 | 原厂（`[recovery]` 命名空间 = `/system/${LIB}`，保证 adbd 能找到 lib64） |

（多一个 `libadb_protos.so` 只在 **OF 自己的 adbd** 上需要，原厂 adbd 不需要。）

**成功判据**：`adb devices` 出现一台非 `fastboot` 状态的设备（banner `recovery`），并且 `adb shell id` 能出结果。
**失败也有信息**：控制台里会留下走到哪一步（`mdev done` / `udc='...'` / `ffs mounted: ep0-present`），
下次启动从 pstore 读即可——所以 2a 无论成败都是"有读数"的实验。

### 2b `exp2b_of_beacon.img` —— 在 OF 内容里塞一个 beacon（14.07 MB，zstd）

只改一件事：把 OF 的 `/init`（原本是软链 → `/system/bin/init`）换成 busybox 脚本，脚本做：

1. 挂 proc/sys/dev + `mdev -s`
2. 往 `/dev/kmsg` 写 `BEACON: initramfs unpacked, our /init ran (pid 1)` + uptime
3. 起一个 20 秒看门狗：如果 OF 到那时还没把 adb 拉起来，就自己按 2a 的方式起 adbd（用 OF 里的 adbd + 库）
4. `exec /system/bin/init` —— **OF 的 init 原封不动地继续跑**

判读只有两种，且互斥：

| 现象 | 结论 |
|---|---|
| 下一次启动在 pstore 里看到 `BEACON:` 行 | initramfs **解开了、用户态跑起来了** ⇒ 卡 logo 死在 OF 的 init/recovery（显示初始化 / 服务 / 分区），**与压缩、尺寸、cpio 全无关** |
| pstore 里**一条 `BEACON:` 都没有** | 内核**没把 initramfs 交到用户态** ⇒ 问题在"内核解包这一层"（格式/尺寸/内存/头部），OF 的内容本身还没开始跑 |

### 2c `exp2c_stock_beacon.img` —— 2b 的对照（14.30 MB，lz4）

**同一个 beacon 脚本**，但装在**原厂内容**上（为了塞进 lz4 预算，去掉本实验用不到的
`system/bin/recovery` 与 `system/bin/toybox`，脚本里已注明）。
它回答的是"2b 没有 beacon 到底怪谁"：2c 有 beacon、2b 没有 ⇒ 差异在 OF 内容，不在我们的重组手法。

> 顺序很重要：**先 2c 再 2b**。2b 用 zstd，2c 用 lz4；若 1c 已经证明 zstd 会卡，
> 那 2b 必须改判（见第五节"若 1c 失败"）。

---

## 四、实验 3 的产出：最可能的三个卡点 + 各自的验证方法

按证据强度排序。**注意：这三条都是"候选"，本轮的静态分析没能、也不该假装能单独定案**——
静态分析已经排掉的假设见 1.4，剩下的分辨只能靠 2b/2c 的 beacon 和 pstore。

### 卡点 A（最强）：显示初始化——本内核没有 fbdev，TWRP/minui 的首选路径必然失败

- 证据：`CONFIG_FB is not set`（`/dev/graphics/fb0` 在内核里根本不存在）；
  `libminuitwrp.so` 里 fbdev 与 DRM 两条路都在（`/dev/graphics/fb0`、`/dev/dri/%s`、`drmModeAddFB2`、`DRM_IOCTL_MODE_CREATE_DUMB`），
  且 `cannot open fb0 (giving up)` 这条串就在库里 —— 也就是说 fb0 打不开时它会走 DRM；
  而 DRM 要 `/dev/dri/card0`，该节点只能由 ueventd 创建（内核无 devtmpfs）。
  原厂是 Android 14 recovery（minui 有成熟 DRM 后端）能画；OF 是 fox-12.1 / sdk32 的 TWRP 分支，DRM 后端是否在这块
  `qcom,mdss_dsi_panel_p255_hx83102j_fhd_video` 屏上 work，**只能上机验**。
- 为什么它解释"静默"：TWRP 在 `gr_init()` 失败时会打印到控制台（本次是 ttyMSM0，屏上看不到）然后卡住/重启，
  **屏幕上永远是 logo，adb 也不会起** —— 与 lead 描述的现象完全吻合。
- 验证方法：刷 2c（对照）→ 刷 2b → `-CollectPstore`。
  有 `BEACON:` 行但屏幕没变、且控制台里出现 `cannot open fb0` / `libminuitwrp` / `gr_init` 字样 ⇒ A 成立。
  若控制台里能看到 `minui` 成功创建了 DRM 帧缓冲，则 A 被否定，看下一条。

### 卡点 B：OF 起来了但没有 adb —— `sys.usb.configfs` / functionfs 这条链没走通

- 证据：OF 的 usb 相关逻辑被拆到 `init.recovery.usb.rc`（`init.rc` 里 `on early-init` 先把 `sys.usb.configfs` 置 **0**，
  真正的 gadget 建立在 `on fs && property:sys.usb.configfs=1` 等条件块里；`idVendor` 用的是 **0x2717**（小米））。
  原厂是"`on init` 就 `setprop sys.usb.configfs 1` + `init.rc` 里直接建 gadget"。
  这条链上任何一环（configfs 未挂、`/config/usb_gadget` 节点属性写失败、`sys.usb.ffs.ready` 没等到）都会导致
  **recovery 界面正常但 adb 不出现**。
- 意义：**"无 adb"不能当作"recovery 没跑"的证据**。这条必须与 A 分开判。
- 验证方法：2a 证明"在这台机器上，configfs+functionfs+adbd 这套手动拉起是可行的"（硬件/内核层面通不通一次说清）；
  2b 的 20 秒看门狗则给出"OF 起不来 adb 时，我们自己能不能补上"。
  若 2a 成功、2b 看门狗也成功但 OF 自己的 adb 不出 ⇒ B 成立，去修 OF 的 usb.rc/configfs 时序。

### 卡点 C：OF 的分区/等待逻辑在这台机器上不成立（不是立刻死，而是"卡住"）

- 证据：`twrp.flags` 里 `/cust`、`/logo` 在本机 GPT **不存在**（本机叫 `lenovocust`、`splash`）；
  `init.recovery.qcom.rc` 的 `on fs` 里有 `wait /dev/block/platform/soc/${ro.boot.bootdevice}`、
  `chmod/chown` 一堆 `/dev` 节点、`install_keyring`；
  `on property:twrp.modules.loaded=true` 里要 `mount vfat .../by-name/modem${ro.boot.slot_suffix}` 并
  `wait /sys/kernel/boot_adsp/boot`、`wait /sys/class/power_supply/battery`；
  fstab 里 7 个逻辑分区都写死 `*_a` + `wait,logical,first_stage_mount`（注释里承认是从 topaz 继承后改的）。
  另外 OF 的身份属性还是 topaz（`ro.build.product=topaz`、`ro.display.series=Redmi Note 12 4G`），
  说明这套设备树是**从 topaz 派生后局部改写**的——改写点之外还有没有漏，静态看不完。
- 为什么它只能排第三：AOSP `wait` 有超时，通常不会永久挂；但 `mount`/`chmod` 组合 + HAL 服务
  （`boot-hal-1-2`、`vibratorfeature-hal-service`、`health-hal-2-1`，这些二进制**不在 ramdisk 里**，要从 `/vendor` 来）
  在 `/vendor` 还没挂上时反复重试，确实可能长时间卡住。
- 验证方法：先跑 2b/2c 拿到 pstore 控制台。若控制台停在某个 `wait`/`mount`/`init:` 报错上 ⇒ C 成立且能直接定位到具体行。
  另外在 OF 里跑通 `recovery.log`（把 `/tmp/recovery.log` 改成写 `/dev/kmsg`，或用 2a 的 adb 起来后 `cat /tmp/recovery.log`）即可一次性看清 TWRP 自己的日志。

---

## 五、执行顺序与判读树（给 lead 的一页表）

每一行都是"刷一次 → 一次判定 → 无条件回滚"。全部命令由 `scripts\run_experiments.ps1` 执行（带 `-s 5e367954`）。

| 步 | 命令 | 期望 | 若不符 |
|---|---|---|---|
| 0 | `.\run_experiments.ps1 -List` | 打印 7 个镜像 + sha256 | — |
| 1 | `-Phase exp1a -Execute -CollectPstore` | 进原厂 recovery | **停**：刷写路径/分区名/槽位有问题 |
| 2 | `-Phase exp1b -Execute -CollectPstore` | 进原厂 recovery | 见 1b 判读（ABL 阈值 = 原厂字节数） |
| 3 | `-Phase exp1c -Execute -CollectPstore` | **若它卡 logo** → zstd 这条路径不通 | 再刷 `exp1d`（gzip）区分 |
| 4 | `-Phase exp2c -Execute -CollectPstore` | pstore 里有 `BEACON:` | 我们的 beacon/重组手法有问题，2b 结果不可用 |
| 5 | `-Phase exp2b -Execute -CollectPstore` | 同上 → 问题在 OF 的 init/recovery | 无 `BEACON:` → 回到"格式/尺寸/内核"这层 |
| 6 | `-Phase exp2a -Execute -CollectPstore` | `adb devices` 见到设备 | 见 2a 控制台，能定位卡在哪个 mount/gadget 步骤 |

**若第 3 步证明 zstd 会卡**（1c 卡 logo）：那 2b（zstd 14.07 MB）也要重出成 lz4；
届时把 2b 的内容再砍到 lz4 ≤ 14.3 MB 即可（可参考 `work\of-slim\报告_of-recovery-瘦身.md` 的成本表，
lz4 地板是 15.02 MB，必须再砍掉 ICU/protobuf 或触摸固件之一）。这条我在本轮**没有**预先准备，
因为它依赖 1c 的结果 —— 有结果后 10 分钟内可以出。

### pstore 怎么读（脚本已自动化，手工版）

```
fastboot flash recovery_a <原厂 recovery_a.bin>     # 回滚
fastboot reboot-recovery
adb devices                                          # 原厂 recovery 的 adb
adb shell cat /sys/fs/pstore/console-ramoops-0       # ← 上一轮（挂死的那个）的控制台
adb shell cat /sys/fs/pstore/dmesg-ramoops-0
```

---

## 六、纪律与回滚（脚本内建）

1. **每条 fastboot 都带 `-s 5e367954`**（另一台 `HF06872291105783` 在线时不会误刷）。
2. 实验前先 `fastboot flash misc misc_full.bin`（1 MiB 净镜像，前 32 字节 BCB 为空），清掉 `boot-recovery` 标记。
3. 实验后**无论结果**：`fastboot flash recovery_a recovery_a.bin`（100 MiB 全分区 dump，即当前已证明能启动的状态）+ 再清一次 misc。
4. 设备不在 fastboot 时（正是"卡 logo"的样子）脚本不会瞎试，会打印：
   长按电源 15–30 s → 按住 音量+ 与 音量- 插 USB → 再跑 `-RollbackOnly -Execute`。
5. `-Execute` 不加就是 dry-run（只打印步骤）。台账追加写 `RESULTS.md`，日志落 `logs\run_<stamp>.log`。

**没有做的事**：本轮没有准备 `ramoops cmdline` 变体（设备树里本来就有 ramoops，不需要），
也没有碰 `vendor_boot`、`boot`、`vbmeta`、`super` 任何一块。

---

## 七、产物清单（`E:\rom\work\of-pipeline\`）

```
out\exp1a_stock_clone.img        14,577,664 B  a97ece2b063322ca2e099378794154c235e161ee819f91b3acbdd1499a5c1a09
out\exp1b_hello_lz4.img          14,577,664 B  67ae2c7402d5d785c37b009fa7600dae7c09d887bb7a891c2aadfd22bc50ccad
out\exp1c_zstd_stock.img          8,134,656 B  6591d7d0d33511dc47da1abd6b9569f2408bb1956386c84b98e0e58cb55893a7
out\exp1d_gzip_stock.img         12,525,568 B  e6893f67abd33a776af58a203b04663d82655e2355c66b3bebc89b40735b8999
out\exp2a_mintel.img              4,947,968 B  ff986f597d68851d58606ef8496fbfb3678dbbd72997e0cc3ab80f031d4c7430
out\exp2b_of_beacon.img          14,073,856 B  a60432cfc85767574fbd05217a7a502bc4bdf5758f0f0cafba1d538f95c532b9
out\exp2c_stock_beacon.img       14,299,136 B  d5bcd9ac36ec7effee5a6e2055fe5d24beb95daac3b4be26d6ee6563a9159c77
scripts\run_experiments.ps1      13,455 B  纯 ASCII，-List / -Phase / -Execute / -RollbackOnly / -CollectPstore
work\01_header_dump.py           头部逐字段注解（给出"原厂 os_version=0、page_size 字段=0"这类的硬事实）
work\02_tail_inspect.py          发现 AVB0@14577664 与 AVBf@100663232
work\03_stock_unpack.py          原厂 ramdisk → cpio → 472 条目清单
work\04_compress_measure.py      ★ 证明 lz4 -l -12 与原厂流比特相同；顺带 gzip/zstd 尺寸
work\05/07/06_*.py               解包 / ELF 闭包审计
work\08/09/10/11/12/13_*.{py,sh}  静态对比（rc/props/flags/显示后端/usb 时序）
work\cpio.py                     cpio 解析/拼接/重组 + ANDROID! v4 打包 + 自检
work\20_build_exp1.py            实验 1 四个镜像（可复算）
work\21_build_exp2.py            实验 2 三个镜像（可复算）
work\init_mintel.sh              2a 的 /init（busybox ash）
work\init_beacon.sh              2b/2c 的 /init（beacon + 看门狗 + exec OF init）
work\{stock,of,slim}_root\        三个 ramdisk 的解包树（分析用，可删）
work\exp1_report.txt / exp2_report.txt / compare.txt / audit_slim.txt   原始输出
```

复算（WSL）：`cd /mnt/e/rom/work/of-pipeline/work && python3 20_build_exp1.py && python3 21_build_exp2.py`

---

## 八、诚实的未验证项

1. **2a 的 adbd 没有在真机上跑过**（本轮不刷机）。它的风险点是"无 property service 时 adbd 的 ffs 拉起时序"，
   顺序按 Android init 的做法写（建 function → mount ffs → 起 adbd → 等 ep1 → 写 UDC），失败会在控制台留痕。
2. **1b 比原厂大 142 B**；ABL 的真实阈值仍然只知道"≤14.57 MB 过、47.6 MB 拒"。
3. **2b 用 zstd**，因此它的解释力依赖 1c 的结论（顺序已排在 1c 之后）。
4. 静态分析**没有**找到"OF 一定死在哪一行"的证据，也不该硬凑——上面三个卡点各自附了可执行的验证动作。
5. 原厂镜像带 AVB，我们的不带；本轮判断它不影响（13 MB 的 OF 能过 ABL 就是证据），但若某次出现 10 秒退回 fastboot，
   先把"尺寸"和"AVB"分开再谈。

---

## 九、本轮做过的校验（离线，可复核）

| 校验 | 结果 |
|---|---|
| GPT 实测：`recovery_a` / `recovery_b` = 104,857,600 B，`misc` = 1,048,576 B | 与 `recovery_a.bin`（100 MiB）、`misc_full.bin`（1 MiB）**正好等长**，可整块刷回 |
| `misc_full.bin` 前 32 字节（BCB command 区） | 为空（仅偏移 8 起有 `-bootloader` 字样），不是待执行的 `boot-recovery` ⇒ 适合当"净 misc" |
| 7 个镜像逐个解压回 cpio 并校验 | 全部 `decompress=OK`、`trailer=yes`、条目数符合预期、关键入口在位 |
| `exp1a` vs `recovery_a.bin[0:14577664]` | **逐字节相同**（sha256 `a97ece2b…`） |
| `lz4 -l -12`(原厂 cpio) vs 原厂 ramdisk 流 | **逐字节相同** |
| `exp2a` 的 adbd 闭包 | 16 个文件，`readelf -d` 逐层追完，缺失 0 |
| `run_experiments.ps1` | 纯 ASCII（13,943 B / 0 个非 ASCII 字节）；`-Phase list` 与 `-Phase exp1a|exp2c` 的 dry-run 已跑通；修掉了一个 `$args` 自动变量冲突（会把真正的参数吞掉，命令变成只有 `fastboot -s 5e367954`）|
| 槽位保护 | `-Execute` 时会先读 `current-slot`，与 `-Partition` 后缀不符则直接中止，不会误刷另一个槽 |
