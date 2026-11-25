# ===========================================================================
#  flash-tb331fc.ps1 - flash the mainline-Linux images to the TB331FC A slot.
#
#  NOTHING here runs unless you pass a form and confirm.  Every fastboot call
#  is pinned to the tablet's serial (-s 5e367954) because another device is
#  usually plugged in at the same time.
#
#  Forms
#    -Form A2        1 partition  : boot_a only, kernel + ONE appended FDT.
#                                  Cheapest probe: expect console output then
#                                  "no root" panic.  Rollback = 1 flash.
#    -Form A         3 partitions : boot_a (kernel) + vendor_boot_a (our
#                                  initramfs + our DTB + our cmdline) +
#                                  init_boot_a (empty cpio placeholder).
#                                  This is the reference-proven shape.
#    -Form B         2 partitions : boot_a (kernel) + recovery_a
#                                  (kernel_size=0, our initramfs).
#    -Form rollback  put boot_a back (and optionally vendor_boot_a /
#                    init_boot_a / recovery_a).
#
#  Examples
#    .\flash-tb331fc.ps1 -Form A2                     # dry run: prints the plan
#    .\flash-tb331fc.ps1 -Form A2 -Go                 # actually flash
#    .\flash-tb331fc.ps1 -Form A -Go -Gz              # gzip kernel variant
#    .\flash-tb331fc.ps1 -Form rollback -Go
#    .\flash-tb331fc.ps1 -Form rollback -Go -Full     # + vendor_boot_a/init_boot_a/recovery_a
# ===========================================================================
[CmdletBinding()]
param(
    [ValidateSet('A', 'A2', 'A3', 'B', 'rollback', 'status')]
    [string]$Form = 'status',

    [switch]$Go,                        # without -Go nothing is written
    [switch]$Gz,                        # Form A: use the gzip kernel image
    [switch]$SkipInitBoot,              # Form A: leave init_boot_a alone
    [switch]$Full,                      # rollback: also restore vendor_boot_a + init_boot_a + recovery_a

    [string]$Serial   = '5e367954',
    [string]$OutDir   = 'E:\rom\work\linux-boot\out',
    [string]$Fastboot = 'E:\rom\tools\platform-tools\fastboot.exe',

    [string]$BootBackup  = 'E:\rom\work\a17dump\boot_a.img',
    [string]$BootBackupHash = '2510b098380a573a40ee6600aa9124ced06a047c14c21e6bf7cd596fbbc3c14b',
    [string]$StockImageDir = 'E:\rom\TB331FC\刷机包\TB331FC_ZUI_16.0.544\image',
    [string]$RecoveryBackup = ''
)

$ErrorActionPreference = 'Stop'

function Say($msg) { Write-Host $msg }
function Head($msg) { Write-Host ""; Write-Host ("=== " + $msg + " " + ('=' * [Math]::Max(0, 60 - $msg.Length))) }
function Fb { param([string[]]$ArgList)
    $cmd = @('-s', $Serial) + $ArgList
    if (-not $Go) { Say ("  [dry-run] fastboot " + ($cmd -join ' ')); return }
    & $Fastboot @cmd
    if ($LASTEXITCODE -ne 0) { throw ("fastboot failed (exit $LASTEXITCODE): fastboot " + ($cmd -join ' ')) }
}

function HashOf($p) {
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower()
}

function Need($p, $wantHash) {
    if (-not (Test-Path -LiteralPath $p)) { throw "missing file: $p" }
    $h = HashOf $p
    if ($wantHash -and $h -ne $wantHash) { throw "hash mismatch for $p`n  got  $h`n  want $wantHash" }
    Say ("  {0,-34} {1,12} bytes  {2}" -f (Split-Path $p -Leaf), (Get-Item -LiteralPath $p).Length, $h.Substring(0,16))
    return $p
}

if (-not (Test-Path -LiteralPath $Fastboot)) {
    $c = Get-Command fastboot -ErrorAction SilentlyContinue
    if ($c) { $Fastboot = $c.Source } else { throw "fastboot not found (pass -Fastboot)" }
}

Head "target"
Say ("  fastboot : " + $Fastboot)
Say ("  serial   : -s " + $Serial + "   (every command below carries it)")
Say ("  form     : " + $Form + $(if ($Go) { "   *** WILL WRITE ***" } else { "   (dry run - pass -Go to write)" }))
Fb @('getvar','current-slot')

switch ($Form) {

'status' {
    Head "device"
    Fb @('devices')
    Fb @('getvar','unlocked')
    Fb @('getvar','current-slot')
    Fb @('getvar','slot-count')
    Say "  (getvar output goes to stderr on most fastboot builds - that is normal)"
}

'A2' {
    Head "Form A2 - boot_a only, kernel + 1 appended FDT"
    $boot = Join-Path $OutDir 'boot_a-linux-dtb.img'
    Need $boot $null | Out-Null
    Say ""
    Say "  touches : boot_a ONLY"
    Say "  expect  : kernel log on the panel, then a panic (cmdline from the stock"
    Say "            vendor_boot has no root=, so there is no userspace)."
    Say "  rollback: .\flash-tb331fc.ps1 -Form rollback -Go   (one flash)"
    Head "flash"
    Fb @('flash','boot_a',$boot)
    Fb @('reboot')
}

'A' {
    Head "Form A - boot_a + vendor_boot_a (+ empty init_boot_a)"
    $boot = if ($Gz) { Join-Path $OutDir 'boot_a-linux-gz.img' } else { Join-Path $OutDir 'boot_a-linux.img' }
    $vboot = Join-Path $OutDir 'vendor_boot_a-linux.img'
    $iboot = Join-Path $OutDir 'init_boot_a-empty.img'
    Need $boot  $null | Out-Null
    Need $vboot $null | Out-Null
    if (-not $SkipInitBoot) { Need $iboot $null | Out-Null }
    Say ""
    Say "  touches : boot_a, vendor_boot_a$(if (-not $SkipInitBoot) { ', init_boot_a' })"
    Say "  kernel  : $(if ($Gz) { 'Image.gz (speculative)' } else { 'raw Image (same shape as both stock boot images)' })"
    Say "  ramdisk : our initramfs, inside vendor_boot_a (ABL segment A)."
    Say "            A boot-embedded ramdisk would be IGNORED here: ABL's"
    Say "            LoadRamdisk segment D is 32-bit only, and segment C reads"
    Say "            init_boot (not boot) when the header is GKI v4."
    Say "  rollback: .\flash-tb331fc.ps1 -Form rollback -Go -Full"
    Head "flash"
    Fb @('flash','boot_a',$boot)
    Fb @('flash','vendor_boot_a',$vboot)
    if (-not $SkipInitBoot) { Fb @('flash','init_boot_a',$iboot) }
    Fb @('reboot')
}

'A3' {
    Head "Form A3 - boot_a + vendor_boot_a (dtb/cmdline only) + init_boot_a (our initramfs)"
    $boot  = Join-Path $OutDir 'boot_a-linux.img'
    $vboot = Join-Path $OutDir 'vendor_boot_a-linux-nord.img'
    $iboot = Join-Path $OutDir 'init_boot_a-initramfs.img'
    Need $boot  $null | Out-Null
    Need $vboot $null | Out-Null
    Need $iboot $null | Out-Null
    Say ""
    Say "  touches : boot_a, vendor_boot_a, init_boot_a"
    Say "  why     : same DTB/cmdline plumbing as Form A, but the initramfs sits in"
    Say "            init_boot (ABL LoadRamdisk segment C) and vendor_boot_a carries"
    Say "            NO vendor_ramdisk, so the kernel receives exactly one cpio with"
    Say "            nothing concatenated after it. Use this if Form A's gz stream"
    Say "            plus the appended init_boot ramdisk ever misbehaves."
    Say "  rollback: .\flash-tb331fc.ps1 -Form rollback -Go -Full"
    Head "flash"
    Fb @('flash','boot_a',$boot)
    Fb @('flash','vendor_boot_a',$vboot)
    Fb @('flash','init_boot_a',$iboot)
    Fb @('reboot')
}

'B' {
    Head "Form B - boot_a (kernel) + recovery_a (kernel_size=0, our initramfs)"
    $boot = Join-Path $OutDir 'boot_a-linux.img'
    $rec  = Join-Path $OutDir 'recovery_a-linux.img'
    Need $boot $null | Out-Null
    Need $rec  $null | Out-Null
    Say ""
    Say "  touches : boot_a, recovery_a"
    Say "  expect  : ABL sees 'Recovery partition has no kernel' and appends the"
    Say "            recovery_a ramdisk (LoadRamdisk segment B) - but the flag it"
    Say "            needs is only ever set from that very path, so this is the"
    Say "            least certain of the three forms."
    Say "  rollback: .\flash-tb331fc.ps1 -Form rollback -Go -Full"
    Head "flash"
    Fb @('flash','boot_a',$boot)
    Fb @('flash','recovery_a',$rec)
    Fb @('reboot')
}

'rollback' {
    Head "Rollback"
    Need $BootBackup $BootBackupHash | Out-Null
    $images = @{ boot_a = $BootBackup }
    if ($Full) {
        $vb = Join-Path $StockImageDir 'vendor_boot.img'
        $ib = Join-Path $StockImageDir 'init_boot.img'
        Need $vb 'd526c77b243c5277fd6fb715c9108f9bdc6f7728359ee19a383bc0442ed7a8a1' | Out-Null
        Need $ib '2d090fb59244cf3cf55b95478b98234f4a27615fd1c63220e685f76ae79bb01b' | Out-Null
        $images['vendor_boot_a'] = $vb
        $images['init_boot_a']   = $ib
        $rb = if ($RecoveryBackup) { $RecoveryBackup } else { Join-Path $StockImageDir 'recovery.img' }
        if (Test-Path -LiteralPath $rb) {
            Need $rb $null | Out-Null
            $images['recovery_a'] = $rb
        }
    }
    Say ""
    Say "  restores : $($images.Keys -join ', ')"
    Head "flash"
    foreach ($k in @('boot_a','vendor_boot_a','init_boot_a','recovery_a')) {
        if ($images.ContainsKey($k)) { Fb @('flash', $k, $images[$k]) }
    }
    Fb @('reboot')
}
}

Head "next"
Say "  watch the panel; for USB console plug the cable in after the kernel boots"
Say "  and look for a new COM port (CDC-ACM gadget -> /dev/ttyGS0 at 115200 8N1)."
Say "  see REPORT.md section '验证判据表' for what each outcome means."
