#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
mkdir -p build
yosys -Q -T -p 'read_verilog -sv -D SYNTHESIS -Irtl rtl/*.sv; hierarchy -check -top noc_board_top; proc; opt; check -assert; stat' > build/elaborate.log 2>&1
if rg -q 'Latch inferred' build/elaborate.log; then
    echo 'Unexpected latch in design; see build/elaborate.log' >&2; exit 1
fi
echo 'Whole SoC RTL elaboration/check passed (see build/elaborate.log)'
