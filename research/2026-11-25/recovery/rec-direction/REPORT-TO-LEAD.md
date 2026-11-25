# 给 lead 的回报（因 `send_message` 目标 session 不可用，落盘在此）

**状态：rec-direction 完成。本轮没有刷机**；设备仍是 A17 正常开机（18:3x 复核 `sys.boot_completed=1`，adb root 可用，`/data/local/tmp` 临时文件已清理）。
交付：`PLAN.md` + `out/dirA_v0_skeleton.img` + `out/dirA_v1_hybrid.img` + `scripts/run_dirA.ps1`。

---

## 一、推荐：方向 A —— 原厂 ZUI16 ramdisk 骨架 + OrangeFox 用户态（镜像已出、已审计）

### 三条新的硬证据

1. **装载层已证明不会失败**：hybrid 里 `/system/bin/recovery` 的依赖闭包 = **94 个 ELF / 23.37 MiB，缺 0 个库**；10,014 条未定义符号引用中 **strong-unresolved 只有 10 个，与原厂 recovery 的 baseline 逐个相同、新增 0**（`logs/audit_built.txt` 末行 `PASS`）。`init`（35 ELF）、`adbd`（14 ELF）闭包同样 **0 新增**。
2. **「OF 的 init 与 recovery 强耦合」这个疑虑被证伪**：两边根本是**同一份 AOSP recovery `init.rc` 的两个版本** —— 同样的 `import /init.recovery.${ro.hardware}.rc`、同一条 `service recovery /system/bin/recovery`（连 `socket recovery stream 422 system system` 和 `seclabel u:r:recovery:s0` 都一致）、同一套 functionfs/configfs gadget 块、同一个 `ro.hardware=qcom`（设备实测）。TWRP 的 `recovery` 对 init 的全部要求，就是"像原厂 recovery 一样被当作普通 service 拉起来"，而这件事**本机已被原厂验证过**。⇒ 原厂 init 完全不需要认识 `install_keyring`（那是 OF 自己 rc 里的内建命令，我们不带它）。
3. **卡 logo 从此是有日志的事件**：ramoops 已在设备树（2 MiB @ `0x1bfe00000`），cmdline 本来就 `console=ttyMSM0,115200n8`。但 **AOSP init 的日志是 level 6（KERN_INFO），会被 console_loglevel 压掉** —— rc 里加一行 `write /proc/sys/kernel/printk 8` 就能把 init 自己的日志送进 ttyMSM0 → pstore。另加一个独立 watchdog，把 `init.svc.recovery` 时间线与 `/tmp/recovery.log` 尾部打进 `/dev/kmsg`（已实测 `/dev/kmsg` 在 init 的设备表里、写入生效）。

### 镜像

| 镜像 | 字节 | ramdisk | sha256(前16) | 说明 |
|---|---|---|---|---|
| `out/dirA_v0_skeleton.img` | 15,626,240 | 15,618,767 | `67A8072D62C15174` | 原厂骨架 + rc/watchdog，**零 OF 文件**；兼 **ABL 上限探针** |
| `out/dirA_v1_hybrid.img` | 26,869,760 | 26,865,312 | `CA7B132D8FC837D8` | 改 4 条、加 449 条、**删 0 条**，其余逐字节原样 |

改动清单：`system/bin/recovery`（OF 2,906,144）、`system/etc/recovery.fstab`（TWRP 版，已写死 `*_a`）、`init.recovery.qcom.rc`（原厂每行保留 + printk 8 / `setenforce 0` / `export PATH` / kmsg 标记 + watchdog service）、`prop.default`（仅 `ro.secure=0`、`ro.debuggable=1`）；新增 52 个 OF 独有 `.so`（12.34 MiB）、`/twres` 393 文件（8.92 MiB）、`twrp.flags`（`cust`→`lenovocust`、`logo`→`splash`，实测本机 GPT 就是这两个名字）、静态 `busybox`、`sbin/dira_wd.sh`。

---

## 二、★ 必须先解决的分歧：ABL 真实上限到底多少

两个口径**互相矛盾**，而 A1 正落在中间，所以必须用一次刷机判定：

- **保守口径 14,572,954 B**：「原厂就这么多、它能启动」；`of-rebuild/PLAN.md` 用的就是这条。
- **派生口径 ≈31.7 MB**：`89,120,768 − 内核`；代入现役 KSU 内核 43,092,480 → 46,028,288 − init_boot 2,005,893 − vendor_boot 11,628,676 = **32,393,719 ≈ 31.7 MB（十进制口径）**。

设备实测（root 回读，本轮）：`init_boot_a` ramdisk **2,005,893**（`ANDROID!` v4、`kernel_size=0`）；`vendor_boot_a` vendor_ramdisk **11,628,676**（`VNDRBOOT` v4、page 4096、dtb 1,290,690）；原厂 recovery ramdisk **14,572,954**。三者之和 28,207,523。

`dirA_v0` = 15.62 MiB，正好卡在两个口径之间：
- 它进得去 ⇒ 尺寸上限 ≥15.6 MB ⇒ A1（26.9 MB）在派生口径下合法；
- 它 10~15 s 回 fastboot ⇒ 上限就是 14.57 MB ⇒ **A1 直接作废**，此时唯一能装进 14.5 MB 的只剩「A2：OF slim 内容 + 原厂 init/rc/sepolicy + zstd ≈13.4 MB」（配方已写进 PLAN §4，未构建，约 1 h）。注意"zstd 与 gzip 同时失败"本身说明压缩不是判别式，A2 值得试。

---

## 三、前 3 步（`scripts/run_dirA.ps1`：纯 ASCII、`-Execute` 才动手、每条 fastboot 带 `-s 5e367954`、**无论结果都回滚**、dry-run 已跑通）

1. `cd E:\rom\work\rec-direction\scripts` → `.\run_dirA.ps1 -Phase dirA0 -Execute`
   - 进原厂 recovery + adb + pstore 有 `DIRA:` 行 ⇒ 尺寸/骨架/我们的补丁全 OK → 第 2 步
   - `REJECTED-BY-ABL`（≤15 s 回 fastboot）⇒ 上限 14.57 → 跳过第 2 步转 A2
   - 连原厂 recovery 都进不去 ⇒ 只回退 `printk 8` / `setenforce 0` 两行
2. `.\run_dirA.ps1 -Phase dirA1 -Execute`
   - TWRP 有画面 + adb ⇒ 达成
   - 只有 adb 没画面（脚本判 `ADB-UP`，已自动抓 `/tmp/recovery.log`）⇒ 死在 `gr_init`
   - `NO-ADB-HUNG` ⇒ 第 3 步
3. 脚本内建 pstore 回读（回滚原厂 recovery → `adb shell cat /sys/fs/pstore/console-ramoops-0`）：
   `DIRA` 行看时间线、`init:` 行看服务是否 `exited status=…`、`fb0|drm|minui|gr_init` 看显示、`avc:` 看 SELinux。
   **先读 pstore 再进 A17**，否则 ramoops 会被覆盖。

---

## 四、四方向矩阵（详见 PLAN §1）

| 方向 | 可用 recovery | 至少"能 adb" | 工作量 | 失败代价 |
|---|---|---|---|---|
| **A 原厂骨架 + TWRP 用户态** | **45 %** | 70 % | **已完成** | 低 |
| D 自写极简（mintel 4.95 MB） | 20 %（无触摸 UI） | **60 %**（唯一不依赖显示） | 1~2 h | 低 |
| C 源码重编（13.67 MB lz4） | 40 % | — | **1~2 天** | 高 |
| B 七镜像阶梯 | 15 %（不产出，只诊断） | 30 % | 0 h，5 次刷机 | 低 |

A 的唯一大未知量：`CONFIG_FB is not set` ⇒ fbdev 必死；`libminuitwrp.so` 里确有 DRM 后端（`/dev/dri/%s`、`drmModeAddFB2`、`DRM_IOCTL_MODE_CREATE_DUMB`），设备上 `/dev/dri/card0` + `card0-DSI-1` 也确实存在，但**它能否驱动 `p255_hx83102j` 这块 DSI video 面板只能上机验**。

---

## 五、「为什么前面十几条路不行」（PLAN §2 有逐条证据）

- **前 9 条**（对齐原厂头/空 cmdline/`flags=3`/全哈希重算/footer `alg=NONE`/塞 `boot`/96 MiB 版/降级 ZUI15 abl/私钥伪造）→ 全在回答「ABL 愿不愿意加载」这个**已被否定**的问题：`fastboot reboot-recovery` 早已实测进原厂 recovery；且 13.26 MB 的 OF 是**卡 logo** 而不是「10 s 回 fastboot」（AVB 拒绝不会给你一次启动机会）。
- **接下来 3~4 条**（OF zstd 13.26 MB / gzip 13.99 MB / of-slim 变体）→ 才是第一次「内容正确但失败」，而它们**同时换了两个以上变量（压缩 + 内容 + 尺寸）且在零信息通道上**：`卡 logo` 是**五选一**（内核没解包 / init 死了 / recovery 死了 / 显示死了 / adb 没起），外部现象完全一样。
- 附带一条判别式：**zstd 与 gzip 同时失败 ⇒ 压缩不是变量、内容才是**（两条独立解压路径不可能一起坏）；而 OF 内容里唯一从没被换过的就是 **init 及其整套 rc/USB/SELinux 环境** —— 这正是方向 A 要换掉的东西。

---

## 六、风险与回滚

只写 `recovery_a` 与 `misc`，不碰 boot / init_boot / vendor_boot / vbmeta / super。

```
fastboot -s 5e367954 flash recovery_a E:\rom\work\dual-boot\backup\recovery_a.bin   # 104,857,600 B, sha256 AF282B9D…
fastboot -s 5e367954 flash misc        E:\rom\work\rescue-matrix\reads\misc_full.bin # 1 MiB 净镜像
```

卡死（无 adb 无 fastboot）时：长按电源 15–30 s → 按住 音量+ 与 音量− 插 USB → `.\run_dirA.ps1 -RollbackOnly -Execute`。
`setenforce 0` 只影响 recovery 这一次启动，不影响系统。
