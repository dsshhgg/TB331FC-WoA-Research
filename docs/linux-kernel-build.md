TB331FC (khaje) mainline Linux 内核 —— 蓝牙/音频补丁版
================================================================
构建时间: 2026-11-24 19:14
内核版本: 6.14.0-rc5-next-20250306
Image sha256: d145291d59753f462b8ec70551a29372d29c98f74ce382295490ff48f84b4499

【本版改了什么】
1. CONFIG_SOUND=y / CONFIG_SND=y / CONFIG_SND_SOC=y
   —— 原 .config 是 "# CONFIG_SOUND is not set"，整个 ALSA/ASoC 不存在，扬声器必然没声
2. CONFIG_BT_LE=y —— 原来未开，BLE 外设全不可用
3. DTS: model / compatible 改成 TB331FC（原来是 tb128 / "Lenovo Tab M10 Plus 3rd gen"）
4. DTS: 蓝牙 compatible 从 qcom,wcn3990-bt 改为 qcom,wcn3988-bt
   —— 依据：设备固件是 apbtfw11.tlv/apnv11.bin，而 btqca.c 里 ap 前缀 = QCA_WCN3988
5. DTS: 固件路径去掉 qcom/sm6225/LENOVO/TB128FU/ 前缀（设备上固件是平铺的）
6. 修了源码自身两处缺陷：syscall_64.tbl 符号链接（zip 解压损坏）、hci_qca.c 函数先用后声明

【产物】
Image-6.14.0-rc5-tb331fc        未压缩内核 37.2 MB
Image.gz                        压缩内核 13.4 MB
boot-v3-linux.img               Android boot v3 头（page 4096）可直刷 boot_b
sm6225-lenovo-tb331fc.dtb       设备树 69 KB
config-6.14.0-rc5-tb331fc       本次生效的完整 .config

【刷入（README 原文规矩：只刷 B 槽，绝不动 A 槽）】
  fastboot flash boot_b boot-v3-linux.img
  fastboot flash vendor_boot_b <你的 Linux vendor_boot.img>   ← 本包不含，需用你的 Linux 系统镜像里那份
  fastboot --set-active=b
  fastboot reboot
回滚:  fastboot --set-active=a

【蓝牙还需要一步：拷固件】
在 Linux 系统的 /lib/firmware/qca/ 下放两个文件（从 Android 侧取）:
  apbtfw11.tlv   ← /vendor/bt_firmware/image/apbtfw11.tlv
  apnv11.bin     ← /vendor/bt_firmware/image/apnv11.bin
放好后 dmesg 应出现 hci0；若 rom_ver 不是 0x11，驱动会去找 apbtfwXX.tlv 对应版本。

【音频现状（诚实说明）】
本版只是把 ALSA/ASoC 子系统编进去了 + 修了 DTS 的 codec 节点引用路径。
「能出声」还差两步：
  1) ADSP 固件：DTS 里 adsp 的 firmware-name 现在指向设备实际的 adsp.mdt（需在 Linux rootfs 的
     /lib/firmware/ 下提供），否则 remoteproc 起不来（/sys/class/remoteproc/*/state 应为 running）
  2) machine driver / codec 绑定：设备是 2× AW883xx + WCD937x，需确认 mainline 的
     sound/soc/qcom 里有没有对应 machine 驱动；DTS 属性名要与驱动一致
