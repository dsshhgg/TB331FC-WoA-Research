$ErrorActionPreference = 'Continue'
$tok = $env:GH_TOKEN   # 原始脚本此处硬编码了 GitHub PAT，入库前已删除，改为读环境变量
$H = @{ Authorization = "token $tok"; 'User-Agent' = 'kernel-research' }

function TryFile($ref, $p) {
  $u = "https://api.github.com/repos/torvalds/linux/contents/$p" + "?ref=$ref"
  try {
    $r = Invoke-RestMethod -Uri $u -Headers $H -TimeoutSec 40
    return [pscustomobject]@{ ok = $true; size = $r.size }
  } catch { return [pscustomobject]@{ ok = $false; size = 0 } }
}

"=== pin down sm6115.dtsi landing (v6.2..v6.5) + sm4250 ==="
foreach ($ref in @('v6.2','v6.3','v6.4','v6.5')) {
  $a = TryFile $ref 'arch/arm64/boot/dts/qcom/sm6115.dtsi'
  $b = TryFile $ref 'arch/arm64/boot/dts/qcom/sm4250.dtsi'
  $c = TryFile $ref 'arch/arm64/boot/dts/qcom/sm6115p-lenovo-j606f.dts'
  "{0,-6} sm6115.dtsi={1,-5}({2})  sm4250.dtsi={3,-5}({4})  j606f={5,-5}" -f $ref,$a.ok,$a.size,$b.ok,$b.size,$c.ok
}

"`n=== master qcom dts: every sm6* / bengal-ish entry ==="
$j = Invoke-RestMethod -Uri 'https://api.github.com/repos/torvalds/linux/contents/arch/arm64/boot/dts/qcom?ref=master' -Headers $H -TimeoutSec 60
$j | Where-Object { $_.name -match '^sm6|bengal|khaje' } | Sort-Object name | ForEach-Object { "{0,-45} {1,8}" -f $_.name, $_.size }

"`n=== sm4250.dtsi content (487B: what is it?) ==="
$c = Invoke-RestMethod -Uri 'https://api.github.com/repos/torvalds/linux/contents/arch/arm64/boot/dts/qcom/sm4250.dtsi?ref=v6.6' -Headers $H -TimeoutSec 40
[System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($c.content))
