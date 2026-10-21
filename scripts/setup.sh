#!/usr/bin/env bash
# Debian 13 cloud setup, entirely under /workspace. APT verifies signed Release
# metadata and package hashes; pip retains HTTPS/artifact verification.
set -euo pipefail
cd "$(dirname "$0")/.."
prefix=/workspace/toolchain
mkdir -p "$prefix/cache" "$prefix/root" "$prefix/apt/lists/partial" \
    "$prefix/apt/cache/archives/partial" "$prefix/apt/empty"
source scripts/env.sh
if ! command -v iverilog >/dev/null || ! command -v yosys >/dev/null || \
   ! command -v yosys-abc >/dev/null || ! command -v riscv64-unknown-elf-gcc >/dev/null; then
    if ! test -r /usr/share/keyrings/debian-archive-keyring.gpg; then
        echo 'Requires Debian archive keyring and Debian 13 compatible libraries' >&2; exit 1
    fi
    cat > "$prefix/apt/apt.conf" <<EOF
Dir::Etc::parts "$prefix/apt/empty";
Dir::Etc::main "$prefix/apt/empty.conf";
Dir::Etc::sourcelist "$prefix/apt/sources.list";
Dir::Etc::sourceparts "$prefix/apt/empty";
Dir::State::lists "$prefix/apt/lists";
Dir::Cache::archives "$prefix/apt/cache/archives";
APT::Sandbox::User "$(id -un)";
EOF
    cat > "$prefix/apt/sources.list" <<'EOF'
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] https://deb.debian.org/debian trixie main
EOF
    export APT_CONFIG="$prefix/apt/apt.conf"
    apt-get -o APT::Update::Error-Mode=any update
    (
        cd "$prefix/apt/cache/archives"
        apt-get download iverilog yosys yosys-abc gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
        for package in ./*.deb; do dpkg-deb -x "$package" "$prefix/root"; done
    )
fi
source scripts/env.sh
if ! python3 -c 'import pyeda, numpy, matplotlib' >/dev/null 2>&1; then
    CC=gcc CXX=g++ CFLAGS='-Wno-error=incompatible-pointer-types' \
        python3 -m pip install --target "$prefix/python" -r requirements-dev.txt
fi
bash scripts/iverilog.sh -V > "$prefix/iverilog-version.txt" 2>&1
yosys -V
riscv64-unknown-elf-gcc --version | head -1
make firmware
echo 'Setup complete. Run make test; optional make benchmark and make synth.'
