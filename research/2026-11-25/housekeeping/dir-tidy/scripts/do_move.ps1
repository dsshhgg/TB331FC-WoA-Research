# E:\rom root tidy (Windows PowerShell 5.1 compatible; file must be saved as UTF-8 WITH BOM) -- move unreferenced text/log/archive files into E:\rom\_archive
# Safety rules: move only, never delete, never touch directories, verify sha256 before/after.
$ErrorActionPreference = 'Stop'

$Root = 'E:\rom'
$Arc  = Join-Path $Root '_archive'
$Tidy = Join-Path $Root 'work\dir-tidy'

$Logs = @(
  'adb_out.txt','adb_err.txt','qsahara_out.txt','qsahara_err.txt','log.txt','port_trace.txt',
  'edl_gpt.log','edl_dbg.log','edl_full.log','edl_master_gpt.log','edl352_full.log','edl_noloader.log'
)
$Misc = @(
  '_p.py','_p2.py','_p3.py','_p4.py','_p5.py','_p6.py','_p7.py','_panic.py','_scan2.py',
  '_mount.py','_vb.py','_vb2.py','pad_str.py','patch_bootfix.sh'
)
$Archives = @(
  'dsh-session-session-8e86f3f3-ad98-43ec-ad3f-186fc868cb0d.zip',
  'dsh-session-session-7366fc24-9d7a-42e2-9e1e-ae794d50b2fc.zip',
  'dsh-session-session-cff82b11-7161-4030-9b79-495a52a5f43a.zip',
  'dsh-session-session-4e0d3c95-e948-451f-9c50-9554a7a2e4a5.zip',
  'dsh-session-session-b43a23ec-effb-4388-b2de-7000202204eb.zip',
  'dsh-session-session-de0ccc60-3b13-45e7-a63c-95cfef84e524.zip'
)

$Reason = @{
  'adb_out.txt'   = '2026-09-23 adb 采集空输出，纯日志，无脚本引用'
  'adb_err.txt'   = '2026-09-23 adb 采集 stderr，纯日志，无脚本引用'
  'qsahara_out.txt' = '2026-09-25 QSaharaServer 空输出，纯日志，无脚本引用'
  'qsahara_err.txt' = '2026-09-25 QSaharaServer stderr，纯日志，无脚本引用'
  'log.txt'       = '2026-10-16 0 字节空日志，无脚本引用'
  'port_trace.txt' = '2026-11-25 07:36 fh_loader 写 misc 的运行日志，无脚本引用'
  'edl_gpt.log'   = '2026-09-26 EDL 读 GPT 日志，无脚本引用'
  'edl_dbg.log'   = '2026-09-26 EDL 调试日志，无脚本引用'
  'edl_full.log'  = '2026-09-26 EDL 全量日志，无脚本引用'
  'edl_master_gpt.log' = '2026-09-26 EDL 备份 GPT 日志，无脚本引用'
  'edl352_full.log' = '2026-09-26 EDL 1.352 全量日志（与 edl_dbg.log 同尺寸），无脚本引用'
  'edl_noloader.log' = '2026-09-26 EDL 缺 loader 失败日志，无脚本引用'
  '_p.py'         = '2026-11-13 一次性 900E 取证 grep 脚本，无脚本引用'
  '_p2.py'        = '2026-11-13 一次性调试脚本，无脚本引用'
  '_p3.py'        = '2026-11-13 一次性调试脚本，无脚本引用'
  '_p4.py'        = '2026-11-13 一次性调试脚本，无脚本引用'
  '_p5.py'        = '2026-11-13 一次性调试脚本，无脚本引用'
  '_p6.py'        = '2026-11-13 一次性调试脚本，无脚本引用'
  '_p7.py'        = '2026-11-13 一次性调试脚本，无脚本引用'
  '_panic.py'     = '2026-11-13 一次性 panic 分析脚本，无脚本引用'
  '_scan2.py'     = '2026-11-13 一次性扫描脚本，无脚本引用'
  '_mount.py'     = '2026-11-13 一次性挂载信息脚本，无脚本引用'
  '_vb.py'        = '2026-11-13 一次性 vbmeta 解析脚本，无脚本引用'
  '_vb2.py'       = '2026-11-13 一次性 vbmeta 解析脚本，无脚本引用'
  'pad_str.py'    = '2026-11-16 一次性 libmiinputflinger 字符串提取，无脚本引用'
  'patch_bootfix.sh' = '2026-09-23 设备端一次性 _boot_fix.sh 补丁脚本，无脚本引用'
}

foreach ($z in $Archives) {
  $Reason[$z] = 'DSH 会话导出 zip；session_dump\ 与 session_logs_extract\ 有同批解包版，无脚本引用'
}

$Plan = @()
foreach ($n in $Logs)     { $Plan += [pscustomobject]@{ Name = $n; Cat = 'logs' } }
foreach ($n in $Misc)     { $Plan += [pscustomobject]@{ Name = $n; Cat = 'misc' } }
foreach ($n in $Archives) { $Plan += [pscustomobject]@{ Name = $n; Cat = 'archives' } }

foreach ($c in 'logs','misc','archives') {
  $p = Join-Path $Arc $c
  if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
}

$Rows = New-Object System.Collections.Generic.List[object]
foreach ($item in $Plan) {
  $src = Join-Path $Root $item.Name
  if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "missing source: $src" }
  $dstDir = Join-Path $Arc $item.Cat
  $dst = Join-Path $dstDir $item.Name
  if (Test-Path -LiteralPath $dst) { throw "target exists, refuse to overwrite: $dst" }

  $fi = Get-Item -LiteralPath $src
  $size = $fi.Length
  $mtime = $fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
  $sha1 = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
  Move-Item -LiteralPath $src -Destination $dst
  if (-not (Test-Path -LiteralPath $dst -PathType Leaf)) { throw "move failed: $dst" }
  $sha2 = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
  if ($sha1 -ne $sha2) {
    Move-Item -LiteralPath $dst -Destination $src
    throw "sha mismatch, rolled back: $src"
  }
  $Rows.Add([pscustomobject]@{
    orig_path   = $src
    new_path    = $dst
    size_bytes  = $size
    mtime       = $mtime
    sha256      = $sha1
    category    = $item.Cat
    reason      = $Reason[$item.Name]
  })
  'MOVED  {0}  ->  _archive\{1}\  ({2} B)' -f $item.Name, $item.Cat, $size
}

$Manifest = Join-Path $Arc 'MANIFEST.tsv'
$Tab = "`t"
$lines = @(('orig_path','new_path','size_bytes','mtime','sha256','category','reason') -join $Tab)
foreach ($r in $Rows) {
  $lines += (($r.orig_path, $r.new_path, [string]$r.size_bytes, $r.mtime, $r.sha256, $r.category, $r.reason) -join $Tab)
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Manifest, (($lines -join "`r`n") + "`r`n"), $utf8)

"`nmanifest rows = $($Rows.Count)"
"root files left = $((Get-ChildItem -LiteralPath $Root -File -Force).Count)"
