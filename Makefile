SHELL := /bin/bash
RTL := $(wildcard rtl/*.sv)
IVERILOG := bash scripts/iverilog.sh
VVP := bash scripts/vvp.sh
PYTHON ?= python3
.PHONY: all test rtl-test model-test formal firmware soc-test axi-test stats-test core-test traffic-test benchmark synth logic elaborate clean
all: test
build:
	mkdir -p build
firmware: build/firmware.hex
build/firmware.hex: firmware/main.c firmware/start.S firmware/link.ld scripts/bin2hex.py | build
	source scripts/env.sh; riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -Os -ffreestanding -fno-builtin -fno-pic -msmall-data-limit=0 -nostdlib -Wl,--no-relax -T firmware/link.ld firmware/start.S firmware/main.c -o build/firmware.elf
	source scripts/env.sh; riscv64-unknown-elf-objcopy -O binary build/firmware.elf build/firmware.bin
	$(PYTHON) scripts/bin2hex.py build/firmware.bin $@
soc-test: firmware
	$(IVERILOG) -g2012 -Irtl -s tb_soc -o build/soc $(RTL) tb/tb_soc.sv
	$(VVP) build/soc
	$(IVERILOG) -g2012 -Irtl -s tb_soc -Ptb_soc.FAST=1 -o build/soc_fast $(RTL) tb/tb_soc.sv
	$(VVP) build/soc_fast
stats-test: | build
	$(CXX) -std=c++17 -Wall -Wextra -Werror hls/welford.cpp hls/test_welford.cpp -o build/hls_stats
	build/hls_stats
	$(PYTHON) -m unittest tests.test_stats -v
model-test: | build
	$(PYTHON) -m unittest tests.test_network -v
axi-test: firmware
	$(IVERILOG) -g2012 -Irtl -s tb_axi -o build/axi $(RTL) tb/tb_axi.sv
	$(VVP) build/axi
	$(IVERILOG) -g2012 -Irtl -s tb_axi -Ptb_axi.FAST=1 -o build/axi_fast $(RTL) tb/tb_axi.sv
	$(VVP) build/axi_fast
build/isa.hex: firmware/isa.S firmware/link.ld | build
	source scripts/env.sh; riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -Wl,--no-relax -T firmware/link.ld firmware/isa.S -o build/isa.elf
	source scripts/env.sh; riscv64-unknown-elf-objcopy -O binary build/isa.elf build/isa.bin
	$(PYTHON) scripts/bin2hex.py build/isa.bin $@
core-test: build/isa.hex
	$(IVERILOG) -g2012 -s tb_core -o build/core rtl/rv32_core.sv tb/tb_core.sv
	$(VVP) build/core
traffic-test: | build
	$(IVERILOG) -g2012 -Irtl -s tb_traffic -o build/traffic $(RTL) tb/tb_traffic.sv
	$(VVP) build/traffic
	$(IVERILOG) -g2012 -Irtl -s tb_traffic -Ptb_traffic.FAST=1 -Ptb_traffic.NX=3 -Ptb_traffic.NY=3 -o build/traffic3 $(RTL) tb/tb_traffic.sv
	$(VVP) build/traffic3
rtl-test: model-test axi-test soc-test stats-test core-test traffic-test
formal: | build
	$(PYTHON) formal/check.py
logic: | build
	$(PYTHON) scripts/logic_opt.py
elaborate: firmware
	bash scripts/elaborate.sh
test: rtl-test formal elaborate
benchmark: | build
	$(PYTHON) -m model.benchmark
synth: | build
	bash scripts/synth.sh
clean:
	rm -rf build
