# E:\rom 根目录整理报告（dir-tidy）

- 执行时间：2026-11-25 18:0x–18:2x（Asia/Shanghai）
- 执行者：目录整理子代理（只读勘察 → 方案 → 安全移动）
- 结果一句话：**根目录 61 项（17 目录 + 44 文件）→ 30 项（18 目录 + 12 文件）**；32 个散落文件移入新建 `E:\rom\_archive\`，**0 删除、0 目录移动、0 sha 漂移、undo 已双向实测**。

---

## 0. 先纠一处事实（和任务书背景不一致）

任务书说的「根目录堆了 `rom_audit_*.txt`、`ubuntu*.txt`、`*.rar`、`ubuntutb_*.txt`、`scan_*.txt`」——**这些文件不在 `E:\rom` 根目录，而在 `E:\rom\release\` 根目录**（release 是「成品包」禁动区）。实测 `E:\rom` 根目录 44 个文件里**没有任何 .rar**：上一轮清理（`work\disk-cleanup-2026-11-24\REPORT.md`）已于 11-24 23:30 删掉根目录那个 6.31 G 的 `tb331fc_device_features.zip等3个文件.rar`。

`release\` 根下确实还躺着那批 11-10 的审计 txt + 两个 3 GB 的 FullKit zip（见 §7 后续建议，本轮**未动**，因为越界）。

---

## 1. 现状表（整理前，61 项 = 17 目录 + 44 文件）

### 1.1 目录（17 个，全部保持原位）

| 目录 | 文件数 / 体积 | 装什么（一句话） |
|---|---:|---|
| `work\` | 103,700 / **47.06 GB** | 主战场：`a17stage`（A17 工作镜像）、`hyperos_out`（成品 ext4/DSU）、`zui17_images`、`zui16_flash`、`tools`（自动化脚本）、`docs`（STATE/协议）、`port_tools`（TWRP/OF/内核树）、`forensics_900e`、`disk-cleanup-*`、本轮新增 `dir-tidy` |
| `release\` | 2,080 / **20.68 GB** | 成品刷机包 `TB331FC_HyperOS4_A17_FullKit_v3/v4`（含 bat + edl + rollback）+ 同名两个 3 GB zip + `tmp\`（DSH 快照等）+ `gh_stage_20261107` + 11 个审计 txt |
| `TB331FC\` | 202 / **12.45 GB** | 原厂资产：`刷机包\TB331FC_ZUI_16.0.544`、`9008 工具箱\`、`9008 驱动\`、`adb 驱动\`、`引导\`、`镜像 img\`、APatch apk |
| `yupei-ota_full-OS4.0.5.0.XPZCNXM-user-17.0-4fe489f542\` | 7 / **9.46 GB** | 移植的输入：小米 yupei 澎湃 OS 4.0.5 源包（`payload.bin` 9.26 G） |
| `extracted\` | 240 / **5.75 GB** | 解包产物三件套：`GSI_Kit`（救砖/自包含 system 镜像）、`device_features`、`NoBlur` |
| `logs\` | 96 / 60.3 MB | 刷机/EDL/DSH 会话日志（`a17_diag_20261116`、`syscap_20261117`、`a17_flash_exec.log` 等） |
| `session_dump\` | 24 / 55.0 MB | 8 个历史 DSH 会话解包目录 + 提取脚本/`out_*` |
| `session_logs_extract\` | 24 / 52.9 MB | 5 个会话日志解包（`4e0d3c95`…`de0ccc60`）+ `digest_*.txt` |
| `$dir\` | 129 / 51.9 MB | **变量没展开的畸形目录名**：bkerler EDL（`edl-master\fastpwn.exe` 可用、`edlclient\edl.py` 是 0 字节）+ erofs 工具（`dump/mkfs/fsck.erofs.exe`） |
| `$out\` | 749 / 18.4 MB | `linux-lenovo-tb331fc-main` —— TB331FC 的 Linux 内核源码树（WoA/Linux 线） |
| `_archive\` | 34 / 20.1 MB | **本轮新建**：归档根目录散落文件（logs / misc / archives + MANIFEST + undo） |
| `tools\` | 5 / 8.1 MB | `platform-tools\`（adb / fastboot） |
| `liquid-glass\` | 4 / 1.4 MB | 一个 HTML 小 demo，与 ROM 无关 |
| `docs\` | 21 / 0.3 MB | 实验记录、复盘、路线图（21 个 md） |
| `.workbuddy-ai\` | 4 / 0.1 MB | 旧 WorkBuddy 记忆快照（`MEMORY.md` + 3 份状态 md，**禁动**） |
| `scripts\` | 8 / 0.02 MB | 8 个刷机/校验 ps1（`flash_system.ps1`、`verify_files.ps1`、`_common.ps1`…） |
| `backup\` | 0 / 0 | `backup\zui_stock\` 是**空目录**（计划放原厂备份，从未落盘） |
| `TB331FC-OrangeFox\` | 8 / 0.02 MB | OrangeFox 设备树（`BoardConfig-fox-additions.mk`、`fox_TB331FC.mk`、`build-fox-local.sh`、`验证清单.md`） |

> 相对 `rom-workspace` skill（2026-11-16 记 55 项）多出来的 6 项：`session_logs_extract\`、`$out\`、`_archive\`（本轮新建）、以及 3 个新文件（见 §3）。`backup\` 仍是空目录。

### 1.2 根目录 44 个散落文件（类型 / 大小 / 修改时间）

| # | 文件 | 类型 | 字节 | 最后修改 | 处置 |
|---:|---|---|---:|---|---|
| 1 | `README.md` | 教程索引 | 3,533 | 10-05 23:17 | **保留**（相对链接指向 01–09，见 §4） |
| 2 | `01-刷机基础.md` | 教程 | 8,240 | 10-05 20:41 | **保留**（同上） |
| 3 | `02-刷机包移植.md` | 教程 | 7,894 | 10-05 20:42 | **保留** |
| 4 | `03-TWRP移植.md` | 教程 | 8,088 | 10-05 20:42 | **保留** |
| 5 | `04-GSI移植.md` | 教程 | 9,280 | 10-05 20:43 | **保留** |
| 6 | `05-OrangeFox移植.md` | 教程 | 10,758 | 10-05 20:40 | **保留** |
| 7 | `06-不解BL使用第三方Recovery.md` | 教程 | 12,130 | 10-05 23:17 | **保留** |
| 8 | `07-TB331FC设备资料与芯片漏洞.md` | 教程 | 15,176 | 10-06 00:00 | **保留** |
| 9 | `08-下载清单.md` | 教程 | 7,300 | 10-05 22:55 | **保留** |
| 10 | `09-ABL白名单静态逆向.md` | 教程 | 37,079 | 10-06 20:11 | **保留** |
| 11 | `开包移植系统教程.docx` | Office 文档 | 47,295 | 10-07 15:21 | **保留**（教程同批，非文本类） |
| 12 | `sn.img` | 镜像片段（356 B，含 `1a2blenovo…0865A7420CCD…`） | 356 | 09-30 00:04 | **保留**（`.img` 本体，纪律禁动；用途待确认） |
| 13 | `dsh-session-session-8e86f3f3-….zip` | 会话导出 | 9,633,181 | 11-19 22:46 | → `_archive\archives\` |
| 14 | `dsh-session-session-7366fc24-….zip` | 会话导出 | 4,625,411 | 10-31 23:13 | → `_archive\archives\` |
| 15 | `dsh-session-session-cff82b11-….zip` | 会话导出 | 3,435,248 | 10-23 20:04 | → `_archive\archives\` |
| 16 | `dsh-session-session-4e0d3c95-….zip` | 会话导出 | 2,303,495 | 11-17 18:05 | → `_archive\archives\` |
| 17 | `dsh-session-session-b43a23ec-….zip` | 会话导出 | 851,109 | 10-24 11:41 | → `_archive\archives\` |
| 18 | `dsh-session-session-de0ccc60-….zip` | 会话导出 | 216,201 | 11-17 18:05 | → `_archive\archives\` |
| 19 | `port_trace.txt` | EDL 运行日志 | 2,841 | 11-25 07:36 | → `_archive\logs\` |
| 20 | `adb_err.txt` | adb stderr | 122 | 09-23 23:26 | → `_archive\logs\` |
| 21 | `adb_out.txt` | adb stdout（空） | 0 | 09-23 23:26 | → `_archive\logs\` |
| 22 | `qsahara_err.txt` | QSaharaServer stderr（空） | 0 | 09-25 19:31 | → `_archive\logs\` |
| 23 | `qsahara_out.txt` | QSaharaServer stdout（空） | 0 | 09-25 19:31 | → `_archive\logs\` |
| 24 | `log.txt` | 空日志 | 0 | 10-16 22:48 | → `_archive\logs\` |
| 25 | `edl_dbg.log` | EDL 调试日志 | 1,878 | 09-26 01:03 | → `_archive\logs\` |
| 26 | `edl352_full.log` | EDL 全量日志（与 25 同尺寸） | 1,878 | 09-26 01:15 | → `_archive\logs\` |
| 27 | `edl_gpt.log` | EDL 读 GPT | 246 | 09-26 01:02 | → `_archive\logs\` |
| 28 | `edl_master_gpt.log` | EDL 备 GPT | 219 | 09-26 01:04 | → `_archive\logs\` |
| 29 | `edl_full.log` | EDL 全量 | 219 | 09-26 01:12 | → `_archive\logs\` |
| 30 | `edl_noloader.log` | EDL 缺 loader 失败 | 139 | 09-26 01:17 | → `_archive\logs\` |
| 31 | `_p.py` | 一次性 py（900E 取证 grep） | 537 | 11-13 11:49 | → `_archive\misc\` |
| 32 | `_p2.py` | 一次性 py | 646 | 11-13 11:49 | → `_archive\misc\` |
| 33 | `_p3.py` | 一次性 py | 482 | 11-13 11:49 | → `_archive\misc\` |
| 34 | `_p4.py` | 一次性 py | 382 | 11-13 12:21 | → `_archive\misc\` |
| 35 | `_p5.py` | 一次性 py | 579 | 11-13 12:21 | → `_archive\misc\` |
| 36 | `_p6.py` | 一次性 py | 382 | 11-13 13:30 | → `_archive\misc\` |
| 37 | `_p7.py` | 一次性 py | 498 | 11-13 13:49 | → `_archive\misc\` |
| 38 | `_panic.py` | 一次性 py（panic 分析） | 578 | 11-13 11:49 | → `_archive\misc\` |
| 39 | `_scan2.py` | 一次性 py（扫描） | 700 | 11-13 12:21 | → `_archive\misc\` |
| 40 | `_mount.py` | 一次性 py（挂载信息） | 757 | 11-13 12:04 | → `_archive\misc\` |
| 41 | `_vb.py` | 一次性 py（vbmeta 解析） | 1,437 | 11-13 12:03 | → `_archive\misc\` |
| 42 | `_vb2.py` | 一次性 py（vbmeta 解析） | 1,046 | 11-13 12:03 | → `_archive\misc\` |
| 43 | `pad_str.py` | 一次性 py（`libmiinputflinger.so` 字符串） | 320 | 11-16 18:39 | → `_archive\misc\` |
| 44 | `patch_bootfix.sh` | 设备端一次性 sh（`_boot_fix.sh` 打补丁） | 617 | 09-23 23:56 | → `_archive\misc\` |

合计移动 32 个、**20,108,148 B（20.1 MB）**。

---

## 2. 依赖检查（危险项 grep）——方法、范围、结果

目的：确认没有 `.ps1/.py/.bat/.sh` 硬编码根目录这些文件的路径，移动后不会把脚本打断。

| 项 | 内容 |
|---|---|
| 扫描范围 | `E:\rom\work\`（103,700 文件）、`E:\rom\release\`（2,080）、`E:\rom\scripts\`、`E:\rom\docs\`、`E:\rom\TB331FC-OrangeFox\` |
| 扩展名过滤 | `.ps1 .py .bat .cmd .sh .cjs .js .mjs .psm1 .mk .yml .yaml .json .reg .xml .ini .cfg .md` |
| 精确绝对路径模式 | `E:\rom\(adb_out|adb_err|qsahara|log\.txt|port_trace|sn\.img|pad_str|patch_bootfix|_p[0-9]?\.py|_panic|_scan2|_mount|_vb2?\.py|dsh-session-session|0[1-9]-)` |
| 裸文件名模式（仅脚本类） | `(pad_str\.py|patch_bootfix\.sh|port_trace\.txt|_scan2\.py|_panic\.py|_mount\.py|_vb2?\.py|_p[1-7]\.py|sn\.img)` |

**结论：`E:\rom` 根目录这 32 个被移走的文件，没有任何脚本引用（0 命中）。**

容易被误判成「命中」的 3 处，逐个核实后都与根目录无关：

1. `work\TB331FC-abl-downgrade\verify_staging.ps1:50` → `$stockLog = 'E:\rom\release\ZUI15-extract\images\port_trace.txt'`
   —— 指 `release\ZUI15-extract\` 下那份 18 KB 的 LUN4 失败 trace，**该目录 2026-11-16 起就不存在了**（老路径漂移，本轮之前就已是悬空引用）。**与根目录 `port_trace.txt`（2,841 B，11-25 07:36 写 misc 分区的 fh_loader 日志）是两份不同的文件。**
2. `work\handover_dbf5\d_19_25.md:273` → `E:\rom\work\edl\port_trace.txt`（`work\edl\` 下的另一份，非根目录）。
3. `release\gh_stage_20261107\docs\skills\…\knowledge-base.md:1567` → 只是一串日志文件名清单（`getvar_all.txt`、`of*.log`、`edl*.log`、`port_trace.txt`、`patch_bootfix.sh`…），无路径，属说明性文字。

另外：`work\disk-cleanup-2026-11-24\REPORT.md:244` 已经点过这批碎片「合计 < 1 MB、象征意义大于收益（可删）」，但**上一轮没删也没动**；本轮按纪律只搬不删。附带更正：那份报告写 `sn.img(0 B)`，实测 **356 B**（内容像 lenovo SN 片段），已按纪律保留。

---

## 3. 方案与执行结果

### 3.1 目标结构（实际落地）

```
E:\rom\
├─ _archive\                 ← 新建（本轮）
│  ├─ MANIFEST.tsv           32 行：原路径 / 新路径 / 大小 / 时间 / sha256 / 分类 / 理由（UTF-8，制表符分隔）
│  ├─ undo.ps1               纯 ASCII 回滚脚本（按 MANIFEST 反向移回）
│  ├─ logs\       (12)       adb / QSahara / edl* / port_trace / log.txt
│  ├─ archives\   (6)        dsh-session-*.zip
│  └─ misc\       (14)       _p*.py / _vb*.py / _scan2 / _panic / _mount / pad_str.py / patch_bootfix.sh
├─ README.md + 01…09-*.md + 开包移植系统教程.docx   ← 保留（教程集，README 相对链接指向 01–09）
├─ sn.img                                          ← 保留（.img 本体禁动）
└─ work\ release\ TB331FC\ yupei-ota_…\ extracted\ $dir\ $out\ docs\ scripts\ tools\ logs\ session_dump\ session_logs_extract\ backup\ TB331FC-OrangeFox\ liquid-glass\ .workbuddy-ai\   ← 全部原位不动
```

没有新建 `audit\`：根目录本轮**没有** `rom_audit_*.txt` 这类审计文本（它们在 `release\` 根下，越界未动），端口 trace 归 `logs\` 更准确。

### 3.2 已执行清单（32 个，全部 sha256 移动前后一致）

| 分类 | 文件 | 字节 | 理由 |
|---|---|---:|---|
| logs | `adb_out.txt` / `adb_err.txt` | 0 / 122 | 09-23 adb 采集输出，无引用 |
| logs | `qsahara_out.txt` / `qsahara_err.txt` | 0 / 0 | 09-25 QSaharaServer 输出，无引用 |
| logs | `log.txt` | 0 | 10-16 空文件 |
| logs | `port_trace.txt` | 2,841 | 11-25 07:36 fh_loader 写 misc 的日志；无 fh_loader 在跑，未被占用 |
| logs | `edl_gpt.log` / `edl_dbg.log` / `edl_full.log` / `edl_master_gpt.log` / `edl352_full.log` / `edl_noloader.log` | 246 / 1,878 / 219 / 219 / 1,878 / 139 | 09-26 EDL 调试与 GPT 备份日志 |
| archives | `dsh-session-session-{8e86f3f3,7366fc24,cff82b11,4e0d3c95,b43a23ec,de0ccc60}.zip` | 20.1 MB 合计 | DSH 会话导出；`session_dump\`、`session_logs_extract\` 有同批**解包版**，6 个 id 逐个核对都能对上 |
| misc | `_p.py` `_p2.py` `_p3.py` `_p4.py` `_p5.py` `_p6.py` `_p7.py` `_panic.py` `_scan2.py` `_mount.py` `_vb.py` `_vb2.py` | 8,024 合计 | 11-13 当天的一次性调试脚本 |
| misc | `pad_str.py` | 320 | 11-16 一次性字符串提取 |
| misc | `patch_bootfix.sh` | 617 | 09-23 设备端一次性补丁脚本（在手机上跑，不在盘上被调用） |

**没有删除任何文件；没有移动/改名任何目录；没有碰 `.img`/ROM 包本体（`sn.img` 原地、`TB331FC\刷机包` 与 `release\*FullKit*` 未动）。**

### 3.3 校验证据

- 基线：`work\dir-tidy\sha_before.tsv`（44 行：name / size / mtime / sha256）
- 每个文件 **Move 前 sha256 → Move 后 sha256 比对**，任一不一致即自动回滚并抛错（本轮 0 次触发）
- 移动完成后独立复核：MANIFEST 32 行逐行重算 sha256 与基线比对 → **rows=32 / mismatches=0**
- 结构复核：根目录 `dirs=18（17+_archive）/ files=12`；归档 `logs=12, misc=14, archives=6, 合计 21,081,148 B`
- 执行脚本（可复跑、只会搬不会删）：`work\dir-tidy\do_move.ps1`、`work\dir-tidy\make_manifest.ps1`

---

## 4. 因被引用/有链接而**留在原地**的清单

| 文件 | 谁依赖它 | 说明 |
|---|---|---|
| `README.md` | 自身是教程索引；`rom-workspace` skill 的「读文档顺序」指向根目录 README + 01–09 | 正文含 9 条**相对链接** `[01-刷机基础.md](01-刷机基础.md)` 等（README.md:7-15），整组搬家会全断 |
| `01-…09-*.md`（9 个） | 同上的 skill 路径描述 + README 相对链接 + 用户既定阅读顺序 | 属「整理好的教程」，不是散落物；如确要收进 `_archive\docs\`，需同步改 skill 与 README 链接，**超出本轮「安全移动」授权** |
| `开包移植系统教程.docx` | 无脚本引用；与 01–09 同批（10-07） | 保持与教程集同目录，便于对照 |
| `sn.img` | 无引用 | `.img` 本体按纪律不动；356 B，内容疑似 lenovo SN 片段，建议后续确认用途（可能是 `sn` 分区残留） |

> 真正意义上的「被脚本引用所以不能动」：**根目录 0 个**（§2 已逐个核实）。唯一相关的是 `verify_staging.ps1` 里那条**已悬空**的 `release\ZUI15-extract\images\port_trace.txt`，与本轮移动无关，也不建议为本轮去修它。

---

## 5. undo 用法（已双向实测）

```powershell
# 看计划，不动文件（任何机器/任何 shell 都可跑，纯 ASCII）
powershell -NoProfile -ExecutionPolicy Bypass -File E:\rom\_archive\undo.ps1 -DryRun

# 真的移回（会要求输入 YES 确认；加 -Force 跳过确认）
powershell -NoProfile -ExecutionPolicy Bypass -File E:\rom\_archive\undo.ps1
```

行为约定：

- 只 **Move-Item 回原位**，从不删除、从不覆盖：目标已存在 → `SKIP`；归档件缺失 → `MISS`；sha 与 MANIFEST 不符 → 拒移并报 `SHA` 差异。
- 逐条 sha256 校验（移动前后各一次），末尾打印 `rows / handled / skipped / problems`，`problems>0` 时退出码 3。
- 校验和：`undo.ps1` 2,959 B，非 ASCII 字节 **0**，`PSParser` parse error **0**；`MANIFEST.tsv` sha256 `687349DE1FF54F5C07B2AA7AD9FD2A785213B7957B38942BECEA196B32EC416F`。
- **实测往返**：先 `-DryRun`（32 行 PLAN，problems=0）→ 再真跑一次（32 条 `BACK`，根目录回到 44 文件，exit 0）→ 重新执行 `do_move.ps1` 与 `make_manifest.ps1` 复原到现在的状态（32 行、sha 全对）。所以「undo 可用」不是只靠 dry-run 推的。

注意：执行策略。本机 `CurrentUser=RemoteSigned` 但仍报「未签名」时，按上面写法带 `-ExecutionPolicy Bypass`；`do_move.ps1` / `make_manifest.ps1` 是 **UTF-8 with BOM**（PS 5.1 读中文需要 BOM，否则原因是乱码）。

---

## 6. 遗留与风险

1. `port_trace.txt` 下次跑 fh_loader（cwd = `E:\rom`）会在根目录**重新生成**——这是正常行为，不是回滚；届时要么不管它，要么再跑一次本套流程（`do_move.ps1` 会因为目标已存在于 `_archive\logs\` 而拒绝覆盖，需先 `undo` 或手工改名，脚本会明确报 `target exists`）。
2. 6 个会话 zip 属「会话导出」而非 ROM 包体；若判定 `.zip` 一律不挪，直接 `undo.ps1` 即可（或只手工把这 6 个搬回）。
3. `backup\` 是空目录，`backup\zui_stock\` 从未使用——要不要留壳由用户定，本轮未动。
4. 移动后 `E:` 剩余 **28.5 GB**（`Get-PSDrive E`，18:2x 实测）：本轮搬动不产生空间收益（.zip 只是换目录），真正空间在 `release\`（两个 3 GB FullKit zip + `tmp\`）和 `work\a17stage` 那 4 个与 FlashKit 重复的大镜像。

## 7. 后续建议（本轮授权之外，需用户/lead 拍板）

1. **`release\` 根目录那 11 个散文件**（`rom_audit_20261110.txt` 7.7K、`rom_audit_sizes.txt` 4.1K、`rom_avb_check.txt`/`rom_avb_check2.txt`、`rom_fam2.txt`、`scan_ctl_all.txt`、`ubuntu24_tools.txt`、`ubuntutb_inventory.txt`、`ubuntutb_predelete.txt`、`BDS-EFI-Probe.zip`）——它们其实是 `work\tools\rom_audit_20261110.py` 等脚本**约定的输出目录**（`_record_rom_audit_20261110.py:41-42` 写明输出在 `E:\rom\release\rom_audit_*.txt`），要动必须连脚本一起改，别单独搬。
2. `release\TB331FC_HyperOS4_A17_FullKit_v3.zip`(3.11 GB) + `v4.zip`(3.05 GB) 与解包目录同时存在，二选一可回收约 6 GB。
3. `release\tmp\` 的 `DiagOutputDir` / `dsh-workspace-changes-*` 约 4 GB，按 11-24 报告口径可清。
4. `work\a17stage` 的 4 个大镜像与 `release\…FlashKit\images\` 逐字节相同（8.68 G），留一份即可。
5. `sn.img` 用途确认后决定去留。
