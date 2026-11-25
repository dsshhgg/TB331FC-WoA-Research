# Regenerate E:\rom\_archive\MANIFEST.tsv with REAL tab separators (the first pass
# accidentally wrote a literal backtick-t because the format string was single quoted).
# Rebuilds from work\dir-tidy\sha_before.tsv and re-verifies every moved file's sha256.
$ErrorActionPreference = 'Stop'

$Root = 'E:\rom'
$Arc  = Join-Path $Root '_archive'
$Tidy = Join-Path $Root 'work\dir-tidy'
$Tab  = "`t"

$Cat = [ordered]@{}
foreach ($n in 'adb_out.txt','adb_err.txt','qsahara_out.txt','qsahara_err.txt','log.txt','port_trace.txt',
                 'edl_gpt.log','edl_dbg.log','edl_full.log','edl_master_gpt.log','edl352_full.log','edl_noloader.log') {
    $Cat[$n] = 'logs'
}
foreach ($n in '_p.py','_p2.py','_p3.py','_p4.py','_p5.py','_p6.py','_p7.py','_panic.py','_scan2.py',
                 '_mount.py','_vb.py','_vb2.py','pad_str.py','patch_bootfix.sh') {
    $Cat[$n] = 'misc'
}
foreach ($z in Get-ChildItem -LiteralPath (Join-Path $Arc 'archives') -File -Force) {
    $Cat[$z.Name] = 'archives'
}

$Reason = @{
  'adb_out.txt'      = '2026-09-23 adb 采集空输出，纯日志，无脚本引用'
  'adb_err.txt'      = '2026-09-23 adb 采集 stderr，纯日志，无脚本引用'
  'qsahara_out.txt'  = '2026-09-25 QSaharaServer 空输出，纯日志，无脚本引用'
  'qsahara_err.txt'  = '2026-09-25 QSaharaServer stderr，纯日志，无脚本引用'
  'log.txt'          = '2026-10-16 0 字节空日志，无脚本引用'
  'port_trace.txt'   = '2026-11-25 07:36 fh_loader 写 misc 的运行日志，无脚本引用'
  'edl_gpt.log'      = '2026-09-26 EDL 读 GPT 日志，无脚本引用'
  'edl_dbg.log'      = '2026-09-26 EDL 调试日志，无脚本引用'
  'edl_full.log'     = '2026-09-26 EDL 全量日志，无脚本引用'
  'edl_master_gpt.log' = '2026-09-26 EDL 备份 GPT 日志，无脚本引用'
  'edl352_full.log'  = '2026-09-26 EDL 1.352 全量日志（与 edl_dbg.log 同尺寸），无脚本引用'
  'edl_noloader.log' = '2026-09-26 EDL 缺 loader 失败日志，无脚本引用'
  '_p.py'            = '2026-11-13 一次性 900E 取证 grep 脚本，无脚本引用'
  '_p2.py'           = '2026-11-13 一次性调试脚本，无脚本引用'
  '_p3.py'           = '2026-11-13 一次性调试脚本，无脚本引用'
  '_p4.py'           = '2026-11-13 一次性调试脚本，无脚本引用'
  '_p5.py'           = '2026-11-13 一次性调试脚本，无脚本引用'
  '_p6.py'           = '2026-11-13 一次性调试脚本，无脚本引用'
  '_p7.py'           = '2026-11-13 一次性调试脚本，无脚本引用'
  '_panic.py'        = '2026-11-13 一次性 panic 分析脚本，无脚本引用'
  '_scan2.py'        = '2026-11-13 一次性扫描脚本，无脚本引用'
  '_mount.py'        = '2026-11-13 一次性挂载信息脚本，无脚本引用'
  '_vb.py'           = '2026-11-13 一次性 vbmeta 解析脚本，无脚本引用'
  '_vb2.py'          = '2026-11-13 一次性 vbmeta 解析脚本，无脚本引用'
  'pad_str.py'       = '2026-11-16 一次性 libmiinputflinger 字符串提取，无脚本引用'
  'patch_bootfix.sh' = '2026-09-23 设备端一次性 _boot_fix.sh 补丁脚本，无脚本引用'
}
foreach ($z in Get-ChildItem -LiteralPath (Join-Path $Arc 'archives') -File -Force) {
    $Reason[$z.Name] = 'DSH 会话导出 zip；session_dump\ 与 session_logs_extract\ 有同批解包版，无脚本引用'
}

$before = @{}
foreach ($r in (Import-Csv -LiteralPath (Join-Path $Tidy 'sha_before.tsv') -Delimiter $Tab)) {
    $before[$r.name] = $r
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add(('orig_path','new_path','size_bytes','mtime','sha256','category','reason') -join $Tab)

$bad = 0
foreach ($name in $Cat.Keys) {
    if (-not $before.ContainsKey($name)) { Write-Host "no baseline record: $name"; $bad++; continue }
    $dst = Join-Path (Join-Path $Arc $Cat[$name]) $name
    if (-not (Test-Path -LiteralPath $dst -PathType Leaf)) { Write-Host "missing in archive: $dst"; $bad++; continue }
    $fi = Get-Item -LiteralPath $dst
    $sha = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
    if ($sha -ne $before[$name].sha256) { Write-Host "SHA DRIFT: $name"; $bad++; continue }
    $lines.Add((('E:\rom\' + $name), $dst, [string]$fi.Length, $fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), $sha, $Cat[$name], $Reason[$name]) -join $Tab)
}

if ($bad -gt 0) { throw "manifest rebuild aborted, $bad problem(s)" }

$utf8bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText((Join-Path $Arc 'MANIFEST.tsv'), (($lines -join "`r`n") + "`r`n"), $utf8bom)

"rows written = $($lines.Count - 1)"
$check = [System.IO.File]::ReadAllLines((Join-Path $Arc 'MANIFEST.tsv'), [System.Text.Encoding]::UTF8)
"line0 fields = $((($check[0] -split $Tab).Count))"
"line1 fields = $((($check[1] -split $Tab).Count))"
$check[0]
$check[1]
