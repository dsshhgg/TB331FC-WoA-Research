$ErrorActionPreference = 'Continue'
$tok = $env:GH_TOKEN   # 原始脚本此处硬编码了 GitHub PAT，入库前已删除，改为读环境变量
$H = @{ Authorization = "token $tok"; 'User-Agent' = 'kernel-research' }

function GH($path) {
  try {
    return Invoke-RestMethod -Uri "https://api.github.com$path" -Headers $H -TimeoutSec 40
  } catch {
    return [pscustomobject]@{ __error = $_.Exception.Message }
  }
}

"=== rate limit ==="
$r = GH '/rate_limit'
if ($r.__error) { "ERR: $($r.__error)" } else { "core: $($r.resources.core.remaining)/$($r.resources.core.limit)" }

"`n=== when did sm6225.dtsi first appear? (oldest commits, torvalds/linux) ==="
$c = GH '/repos/torvalds/linux/commits?path=arch/arm64/boot/dts/qcom/sm6225.dtsi&per_page=100'
if ($c.__error) { "ERR: $($c.__error)" } else {
  "commit count returned: $($c.Count)"
  $c | Select-Object -Last 3 | ForEach-Object {
    "{0}  {1}  {2}" -f $_.commit.author.date, $_.sha.Substring(0,12), ($_.commit.message -split "`n")[0]
  }
}

"`n=== sm6115.dtsi history (oldest) ==="
$c2 = GH '/repos/torvalds/linux/commits?path=arch/arm64/boot/dts/qcom/sm6115.dtsi&per_page=100'
if ($c2.__error) { "ERR: $($c2.__error)" } else {
  "commit count returned: $($c2.Count)"
  $c2 | Select-Object -Last 3 | ForEach-Object {
    "{0}  {1}  {2}" -f $_.commit.author.date, $_.sha.Substring(0,12), ($_.commit.message -split "`n")[0]
  }
}
