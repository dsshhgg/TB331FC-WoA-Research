# kernel-re —— 原厂 5.15 内核逆向（2026-11-25）

> 本轮该目录**只产出取证产物，没有写 REPORT.md**（报告缺口因此在本索引里如实记录，而不是把产物当结论）。
> 原始工作目录：`E:\rom\work\kernel-re\`

## 产物

| 文件 | 字节 | 是什么 |
|---|---|---|
| [out/a17-ikconfig.txt](out/a17-ikconfig.txt) | 188,624 | 从 A17（HyperOS 4）现役 `boot_a` 内核里提取的**完整 `.config`**（6610 行）：`Linux/arm64 5.15.167 Kernel Configuration`，clang 17.0.4 + LLD，`CONFIG_CC_IS_CLANG=y`。判断「设备内核开了什么」的一手材料，不是转述 |
| [out/strings-key.txt](out/strings-key.txt) | 189,264 | kernel blob 的**按主题分节的字符串索引**（4760 行）。格式 `<文件偏移> <字符串>`，文件偏移 0 == VMA `0xffffffc008000000`。分节含「构建身份 / vermagic 与模块版本」等 |
| [out/kallsyms.py](out/kallsyms.py) | 7,991 | **独立 kallsyms 解析器**：只靠 raw kernel blob + Python stdlib，不依赖 Ghidra/IDA/ELF，按 `scripts/kallsyms.c` 的 base-relative 布局（`kallsyms_offsets[]` / `relative_base` / `num_syms` / 压缩 `names[]`）抽表 |

## 已知事实（来自上面两份产物，可直接引用）

- 设备内核构建串：`Linux version 5.15.167-android13-5.15.167_r00-dirty (runner@runnervmliwqe) (clang version 17.0.4 …, LLD 17.0.4) #1 SMP PREEMPT Sun Aug 9 16:49:46 UTC 2026`
- 与 `kernel/overclock/REPORT.md` 的取证是同一位的内核（`CONFIG_CFI_CLANG=y` / `CONFIG_LTO_CLANG_FULL=y` / `CONFIG_MODULE_SIG=y`，`SIG_FORCE` 未开）—— 那条报告里「模块改频做不到」的结论就是建立在这套配置上的。

## 未上传

`System.map` 类大转储、内核 blob 本体、`__pycache__` 未上传（体积/派生产物）。需要时用 `kallsyms.py` 对 `boot_a` 内核原地重生成。
