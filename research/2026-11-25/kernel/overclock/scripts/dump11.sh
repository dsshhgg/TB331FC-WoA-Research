#!/system/bin/sh
D=/sys/firmware/devicetree/base/soc
echo "===DDR_FREQ_TABLE"
for f in "$D/ddr-freq-table"/*; do
  [ -f "$f" ] && echo "$(basename $f) = $(od -An -tx1 "$f" | tr -d '\n' | tr -s ' ')"
done
echo "===GPU_BW_TBL"
for f in "$D/gpu-bw-tbl"/*; do
  [ -f "$f" ] && echo "$(basename $f) = $(od -An -tx1 "$f" | tr -d '\n' | tr -s ' ')"
done
echo "===QCOM_BUS_TABLE_DDR"
for f in "$D/qcom,kgsl-3d0@5900000/qcom,bus-table-ddr" "$D/qcom,kgsl-3d0@5900000/qcom,bus-table-cnoc"; do
  [ -f "$f" ] && echo "$(basename $f) = $(od -An -tx1 "$f" | tr -d '\n' | tr -s ' ')"
done
echo "===DONE"
