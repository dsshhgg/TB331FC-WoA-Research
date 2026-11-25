$ErrorActionPreference='Continue'
$tok=$env:GH_TOKEN   # 原始脚本此处硬编码了 GitHub PAT，入库前已删除，改为读环境变量
$H=@{Authorization="token $tok";'User-Agent'='kr'}
function Oldest($p){
  $u="https://api.github.com/repos/torvalds/linux/commits?path=$p&per_page=100"
  try{
    $c=Invoke-RestMethod -Uri $u -Headers $H -TimeoutSec 40
    if(-not $c -or $c.Count -eq 0){ return "NEVER (no commits)" }
    $o=$c[-1]
    "{0}  {1}" -f $o.commit.author.date.ToString('yyyy-MM-dd'), (($o.commit.message -split "`n")[0])
  }catch{ "ERR $($_.Exception.Response.StatusCode.value__)" }
}
$paths=@(
 'arch/arm64/boot/dts/qcom/sm6115.dtsi',
 'arch/arm64/boot/dts/qcom/sm6115p-lenovo-j606f.dts',
 'drivers/clk/qcom/gcc-sm6115.c',
 'drivers/gpu/drm/panel/panel-himax-hx83102.c',
 'drivers/video/backlight/ktz8866.c',
 'drivers/power/supply/mm8013.c',
 'drivers/input/touchscreen/novatek-nvt-ts.c',
 'drivers/net/wireless/ath/ath10k/snoc.c',
 'drivers/bluetooth/btqca.c',
 'drivers/gpu/drm/msm/adreno/a6xx_gpu.c',
 'drivers/phy/qualcomm/phy-qcom-qmp-ufs.c',
 'drivers/usb/typec/tcpm/tcpci_rt1711h.c',
 'drivers/iio/imu/bmi323/bmi323_core.c',
 'drivers/mfd/qcom-spmi-pmic.c'
)
"path | first commit (yyyy-MM-dd) | subject"
foreach($p in $paths){ "{0,-58} {1}" -f $p, (Oldest $p) }
