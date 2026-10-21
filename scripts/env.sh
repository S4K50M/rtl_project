#!/usr/bin/env bash
# Source from any working directory. Normal system installations take priority.
if [ -d /workspace/toolchain/root/usr/bin ]; then
    export PATH="$PATH:/workspace/toolchain/root/usr/bin"
    export YOSYS_DATDIR=/workspace/toolchain/root/usr/share/yosys
    export NOC_IVL_DIR=/workspace/toolchain/root/usr/lib/x86_64-linux-gnu/ivl
fi
if [ -d /workspace/toolchain/python ]; then
    export PYTHONPATH="/workspace/toolchain/python${PYTHONPATH:+:$PYTHONPATH}"
fi
export MPLCONFIGDIR="${MPLCONFIGDIR:-/workspace/toolchain/cache/matplotlib}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/workspace/toolchain/cache}"
