<#
.SYNOPSIS
    方案 2（改 APK 版）的完整镜像流水线：把重签过的 MIUIPackageInstallerVariants.apk
    塞进 product_a.img，重算 hashtree、重签 vbmeta_system，产出可刷的三件套。

.DESCRIPTION
    配方照抄 E:\rom\work\kit-baked\rebake.ps1（已被逐字节验证过 hashes 自洽），
    但**只动 product**，system / system_ext 直接沿用 kit-baked 的成品（它们已经带 5 项修复）。

      1. preflight    底图存在 + 尺寸/sha256 记录
      2. truncate     剥 AVB footer → work/<name>.img（ext4 数据区）
      3. surgery      debugfs 替换 /priv-app/.../MIUIPackageInstallerVariants.apk
      4. e2fsck -fy + 钉 s_lastcheck（否则产物不可复算）
      5. add_hashtree_footer  product（salt 00..01 / SHA256_RSA4096 / no FEC / rollback 0）
      6. make_vbmeta_image    vbmeta_system（描述符顺序 product → system → system_ext）
      7. verify_image + 产物拷到 -OutDir

.PARAMETER Apk
    要注入的 APK（默认 out\payload\MIUIPackageInstallerVariants.apk）

.PARAMETER BaseImages
    底图目录（默认 work\kit-baked\out，即"已烘 5 修"的那套）

.PARAMETER OutDir
    产物目录（默认 out\）

.PARAMETER SelfCheck
    只做 1-5 + 用"镜像里原本那份 APK"重放，检查 product_a.img 是否与底图逐字节一致。
    用来证明流水线本身没跑偏（注意：inode 复用顺序可能与底图不同，不一致不代表错，
    但"一致性成立"就是强证据）。

.EXAMPLE
    .\rebake-installer.ps1 -Apk E:\rom\work\pkg-installer\out\payload\MIUIPackageInstallerVariants.apk
#>
[CmdletBinding()]
param(
    [string]$Apk        = '',
    [string]$BaseImages = 'E:\rom\work\kit-baked\out',
    [string]$OutDir     = '',
    [string]$ToolsDir   = 'E:\rom\work\tools',
    [switch]$SelfCheck,
    [int]$Step          = 7
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrEmpty($here)) { $here = (Get-Location).Path }
$root = Split-Path -Parent (Split-Path -Parent $here)      # E:\rom\work\pkg-installer
if ([string]::IsNullOrEmpty($OutDir)) { $OutDir = Join-Path $root 'out' }
if ([string]::IsNullOrEmpty($Apk))    { $Apk    = Join-Path $OutDir 'payload\MIUIPackageInstallerVariants.apk' }

$PY    = (Get-Command python -ErrorAction SilentlyContinue).Source
$AVB   = Join-Path $ToolsDir 'avbtool.py'
$K4096 = Join-Path $ToolsDir 'testkey_rsa4096.pem'
$K2048 = Join-Path $ToolsDir 'testkey_rsa2048.pem'
$SALT  = '0000000000000000000000000000000000000000000000000000000000000001'
$Work  = Join-Path $root 'out\work'

# product 的 (ext4 数据段, 整分区) 尺寸 —— 与 kit-baked\truncate.py 的 SPEC 一致
$ProductData = 2909995008
$ProductPart = 2999996416

function Say([string]$m) { Write-Host $m }
function ToWsl([string]$p) {
    $q = $p -replace '\\', '/'
    if ($q -match '^([A-Za-z]):/(.*)$') { return '/mnt/' + $matches[1].ToLower() + '/' + $matches[2] }
    return $q
}
function Check([int]$code, [string]$what) {
    if ($code -ne 0) { Say ("!! FAILED (" + $code + "): " + $what); exit $code }
}

# ---- 1. preflight
Say '--- step 1 : preflight ---'
foreach ($n in @('product_a.img', 'system_a.img', 'system_ext_a.img')) {
    $p = Join-Path $BaseImages $n
    if (-not (Test-Path $p)) { Say ("!! missing " + $p); exit 2 }
    Say ("    " + $n + "  " + (Get-Item $p).Length + "  " + (Get-FileHash $p -Algorithm SHA256).Hash.Substring(0,16) + "...")
}
if (-not (Test-Path $Apk)) { Say ("!! missing payload " + $Apk); exit 2 }
foreach ($f in @($AVB, $K4096, $K2048)) { if (-not (Test-Path $f)) { Say ("!! missing " + $f); exit 2 } }

# ---- 2. truncate（复用 kit-baked\truncate.py，它按 SPEC 读取 src 目录）
if ($Step -ge 2) {
    Say '--- step 2 : truncate (strip AVB footer) ---'
    New-Item -ItemType Directory -Force -Path $Work | Out-Null
    & $PY 'E:\rom\work\kit-baked\truncate.py' $BaseImages $Work
    Check $LASTEXITCODE 'truncate.py'
}

# ---- 3. surgery
$img = Join-Path $Work 'product.img'
$payload = $Apk
if ($SelfCheck) {
    # 用镜像里自带的 APK 重放，产物应与底图 product_a.img 一致
    Say '--- SELF-CHECK : re-inject the APK already inside the image ---'
    $tmp = Join-Path $Work 'selfcheck.apk'
    $cmd = 'debugfs -R "dump /priv-app/MIUIPackageInstallerVariants/MIUIPackageInstallerVariants.apk ' + (ToWsl $tmp) + '" ' + (ToWsl (Join-Path $BaseImages 'product_a.img')) + ' >/dev/null 2>&1'
    & wsl -d ub -u root -- bash -lc $cmd
    Check $LASTEXITCODE 'self-check dump'
    $payload = $tmp
}
if ($Step -ge 3) {
    Say '--- step 3 : debugfs surgery ---'
    & wsl -d ub -u root -- bash (ToWsl (Join-Path $here 'surgery-installer.sh')) (ToWsl $img) (ToWsl $payload)
    Check $LASTEXITCODE 'surgery-installer.sh'
}

# ---- 4. e2fsck + 钉 lastcheck
if ($Step -ge 4) {
    Say '--- step 4 : e2fsck -fy ---'
    & wsl -d ub -u root -- bash -lc ("e2fsck -fy " + (ToWsl $img) + " 2>&1 | tail -2")
    Check $LASTEXITCODE 'e2fsck'
    & wsl -d ub -u root -- bash -lc ("debugfs -w -R 'ssv lastcheck 1230768000' " + (ToWsl $img) + " 2>&1 | grep -v '^debugfs' | head -2")
    Check $LASTEXITCODE 'pin lastcheck'
}

# ---- 5. hashtree
if ($Step -ge 5) {
    Say '--- step 5 : add_hashtree_footer (product) ---'
    $env:PATH = 'C:\msys64\usr\bin;' + $env:PATH      # avbtool 要 openssl
    if ((Get-Item $img).Length -ne $ProductData) { Say ("!! product.img=" + (Get-Item $img).Length + " 期望 " + $ProductData); exit 5 }
    & $PY $AVB add_hashtree_footer --image $img --partition_size $ProductPart `
        --partition_name product --do_not_generate_fec --salt $SALT `
        --algorithm SHA256_RSA4096 --hash_algorithm sha256 --key $K4096 --rollback_index 0
    Check $LASTEXITCODE 'add_hashtree_footer product'
    if ((Get-Item $img).Length -ne $ProductPart) { Say '!! 分区尺寸不对'; exit 5 }
}

if ($SelfCheck) {
    $h1 = (Get-FileHash $img -Algorithm SHA256).Hash.ToLower()
    $h2 = (Get-FileHash (Join-Path $BaseImages 'product_a.img') -Algorithm SHA256).Hash.ToLower()
    Say ("self-check product sha256 : " + $h1)
    Say ("baseline  product sha256 : " + $h2)
    if ($h1 -eq $h2) { Say 'SELF-CHECK: BYTE-IDENTICAL (流水线可复算)' } else { Say 'SELF-CHECK: DIFFERENT（inode 复用顺序不同，内容依赖步骤需人工确认）' }
    exit 0
}

# ---- 6. vbmeta_system
if ($Step -ge 6) {
    Say '--- step 6 : make_vbmeta_image (product -> system -> system_ext) ---'
    $env:PATH = 'C:\msys64\usr\bin;' + $env:PATH
    $vb = Join-Path $Work 'vbmeta_system.img'
    & $PY $AVB make_vbmeta_image --output $vb --flags 0 `
        --algorithm SHA256_RSA2048 --key $K2048 --padding_size 65536 --rollback_index 0 `
        --include_descriptors_from_image $img `
        --include_descriptors_from_image (Join-Path $BaseImages 'system_a.img') `
        --include_descriptors_from_image (Join-Path $BaseImages 'system_ext_a.img')
    Check $LASTEXITCODE 'make_vbmeta_image'
}

# ---- 7. verify + collect
if ($Step -ge 7) {
    Say '--- step 7 : verify + collect ---'
    $env:PATH = 'C:\msys64\usr\bin;' + $env:PATH
    & $PY $AVB verify_image --image $img            ; Check $LASTEXITCODE 'verify product'
    & $PY $AVB verify_image --image (Join-Path $Work 'vbmeta_system.img') ; Check $LASTEXITCODE 'verify vbmeta_system'
    & wsl -d ub -u root -- bash (ToWsl (Join-Path $here 'verify-installer.sh')) (ToWsl $img) (ToWsl $payload)
    Check $LASTEXITCODE 'verify-installer.sh'

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    Copy-Item $img (Join-Path $OutDir 'product_a.img') -Force
    Copy-Item (Join-Path $Work 'vbmeta_system.img') (Join-Path $OutDir 'vbmeta_system_a.img') -Force
    Say ''
    Say '--- final sha256 ---'
    Get-ChildItem (Join-Path $OutDir '*.img') | Sort-Object Name | ForEach-Object {
        Say ('    ' + (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower() + '  ' + $_.Name)
    }
    Get-ChildItem (Join-Path $OutDir '*.img') | Sort-Object Name | ForEach-Object {
        ((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower() + '  ' + $_.Name)
    } | Set-Content (Join-Path $OutDir 'SHA256SUMS-installer.txt') -Encoding ascii
}

Say ''
Say 'rebake-installer complete.'
exit 0
