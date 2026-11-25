# out\ —— TB331FC mainline Linux 启动包（2026-11-25）

先读上一层的 `REPORT.md`。这里是可直接刷的镜像，`SHA256SUMS` 是校验清单。

> 全程只写 **A 槽**；每条 fastboot 命令都必须带 `-s 5e367954`（机器上常同时插着另一台设备）。

## 推荐顺序

| 步 | 刷什么 | 期望 |
|---|---|---|
| 1（探针） | `boot_a-linux-dtb.img` → `boot_a` | 屏出内核日志后 panic（说明 ABL 放行、内核活、屏可用） |
| 2（首选正式） | `boot_a-linux.img` + `vendor_boot_a-linux-nord.img` + `init_boot_a-initramfs.img` | 屏出 `[init] alive #N`，USB 出现 COM 口 |
| 3（备选正式） | `boot_a-linux.img` + `vendor_boot_a-linux.img` + `init_boot_a-empty.img` | 同上 |
| 4（可选） | `boot_a-linux.img` + `recovery_a-linux.img` | 同上（验证 recovery 通道） |

用脚本，别手打：

```powershell
cd E:\rom\work\linux-boot
powershell -File .\scripts\flash-tb331fc.ps1 -Form A2         # 只打印计划
powershell -File .\scripts\flash-tb331fc.ps1 -Form A2 -Go     # 真刷
powershell -File .\scripts\flash-tb331fc.ps1 -Form rollback -Go        # 只回 boot_a
powershell -File .\scripts\flash-tb331fc.ps1 -Form rollback -Go -Full  # 连 vendor_boot_a/init_boot_a/recovery_a
```

## 文件

| 文件 | 字节 | 说明 |
|---|---|---|
| `boot_a-linux.img` | 38,965,248 | v4 / page 4096 / 未压缩 `Image` / ramdisk 0 |
| `boot_a-linux-gz.img` | 14,090,240 | 同上，`Image.gz`（ABL 是否解压未实测） |
| `boot_a-linux-dtb.img` | 39,043,072 | 内核 + 恰好一棵 appended FDT（计入 kernel_size） |
| `vendor_boot_a-linux.img` | 1,003,520 | vendor_ramdisk=initramfs + dtb + cmdline |
| `vendor_boot_a-linux-nord.img` | 86,016 | dtb + cmdline，vendor_ramdisk=0 |
| `init_boot_a-initramfs.img` | 921,600 | kernel_size=0 + initramfs |
| `init_boot_a-empty.img` | 8,192 | 512 B 空 cpio 占位 |
| `recovery_a-linux.img` | 921,600 | kernel_size=0 + initramfs |
| `initramfs-tb331fc.cpio.gz` | 914,098 | 最小 initramfs（≤5 MB ✅） |
| `sm6225-lenovo-tb331fc-linux.dtb` | 75,566 | 蓝牙已修、`dtc -@`、`__symbols__`=122 |
| `dts-bt-fix.diff` | — | DTS 改动 |

回滚源（`REPORT.md` §8 有哈希）：`E:\rom\work\a17dump\boot_a.img`、`E:\rom\TB331FC\刷机包\TB331FC_ZUI_16.0.544\image\{vendor_boot,init_boot,recovery}.img`

## 判据一句话

屏上出现 `[init] alive #1` = 成功（ABL 放行 + 内核活 + fbcon 出图 + initramfs 解出 + init 在跑）。
`adb` 不会有——mainline 没有 adbd；控制台只有面板和 USB CDC-ACM（Windows 上的新 COM 口）。
