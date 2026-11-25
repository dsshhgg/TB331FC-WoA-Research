# out\payload\

方案 2（改 APK 版）用的注入源目录。默认是空的 —— 因为本次结论是**不重签、不改 APK**。

要用的时候把重签好的 APK 放这里，文件名必须是：

    MIUIPackageInstallerVariants.apk

然后跑：

    ..\bake\rebake-installer.ps1

对照检查清单（缺一条就别刷）：
1. `apksigner verify --print-certs` 能过，且 signer 是 testkey（sha256 ≠ C9:00:9D:01…，这是必然的）
2. manifest 里 `versionCode` > 55402（真机 /data 那份是 55402，否则系统副本赢不了）
3. 重签前先备份原始：`work\MIUIPackageInstallerVariants.apk`（sha256 25d66a04…，已存）
4. 刷完要 `pm uninstall-system-updates com.miui.packageinstaller` 或清 /data/app 里旧签名副本
