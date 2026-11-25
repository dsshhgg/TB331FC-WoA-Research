$ErrorActionPreference='Continue'
$tok=$env:GH_TOKEN   # 原始脚本此处硬编码了 GitHub PAT，入库前已删除，改为读环境变量
$H=@{Authorization="token $tok";'User-Agent'='kr'}
$out='E:\rom\work\kernel-research\ref'
function Grab($repo,$path,$ref,$saveAs){
  $u="https://api.github.com/repos/$repo/contents/" + $path + "?ref=" + $ref
  try{
    $r=Invoke-RestMethod -Uri $u -Headers $H -TimeoutSec 60
    [System.IO.File]::WriteAllBytes("$out\$saveAs",[Convert]::FromBase64String($r.content))
    "OK $saveAs ($($r.size)B)"
  }catch{"MISSING $path @ $ref (HTTP$($_.Exception.Response.StatusCode.value__))"}
}
"=== upstream sm6115.dtsi at v6.6 / v6.12 / v6.14 ==="
Grab 'torvalds/linux' 'arch/arm64/boot/dts/qcom/sm6115.dtsi' 'v6.6'  'sm6115-v6.6.dtsi'
Grab 'torvalds/linux' 'arch/arm64/boot/dts/qcom/sm6115.dtsi' 'v6.12' 'sm6115-v6.12.dtsi'
Grab 'torvalds/linux' 'arch/arm64/boot/dts/qcom/sm6115.dtsi' 'v6.14' 'sm6115-v6.14.dtsi'
"=== upstream panel/phy drivers presence ==="
foreach($x in @(
  @('drivers/gpu/drm/panel/panel-novatek-nt36523.c','v6.14'),
  @('drivers/phy/qualcomm/phy-qcom-qmp-ufs.c','v6.0'),
  @('drivers/gpu/drm/msm/msm_mdss.c','v6.0'),
  @('arch/arm64/boot/dts/qcom/sm6115.dtsi','v6.0'),
  @('drivers/clk/qcom/dispcc-sm6115.c','v6.0'),
  @('drivers/clk/qcom/gpucc-sm6115.c','v6.0'),
  @('drivers/phy/qualcomm/phy-qcom-qmp-ufs.c','v6.6')
)){
  $u="https://api.github.com/repos/torvalds/linux/contents/" + $x[0] + "?ref=" + $x[1]
  try{ $r=Invoke-RestMethod -Uri $u -Headers $H -TimeoutSec 30; "{0,-55} @{1,-6} EXISTS {2}B" -f $x[0],$x[1],$r.size }
  catch{ "{0,-55} @{1,-6} ABSENT" -f $x[0],$x[1] }
}
