# =============================================================================
#  of-pipeline / recovery experiment runner   (TB331FC  serial 5e367954)
#  ASCII ONLY on purpose (PS 5.1 + cp936 console).
#
#  Every fastboot invocation is pinned with -s 5e367954 because a second device
#  (HF06872291105783) shows up in this host's fastboot list.
#
#  Order of operations for one experiment (nothing else on the device is touched):
#     1. flash a pristine misc image   -> clears any lingering boot-recovery BCB
#     2. fastboot flash <partition> <image>
#     3. fastboot reboot-recovery
#     4. classify the outcome by timing + adb polling
#     5. ALWAYS: flash the stock recovery image back, clear misc, reboot
#     6. optional: boot stock recovery once and pull /sys/fs/pstore/console-ramoops*
#
#  Usage
#     .\run_experiments.ps1 -List
#     .\run_experiments.ps1 -Phase exp1a            # dry run: prints the steps only
#     .\run_experiments.ps1 -Phase exp1a -Execute   # really flashes
#     .\run_experiments.ps1 -Phase exp2b -Execute -CollectPstore
#     .\run_experiments.ps1 -RollbackOnly -Execute
#
#  Exit codes: 0 = experiment ran (any result), 2 = precondition failed, 3 = rollback failed
# =============================================================================

[CmdletBinding()]
param(
    [ValidateSet('list','exp1a','exp1b','exp1c','exp1d','exp2a','exp2b','exp2c','rollback')]
    [string]$Phase = 'list',

    [switch]$Execute,
    [switch]$CollectPstore,
    [switch]$RollbackOnly,
    [string]$Serial = '5e367954',
    [string]$Partition = 'recovery_a',

    [string]$OutDir     = 'E:\rom\work\of-pipeline',
    [string]$StockImage = 'E:\rom\work\dual-boot\backup\recovery_a.bin',
    [string]$MiscImage  = 'E:\rom\work\rescue-matrix\reads\misc_full.bin',
    [string]$Fastboot   = 'E:\rom\tools\platform-tools\fastboot.exe',
    [string]$Adb        = 'E:\rom\tools\platform-tools\adb.exe'
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logDir = Join-Path $OutDir 'logs'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ("run_" + $stamp + ".log")

function L([string]$m) {
    $line = ('[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $m)
    Write-Host $line
    [System.IO.File]::AppendAllText($logFile, $line + "`r`n", $utf8)
}

function Fail([string]$m) { L ('FATAL: ' + $m); exit 2 }

# ---------------------------------------------------------------- inventory ---
$Images = [ordered]@{
    'exp1a' = @{ File = 'out\exp1a_stock_clone.img';   Desc = 'stock ramdisk VERBATIM (must be byte-identical to stock, control)'; Exp = 'boots -> header/flash path is fine' }
    'exp1b' = @{ File = 'out\exp1b_hello_lz4.img';     Desc = 'stock ramdisk + /hello.txt, re-packed by us, lz4 -l -12';           Exp = 'boots -> our cpio surgery + lz4 are valid, OF content is the problem' }
    'exp1c' = @{ File = 'out\exp1c_zstd_stock.img';    Desc = 'stock ramdisk content, zstd -19 (8.13 MB)';                        Exp = 'boots -> zstd initramfs works, compression format is NOT the OF culprit' }
    'exp1d' = @{ File = 'out\exp1d_gzip_stock.img';    Desc = 'stock ramdisk content, gzip -9 (12.52 MB)';                        Exp = 'boots -> gzip works as well' }
    'exp2a' = @{ File = 'out\exp2a_mintel.img';        Desc = 'our own minimal init + adbd (busybox static, no Android init)';     Exp = 'adb devices lists recovery -> we can drive the device from user space' }
    'exp2b' = @{ File = 'out\exp2b_of_beacon.img';     Desc = 'OrangeFox slim ramdisk with /init replaced by the kmsg beacon';     Exp = 'beacon in pstore -> initramfs reached user space; OF init/recovery is what dies' }
    'exp2c' = @{ File = 'out\exp2c_stock_beacon.img';  Desc = 'STOCK content + the same beacon /init, lz4 (control for exp2b)';   Exp = 'beacon in pstore -> our repack+beacon method is sound, so exp2b is interpretable' }
}

function Show-Inventory {
    L '--- image inventory -------------------------------------------------'
    foreach ($k in $Images.Keys) {
        $p = Join-Path $OutDir $Images[$k].File
        if (Test-Path -LiteralPath $p) {
            $f = Get-Item -LiteralPath $p
            $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.Substring(0, 16)
            $rd = [int]$f.Length - 4096
            L ('{0}: {1,12} bytes  sha256:{2}  ramdisk~{3,11}  {4}' -f $k, $f.Length, $h, $rd, $Images[$k].Desc)
        } else {
            L ('{0}: MISSING  {1}' -f $k, $p)
        }
    }
    L '--- ladder -----------------------------------------------------------'
    L 'exp1a first. If exp1a does not boot, stop: the flash path itself is broken.'
    L 'then exp1b (our lz4 + added file) and exp1c (zstd) / exp1d (gzip) for the format question.'
    L 'then exp2c (stock content + beacon, lz4) BEFORE exp2b (OF content + beacon, zstd).'
    L 'then exp2a (our own init/adbd) whenever you want adb without Android init.'
    L 'read pstore after every HUNG verdict: run the script again with -CollectPstore.'
}

# ----------------------------------------------------------------- helpers ----
function Invoke-FB([string[]]$fbArgs, [int]$timeout = 120) {
    $all = @('-s', $Serial) + $fbArgs
    $cmdline = ('fastboot ' + ($all -join ' '))
    L ('  $ ' + $cmdline)
    if (-not $Execute) { return @{ ExitCode = 0; Out = 'DRY-RUN' } }
    $p = Start-Process -FilePath $Fastboot -ArgumentList $all -NoNewWindow -PassThru `
                       -RedirectStandardOutput ($logDir + '\fb_out.tmp') `
                       -RedirectStandardError  ($logDir + '\fb_err.tmp')
    if (-not $p.WaitForExit($timeout * 1000)) { try { $p.Kill() } catch {}; L '  !! fastboot timeout'; return @{ ExitCode = 124; Out = 'TIMEOUT' } }
    $out = ''
    if (Test-Path ($logDir + '\fb_out.tmp')) { $out += [System.IO.File]::ReadAllText($logDir + '\fb_out.tmp') }
    if (Test-Path ($logDir + '\fb_err.tmp')) { $out += [System.IO.File]::ReadAllText($logDir + '\fb_err.tmp') }
    if ($out.Trim().Length -gt 0) { L ('    ' + ($out.Trim() -replace "`r?`n", ' | ')) }
    [System.IO.File]::AppendAllText($logFile, "    OUT: $out`r`n", $utf8)
    return @{ ExitCode = $p.ExitCode; Out = $out }
}

function Test-FastbootPresent {
    if (-not $Execute) { return $false }
    $r = Invoke-FB @('devices')
    return ($r.Out -match [regex]::Escape($Serial))
}

function Get-AdbState {
    if (-not $Execute) { return 'DRY-RUN' }
    $out = & $Adb -s $Serial get-state 2>&1
    $s = ($out | Out-String).Trim()
    if ($s -match 'recovery') { return 'recovery' }
    if ($s -match 'device')   { return 'device' }
    if ($s -match 'unauthorized') { return 'unauthorized' }
    # fall back: the recovery-side serial may differ, so look at the whole list
    $list = (& $Adb devices 2>&1 | Out-String)
    if ($list -match 'recovery') { return 'recovery(other-serial)' }
    return 'none'
}

function Clear-Misc {
    if (-not (Test-Path -LiteralPath $MiscImage)) { Fail ('misc image missing: ' + $MiscImage) }
    L 'STEP 1  flash pristine misc (clears boot-recovery BCB)'
    Invoke-FB @('flash', 'misc', $MiscImage) | Out-Null
}

function Flash-Target([string]$img) {
    L ('STEP 2  flash ' + $Partition + ' <= ' + (Split-Path -Leaf $img) + ' (' + (Get-Item -LiteralPath $img).Length + ' bytes)')
    $r = Invoke-FB @('flash', $Partition, $img) 300
    if ($Execute -and $r.ExitCode -ne 0) { L '  !! flash reported failure (will still attempt classification + rollback)' }
    return $r
}

function Trigger-Recovery {
    L 'STEP 3  fastboot reboot-recovery'
    Invoke-FB @('reboot-recovery') 60 | Out-Null
}

function Classify-Outcome([int]$waitSeconds = 60) {
    L ('STEP 4  classify (polling ' + $waitSeconds + 's)')
    if (-not $Execute) { L '  DRY-RUN: would poll fastboot + adb'; return 'DRY-RUN' }

    $t0 = Get-Date
    $backToFastboot = $null
    $adbSeen = $null
    for ($i = 0; $i -lt ($waitSeconds * 2); $i++) {
        Start-Sleep -Milliseconds 500
        $st = Get-AdbState
        if ($st -ne 'none') { $adbSeen = $st; break }
        # look for 'fastboot' banner without spamming the log: only after 6 s
        if (((Get-Date) - $t0).TotalSeconds -gt 6) {
            $out = (& $Fastboot -s $Serial getvar version 2>&1 | Out-String)
            if ($out -match 'version') { $backToFastboot = [int]((Get-Date) - $t0).TotalSeconds; break }
        }
    }
    $elapsed = [int]((Get-Date) - $t0).TotalSeconds

    if ($adbSeen) {
        L ('  RESULT: BOOTED, adb state=' + $adbSeen + ' after ~' + $elapsed + 's')
        return 'BOOTED'
    }
    if ($backToFastboot -ne $null) {
        if ($backToFastboot -le 15) { L ('  RESULT: REJECTED-BY-ABL (back in fastboot after ' + $backToFastboot + 's)'); return 'REJECTED' }
        L ('  RESULT: REBOOTED (back in fastboot after ' + $backToFastboot + 's, not a size reject)'); return 'REBOOTED'
    }
    L ('  RESULT: HUNG (no fastboot, no adb after ' + $waitSeconds + 's) -> this is the logo-hang signature')
    return 'HUNG'
}

function Restore-Stock {
    L 'STEP 5  ROLLBACK  (unconditional)'
    if (-not (Test-Path -LiteralPath $StockImage)) { Fail ('stock image missing: ' + $StockImage) }
    $r = Invoke-FB @('flash', $Partition, $StockImage) 600
    if ($Execute -and $r.ExitCode -ne 0) {
        L '  !! could not restore stock recovery through fastboot.'
        L '  !! device may be hung: long-press POWER 15-30 s, then hold VOL+ AND VOL- and plug USB,'
        L '  !! re-run:  .\run_experiments.ps1 -RollbackOnly -Execute'
        return $false
    }
    Clear-Misc
    L '  stock recovery + clean misc restored'
    return $true
}

function Save-Pstore {
    L 'STEP 6  collect pstore (previous boot console) from stock recovery'
    Invoke-FB @('reboot-recovery') 60 | Out-Null
    $ok = $false
    for ($i = 0; $i -lt 90; $i++) {
        Start-Sleep -Seconds 1
        $st = Get-AdbState
        if ($st -ne 'none' -and $st -ne 'unauthorized') { $ok = $true; break }
    }
    if (-not $ok) { L '  !! adb never came up in stock recovery; pstore not collected'; return }
    L '  adb up, dumping pstore + kernel info'
    $dump = Join-Path $logDir ('pstore_' + $stamp + '.txt')
    $cmds = @(
        'ls -l /sys/fs/pstore/',
        'cat /proc/cmdline',
        'cat /sys/fs/pstore/console-ramoops-0 2>/dev/null || cat /sys/fs/pstore/console-ramoops 2>/dev/null',
        'cat /sys/fs/pstore/dmesg-ramoops-0 2>/dev/null',
        'getprop ro.boot.bootreason',
        'getprop ro.boot.slot_suffix'
    )
    $all = ''
    foreach ($c in $cmds) {
        $all += ("### " + $c + "`r`n")
        $all += ((& $Adb -s $Serial shell $c 2>&1 | Out-String))
        $all += "`r`n"
    }
    [System.IO.File]::WriteAllText($dump, $all, $utf8)
    L ('  pstore -> ' + $dump)
    # persist across reboot by pulling it to the host as well
    & $Adb -s $Serial pull /sys/fs/pstore/console-ramoops-0 (Join-Path $logDir ('console-ramoops_' + $stamp + '.txt')) 2>&1 | Out-Null
}

# -------------------------------------------------------------------- main ----
L ('=== of-pipeline recovery experiments === phase=' + $Phase + ' execute=' + [bool]$Execute + ' serial=' + $Serial)

if ($Phase -eq 'list') { Show-Inventory; exit 0 }

if (-not (Test-Path -LiteralPath $Fastboot)) { Fail ('fastboot not found: ' + $Fastboot) }
if (-not (Test-Path -LiteralPath $Adb))      { Fail ('adb not found: ' + $Adb) }

if ($RollbackOnly) {
    if (-not (Test-FastbootPresent)) { Fail 'device not in fastboot; long-press POWER 15-30 s then VOL+ + VOL- + USB' }
    if (Restore-Stock) { exit 0 } else { exit 3 }
}

if (-not $Execute) { L 'DRY RUN: nothing will be flashed. Add -Execute to perform it.' }

if ($Phase -ne 'rollback') {
    $img = Join-Path $OutDir $Images[$Phase].File
    if (-not (Test-Path -LiteralPath $img)) { Fail ('image missing: ' + $img) }
    L ('image: ' + $img + '  (' + $Images[$Phase].Desc + ')')
    L ('expectation: ' + $Images[$Phase].Exp)
}

if ($Execute) {
    if (-not (Test-FastbootPresent)) { Fail 'device is not in fastboot mode (power button + VOL+/VOL- + USB)' }
    $slotR = Invoke-FB @('getvar', 'current-slot')
    Invoke-FB @('getvar', 'max-download-size')     | Out-Null
    $slot = ''
    if ($slotR.Out -match 'current-slot:\s*([ab])') { $slot = $Matches[1] }
    L ('current-slot = ' + $slot + '   target partition = ' + $Partition)
    if ($slot -eq 'b' -and $Partition -like '*_a') {
        Fail ('device slot is b but -Partition is ' + $Partition + '; re-run with -Partition recovery_b')
    }
    if ($slot -eq 'a' -and $Partition -like '*_b') {
        Fail ('device slot is a but -Partition is ' + $Partition + '; re-run with -Partition recovery_a')
    }
}

$verdict = 'NOT-RUN'
$rolledBack = $false
try {
    if ($Phase -ne 'rollback') {
        Clear-Misc
        $null = Flash-Target (Join-Path $OutDir $Images[$Phase].File)
        Trigger-Recovery
        $verdict = Classify-Outcome 60
    }
} catch {
    L ('EXCEPTION: ' + $_.Exception.Message)
} finally {
    if ($Execute) {
        if (Test-FastbootPresent) {
            $rolledBack = Restore-Stock
        } else {
            L 'STEP 5  ROLLBACK deferred: device is not visible in fastboot.'
            L '  long-press POWER 15-30 s, then hold VOL+ and VOL- while plugging USB, then run:'
            L ('  .\run_experiments.ps1 -RollbackOnly -Execute')
            $rolledBack = $false
        }
        if ($rolledBack -and $CollectPstore -and $verdict -ne 'BOOTED') {
            Save-Pstore
        }
    }
}

L ('=== verdict for ' + $Phase + ': ' + $verdict + '   rolled_back=' + $rolledBack + ' ===')
$summary = Join-Path $OutDir 'RESULTS.md'
[System.IO.File]::AppendAllText($summary,
    ('| ' + $stamp + ' | ' + $Phase + ' | ' + $verdict + ' | ' + $rolledBack + ' | ' + $Serial + ' |' + "`r`n"), $utf8)

if ($Execute -and -not $rolledBack) { exit 3 }
exit 0
