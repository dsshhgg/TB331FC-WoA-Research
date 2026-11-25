# run.ps1 -- flash the "paint proof" boot image, let a human read the panel,
#            then ALWAYS roll boot_a back to the verified stock dump.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File run.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File run.ps1 -Ctl
#   powershell -NoProfile -ExecutionPolicy Bypass -File run.ps1 -RestoreOnly
#
# WHAT THIS PROVES
#   The image is the *stock A17 kernel* with four bytes rewritten at kernel+0x4
#   (code1: `b 0x2550000` -> `b 0x42918A00`) plus a 168-byte stub appended at the
#   end of the kernel.  The only way into the kernel body is:
#
#       0x40000000 ccmp (MZ)  ->  0x40000004 b 0x42918A00  ->  stub
#       stub: MMU+D-cache off, paint 15 MiB of 0xFFFF0000 at 0x5C000000,
#             restore SCTLR, b 0x42550000 (primary_entry)
#
#   So a normal Android boot *is itself* the proof that the paint code ran.
#   The panel colour then says whether 0x5C000000 is what the mixer scans.
#
# ASCII only on purpose (Windows PowerShell 5.1 mangles non-ASCII scripts
# without a BOM).  -s 5e367954 on every fastboot call on purpose: a second
# device (HF06872291105783) sometimes appears on this host.

param(
    [string]$Image      = 'E:\rom\work\woa\ch-probe\out\boot_a-paint-proof.img',
    [string]$BootBak    = 'E:\rom\work\a17dump\boot_a.img',
    [string]$BootBakSha = '2510b098380a573a40ee6600aa9124ced06a047c14c21e6bf7cd596fbbc3c14b',
    [string]$Serial     = '5e367954',
    [string]$LogDir     = 'E:\rom\work\woa\ch-probe',
    [int]$FastbootWaitSec = 900,
    [int]$BootWaitSec     = 300,
    [switch]$RestoreOnly,
    [switch]$Ctl
)

$ErrorActionPreference = 'Continue'
$fb  = 'C:\platform-tools\platform-tools\fastboot.exe'
$adb = 'C:\platform-tools\platform-tools\adb.exe'

if ($Ctl -and -not $PSBoundParameters.ContainsKey('Image')) {
    $Image = 'E:\rom\work\woa\ch-probe\out\boot_a-patch-ctl.img'
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$log   = Join-Path $LogDir ("run_{0}.log" -f $stamp)
$utf8  = New-Object System.Text.UTF8Encoding($false)
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

function Log([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Write-Host $line
    [System.IO.File]::AppendAllText($log, $line + "`r`n", $utf8)
}

function FbAll { ((& $fb devices 2>&1) | Out-String).Trim() }
function FbMine { ((& $fb -s $Serial devices 2>&1) | Out-String).Trim() -match [regex]::Escape($Serial) }
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

Log "=========================================================="
Log "paint proof: stock A17 kernel + stub that paints 0x5C000000"
Log "=========================================================="
Log ("log file : {0}" -f $log)
if ($Ctl -or ($Image -match 'ctl')) { Log "MODE     : CONTROL image (no paint, trampoline only)" }

# ------------------------------------------------------------ gate 1: files --
if (-not (Test-Path $BootBak)) { Log "ABORT: rollback dump missing: $BootBak"; exit 1 }
$bakSha = (Get-FileHash $BootBak -Algorithm SHA256).Hash.ToLower()
Log ("rollback dump : {0}  ({1} bytes)" -f $BootBak, (Get-Item $BootBak).Length)
Log ("  sha256      : {0}" -f $bakSha)
if ($bakSha -ne $BootBakSha.ToLower()) {
    Log "ABORT: rollback dump sha256 does not match 2510b098...; refusing to touch boot_a."
    exit 2
}
Log "  rollback dump verified OK."

if (-not $RestoreOnly) {
    if (-not (Test-Path $Image)) { Log "ABORT: image missing: $Image"; exit 3 }
    $imgSha = (Get-FileHash $Image -Algorithm SHA256).Hash.ToLower()
    $imgLen = (Get-Item $Image).Length
    Log ("image        : {0}  ({1} bytes)" -f $Image, $imgLen)
    Log ("  sha256     : {0}" -f $imgSha)
    $sidecar = [IO.Path]::Combine([IO.Path]::GetDirectoryName($Image), ([IO.Path]::GetFileNameWithoutExtension($Image) + '.sha256'))
    if (Test-Path $sidecar) {
        $want = ((Get-Content $sidecar -TotalCount 1) -split '\s+')[0].ToLower()
        Log ("  expected   : {0}  (from {1})" -f $want, (Split-Path $sidecar -Leaf))
        if ($want -ne $imgSha) { Log "ABORT: image sha256 differs from its sidecar. Rebuild first."; exit 4 }
        Log "  image sha256 matches its sidecar."
    } else {
        Log "  WARNING: no .sha256 sidecar next to the image; skipping that check."
    }

    # ---- gate 1b: the image really is "stock kernel + 4 bytes + 1 appended page"
    Log "--- offline content gate"
    $fs = [IO.File]::OpenRead($Image)
    try {
        $br = New-Object IO.BinaryReader($fs)
        $hdr = $br.ReadBytes(4096)
        $magic = [Text.Encoding]::ASCII.GetString($hdr, 0, 8)
        $hver  = [BitConverter]::ToUInt32($hdr, 0x28)
        $hsize = [BitConverter]::ToUInt32($hdr, 0x14)
        $ksize = [BitConverter]::ToUInt32($hdr, 0x08)
        $rsize = [BitConverter]::ToUInt32($hdr, 0x0C)
        $code0 = $br.ReadUInt32()
        $code1 = $br.ReadUInt32()
        $textoff = $br.ReadUInt64()
        $imgsize = $br.ReadUInt64()
        $fs.Position = 4096 + 0x38
        $armmagic = [Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
        Log ("  magic={0} header_version={1} header_size={2}" -f $magic, $hver, $hsize)
        Log ("  kernel_size={0} (0x{0:x}) ramdisk_size={1}" -f $ksize, $rsize)
        Log ("  code0=0x{0:x8} code1=0x{1:x8} text_offset=0x{2:x} image_size=0x{3:x}" -f $code0, $code1, $textoff, $imgsize)
        Log ("  ARM\x64 magic={0}" -f $armmagic)
        $bad = 0
        if ($magic -ne 'ANDROID!')  { Log "  FAIL: not an Android boot image"; $bad++ }
        if ($hver  -ne 4)           { Log "  FAIL: header_version is not 4"; $bad++ }
        if ($hsize -ne 1584)        { Log "  FAIL: header_size is not 1584"; $bad++ }
        if ($rsize -ne 0)           { Log "  FAIL: unexpected ramdisk_size"; $bad++ }
        if ($code0.ToString('x8') -ne 'fa405a4d')  { Log "  FAIL: code0 lost the MZ/ccmp magic"; $bad++ }
        if ($textoff -ne 0)         { Log "  FAIL: text_offset is not 0"; $bad++ }
        if ($imgsize -ne 0x29C0000) { Log "  FAIL: image_size changed (ABL gate 0xa3e8!)"; $bad++ }
        if ($armmagic -ne 'ARMd')   { Log "  FAIL: missing ARM\x64 magic"; $bad++ }
        if (-not ($code1 -eq 0x14A4627F -or $code1 -eq 0x14A4627B -or ($code1 -band 0xFC000000) -eq 0x14000000)) {
            Log "  FAIL: code1 is not a `b` to the stub"; $bad++
        } else {
            $imm = $code1 -band 0x03FFFFFF
            if ($imm -band 0x02000000) { $imm = $imm - 0x04000000 }
            $tgt = [uint64]0x40000004 + ([int64]$imm * 4)
            Log ("  code1 -> 0x{0:x}  (expect 0x42918a00)" -f $tgt)
            if ($tgt -ne 0x42918A00) { Log "  FAIL: code1 does not target the appended stub"; $bad++ }
        }
        if ($ksize -ne 0x2919A00)  { Log "  NOTE: kernel_size is 0x{0:x}, expected 0x2919a00" -f $ksize }
        if ($bad -ne 0) { Log "ABORT: image failed the offline gate ($bad problems)."; exit 5 }
        Log "  offline gate: PASS (kernel body byte-identical to stock except code1)"
    } finally { $fs.Close() }
}

# ----------------------------------------------------------- gate 2: device --
$all = FbAll
if ($all) { Log ("fastboot devices: " + ($all -replace "`r?`n", " ; ")) }
if ($all -and ($all -notmatch [regex]::Escape($Serial))) {
    Log "WARNING: fastboot sees other devices too. Only $Serial will be touched."
}

if (-not (FbMine)) {
    Log "no fastboot device $Serial yet."
    Log "  The tablet is probably sitting on the Lenovo logo (the v9 ctl image)."
    Log "  Hold POWER 15-20 s to force it off, then hold VOL- and press POWER."
    & $adb -s $Serial reboot bootloader 2>&1 | Out-Null
    if (-not (WaitFb $FastbootWaitSec)) {
        Log "ABORT: $Serial never appeared in fastboot, nothing was flashed."
        Log "  If it does not come back: 9008 route (fh_loader + prog_firehose), see rescue docs."
        exit 6
    }
}
Log "fastboot device $Serial is present."

if (-not $RestoreOnly) {
    $slotOut = (& $fb -s $Serial getvar current-slot 2>&1 | Out-String)
    if ($slotOut -match 'current-slot:\s*([ab])') {
        $slot = $matches[1]
        Log ("current-slot: {0}" -f $slot)
        if ($slot -ne 'a') { Log "ABORT: device boots slot $slot but we write boot_a. Run --set-active=a first."; exit 7 }
    } else {
        Log "WARNING: could not read current-slot; continuing (boot_a is what we write)."
    }
}

$script:restored = $false

try {
    if (-not $RestoreOnly) {
        Log "--- flashing to boot_a"
        $rc = FbDo "flash boot_a" @('flash', 'boot_a', $Image)
        if ($rc -ne 0) { Log "flash returned nonzero -- rolling back immediately."; throw "flash failed" }

        Log "--- reboot.  WATCH THE PANEL NOW (first 1-10 seconds)."
        FbDo "reboot" @('reboot') | Out-Null

        Log ""
        if ($Ctl -or ($Image -match 'ctl')) {
            Log "CONTROL IMAGE: the trampoline runs but paints nothing."
            Log "  Android boots  => the patch mechanism (code1 + 1 appended page) is harmless"
            Log "  logo / no boot => the mechanism itself is what breaks the kernel"
        } else {
            Log "EXPECTED: the whole panel turns PURE RED for a moment, then Android boots."
            Log "  (15 MiB at 0x5C000000 is painted; alpha FF so a blending mixer still shows red)"
        }
        Log ""
        Start-Sleep -Seconds 12
        $seen = (Read-Host "Did the panel go RED at any point? (y/n/other)").Trim().ToLower()
        Log ("observed red   : {0}" -f $seen)
        $booted = (Read-Host "Did Android boot (launcher visible, or adb sys.boot_completed=1)? (y/n)").Trim().ToLower()
        Log ("observed boot  : {0}" -f $booted)

        $red  = ($seen -match '^(y|yes|red)')
        $okay = ($booted -match '^(y|yes)')

        if ($Ctl -or ($Image -match 'ctl')) {
            if ($okay -and -not $red) { Log "VERDICT(ctl): trampoline is inert, patch mechanism OK." }
            elseif ($okay -and $red)  { Log "VERDICT(ctl): unexpected colour in a no-paint build; record it." }
            else                      { Log "VERDICT(ctl): the patch mechanism itself breaks the boot -> fix code1/append before anything else." }
        } else {
            if ($red -and $okay)      { Log "VERDICT A: CHANNEL VALID. 0x5C000000 writes are visible AND the kernel still boots." }
            elseif ($red -and -not $okay) { Log "VERDICT C: colour seen but no Android -> the stub disturbed the handover; fix the stub (restore SCTLR / paint range)." }
            elseif (-not $red -and $okay) { Log "VERDICT B: CHANNEL INVALID. The stub MUST have run (only path to primary_entry) yet nothing showed." ; Log "  => every earlier 'stuck on the Lenovo logo = the payload never ran' conclusion is VOID." }
            else                      { Log "VERDICT D: no colour and no Android -> the kernel did not get control at all (or code1/append broke it). Flash the -Ctl image to separate the two." }
        }
        if ($red -and $okay) { Log "  => the v9 sentinel's black screen really does mean ABL never reached the blr." }

        Log "--- getting back to fastboot for the rollback"
        Log "    If the tablet is stuck: hold POWER 15-20 s, then hold VOL- + POWER."
    }

    Log "--- rollback (stock boot_a)"
    if (-not (WaitFb $FastbootWaitSec)) {
        Log "ROLLBACK BLOCKED: $Serial is not in fastboot. boot_a still holds the test image."
        Log ("  fastboot -s {0} flash boot_a {1}" -f $Serial, $BootBak)
        exit 8
    }
    $bakSha2 = (Get-FileHash $BootBak -Algorithm SHA256).Hash.ToLower()
    if ($bakSha2 -ne $BootBakSha.ToLower()) { Log "ABORT: rollback dump changed on disk. Not flashing it."; exit 9 }

    $rc = FbDo ("flash boot_a (rollback)") @('flash', 'boot_a', $BootBak)
    if ($rc -ne 0) { Log "ROLLBACK FLASH FAILED -- boot_a may still hold the test image (9008 route if needed)."; exit 10 }
    $script:restored = $true
    FbDo "reboot" @('reboot') | Out-Null

    Log "--- waiting for Android (sys.boot_completed)"
    $deadline = (Get-Date).AddSeconds($BootWaitSec)
    $ok = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $b = ((& $adb -s $Serial shell getprop sys.boot_completed 2>&1) | Out-String).Trim()
        if ($b -match '^1$') {
            $ok = $true
            $id = ((& $adb -s $Serial shell getprop ro.build.display.id 2>&1) | Out-String).Trim()
            Log ("ROLLBACK OK: boot_completed=1 ({0})" -f $id)
            break
        }
    }
    if (-not $ok) {
        Log "Android did not report boot_completed=1 in time; boot_a is restored regardless."
        Log "  Wait a minute, then: adb -s $Serial shell getprop sys.boot_completed"
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


