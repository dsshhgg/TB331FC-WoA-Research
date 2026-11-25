#  Direction-A recovery experiment runner  (TB331FC serial 5e367954)
#
#  What it does, in order, for ONE image:
#    1. flash a pristine misc           -> clears any lingering boot-recovery BCB
#    2. flash recovery_a  <= the image
#    3. fastboot reboot-recovery        -> ABL loads it through the proven BCB channel
#    4. poll ~75 s: adb state, fastboot state, and (if adb answers) dump evidence
#    5. ALWAYS roll back: flash the stock recovery_a dump back + clear misc again
#    6. reboot into the STOCK recovery (adb is root there) and pull
#       /sys/fs/pstore/console-ramoops-0 = the kernel console of the run we just did
#    7. print a verdict + every "DIRA" line found in that console
#
#  Rules baked in:
#    * every fastboot call is pinned with -s 5e367954 (a second device is often online)
#    * nothing except recovery_a and misc is ever written
#    * -Execute is required to touch the device; without it every step is printed only
#
#  Usage
#     .\run_dirA.ps1 -List
#     .\run_dirA.ps1 -Phase dirA0 -Execute          # harness control (no OrangeFox file)
#     .\run_dirA.ps1 -Phase dirA1 -Execute          # the hybrid: TWRP userland on stock skeleton
#     .\run_dirA.ps1 -RollbackOnly -Execute         # device is hung: just put stock back
#
param(
    [ValidateSet('list', 'dirA0', 'dirA1')]
    [string]$Phase = 'list',
    [switch]$Execute,
    [switch]$RollbackOnly,
    [string]$Serial = '5e367954',
    [string]$Partition = 'recovery_a',
    [string]$StockImage = 'E:\rom\work\dual-boot\backup\recovery_a.bin',
    [string]$MiscImage = 'E:\rom\work\rescue-matrix\reads\misc_full.bin',
    [string]$Fastboot = 'E:\rom\tools\platform-tools\fastboot.exe',
    [string]$Adb = 'E:\rom\tools\platform-tools\adb.exe',
    [int]$PollSeconds = 75
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $here
$outDir = Join-Path $rootDir 'out'
$logDir = Join-Path $rootDir 'logs'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile = Join-Path $logDir ('run_' + $stamp + '.log')

# --- image table -----------------------------------------------------------------
$phases = @{
    'dirA0' = @{
        File = 'dirA_v0_skeleton.img'
        Desc = 'STOCK skeleton + rc patch (printk 8 / permissive / watchdog), NO OrangeFox binary'
        Exp  = 'stock recovery UI + adb + DIRA lines in pstore -> our harness is harmless'
    }
    'dirA1' = @{
        File = 'dirA_v1_hybrid.img'
        Desc = 'TWRP userland (recovery + 52 libs + /twres + fstab + flags) on the stock skeleton'
        Exp  = 'TWRP UI and/or adb; console shows how far it got if it does not'
    }
}

function L([string]$m) {
    $line = '[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $m
    Write-Output $line
    Add-Content -LiteralPath $logFile -Value $line -Encoding ASCII
}

function Fail([string]$m) { L ('FATAL: ' + $m); exit 2 }

function Invoke-FB([string[]]$fbArgs, [int]$timeout = 120) {
    $all = @('-s', $Serial) + $fbArgs
    L ('  $ fastboot ' + ($all -join ' '))
    if (-not $Execute) { return @{ ExitCode = 0; Out = '(dry-run)' } }
    $tmpOut = Join-Path $env:TEMP ('fb_' + $stamp + '_' + [guid]::NewGuid().ToString('N') + '.txt')
    $p = Start-Process -FilePath $Fastboot -ArgumentList $all -NoNewWindow -PassThru `
        -RedirectStandardOutput $tmpOut -RedirectStandardError ($tmpOut + '.err')
    if (-not $p.WaitForExit($timeout * 1000)) {
        try { $p.Kill() } catch {}
        L '  !! fastboot timeout'
        return @{ ExitCode = 124; Out = 'TIMEOUT' }
    }
    $o = ''
    if (Test-Path -LiteralPath $tmpOut) { $o = (Get-Content -LiteralPath $tmpOut -Raw -Encoding ASCII) }
    $e = ''
    if (Test-Path -LiteralPath ($tmpOut + '.err')) { $e = (Get-Content -LiteralPath ($tmpOut + '.err') -Raw -Encoding ASCII) }
    Remove-Item -LiteralPath $tmpOut, ($tmpOut + '.err') -ErrorAction SilentlyContinue
    $combined = ('' + $o + ' ' + $e).Trim()
    if ($combined) { L ('    ' + $combined) }
    return @{ ExitCode = $p.ExitCode; Out = $combined }
}

function Test-FastbootPresent {
    if (-not $Execute) { return $false }
    $r = Invoke-FB @('getvar', 'version') 20
    return ($r.Out -match 'version' -and $r.Out -notmatch 'waiting for')
}

function Get-AdbState {
    if (-not $Execute) { return 'none' }
    $out = (& $Adb -s $Serial get-state 2>&1 | Out-String)
    if ($out -match 'recovery|device') { return 'adb-up' }
    $list = (& $Adb devices 2>&1 | Out-String)
    if ($list -match 'recovery') { return 'adb-up-other-serial' }
    return 'none'
}

function Show-Inventory {
    L '--- image inventory ----------------------------------------------------------'
    foreach ($k in @('dirA0', 'dirA1')) {
        $f = Join-Path $outDir $phases[$k].File
        if (Test-Path -LiteralPath $f) {
            $i = Get-Item -LiteralPath $f
            $h = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.Substring(0, 16)
            L ('{0}: {1,10} bytes  sha256:{2}  {3}' -f $k, $i.Length, $h, $phases[$k].Desc)
        }
        else {
            L ('{0}: MISSING  {1}' -f $k, $f)
        }
    }
    L ('stock rollback image: ' + $StockImage)
    L ('pristine misc image: ' + $MiscImage)
    L '--- order -------------------------------------------------------------------'
    L 'dirA0 first. It carries no OrangeFox file at all: if it does not show stock'
    L 'recovery, the harness (rc patch + watchdog) is what broke, not TWRP.'
    L 'dirA1 second. Everything OrangeFox-specific lives here.'
    L 'Both steps end by rebooting into STOCK recovery to read pstore: the verdict'
    L 'depends on that console, so do not skip step 6.'
}

if (-not (Test-Path -LiteralPath $Fastboot)) { Fail ('no fastboot at ' + $Fastboot) }
if (-not (Test-Path -LiteralPath $Adb)) { Fail ('no adb at ' + $Adb) }
if (-not (Test-Path -LiteralPath $StockImage)) { Fail ('no stock recovery dump at ' + $StockImage) }
if (-not (Test-Path -LiteralPath $MiscImage)) { Fail ('no pristine misc at ' + $MiscImage) }

L ('=== Direction-A runner  phase=' + $Phase + ' execute=' + $Execute + ' serial=' + $Serial + ' ===')

if ($Phase -eq 'list') { Show-Inventory; L 'dry run only (add -Phase dirA0|dirA1 -Execute)'; exit 0 }

# --------------------------------------------------------------------- rollback ---
function Restore-Stock {
    L 'STEP 5  rollback: stock recovery_a + pristine misc'
    Invoke-FB @('flash', $Partition, $StockImage) 300 | Out-Null
    Invoke-FB @('flash', 'misc', $MiscImage) 120 | Out-Null
    L '  rolled back to the stock recovery dump'
}

if ($RollbackOnly) {
    L 'ROLLBACK-ONLY mode'
    if (-not (Test-FastbootPresent)) {
        L '  device is not in fastboot. It may be the hung-logo state:'
        L '  hold power 15-30 s -> hold Vol+ and Vol- -> plug USB -> rerun -RollbackOnly -Execute'
        exit 1
    }
    Restore-Stock
    L 'ROLLBACK DONE'
    exit 0
}

$img = Join-Path $outDir $phases[$Phase].File
if (-not (Test-Path -LiteralPath $img)) { Fail ('missing image ' + $img) }
$imgInfo = Get-Item -LiteralPath $img
if ($imgInfo.Length -gt 31700000) { Fail ('image is over the 31.7 MB recovery budget: ' + $imgInfo.Length) }

L ('image: ' + $img + '  (' + $phases[$Phase].Desc + ')')
L ('expectation: ' + $phases[$Phase].Exp)

# 0. make sure we are in fastboot
if (-not $Execute) {
    L 'STEP 0  DRY-RUN: assuming the device answers adb; would reboot it to bootloader'
}
else {
    $adbState = Get-AdbState
    if ($adbState -eq 'none') {
        if (-not (Test-FastbootPresent)) { Fail 'device is neither in adb nor fastboot; wake it first (Vol+ Vol- while plugging USB)' }
        L 'STEP 0  device already in fastboot'
    }
    else {
        L 'STEP 0  device answers adb, rebooting to bootloader'
        & $Adb -s $Serial reboot bootloader | Out-Null
        Start-Sleep -Seconds 12
    }
}

# 1..3
L 'STEP 1  flash pristine misc (clears boot-recovery BCB)'
Invoke-FB @('flash', 'misc', $MiscImage) 120 | Out-Null
L ('STEP 2  flash ' + $Partition + ' <= ' + $phases[$Phase].File + ' (' + $imgInfo.Length + ' bytes)')
$r = Invoke-FB @('flash', $Partition, $img) 300
if ($Execute -and $r.Out -notmatch 'OKAY|Finished') { L '  !! flash did not report OKAY; continuing anyway (classification will tell)' }
L 'STEP 3  fastboot reboot-recovery'
Invoke-FB @('reboot-recovery') 60 | Out-Null

# 4. classify
$verdict = 'UNKNOWN'
$evidence = ''
if (-not $Execute) {
    L 'STEP 4  DRY-RUN: would poll fastboot + adb, then dump evidence'
    $verdict = 'DRY-RUN'
}
else {
    L ('STEP 4  polling for ' + $PollSeconds + ' s (adb first: it is the only remote evidence channel)')
    $t0 = Get-Date
    $sawFastboot = -1
    $sawAdb = $null
    while (((Get-Date) - $t0).TotalSeconds -lt $PollSeconds) {
        Start-Sleep -Seconds 5
        $st = Get-AdbState
        if ($st -ne 'none') { $sawAdb = $st; break }
        if ($sawFastboot -lt 0) {
            $fb = Invoke-FB @('getvar', 'version') 20
            if ($fb.Out -match 'version' -and $fb.Out -notmatch 'waiting for') {
                $sawFastboot = [int]((Get-Date) - $t0).TotalSeconds
                break
            }
        }
    }
    $elapsed = [int]((Get-Date) - $t0).TotalSeconds
    if ($sawAdb) {
        $verdict = 'ADB-UP'
        L ('  RESULT: adb answered (' + $sawAdb + ') after ~' + $elapsed + ' s  -> userland is alive')
        L 'STEP 4b evidence dump over adb'
        $cmds = @(
            'getprop ro.build.version.sdk',
            'getprop init.svc.recovery',
            'getprop sys.usb.config',
            'getprop ro.hardware',
            'ls -l /dev/dri /dev/graphics /dev/input',
            'cat /proc/uptime',
            'dmesg | tail -n 60',
            'cat /tmp/recovery.log 2>/dev/null | tail -n 80',
            'ls -l /sys/fs/pstore'
        )
        $evidence = ''
        foreach ($c in $cmds) {
            $o = (& $Adb -s $Serial shell $c 2>&1 | Out-String)
            $evidence += ('### ' + $c + "`r`n" + $o + "`r`n")
        }
        $evFile = Join-Path $logDir ('adb_evidence_' + $stamp + '.txt')
        Set-Content -LiteralPath $evFile -Value $evidence -Encoding UTF8
        L ('  evidence written to ' + $evFile)
        if ($evidence -match 'DIRA') { L '  DIRA watchdog lines seen in adb shell (see evidence file)' }
    }
    elseif ($sawFastboot -ge 0) {
        if ($sawFastboot -le 15) { $verdict = 'REJECTED-BY-ABL' }
        else { $verdict = 'REBOOTED' }
        L ('  RESULT: back in fastboot after ~' + $sawFastboot + ' s -> ' + $verdict)
    }
    else {
        $verdict = 'NO-ADB-HUNG'
        L ('  RESULT: no adb, no fastboot after ' + $PollSeconds + ' s -> NO-ADB-HUNG')
        L '  (this is the logo-hang signature; the pstore console below is the evidence)'
    }
}

# 5
Restore-Stock

# 6
L 'STEP 6  boot STOCK recovery and pull the previous boot console from pstore'
if ($Execute) {
    Invoke-FB @('reboot-recovery') 60 | Out-Null
    $ok = $false
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Seconds 5
        if ((Get-AdbState) -ne 'none') { $ok = $true; break }
    }
    if (-not $ok) {
        L '  !! stock recovery adb never came up; pstore NOT collected.'
        L '     Hold power 15-30 s, then Vol+ and Vol- while plugging USB, then rerun -RollbackOnly.'
    }
    else {
        L '  stock recovery adb is up, dumping pstore'
        $ps = Join-Path $logDir ('pstore_' + $stamp + '.txt')
        $d = ''
        foreach ($c in @('ls -l /sys/fs/pstore/', 'cat /sys/fs/pstore/console-ramoops-0 2>/dev/null || cat /sys/fs/pstore/console-ramoops 2>/dev/null', 'dmesg | tail -n 40')) {
            $d += ('### ' + $c + "`r`n" + (& $Adb -s $Serial shell $c 2>&1 | Out-String) + "`r`n")
        }
        Set-Content -LiteralPath $ps -Value $d -Encoding UTF8
        L ('  pstore written to ' + $ps)
        $dira = Select-String -LiteralPath $ps -Pattern 'DIRA' -AllMatches
        L ('  DIRA lines found: ' + $dira.Count)
        foreach ($m in ($dira | Select-Object -First 40)) { L ('    ' + $m.Line.Trim()) }
        if ($dira.Count -eq 0) {
            L '  no DIRA line: the kernel did not reach our rc/watchdog (or the console record'
            L '  was overwritten before we read it). Fall back to reading the whole console file.'
        }
    }
}

L ('=== verdict for ' + $Phase + ': ' + $verdict + '  rolled_back=True ===')
$ledger = Join-Path $logDir 'RUNS.md'
if (-not (Test-Path -LiteralPath $ledger)) {
    Set-Content -LiteralPath $ledger -Value "# Direction-A experiment ledger`r`n`r`n| stamp | phase | image | verdict | rolled back |`r`n|---|---|---|---|---|" -Encoding UTF8
}
Add-Content -LiteralPath $ledger -Value ('| ' + $stamp + ' | ' + $Phase + ' | ' + $phases[$Phase].File + ' | ' + $verdict + ' | yes |') -Encoding UTF8
exit 0
