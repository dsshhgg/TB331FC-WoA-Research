$ErrorActionPreference = 'Continue'
$tok = $env:GH_TOKEN   # 原始脚本此处硬编码了 GitHub PAT，入库前已删除，改为读环境变量
$H = @{ Authorization = "token $tok"; 'User-Agent' = 'kernel-research' }
function GH($u) { try { Invoke-RestMethod -Uri $u -Headers $H -TimeoutSec 45 } catch { $null } }

foreach ($repo in @('LzwPluto/linux-lenovo-tb331fc','LzwPluto/lenovo-tb331fc-mainline')) {
  "############ $repo ############"
  $r = GH "https://api.github.com/repos/$repo"
  if (-not $r) { "  (API returned nothing)"; continue }
  "  default_branch : $($r.default_branch)"
  "  size(KB)       : $($r.size)"
  "  pushed_at      : $($r.pushed_at)"
  "  updated_at     : $($r.updated_at)"
  "  created_at     : $($r.created_at)"
  "  description    : $($r.description)"
  $br = GH "https://api.github.com/repos/$repo/branches?per_page=100"
  if ($br) { "  branches       : " + (($br | ForEach-Object { $_.name }) -join ', ') }
  $cm = GH "https://api.github.com/repos/$repo/commits?per_page=5"
  if ($cm) {
    "  last commits:"
    foreach ($c in $cm) { "    {0}  {1}  {2}" -f $c.commit.author.date, $c.sha.Substring(0,10), (($c.commit.message -split "`n")[0]) }
  }
  ""
}
