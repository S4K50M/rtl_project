#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
mkdir -p build/synth
for spec in baseline:0:0 fast:1:0 espresso:0:1; do
    IFS=: read -r name fast minimized <<< "$spec"
    cat > "build/synth/$name.ys" <<EOF
read_verilog -sv -D SYNTHESIS -Irtl rtl/noc_fifo.sv rtl/xy_route.sv rtl/rr_arbiter.sv rtl/logic_minimized.sv rtl/noc_router.sv
chparam -set X 1 -set Y 1 -set FAST $fast -set MINIMIZED $minimized noc_router
synth_xilinx -family xc7 -top noc_router -noiopad -noclkbuf
check -assert
tee -o build/synth/$name.json stat -json -tech xilinx
write_json build/synth/$name.netlist.json
EOF
    yosys -Q -T -s "build/synth/$name.ys" > "build/synth/$name.log" 2>&1
    echo "Xilinx 7-series router mapping complete: $name"
done
python3 scripts/synth_report.py
