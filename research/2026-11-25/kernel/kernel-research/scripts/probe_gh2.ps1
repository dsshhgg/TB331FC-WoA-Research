$ErrorActionPreference = 'Continue'
$tok = $env:GH_TOKEN   # 原始脚本此处硬编码了 GitHub PAT，入库前已删除，改为读环境变量
$H = @{ Authorization = "token $tok"; 'User-Agent' = 'kernel-research' }

function TryFile($ref, $p) {
  $u = "https://api.github.com/repos/torvalds/linux/contents/$p" + "?ref=$ref"
  try {
    $r = Invoke-RestMethod -Uri $u -Headers $H -TimeoutSec 40
    return [pscustomobject]@{ ref = $ref; file = $p; exists = $true; size = $r.size; sha = $r.sha.Substring(0,10) }
  } catch {
    $code = $_.Exception.Response.StatusCode.value__
    return [pscustomobject]@{ ref = $ref; file = $p; exists = $false; size = 0; sha = "HTTP$code" }
  }
}

$files = @(
  'arch/arm64/boot/dts/qcom/sm6225.dtsi',
  'arch/arm64/boot/dts/qcom/sm6115.dtsi',
  'arch/arm64/boot/dts/qcom/sm6115p-lenovo-j606f.dts',
  'arch/arm64/boot/dts/qcom/sm6115-fxtec-pro1x.dts',
  'arch/arm64/boot/dts/qcom/sm4250.dtsi',
  'arch/arm64/boot/dts/qcom/sm6125.dtsi',
  'arch/arm64/boot/dts/qcom/sm6375.dtsi'
)
$refs = @('v6.0','v6.1','v6.6','v6.12','v6.14','master')

$rows = @()
foreach ($ref in $refs) {
  foreach ($f in $files) {
    $rows += TryFile $ref $f
  }
}
$rows | ForEach-Object { "{0,-9} {1,-52} exists={2,-5} size={3,-7} {4}" -f $_.ref, $_.file, $_.exists, $_.size, $_.sha }
