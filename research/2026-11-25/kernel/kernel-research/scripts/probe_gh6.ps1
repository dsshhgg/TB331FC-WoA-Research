$ErrorActionPreference = 'Continue'
$tok = $env:GH_TOKEN   # 原始脚本此处硬编码了 GitHub PAT，入库前已删除，改为读环境变量
$H = @{ Authorization = "token $tok"; 'User-Agent' = 'kernel-research' }
$out = 'E:\rom\work\kernel-research\ref'
New-Item -ItemType Directory -Force -Path $out | Out-Null

function GH($u) { try { Invoke-RestMethod -Uri $u -Headers $H -TimeoutSec 60 } catch { Write-Host "ERR $u : $($_.Exception.Message)"; $null } }
function GetRaw($repo, $path, $saveAs) {
  $u = "https://api.github.com/repos/$repo/contents/$path"
  $r = GH $u
  if (-not $r) { "  MISSING: $repo/$path"; return }
  if ($r -is [array]) { "  path is dir: $repo/$path -> " + (($r | ForEach-Object { $_.name }) -join ', '); return }
  $bytes = [Convert]::FromBase64String($r.content)
  [System.IO.File]::WriteAllBytes("$out\$saveAs", $bytes)
  "  OK $repo/$path -> $saveAs  ($($bytes.Length) B, sha $($r.sha.Substring(0,10)))"
}

"=== A. assets repo: build/CANONICAL.dts + docs ==="
GetRaw 'LzwPluto/lenovo-tb331fc-mainline' 'build/CANONICAL.dts' 'CANONICAL.dts'
GetRaw 'LzwPluto/lenovo-tb331fc-mainline' 'WORKING-BOOT-RECIPE.md' 'WORKING-BOOT-RECIPE.md'

"`n=== B. kernel repo: pristine tb331fc.dts at main ==="
GetRaw 'LzwPluto/linux-lenovo-tb331fc' 'arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dts' 'repo-tb331fc.dts'

"`n=== C. assets repo top-level tree ==="
$t = GH 'https://api.github.com/repos/LzwPluto/lenovo-tb331fc-mainline/contents/'
if ($t) { $t | ForEach-Object { "  {0,-40} {1,-6} {2}" -f $_.name, $_.type, $_.size } }

"`n=== D. assets repo: any patch/config files? (2 levels) ==="
foreach ($d in @('build','tools','docs','config','patches')) {
  $x = GH "https://api.github.com/repos/LzwPluto/lenovo-tb331fc-mainline/contents/$d"
  if ($x -and $x -isnot [array]) { "  $d -> (file)" ; continue }
  if ($x) { "  $d/ : " + (($x | ForEach-Object { $_.name }) -join ', ') }
}
