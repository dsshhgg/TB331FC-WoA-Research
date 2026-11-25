$ErrorActionPreference = 'Continue'
$tok = $env:GH_TOKEN   # 原始脚本此处硬编码了 GitHub PAT，入库前已删除，改为读环境变量
$H = @{ Authorization = "token $tok"; 'User-Agent' = 'kernel-research' }
$dir = 'E:\rom\work\kernel-research'
function Tree($u) {
  try { return Invoke-RestMethod -Uri $u -Headers $H -TimeoutSec 180 } catch { Write-Host "ERR $u : $($_.Exception.Message)"; return $null }
}
"=== fetching LzwPluto tree ==="
$t1 = Tree 'https://api.github.com/repos/LzwPluto/linux-lenovo-tb331fc/git/trees/main?recursive=1'
if ($t1) { "  truncated=$($t1.truncated)  entries=$($t1.tree.Count)"; $t1.tree | Where-Object { $_.type -eq 'blob' } | ForEach-Object { "$($_.path)`t$($_.sha)" } | Set-Content "$dir\tree-lzwpluto.tsv" -Encoding UTF8 }
"=== fetching torvalds v6.15-rc1 tree ==="
$t2 = Tree 'https://api.github.com/repos/torvalds/linux/git/trees/v6.15-rc1?recursive=1'
if ($t2) { "  truncated=$($t2.truncated)  entries=$($t2.tree.Count)"; $t2.tree | Where-Object { $_.type -eq 'blob' } | ForEach-Object { "$($_.path)`t$($_.sha)" } | Set-Content "$dir\tree-v615rc1.tsv" -Encoding UTF8 }
Get-ChildItem "$dir\tree-*.tsv" | Select-Object Name,Length | Format-Table -AutoSize | Out-String
