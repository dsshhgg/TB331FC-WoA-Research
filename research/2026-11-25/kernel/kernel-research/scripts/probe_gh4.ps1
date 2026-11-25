$ErrorActionPreference = 'Continue'
$tok = $env:GH_TOKEN   # 原始脚本此处硬编码了 GitHub PAT，入库前已删除，改为读环境变量
$H = @{ Authorization = "token $tok"; 'User-Agent' = 'kernel-research' }

function TryFile($ref, $p) {
  $u = "https://api.github.com/repos/torvalds/linux/contents/$p" + "?ref=$ref"
  try { $r = Invoke-RestMethod -Uri $u -Headers $H -TimeoutSec 30; return "EXISTS  $($r.size)B" }
  catch { return "ABSENT (HTTP$($_.Exception.Response.StatusCode.value__))" }
}

$cand = @(
 'include/dt-bindings/clock/qcom,gcc-sm6225.h',
 'include/dt-bindings/clock/qcom,dispcc-sm6225.h',
 'include/dt-bindings/clock/qcom,sm6225-gpucc.h',
 'drivers/clk/qcom/gcc-sm6225.c',
 'drivers/clk/qcom/dispcc-sm6225.c',
 'drivers/clk/qcom/gpucc-sm6225.c',
 'include/dt-bindings/clock/qcom,gcc-sm6115.h',
 'drivers/clk/qcom/gcc-sm6115.c',
 'drivers/clk/qcom/dispcc-sm6115.c',
 'drivers/phy/qualcomm/phy-qcom-qmp-ufs.c',
 'drivers/phy/qualcomm/phy-qcom-qusb2.c',
 'drivers/gpu/drm/msm/adreno/a6xx_gpu.c',
 'drivers/net/wireless/ath/ath10k/snoc.c',
 'drivers/bluetooth/btqca.c',
 'drivers/soc/qcom/llcc-qcom.c',
 'drivers/interconnect/qcom/sm6115.c',
 'drivers/remoteproc/qcom_q6v5_pas.c',
 'drivers/soundwire/qcom.c'
)
"=== mainline master (torvalds/linux) presence ==="
foreach ($f in $cand) { "{0,-60} {1}" -f $f, (TryFile 'master' $f) }

"`n=== dt-bindings clock dir: is there ANY sm6225 binding upstream? search via code search is not available; check sm6115 variants ==="
foreach ($f in @('include/dt-bindings/clock/qcom,gpucc-sm6115.h','drivers/clk/qcom/gpucc-sm6115.c','include/dt-bindings/clock/qcom,dispcc-sm6115.h')) {
  "{0,-60} {1}" -f $f, (TryFile 'master' $f)
}
