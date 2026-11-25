$ErrorActionPreference='Continue'
$tok=$env:GH_TOKEN   # 原始脚本此处硬编码了 GitHub PAT，入库前已删除，改为读环境变量
$H=@{Authorization="token $tok";'User-Agent'='kr'}
$out='E:\rom\work\kernel-research\ref'
function Grab($repo,$path,$ref,$saveAs){
  $u="https://api.github.com/repos/$repo/contents/" + $path + "?ref=" + $ref
  try{ $r=Invoke-RestMethod -Uri $u -Headers $H -TimeoutSec 60
       [System.IO.File]::WriteAllBytes("$out\$saveAs",[Convert]::FromBase64String($r.content)); "OK $saveAs ($($r.size)B)"; }
  catch{"MISSING $path @ $ref"}
}
Grab 'torvalds/linux' 'arch/arm64/boot/dts/qcom/sm6115p-lenovo-j606f.dts' 'v6.14' 'j606f-v6.14.dts'
Grab 'torvalds/linux' 'arch/arm64/boot/dts/qcom/sm6115-xiaomi-lemon.dts' 'master' 'lemon-master.dts'
Grab 'LzwPluto/lenovo-tb331fc-mainline' 'TB331FC-FULL-PORT-GUIDE.md' 'main' 'TB331FC-FULL-PORT-GUIDE.md'
Grab 'LzwPluto/lenovo-tb331fc-mainline' 'HANDOVER.md' 'main' 'HANDOVER.md'
