# 启动镜像组报告（boot / init_boot / vendor_boot / dtbo / vbmeta / vbmeta_system）

> 分析对象：TB331FC（khaje / SM6225，Lenovo 小新 Pad 2024）
> 日期：2026-11-25　范围：只读，未写回任何镜像，未动设备
> 原始数据：`E:\rom\work\of\v3\stock\{dtbo_a.bin,vendor_boot_a.bin}`、`E:\rom\work\a17dump\{boot_a.img,vbmeta_a.img,vbmeta_system_a.img,system_a.img,product_a.img,system_ext_a.img}`、`E:\rom\work\zui16_flash\image\{boot.img,init_boot.img,dtbo.img}`
> 工具与中间产物：本目录 `tools\`、`dtbo_extract\`（45 棵 FDT + dts）、`dtbo_entries.json`、`dtbo_cross.json`、`dtbo_report.txt`、`dtbo_cross.txt`

---

## 0. 一页结论

1. **init_boot 的"尺寸不符"是误判**。`2,011,136` 是**镜像大小**（= 4096 头页 + 2,005,893 ramdisk 向 4096 对齐），不是 ramdisk 长度。手里这份原厂 `init_boot.img` 的哈希与 `vbmeta_a` 声明**逐字节完全一致**（`ab394ed4…` MATCH）。所以"init_boot 的 AVB 已破"这条不成立；真破的是 **boot**。
2. **真正 AVB 破的是 boot**：设备上的 `boot_a` = 43,098,112 B 的"仅内核"重打包（kernel 43,092,480 / ramdisk 0），其后 3,743,744 B 是**原厂 boot 的残留字节**，`vbmeta_a` 却按 46,841,856 B 计算哈希 ⇒ 实测 `89013232…` vs 声明 `ad970718…` **MISMATCH**。`verifiedbootstate=orange` 本身是"解锁态"的正常取值；boot 这条失配说明 ABL 确实走的是**"校验失败但放行"**分支（`0x1cdf0`：`State: Unlocked, … continue boot`），而不是没校验。
3. `dtbo` / `init_boot` / `vendor_boot` 三个的 hash 描述符**全部 MATCH**（原厂套件自洽）。也就是说：**当前机器上只有 boot 一个分区破了 boot 链的 AVB**。
   `veritymode=eio` 不是 super 的 hashtree 造成的，而是"boot 验不过 → 引导器把 `androidboot.veritymode` 降级成 `eio`"这个开关（见 §3.4）；而 `vbmeta_system` 的**三条 hashtree 本轮全部复算通过**（system / product / system_ext 的 root 与声明逐字节相同），所以 super 三件**当前不再是变量**——11-13 的 product 不自洽已经被那轮 `product_FIX + vbmeta_system` 重签修掉了。
4. **dtbo 不是"几片小补丁"，而是 45 棵完整的板级 overlay 树**（3,500,977 B，24 棵带显示/触摸全量配置）。表头 `id/rev` 全 0，ABL 靠**每棵树自带的 `qcom,msm-id` / `qcom,board-id` / `qcom,pmic-id`** 选树；本机 `ro.boot.dtbo_idx=2`、`ro.boot.dtb_idx=0` ⇒ 生效的是 **entry 2「KHAJE IDP nopmi」**（182,701 B，msm-id `<518 0x10000>`，board-id `<65570 0>`）。
5. **panel / touch 全部只在 dtbo 里**，`vendor_boot` 的 DTB 里**一个都没有**（连 `p255_*` 字符串都不存在）。base DTB 只有 SoC 侧的 `qcom,mdss_mdp / dsi_ctrl0 / dsi_phy0 / pinctrl / thermal`。→ 做 Linux / UEFI 想要面板参数，只能从 dtbo 抄。
6. 面板三个变体：**BOE + HX83102J（默认，phandle 0x35）**、INX + NT36523N、CSOT + NT36523N；全部 1200×1920 @90 Hz，`orientation=180`。触摸是同颗 TDDI 的 **`touch@0`（compatible `himax,hxcommon` + `novatek,NVT-ts-spi`）**，另有 i2c 的 `novatek@62` / `synaptics_tcm@20` 备选。
7. 关于"ABL 需要 120 条符号"：**实测不是 120**。base DTB 有 **829** 条 `__symbols__`；45 棵 overlay 合计只用到 **143** 条不同符号，全部能在 base 里解析（**0 缺失**）；单棵树 `__fixups__` 41–129 条。自建 DTB 若要套原厂 dtbo，必须保留的是**这 143 个符号名**（不是 120）。

---

## 1. 对象与方法

### 1.1 文件清单（逐一 sha256）

| 文件 | 字节 | sha256 | 说明 |
|---|---|---|---|
| `a17dump\boot_a.img`（=`release\…FullKit_v3\images\boot_a.img`） | 100,663,296 | `2510b098…c3c14b` | 设备 boot 分区原样 dump（96 MB 分区） |
| `zui16_flash\image\boot.img` | 100,663,296 | `09daedb9…f8718d5b` | **原厂 544 boot**（与 vbmeta 完全自洽） |
| `of\v3\stock\vendor_boot_a.bin` | 100,663,296 | `d526c77b…ed7a8a1` | 原厂 544 vendor_boot（hash MATCH） |
| `zui16_flash\image\init_boot.img`（=`port_zui\init_boot.img`） | 8,388,608 | `2d090fb5…9bb01b` | 原厂 544 init_boot（hash MATCH） |
| `of\v3\stock\dtbo_a.bin` | 25,165,824 | `ac8fc83d…80ad0c09` | 设备 dtbo 分区（24 MB）；**镜像本体 3,500,977 B**，与包内 `dtbo.img`（8 MB）前 3,500,977 B 逐字节相同 |
| `a17dump\vbmeta_a.img` | 65,536 | `9466f0e8…55223ec` | 分区 dump；**镜像本体 8,192 B**，其余 57 KB 全零 |
| `a17dump\vbmeta_system_a.img` | 65,536 | `cea948ea…bb86643` | 分区 dump；**镜像本体 4,096 B**，其余全零 |

> 方法：自写解析器（`tools\bootimg.py` / `dtbo.py` / `avbverify.py` / `verity_fast.py`）+ 官方 `avbtool.py`（`E:\rom\work\tools\avbtool.py`）+ `dtc`（WSL `ub`）。所有数字都是本机实测，不用转述。

### 1.2 三条既有结论的更正（有字节级证据）

| 旧说法 | 实测 | 证据 |
|---|---|---|
| `init_boot` 内核 0 + ramdisk 2,005,893 ≠ vbmeta 声明 2,011,136 ⇒ AVB 已破 | **不成立**。2,011,136 = `4096 + round_up(2,005,893, 4096)`，是**镜像大小**字段语义 | `sha256(salt‖init_boot[:2011136]) == ab394ed4…` MATCH |
| `boot_a` 是"原厂 ZUI16 544 内核" | 内容上是**重打包件**：头里 kernel_size=43,092,480（原厂 46,819,840），ramdisk=0，尾部 3.7 MB 是原厂残留 | 与 `boot_tb331fc_v3_kernel_only.img` 前 43,098,112 B **完全相同**；`dev[43098112:46841856] == stock[...]` true |
| （技能库）修补 init_boot 必须保留 `lib/firmware/novatek_ts_fw.bin`(196,608 B) 与 `system/etc/ramdisk/build.prop`(1,302 B) | 原厂 544 的 init_boot ramdisk **只有 16 个条目**：`init`(2,567,024)、`system/bin/snapuserd`、`system/etc/init/snapuserd.rc`、`system/etc/ramdisk/build.prop`(**1,064 B**) 和几个空目录；**没有 `lib/`、没有 novatek 固件** | `tools\ramdisk.py` 解 lz4-legacy cpio 全量列表。→ 那条记忆应是别的构建（460/其它）或别的分区，**待核** |

---

## 2. 五个镜像的完整头解析

### 2.1 `boot`（v4，GKI：只有内核）

| 偏移 | 字段 | 值 |
|---|---|---|
| 0x000 | magic | `ANDROID!` |
| 0x008 | kernel_size | **43,092,480**（设备件）/ 46,819,840（原厂件） |
| 0x00C | ramdisk_size | **0** |
| 0x010 | os_version | 0（未写） |
| 0x014 | header_size | 1584（0x630） |
| 0x018 | reserved[4] | 0,0,0,0 |
| 0x028 | header_version | **4** |
| 0x02C | cmdline[1536] | **全零**（空；cmdline 在 vendor_boot） |
| 0x62C | signature_size（v4 扩展） | 0 |
| — | page_size | 4096（v3/v4 **固定值，不在头部**） |

**布局与 ABL 读取公式（v4）**

```
kernel_off  = 4096                                   # page 0 = 头
ramdisk_off = 4096 + round_up(kernel_size, 4096)     # ramdisk_size=0 ⇒ 不存在
second/imgs = v4 无
image_size  = 头 + kernel + AVB 附加块（原厂 16,384 B，内含两份 AVB0 签名）
```
设备件：kernel@4096 … 43,098,112；payload_end = 43,098,112；AVB footer 声称 `original_image_size = 46,841,856`，`vbmeta@46,841,856 +896`。
原厂件：kernel@4096 … 46,825,472，随后 **16,384 B 的 AVB0 区**（实测两份 `AVB0`，见下），image 46,841,856；footer 的 vbmeta 在 `46,841,856 +896`。

> 原厂 boot 尾部 AVB0 实测：`46,825,472` 处 2,304 B（alg=SHA256_RSA4096）、`46,827,776` 处 2,368 B（alg=SHA256_RSA4096）；`46,841,856` 处 896 B（alg=NONE）= footer 的 vbmeta 本体（**不计入** image_size）。
> ⇒ **重建 boot 时这 16,384 B 必须保留或重算**，否则哈希必变（`mkbootimg` 不生成它，要用 `avbtool add_hash_footer` 或原样复制）。

### 2.2 `vendor_boot`（v4，vendor ramdisk + DTB + bootconfig）

| 偏移 | 字段 | 值 | 备注 |
|---|---|---|---|
| 0x000 | magic | `VNDRBOOT` | |
| 0x008 | header_version | 4 | |
| 0x00C | page_size | 4096 | |
| 0x010 | kernel_addr | 0x00008000 | **ABL 不读**（GKI 无第二内核） |
| 0x014 | ramdisk_addr | 0x01000000（16 MiB） | vendor ramdisk 装载地址 |
| 0x018 | vendor_ramdisk_size | **11,628,676** | |
| 0x01C | cmdline[2048] | `video=vfb:640x400,bpp=32,memsize=3072000 bootconfig`（51 B） | 原厂就是这样（三版一致） |
| 0x81C | tags_addr | 0x00000100 | |
| 0x820 | name[16] | 空 | |
| 0x830 | header_size | 2128（0x850） | |
| 0x834 | dtb_size | **1,290,690** | 6 棵 FDT |
| 0x838 | dtb_addr | **0x01F00000**（32,505,856） | ABL 把整块 blob 放这里 |
| 0x840 | vendor_ramdisk_table_size | 108（0x6C） | |
| 0x844 | table_entry_num | **1** | |
| 0x848 | table_entry_size | 108 | |
| 0x84C | bootconfig_size | 125（0x7D） | |

**Ramdisk table（唯一一条）**：`size=11,628,676 offset=0 type=1(PLATFORM) name="" board_id[16]=全0`

**bootconfig（125 B，原文）**
```
androidboot.hardware=qcom
androidboot.memcg=1
androidboot.load_modules_parallel=false
androidboot.usbcontroller=4e00000.dwc3
```

**布局与 ABL 读取公式（v4）**
```
vendor_ramdisk_off = round_up(2128, 4096)  = 4,096
dtb_off            = 4,096 + round_up(11,628,676,4096)  = 11,636,736
table_off          = 11,636,736 + round_up(1,290,690,4096) = 12,931,072
bootconfig_off     = 12,931,072 + round_up(108,4096)       = 12,935,168
image_size         = 12,935,168 + round_up(125,4096)       = 12,939,264   # = vbmeta 声明值 ✓
```

### 2.3 `init_boot`（v4，只有 ramdisk）

| 偏移 | 字段 | 值 |
|---|---|---|
| 0x000 | magic | `ANDROID!` |
| 0x008 | kernel_size | 0 |
| 0x00C | ramdisk_size | **2,005,893**（0x1E9B85） |
| 0x010 | os_version | 0 |
| 0x014 | header_size | 1584 |
| 0x028 | header_version | 4 |
| 0x02C | cmdline | 空 |
| 0x62C | signature_size | 0 |

布局：`ramdisk@4096 … 2,011,136`（ramdisk 为 **lz4 legacy** 压缩，解压 3,630,592 B，16 条目）；AVB footer `original_image_size=2,011,136`，`vbmeta@2,011,136 +832`。
**ramdisk 内容（全量）**：`init`(2,567,024)、`system/bin/snapuserd`(1,059,856)、`system/etc/init/snapuserd.rc`(507)、`system/etc/ramdisk/build.prop`(1,064)、`debug_ramdisk/ dev/ metadata/ mnt/ proc/ second_stage_resources/ sys/ system/ system/bin/ system/etc/ system/etc/init/ system/etc/ramdisk/`（空目录）。
→ 这是 **GKI 通用 ramdisk**：没有 `/lib`、没有任何固件；first-stage 的 `.rc`/策略都在 `system` 分区。

### 2.4 `dtbo`（Android DTBO 表 + 45 棵 FDT）

| 偏移 | 字段 | 值 |
|---|---|---|
| 0x00 | magic | 0xD7B7AB1E |
| 0x04 | total_size | **3,500,977** |
| 0x08 | header_size | 32 |
| 0x0C | dt_entry_size | 32 |
| 0x10 | dt_entry_count | **45** |
| 0x14 | dt_entries_offset | 32 |
| 0x18 | page_size | 4096 |
| 0x1C | version | 0 |

条目结构：`{dtb_size u32, dtb_offset u32, id u32, rev u32, custom[4] u32}`，**45 条的 id / rev / custom 全为 0**（选树不靠这两个字段，见 §4.3）。
DTB 区从 `0x5C0`（=32+45×32）开始，每棵向 4096 对齐。
分区里 3,500,977 之后是历史残留（8 MB 处还有一份 2024 版包内 dtbo 的 AVB footer），`vbmeta` 只覆盖前 3,500,977 B，所以 **hash MATCH**。

### 2.5 `vbmeta` / `vbmeta_system`

| 项 | `vbmeta_a` | `vbmeta_system_a` |
|---|---|---|
| 镜像本体 | 8,192 B（header 256 + auth 576 + aux 6,080 = 6,912，补齐 8 K） | 4,096 B（256 + 320 + 1,344 = 1,920，补齐 4 K） |
| 分区大小 | 65,536（其余全零） | 65,536（其余全零） |
| Algorithm | **SHA256_RSA4096**（avbtool alg=2） | **SHA256_RSA2048**（alg=1） |
| 公钥 sha1 | `2597c218 aae470a1 30f61162 feaae70a fd97f011` | `cdbb7717 7f731920 bbe0a0f9 4f84d903 8ae0617d` |
| rollback_index / loc / flags | 0 / 0 / **0** | 0 / 0 / **0** |
| release string | `avbtool 1.2.0` | `avbtool 1.3.0`（**第三方重签过的痕迹**） |
| 描述符 | Chain×1 + Prop×20 + Hash×5 + Hashtree×4 | Hashtree×3 |

> 公钥 = AOSP testkey：`vbmeta_a` 的 1,032 B = `testkey_rsa4096` 公钥，`vbmeta_system_a` 的 520 B = `testkey_rsa2048`（前一轮已用 `avbtool extract_public_key` 逐字节核对，本轮沿用）。这意味着**我们随时能重签出 ABL 认可的 vbmeta**。

---

## 3. 交叉依赖

### 3.1 `vbmeta_a` 描述符全表（20 prop + 10 描述符）

| # | 类型 | 分区 | Image Size | 算法 / 树参数 | Salt | Digest / Root |
|---|---|---|---|---|---|---|
| 1 | **Chain** | `vbmeta_system` | — | RIL=2 | — | pubkey sha1 `cdbb7717…617d`，flags 0 |
| 2 | Hash | `boot` | 46,841,856 | sha256 | `0b8f7e2f…7689` | `ad970718…21e3e5` |
| 3 | Hash | `dtbo` | 3,500,977 | sha256 | 同上 | `b1858a6b…ab915a` |
| 4 | Hash | `init_boot` | 2,011,136 | sha256 | **`6cb9fac0…0f42b`**（唯一不同） | `ab394ed4…29ad0c9` |
| 5 | Hash | `recovery` | 14,577,664 | sha256 | `0b8f7e2f…` | `57af3911…8d72aa7b` |
| 6 | Hash | `vendor_boot` | 12,939,264 | sha256 | `0b8f7e2f…` | `a81b4405…0e6ec0e9a` |
| 7 | Hashtree | `odm` | 1,310,720 | v1 / 4096 / sha256 / FEC 2 roots / tree 16,384 | `2e7e7a71…c9f613` | `e5bf7ad6…70a69785` |
| 8 | Hashtree | `system_dlkm` | 352,256 | 同上（tree 4,096） | 同上 | `04114d7d…46526031` |
| 9 | Hashtree | `vendor` | 670,437,376 | tree 5,283,840 / FEC 5,349,376 | 同上 | `9f28d49c…775c6800` |
| 10 | Hashtree | `vendor_dlkm` | 57,925,632 | tree 458,752 / FEC 466,944 | 同上 | `ac9cb2bd…7dce22c` |

Prop 20 条：`com.android.build.{boot,init_boot,vendor_boot,recovery,vendor,odm,vendor_dlkm,system_dlkm,dtbo}.{os_version,fingerprint,security_patch}`，指纹统一 `Lenovo/TB331FC_PRC/TB331FC:14/UKQ1.230917.001/ZUI_16.0.544_241115_PRC`，`security_patch=2024-10-05`，`os_version=13`（注意 `boot.security_patch` 与 `vendor.security_patch` **各有两条重复描述符**）。

### 3.2 逐分区 hash 复算（本机实测，`tools\avbverify.py`）

| 分区 | 声明 digest | 实测（对现有文件前 image_size 字节 + salt） | 结论 |
|---|---|---|---|
| `boot` | `ad970718…` | `89013232fa91fa39bfb722484dec8bf5ce852c550a8fd0bb30e02391ed273990` | **MISMATCH** |
| `dtbo` | `b1858a6b…` | `b1858a6b5975a0f6dff25462b64daff50ac58459dfc38b60dfdb783849ab915a` | **MATCH** |
| `init_boot` | `ab394ed4…` | `ab394ed4e359ce444fd64cba717f982d038f30fb696b46f054044fe6329ad0c9` | **MATCH** |
| `vendor_boot` | `a81b4405…` | `a81b4405a7dd25e8287a0dd83fefdb877f40095dd4f90bb6ee0fd18ce6ec0e9a` | **MATCH** |
| `recovery` | `57af3911…` | `f48cc3aa…`（比对的是 OF v3 recovery，不是原厂） | 不适用 |

**结论**：boot 链里只有 `boot` 一处破。`vendor_boot`（含 6 棵 FDT 与全部 vendor ramdisk 模块）、`dtbo`（全 45 棵）、`init_boot`（GKI ramdisk）当前与原厂签名内容**完全一致**。
⇒ 反过来说：**任何改动都会立刻让对应 hash 失配**，而本机 unlocked ⇒ ABL 只把 `verifiedbootstate` 置 orange、继续启动（`0x1cdf0` 打印 `State: Unlocked, … continue boot`）。所以 AVB 在这台机器上**不是硬门禁，是"状态指示器"**；但**换锁/回锁/送修前必须把这些哈希补回去**。

### 3.3 尺寸链路（谁按谁的尺寸算）

```
vbmeta_a.boot.image_size = 46,841,856
  = 4096(头) + 46,819,840(原厂 kernel) + 16,384(AVB0 签名区)
  ≠ 设备件 payload 43,098,112                    ← 破点

vbmeta_a.init_boot.image_size = 2,011,136
  = 4096 + round_up(2,005,893,4096)              ← 完全一致

vbmeta_a.vendor_boot.image_size = 12,939,264
  = 4096 + round_up(11,628,676) + round_up(1,290,690) + round_up(108) + 125(对齐后 4096)

vbmeta_a.dtbo.image_size = 3,500,977             # dt_table_header.total_size
vbmeta_system.{product,system,system_ext}.image_size = footer 的 original_image_size
  product 2,909,995,008 / system 1,697,497,088 / system_ext 1,503,494,144
```

### 3.4 `veritymode=eio` 的真正来源（本轮已定案到"不再由 super 引起"）

`eio` 是 **libavb/ABL 的降级开关**：解锁态下验签/校验不通过时，引导器不拦启动，而是把 `androidboot.veritymode` 置成 `eio`，让内核的 dm-verity 在遇到不一致时返回 EIO（"错误忽略"）而不是 panic。因此：

- **触发点在这台机器上是 `boot` 的 hash 失配**（§3.2）——这是 boot 链里唯一的失配项；
- `vbmeta_a` 另有 4 条 hashtree（`odm / system_dlkm / vendor / vendor_dlkm`），`vbmeta_system` 有 3 条（`product / system / system_ext`，salt `00…01`，`fec_roots=0`）。

**本轮对 super 三件做了独立复算**（`tools\verity_fast.py`，流式：level0 = sha256(salt‖4 KiB 块)，逐层 128 路折叠到根；结果落 `verity_result.txt`）：

| 分区 | data_size | 重算 root | vbmeta_system 声明 | 结论 |
|---|---|---|---|---|
| `system_ext` | 1,503,494,144 | `fef554f21f19…02512ae` | 同 | **MATCH** |
| `system` | 1,697,497,088 | `971e7bb18f7f…240ba024` | 同 | **MATCH** |
| `product` | 2,909,995,008 | `02c25fcfbb40…f62cbce7` | 同 | **MATCH** |

⇒ 三件**完全自洽**，dm-verity 在它们上面不会失败。11-13 那条"product 的 hashtree 与自身数据不符"（重算 `0bcedeb0…` vs 声明 `832596f2…`）在当前 dump 里**已不存在**，说明那轮的 `product_FIX`（数据段 2,909,995,008 + `add_hashtree_footer` 重出 root）+ `vbmeta_system` 重签确实生效了。
⇒ **`eio` 这条观测已经不能再当作"super 破了"的证据**；它现在的解释是"boot 破了 → 引导器进了降级模式"。仍未复算的是 `vbmeta_a` 那 4 条 hashtree（缺 `odm / system_dlkm / vendor / vendor_dlkm` 的分区 dump）。

---

## 4. `dtbo` 深挖

### 4.1 45 棵 overlay 全清单（`dtbo_report.txt` 全文，此处摘要）

每棵都是"以 root 为目标"的板级 overlay（`target = <0xffffffff>`，即 `&{/}`），带自己的 `qcom,msm-id / qcom,board-id / qcom,pmic-id`：

| # | 偏移 | 大小 | nodes | syms | fixups | frags | model | msm-id | board-id | pmic-id |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0x5C0 | 92,048 | 307 | 72 | 85 | 33 | Khaje ATP | 518,0x10000 | 33 | 45,46 |
| 1 | — | 36,749 | 222 | 48 | 73 | 26 | Khaje ATP | 586 | 33 | 45,46 |
| **2** | — | **182,701** | **315** | **67** | **115** | **45** | **KHAJE IDP nopmi** | **518** | **65570** | **45** |
| 3 | — | 47,819 | 208 | 43 | 102 | 35 | KHAJE IDP nopmi | 586 | 65570 | 45 |
| 4 | — | 216,018 | 455 | 85 | 117 | 39 | Khaje IDP | 586,518 | 65570 | 45,46 |
| 5 | — | 28,219 | 145 | 25 | 85 | 31 | Khaje IDP +PM8010 | 586,518 | 66082 | 45,46 |
| 6 | — | 79,856 | 352 | 61 | 98 | 30 | IDP USBC Audio | 518 | 16842786 | 45,46 |
| 7 | — | 71,197 | 329 | 54 | 83 | 28 | IDP USBC Audio | 586 | 16842786 | 45,46 |
| 8 | — | 222,488 | 481 | 85 | 111 | 43 | IDPS +90Hz | 518 | 65826 | 45,46 |
| 9 | — | 214,976 | 458 | 85 | 111 | 41 | IDPS +90Hz | 586 | 65826 | 45,46 |
| 10 | — | 146,648 | 509 | 104 | 129 | 38 | QRD HVDCP3P5 | 586,518 | 65803 | 45,46 |
| 11 | — | 102,264 | 294 | 76 | 124 | 33 | QRD nopmi | 518 | 65547 | 45 |
| 12 | — | 47,174 | 203 | 52 | 112 | 25 | QRD nopmi | 586 | 65547 | 45 |
| 13 | — | 146,917 | 509 | 104 | 129 | 38 | QRD NOWCD9375 | 518 | 131339 | 45,46 |
| 14 | — | 75,909 | 393 | 70 | 88 | 29 | QRD NOWCD9375 | 586 | 131339 | 45,46 |
| 15 | — | 146,330 | 508 | 103 | 129 | 38 | QRD | 586,518 | 65547 | 45,46 |
| 16–25 | | 12,603–206,332 | | | | | **khajeg** 全套（msm-id 585） | 585 | 同上各型 | |
| 26–34 | | 12,603–209,636 | | | | | **khajep** 全套（msm-id 561） | 561 | 同上 | |
| 35–44 | | 12,603–132,796 | | | | | **khajeq** 全套（msm-id 562） | 562 | 同上 | |

合计：**45 棵、3,500,977 B**；单棵 `__symbols__` 4–112 条，`__fixups__` 41–129 条，fragment 15–45 个。
（完整逐条数据见 `dtbo_report.txt` 与 `dtbo_entries.json`。）

### 4.2 为什么表头 id/rev 全 0 也能选树

Qualcomm 的选树不读 `dt_entry.id/rev`，而是读**每棵 DTB 自己的** `qcom,msm-id`（SoC+版本）、`qcom,board-id`（板型+子型）、`qcom,pmic-id`，并按最优匹配打分。证据：
- 45 条的 `id/rev` 全 0，但每棵都带完整的三元组；
- 真机 `ro.boot.dtbo_idx=2` / `ro.boot.dtb_idx=0` 是**引导器写回**的选择结果（AOSP 约定 `androidboot.dtbo_idx`），说明选择确实发生在 ABL 侧；
- 本机 SoC = khaje（`msm-id 518`），board = IDP-nopmi（`65570`），⇒ **entry 2**。

> 若要验证自己的判断，只需读机上 `ro.boot.dtbo_idx`（本次因设备不在线未复读，数值取自 `work\system-profile\REPORT.md:213/747` 的真机记录）。

### 4.3 生效树（entry 2）的 45 个 fragment —— 板级配置全景

| frag | __overlay__ 顶层节点 | 作用 |
|---|---|---|
| 0–5 | `pm6125-tz` / `rf_pa1_therm` / `batt_therm` / `key_vol_up` / `eldo9_pin` | PMIC 温度与按键 |
| 6 | `gpio_keys` / `vdda_usb_ss_dp_core` | 电源键 |
| 8 | `awinic@64` | 霍尔/传感器 |
| 11 | `simtray` | SIM 卡托（本机无卡槽也留着） |
| 15 / 16 / 42 / 44 | `synaptics_tcm@20` / `novatek@62` | 备用 i2c 触摸，16 里两者 `status="disabled"` |
| 17–19 | `rt1711h@4e` / `aw35615@22` / `rt-pd-manager` | Type-C PD |
| 21–24 | `mm8013c10@55` / `sc8960x_master@6b` / `sc8960x_slave@6b` / `nopmi_chg` | 充电计 |
| 25–29 | `bolero-clk-rsc-mngr` / `tx|rx|va-macro` / `wcd937x-codec` / `sound` / `aw883xx_smartpa@34,@35` / `wsa881x-i2c-codec` | 音频（4 颗 smartpa） |
| 31 | `nq@28` | NFC |
| 32–34 | `qcom,eeprom0/1` / `qcom,cam-sensor0/1` / `qcom,camera-flash@0..2` / `qcom,actuator0` | 前后摄 |
| **35** | `qcom,mdss_mdp` / `mdss_rotator` / `mdss_dsi_ctrl0@5e94000` / `mdss_dsi_phy0@5e94400` / `dsi_pll_codes` | **显示控制器 + 3 个 panel 节点（见 §4.4）** |
| 36–37 | `smmu_sde_un/sec_cb` / `dfps_data_region@5cf00000` | SDE 内存 |
| **38** | `dsi_panel_pwr_supply_no_labibb` / **`qcom,dsi-display-primary`** / `wb-display@0` / `msm_notifier@0` | 显示面板绑定（`qcom,dsi-default-panel = <0x35>`） |
| 39–40 | `disp_rdump_region@5c000000` / **`splash_region@5c000000`** | splash / 崩溃转储区（对应 bootchain 报告里 `0x5C000000+0xF00000`） |
| **41** | **`touch@0`** | **TDDI 触摸（himax + novatek 双 compatible）** |
| 43 | `bkl-bl@11` | 背光 IC |

> 与 OF/UEFI 直接相关：`splash_region@5c000000` 与 `disp_rdump_region@5c000000` 是 ABL splash 与 dump 的地址来源（ABL 找不到 splash region 会**主动关屏**）。

### 4.4 panel / touch 在哪棵树、长什么样

**结论：只在 dtbo 的 entry 2（及其它 IDP/QRD 全量树）里；`vendor_boot` 的 6 棵 base DTB 里 `p255_*` / `hx83102` / `himax,hxcommon` 出现次数全为 0。**（`tools\where.py` 实测）

三个 panel 变体（都在 `/fragment@35/__overlay__/qcom,mdss_mdp/` 下）：

| 节点 | phandle | panel-name | 分辨率 | fps | hfp/hbp/hpw | vfp/vbp/vpw | phy-timings | 绑定 |
|---|---|---|---|---|---|---|---|---|
| `qcom,mdss_dsi_panel_p255_hx83102j_fhd_video` | **0x35** | `hx83102j video mode dsi boe panel` | 1200×1920 | 90 | 185/40/20 | 118/12/8 | `19 06 06 15 20 07 06 07 02 04 00 16 0b` | **默认（dsi-default-panel=0x35）** |
| `…p255_inx_fhd_video` | 0x36 | `nt36523n video mode dsi inx panel` | 1200×1920 | 90 | 96/96/4 | 56/248/2 | `19 06 06 15 20 07 06 07 02 04 00 16 0b` | 备选 |
| `…p255_csot_fhd_video` | 0x37 | `nt36523n video mode dsi csot panel` | 1200×1920 | 90 | 100/100/4 | 30/134/2 | `18 06 06 15 20 06 06 07 02 04 00 15 0b` | 备选 |

三者共同：`qcom,mdss-dsi-panel-type = "dsi_video_mode"`、`orientation = "180"`、`bl-max-level = 0xFFF`、`bl-min-level = 13`、`status-check-mode = reg_read`（`0x06 0x01` 读 `0x0A`，期望 `0x9C`/`0x9D`）、timings 下只有 `timing@0` 一个。
⇒ 对外只说"1200×1920 竖屏 + 180° 旋转 = 1920×1200 横屏 @90Hz"。

触摸（fragment@41，`target=&{/}`）：

```
touch@0 {
    compatible = "himax,hxcommon", "novatek,NVT-ts-spi";   // 同一颗 TDDI，两个驱动名
    reg = <0>;  spi-max-frequency = <0x989680>;            // 10 MHz
    interrupt-parent = <&tlmm>;  himax,irq-gpio  = <&tlmm 0x50 0x01>;
                                 himax,rst-gpio  = <&tlmm 0x56 0x02>;
                                 novatek,irq-gpio= <&tlmm 0x50 0x01>;
                                 novatek,reset-gpio=<&tlmm 0x56 0x02>;
    panel = <0x35 0x36 0x37>;            // 三块面板共用这套触摸
    himax,display-coords = <0 0x2EE0 0 0x4B00>;   // 12000 × 19200 (×10 ⇒ 1200×1920)
    himax,panel-coords   = <0 0x2EE0 0 0x4B00>;
    report_type = <1>;  novatek,pen-support;  novatek,mp-support-dt;
    novatek-mp-criteria-6072@0 { … }     // 646 行自检门限表（PenTip/PenRing X/Y 的 Raw/Diff）
}
```

另有 `novatek@62`（i2c `compatible="novatek,NVT-ts"`，irq 0x50 / rst 0x56，`status="ok"` 在 frag15，`disabled` 在 frag16）与 `synaptics_tcm@20`（`synaptics,tcm-i2c`，`firmware-name="synaptics_firmware_k.img"`）——IDP 板上还写了根级 `qcom,i2c-touch-active = "synaptics,tcm-i2c"`。
⇒ **真正在跑的是哪一颗，必须以 dmesg 为准**：OF v3 报告里 `hxchipset.ko` 的 `softdep pre: msm_drm` 说明 himax 线是活的（HX83102J 是 BOE 屏的 TDDI，触摸走 SPI 的 `touch@0`）；`novatek@62` 在 IDP 变体上被 frag16 关掉。**这条别猜，上机 `dmesg | grep -iE "hxchipset|nt36|synaptics"` 一次就定。**

### 4.5 `__symbols__` 账本（决定"能不能自建 DTB"）

| 项 | 实测 |
|---|---|
| base DTB（`dtb_idx=0`，khaje SoC） | 1,940 nodes / 7,830 props / **`__symbols__` 829 条** |
| 其余 5 棵 base | 829 / 793（khajeg）/ 48（khajep-QRD，异常）/ 628（khajep）/ 627（khajeq） |
| 45 棵 overlay 合计需要的符号 | **143 条（去重）**，覆盖全部 `__fixups__` |
| base 里找不到的 | **0** |
| base 中未被任何 overlay 用到 | 686 |
| 单棵 overlay `__fixups__` | 41–129 条（entry 2 = **115**） |

⇒ 若自建 vendor_boot 的 DTB（OF/UEFI 常常要改 `bootargs`/`chosen`），**必须原样保留这 143 个符号名**，否则 `ufdt_apply_overlay` 解析 `__fixups__` 失败 → 该 fragment 被丢或整体报错 → 出现"overlay 里明明有 panel，起来却没屏"。
另：base 里有一棵 **异常项**——第 3 棵（off 820,272，59,575 B）不是 SoC base，而是 `Khajep QRD`（board-id 65547），与 entry 44 重复。属原厂打包瑕疵，不影响本机（dtb_idx=0）。

> 关于"120 条符号"：**四份 vendor_boot（原厂 544、ZUI17、两份 boot-backup）的 dtb blob 完全相同**（6 棵 FDT，符号数 829/829/793/48/628/627），没有一份是 120。所以 120 这个数在现有素材里对不上；**可操作的门槛是"143 个被引用的符号名必须都在"**，不是某个总数。

---

## 5. 可改边界矩阵

| 镜像 | 改动是否要重签 | 改了会破坏什么 | 回滚成本 |
|---|---|---|---|
| **`boot`** | 要。`vbmeta_a` 有 `boot` 的 hash 描述符（46,841,856 B，sha256+salt）。要么 `avbtool add_hash_footer` 后 `make_vbmeta_image` 重签根 vbmeta，要么接受 hash 失配（unlocked 仍能起） | ① 内核/cfg/AVB 签名区（原厂 16,384 B）；② **cmdline 改不动**（v4 的 cmdline 在 vendor_boot）；③ 内核与 `vendor_dlkm`/`vendor` 的 KMI 必须匹配（5.15.167 GKI） | 低：`fastboot flash boot_a` 一份 43 MB 原厂/内核件即回。**分区 96 MB，写小镜像不会清尾巴**（残留会像现在这样把 AVB 哈希搞脏，但不影响功能） |
| **`init_boot`** | 要（hash 描述符，salt 与自己一套 `6cb9fac0…`） | 一改就是 first-stage：`/init` 与 snapuserd 全在这里；ramdisk 只有 16 条目，**没有固件**，加/减文件都要重打 lz4-legacy cpio 并重算 2,011,136 对齐 | 极低：8 MB 分区，`fastboot flash init_boot_a` 秒回；KSU 修补失败的症状（触控/密度）见技能库 |
| **`vendor_boot`** | 要（hash 描述符 12,939,264） | ① **全部内核 cmdline**（唯一入口）；② 246 个 GKI 模块（含 `msm_drm.ko` 4.17 MB、`panel_event_notifier.ko`）——缺一个就掉显示/触控；③ 6 棵 FDT（143 个符号）；④ 125 B bootconfig。四段任一长度变化都会改变后续所有偏移 | 中：96 MB 分区，`fastboot flash vendor_boot_a` 一份即可；但要 **四段长度自洽**（改 ramdisk 必须重算 dtb/table/bootconfig 偏移，否则 900E） |
| **`dtbo`** | 要（hash 描述符 3,500,977） | 只影响"板级外设"：屏（panel 三选一）、触摸、音频 4 颗 smartpa、充电、摄像头、splash 区。dtbo 与 vendor_boot base DTB 是**符号耦合**关系，两边版本错配 → 屏或触控或音频掉 | 极低：3.5 MB，`fastboot flash dtbo_a` 一份 8 MB 包内件即回；**选树错（dtbo_idx）**比内容错更常见 |
| **`vbmeta`** | 它本身就是签名者 | 它是 boot 链的"总闸"：改坏 → ABL 判 AVB 失败（unlocked 仍放行，但 `verifiedbootstate` 变红/黄）；**换锁/回锁必失败** | 极低：8 KB，`fastboot flash vbmeta_a` 秒回。重签用 `testkey_rsa4096.pem` 即被 ABL 认可（公钥已在 ABL 里 memcmp 1,032 B） |
| **`vbmeta_system`** | 它是 system 三件的签名者 | 只影响 `system / product / system_ext` 的 dm-verity 开关。**这是"能不能起 A17"的真正开关**（11-13 已定案：product 的 hashtree 必须与数据自洽） | 极低：4 KB，`fastboot flash vbmeta_system_a`；但**必须与你刷的那三份镜像同批**，否则 eio/900E |

### 5.1 一句话原则

- **改内容就必须重签 vbmeta**（或用 `--flags 0` + 全哈希重算），但**解锁态下不重签也能起**——只是 `verifiedbootstate=orange` 且**回锁必砖**。
- **"混搭"是 900E 的唯一已知系统性原因**：boot / init_boot / vendor_boot / dtbo / vbmeta 必须来自同一发布套件（这是 A17 三周反复的教训）。
- **回滚成本从低到高**：vbmeta(8 K) < vbmeta_system(4 K) < dtbo(3.5 M) < init_boot(2 M) < boot(43 M) < vendor_boot(12.9 M)。全部可在 fastboot 完成，不需要 9008。

---

## 6. 四条线对照表

| 线 | 该动哪个镜像 | 怎么动 | 风险 / 前置 |
|---|---|---|---|
| **刷机包（A17 / HyperOS4 这套）** | `boot`（换内核）+ `init_boot`（换 ramdisk）+ `vendor_boot`（改 cmdline/模块）+ `dtbo`（保持原厂）+ `vbmeta`（重签根）+ `vbmeta_system`（随 system 三件重签） | 六件成套出包：`mkbootimg` 打 v4 头 → `avbtool add_hash_footer`（`--partition_size` 用**分区**大小、去掉 padding 差异）→ `make_vbmeta_image --include_descriptors_from_image` 逐件收描述符 → `testkey_rsa4096` 签根、`testkey_rsa2048` 签 system | 风险中。**唯一硬约束**：vendor_boot 四段偏移自洽 + 143 个符号保留 + system 三件与 vbmeta_system 同批。当前机器 boot 已破 AVB 仍在跑，说明"不重签"在解锁态可行 |
| **UEFI（WOA / BootShim）** | **只动 `boot`**（+ 根 `vbmeta` 重签） | 把 UEFI FD（或 BootShim + FD）当作 boot v4 的 "kernel"：`mkbootimg --kernel uefi_fd --ramdisk none --header_version 4`。ABL 从偏移 0 进入、必要时 zlib 就地 inflate（`0x7894`），**入口契约 = 头部前 8 字节可执行、从 0 进入** | 风险高。① `0x5FC00000` 是 XBL 自己那份 UEFI FV 的装载地址，BootShim 往那儿拷贝可能自踩（未验证，别盲试）；② 屏不亮要自己写 GOP/panel 驱动——**panel 参数只能从 dtbo entry 2 抄**（§4.4 的 timings 表）；③ 不动 dtbo/vendor_boot，所以 Android 侧随时可回 |
| **OF / 第三方 recovery** | `boot_b` + `vendor_boot_b` + `init_boot_b` + `dtbo_b`（**b 槽**，全部）+ `misc`(BCB)；**不碰 `recovery` 分区**（ABL 有原厂签名白名单，直接进不去） | 走 v3 的做法：`--set-active b` → `flash boot_b`（纯内核）→ `vendor_boot_b`（v3 拼接版）→ `init_boot_b`（512 B 空 cpio）→ `dtbo_b`（原厂）→ `fastboot continue` | 风险中高。① **b 槽四件曾被 ABL 拒（20:10，原因未定）**；② recovery 白名单是死路，别在 `recovery` 分区上耗；③ 回滚 = `--set-active a`，a 槽零写入。a 槽永远不动是底线 |
| **mainline Linux** | `boot_b`（内核 Image）+ **自建 DTB**（可塞进 vendor_boot_b 的 dtb 段，或用 appended DTB，但**内核后追加的 DTB 只允许单棵**）；`initramfs` 可走 init_boot_b 或 vendor_boot_b 的 ramdisk | 从 dtbo entry 2 反推 DTS：mdss/dsi/panel timings（§4.4）+ `touch@0`（himax/novatek）+ `bkl-bl@11` 背光 + `splash_region`；再用 mainline 的 `qcom` 驱动树重写 | 风险高（工作量而非砖）。① base DTB 的 6 棵 FDT 是 Android/GKI 口径，**不能直接喂 mainline**；② 触控 mainline 无 hx83102j 驱动（有 `himax_hx83112b`，需改 ID 表）；③ 显示走 `msm`/`dpu` 主线支持度有限；④ 全程 b 槽，a 槽 Android 不受影响 |

---

## 7. 未闭合 / 待核

1. **`msm_drm.dsi_display0=` 的来源不明**。设备历史记录里 `/proc/cmdline` 有 `msm_drm.dsi_display0=qcom,mdss_dsi_panel_p255_hx83102j_fhd_video`，但：原厂 `vendor_boot` 的 cmdline 只有 51 B（`video=vfb…`）、bootconfig 125 B、`boot` 的 cmdline 为空、**45 棵 dtbo 与 base DTB 里都没有 `dsi_display0` 这个字符串**（`tools\where.py`）。⇒ 该参数要么是 ABL 运行时追加（ABL 有面板选择逻辑，未反汇编证实），要么来自当时机器上那份**被改过的 vendor_boot**。DT 侧的等价物是 `qcom,dsi-default-panel = <0x35>`（= hx83102j），**以 DT 为准即可**。
2. **`ro.boot.dtbo_idx=2` 是历史真机读数**（`work\system-profile\REPORT.md:213`）。本次 adb 只连到手表的 adb（`s5e5515`），平板不在线（序列号 `5e367954` 未找到），故**未复读**。复读命令：`adb shell getprop ro.boot.dtbo_idx`。
3. **super 三件的 hashtree root 复算已完成**：`system_ext / system / product` 三条 **全部 MATCH**（见 §3.4 与 `verity_result.txt`）。仍未复算：`vbmeta_a` 的 `odm / system_dlkm / vendor / vendor_dlkm`（缺分区 dump）。要闭合"eio 到底由谁引起"，dump 这四个分区后同法再跑一次即可。
4. **原始 `init_boot` ramdisk 里没有 novatek 固件**（与技能库记忆冲突，见 §1.2）。若确实需要 `novatek_ts_fw.bin`，它在 `vendor_dlkm`（`/lib/modules` 侧）而非 init_boot，需另查。
5. **b 槽四件被 ABL 拒的原因**仍未定（见 `work\dual-boot\REPORT.md` §2.2），四条线里 OF / Linux 都压在 b 槽上，这条不闭合就都悬着。

---

## 8. 复现（只读）

```bash
# 头解析（boot / init_boot / vendor_boot）
python3 tools/bootimg.py <img> [<img> …]

# vbmeta 描述符 + 逐分区 hash 复算
python3 tools/avbverify.py

# dtbo：表头 + 45 棵 FDT + fragment/panel/touch 清单
python3 tools/dtbo.py                       # 输出 dtbo_report.txt
python3 tools/analyze2.py                   # fixups↔base symbols 账本
python3 tools/where.py                      # panel/touch 到底在哪棵树
python3 tools/split_dtb.py                  # vendor_boot 的 6 棵 FDT
python3 tools/panelinfo2.py                 # panel timings / phandle 映射
bash    tools/decompile.sh                  # 45 棵 dtb → dts（dtc）

# 流式 dm-verity root
bash    tools/run_verity.sh
```

关键产物：`dtbo_extract\`（45 × .dtb/.dts + `vendor_boot_base` 相关）、`dtbo_entries.json`、`dtbo_cross.json`、`dtbo_report.txt`、`dtbo_cross.txt`、`verity_result.txt`。
