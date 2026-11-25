# run_sentinel.ps1 -- flash the v9 three-colour sentinel to boot_a, let a human read
# the panel, then ALWAYS roll boot_a back to the verified stock dump.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File run_sentinel.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File run_sentinel.ps1 -RestoreOnly
#
# ASCII only on purpose (Windows PowerShell 5.1 mangles non-ASCII scripts that
# have no BOM).  Nothing here is destructive beyond boot_a, and boot_a is gated
# on the sha256 of the backup dump before anything is written.
#
# WHY -s 5e367954 EVERYWHERE: a second device (HF06872291105783) sometimes shows
# up on this host.  Without -s, fastboot picks the first one it sees.

param(
    [string]$Image      = 'E:\rom\work\woa\out\Mu-tb331fc-v9-sentinel.img',
    [string]$BootBak    = 'E:\rom\work\a17dump\boot_a.img',
    [string]$BootBakSha = '2510b098380a573a40ee6600aa9124ced06a047c14c21e6bf7cd596fbbc3c14b',
    [string]$Serial     = '5e367954',
    [string]$LogDir     = 'E:\rom\work\woa\sentinel',
    [int]$FastbootWaitSec = 900,
    [int]$BootWaitSec     = 240,
    [switch]$RestoreOnly
)

$ErrorActionPreference = 'Continue'
$fb  = 'C:\platform-tools\platform-tools\fastboot.exe'
$adb = 'C:\platform-tools\platform-tools\adb.exe'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$log   = Join-Path $LogDir ("run_sentinel_{0}.log" -f $stamp)
$utf8  = New-Object System.Text.UTF8Encoding($false)
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

function Log([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Write-Host $line
    [System.IO.File]::AppendAllText($log, $line + "`r`n", $utf8)
}

function FbAll { ((& $fb devices 2>&1) | Out-String).Trim() }
function FbMine { ((& $fb -s $Serial devices 2>&1) | Out-String).Trim() -match [regex]::Escape($Serial) }
function AdbMine {
    ((& $adb -s $Serial get-state 2>&1) | Out-String).Trim() -match 'device|recovery|sideload'
}

function WaitFb([int]$seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        if (FbMine) { return $true }
        Start-Sleep -Seconds 3
    }
    return (FbMine)
}

function FbDo([string]$what, [string[]]$fbargs) {
    Log ("fastboot -s {0} {1}" -f $Serial, $what)
    $out = (& $fb -s $Serial @fbargs 2>&1 | Out-String).Trim()
    if ($out) { Log ("  " + ($out -replace "`r?`n", " | ")) }
    if ($LASTEXITCODE -ne 0) { Log ("  WARNING: exit code {0}" -f $LASTEXITCODE) }
    return $LASTEXITCODE
}

# ---------------------------------------------------------------- banner ----
Log "=========================================================="
Log "v9 three-colour sentinel  (shim RED / shim GREEN / SEC BLUE)"
Log "=========================================================="
Log ("log file : {0}" -f $log)

# ------------------------------------------------------------ gate 1: files -
if (-not (Test-Path $BootBak)) { Log "ABORT: rollback dump missing: $BootBak"; exit 1 }
$bakSha = (Get-FileHash $BootBak -Algorithm SHA256).Hash.ToLower()
Log ("rollback dump : {0}" -f $BootBak)
Log ("  size        : {0} bytes" -f (Get-Item $BootBak).Length)
Log ("  sha256      : {0}" -f $bakSha)
if ($bakSha -ne $BootBakSha.ToLower()) {
    Log "ABORT: rollback dump sha256 does not match the expected value."
    Log ("  expected : {0}" -f $BootBakSha)
    Log "  Refusing to touch boot_a: without a trusted rollback the device stays bricked."
    exit 2
}
Log "  rollback dump verified OK."

if (-not $RestoreOnly) {
    if (-not (Test-Path $Image)) { Log "ABORT: image missing: $Image"; exit 3 }
    Log ("sentinel image: {0}" -f $Image)
    Log ("  size        : {0} bytes" -f (Get-Item $Image).Length)
    Log ("  sha256      : {0}" -f (Get-FileHash $Image -Algorithm SHA256).Hash.ToLower())
}

# ------------------------------------------------------ gate 2: the device --
$all = FbAll
if ($all) { Log ("fastboot devices: " + ($all -replace "`r?`n", " ; ")) }
if ($all -and ($all -notmatch [regex]::Escape($Serial))) {
    Log "WARNING: fastboot sees devices other than $Serial. Only $Serial will be touched."
}

if (-not (FbMine)) {
    Log "no fastboot device $Serial yet; trying adb reboot bootloader"
    & $adb -s $Serial reboot bootloader 2>&1 | Out-Null
    if (-not (WaitFb $FastbootWaitSec)) {
        Log "ABORT: $Serial never appeared in fastboot, nothing was flashed."
        exit 4
    }
}
Log "fastboot device $Serial is present."

if (-not $RestoreOnly) {
    # the image only runs if the device boots slot a
    $slotOut = (& $fb -s $Serial getvar current-slot 2>&1 | Out-String)
    if ($slotOut -match 'current-slot:\s*([ab])') {
        $slot = $matches[1]
        Log ("current-slot: {0}" -f $slot)
        if ($slot -ne 'a') {
            Log "ABORT: device boots slot $slot, the sentinel is flashed to boot_a."
            Log "  Run: fastboot -s $Serial --set-active=a   (then re-run this script)"
            exit 5
        }
    } else {
        Log "WARNING: could not read current-slot; continuing (boot_a is what we write)."
    }
}

$script:restored = $false

try {
    if (-not $RestoreOnly) {
        # ------------------------------------------------------------- flash --
        Log "--- flashing the sentinel to boot_a"
        $rc = FbDo "flash boot_a" @('flash', 'boot_a', $Image)
        if ($rc -ne 0) {
            Log "flash returned nonzero -- rolling back immediately."
            throw "flash failed"
        }

        Log "--- reboot. WATCH THE PANEL NOW."
        FbDo "reboot" @('reboot') | Out-Null

        Log ""
        Log "THE PANEL, 5-20 s AFTER THE REBOOT (top of the screen):"
        Log "  RED     = the shim executed; died in / before the FD copy or jump"
        Log "  GREEN   = FD copied and the jump happened; died in SEC/DXE"
        Log "  BLUE    = SEC reached its first C statement; died in DXE init"
        Log "  WHITE   = SEC painted both early bands (same as BLUE, further)"
        Log "  YELLOW  = SEC finished InitializeMemory"
        Log "  CYAN    = (small band at +0x20000) ABL handed over with the MMU ON"
        Log "  BLACK / logo unchanged = the shim never executed => ABL side"
        Log "Remember: CYAN may sit next to the main band; the main band is what counts."
        Log ""
        $seen = (Read-Host "What colour is the band at the TOP of the screen? (red/green/blue/white/yellow/none)").Trim().ToLower()
        Log ("observed colour: {0}" -f $seen)
        switch -regex ($seen) {
            '^red'    { Log "VERDICT: shim alive, FD copy/jump never completed -> ABL->shim handoff or the copy itself." }
            '^green'  { Log "VERDICT: shim completed the copy and jumped -> SEC/DXE died. Shim and handoff are fine." }
            '^blue'   { Log "VERDICT: SEC C code ran -> the FD is fine; the death is inside SEC/DXE init." }
            '^white'  { Log "VERDICT: SEC C code ran and both bands are up -> same as BLUE." }
            '^yellow' { Log "VERDICT: SEC finished InitializeMemory -> death is after memory init (DXE)." }
            '^none|black|no' { Log "VERDICT: nothing painted -> shim never executed (ABL side) OR the framebuffer channel is dead." }
            default   { Log "VERDICT: unparsed answer, record it verbatim in the report." }
        }
        Log ""
        Log "--- now getting back to fastboot for the rollback."
        Log "    If the tablet is stuck: hold POWER 15-20 s to force it off, then hold"
        Log "    VOL- and press POWER to re-enter the bootloader."
    }

    # ------------------------------------------------------------ rollback --
    Log "--- rollback"
    if (-not (WaitFb $FastbootWaitSec)) {
        $script:restored = $false
        Log "ROLLBACK BLOCKED: $Serial is not in fastboot. boot_a still holds the sentinel."
        Log "  Force off (POWER 15-20 s), hold VOL- + POWER, then run:"
        Log ("  fastboot -s {0} flash boot_a {1}" -f $Serial, $BootBak)
        exit 6
    }

    $bakSha2 = (Get-FileHash $BootBak -Algorithm SHA256).Hash.ToLower()
    if ($bakSha2 -ne $BootBakSha.ToLower()) {
        Log "ABORT: rollback dump changed on disk since the gate check. Not flashing it."
        exit 7
    }

    $rc = FbDo ("flash boot_a (rollback)") @('flash', 'boot_a', $BootBak)
    if ($rc -ne 0) {
        Log "ROLLBACK FLASH FAILED -- boot_a may still hold the sentinel. Use the 9008 route if needed."
        exit 8
    }
    $script:restored = $true
    FbDo "reboot" @('reboot') | Out-Null

    Log "--- waiting for Android (boot_completed)"
    $deadline = (Get-Date).AddSeconds($BootWaitSec)
    $ok = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $b = ((& $adb -s $Serial shell getprop sys.boot_completed 2>&1) | Out-String).Trim()
        if ($b -match '^1$') {
            $ok = $true
            $id = ((& $adb -s $Serial shell getprop ro.build.display.id 2>&1) | Out-String).Trim()
            Log ("ROLLBACK OK: boot_completed=1  ({0})" -f $id)
            break
        }
    }
    if (-not $ok) {
        Log "Android did not report boot_completed=1 in time."
        Log "  boot_a has been restored anyway; wait a minute, then check adb devices."
    }
}
finally {
    if (-not $script:restored -and -not $RestoreOnly) {
        Log ""
        Log "!!! boot_a was NOT restored by this script !!!"
        Log ("    Restore by hand: fastboot -s {0} flash boot_a {1}" -f $Serial, $BootBak)
    }
}

Log "done. Log kept at $log"
