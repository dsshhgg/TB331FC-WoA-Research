# 方案 2（改 APK 版）镜像级落地说明

> 这份文件是给"坚持要把改动烘进镜像"的人看的。
> **默认推荐仍是方案 1（`out/block-installer.sh`）**，理由见 `..\..\REPORT.md` §1.1 / §5：
> 安装器是 MIUI 平台签名（SHA-256 `C9:00:9D:01…`），我们没有任何一把能复现它的 key。

## 0. 先确认这四件事，否则烘了也白烘

1. **真机跑的是 /data 里的 5.5.4.0.2**，镜像里是 5.4.5.1.2（`UPDATED_SYSTEM_APP`）。
   光换镜像不生效，必须二选一：
   - 把新 APK 的 `versionCode` 抬到 > 55402（例如 55403），开机后 PMS 会用"系统副本更新"覆盖 data 副本；
   - 或者刷完后主动 `adb shell pm uninstall-system-updates com.miui.packageinstaller`（此举会回到镜像版本，签名是新的）。
2. **签名迁移**：系统副本换成 testkey 签名后，`/data/app` 下旧签名的副本会被 PMS 判为不一致（AOSP 逻辑要么丢弃 data 副本，要么让系统副本不生效）。建议顺序：
   `pm uninstall com.miui.packageinstaller`（仅清更新，需 system 权限）→ 刷镜像 → 开机让 PMS 重新扫描。
3. **privapp 白名单**（`/product/etc/permissions/privapp-permissions-product.xml`，真机验证过）只保护
   `INSTALL_PACKAGES / DELETE_PACKAGES / CLEAR_APP_CACHE / PACKAGE_USAGE_STATS / USE_RESERVED_DISK /
   MANAGE_USERS / UPDATE_APP_OPS_STATS / READ_PHONE_STATE / REAL_GET_TASKS / WRITE_SECURE_SETTINGS /
   ACCESS_MTP / CHANGE_COMPONENT_ENABLED_STATE` 这 12 个**特权**权限 —— 换签名不影响它们。
   但**签名级**权限（`miui.packageinstaller.permission.ACTION_INFO` 等 4 个，见 REPORT §1.2）不受白名单保护，换签即丢。
4. **APK 里 4 处 `signature|privileged` 声明权限**对端是 Settings / SecurityCenter，丢了之后
   "安装未知应用授权页 / 安全模式被调度"这类入口**可能直接抛 SecurityException**。接受不了就别走方案 2。

## 1. 重签（apksigner 不在机器上时的手工做法）

机器上目前**没有** `apksigner`/`zipalign`（WSL 里也没有），只有 jadx 1.5.1 + apktool 2.11.1。
两条路：

- **A（推荐）**：把 `build-tools` 里的 `apksigner.jar` + `zipalign` 拷进 WSL/Windows PATH（`apksigner` 只是个 java -jar wrapper）。
- **B（全手工）**：用 `openssl` + 自己写的 v2/v3 签名器（不划算）。

签之前先把 PEM 私钥转 pk8：
```bash
openssl pkcs8 -topk8 -nocrypt -in E:/rom/work/tools/testkey_rsa4096.pem -outform DER -out testkey_rsa4096.pk8
# 自签 x509（如果只有 PEM 没有 cert）
openssl req -new -x509 -key testkey_rsa4096.pem -out testkey_rsa4096.x509.pem -days 10000 -subj "/CN=testkey/O=rom-surgery"
```

## 2. 镜像流水线

```powershell
cd E:\rom\work\pkg-installer\out\bake
# 先把重签好的 APK 放到 out\payload\MIUIPackageInstallerVariants.apk
.\rebake-installer.ps1 -Apk E:\rom\work\pkg-installer\out\payload\MIUIPackageInstallerVariants.apk
# 首次建议先跑自检（用镜像里原有 APK 重放，检查流水线可复算）
.\rebake-installer.ps1 -SelfCheck
```

产物：`out\product_a.img`（2,999,996,416 B）、`out\vbmeta_system_a.img`（65,536 B）、`out\SHA256SUMS-installer.txt`。

### 配方参数（本次用 `avbtool info_image` 对 kit-baked 成品复核过，不是抄文档）

```
product_a.img
  Image size            2999996416   (整分区)
  Original image size   2909995008   (ext4 数据区, = truncate.py 的切点)
  VBMeta offset         2932916224
  Algorithm             SHA256_RSA4096     key sha1 2597c218aae470a130f61162feaae70afd97f011
  Salt                  00…01 (64 hex)
  FEC                   0                 Rollback 0   Flags 0
vbmeta_system_a.img
  Algorithm             SHA256_RSA2048     key sha1 cdbb77177f731920bbe0a0f94f84d9038ae0617d
  Descriptors 顺序       product → system(1697497088) → system_ext(1503494144)
  padding               65536
```
（这段是 `python avbtool.py info_image` 的实测输出摘要，写在 REPORT §4.2 的命令里就是这些值。）

## 3. 不推荐但确实存在的第三条路（镜像内 init 脚本）

想在镜像里"开机自动 iptables + settings"，唯一入口是 `/product/etc/init/*.rc`：

```
service installer_net_block /system/bin/sh /product/etc/installer_net_block.sh
    class late_start
    user root
    group root net_bt_admin inet
    oneshot
```
代价：`init` 域 exec shell、shell 域 exec iptables、iptables 往 `netd` 域写 socket 都要 SELinux allow，
得改 `plat_sepolicy.cil`（kit-baked 里已有先例：`work\kit-baked\payload\plat_sepolicy.cil` 加了 4 条 allow）。
**风险明显高于 KernelSU 模块，且每次改策略都要重新签 vbmeta_system。不推荐。**

## 4. 刷入 / 回滚

刷（不在本次范围）：
```
fastboot flash product     out\product_a.img
fastboot flash vbmeta_system out\vbmeta_system_a.img
```
回滚：
```
fastboot flash product     E:\rom\release\TB331FC_HyperOS4_A17_FullKit_v4\images\product_a.img
fastboot flash vbmeta_system E:\rom\release\TB331FC_HyperOS4_A17_FullKit_v4\images\vbmeta_system_a.img
# 或回到"只烘了 5 修"的状态：
#   E:\rom\work\kit-baked\out\product_a.img + vbmeta_system_a.img
```

## 5. 本目录脚本做了什么（对照）

| 脚本 | 作用 | 与 kit-baked 的关系 |
|---|---|---|
| `rebake-installer.ps1` | 1→7 步总装 | 参数逐项照抄 `rebake.ps1`，只动 product |
| `surgery-installer.sh` | debugfs 单文件替换 | 照抄 `surgery.sh` 的 `replace_file`：`rm/write/sif/ea_set -f/mtime/ctime/atime` |
| `verify-installer.sh` | in-image sha256 vs payload、mode/xattr、AVB | 对应 `verify.sh` 的 §1/§6 |
