$ErrorActionPreference='Continue'
$tok=$env:GH_TOKEN   # 原始脚本此处硬编码了 GitHub PAT，入库前已删除，改为读环境变量
$H=@{Authorization="token $tok";'User-Agent'='kr'}
function T($p,$ref='master'){ try{$r=Invoke-RestMethod -Uri "https://api.github.com/repos/torvalds/linux/contents/$p?ref=$ref" -Headers $H -TimeoutSec 30; "EXISTS $($r.size)B"}catch{"ABSENT(HTTP$($_.Exception.Response.StatusCode.value__))"} }
foreach($f in @(
 'sound/soc/codecs/aw88166.c',
 'drivers/video/backlight/ktz8866.c',
 'drivers/usb/typec/tcpm/tcpci_rt1711h.c',
 'drivers/input/touchscreen/novatek-nvt-ts.c',
 'drivers/gpu/drm/panel/panel-himax-hx83102.c',
 'drivers/power/supply/mm8013.c',
 'drivers/gpu/drm/panel/panel-novatek-nt36523.c',
 'drivers/mfd/qcom-spmi-pmic.c',
 'sound/soc/qcom/sm8250.c',
 'sound/soc/qcom/lpass-cdc-dma.c',
 'drivers/gpu/drm/msm/adreno/a6xx_gmu.c',
 'drivers/net/wireless/ath/ath10k/wcn3990.c'
)){ "{0,-52} {1}" -f $f, (T $f) }
