# From repository root:
# vivado -mode batch -source fpga/build.tcl -tclargs PART board.xdc CLK_HZ FAST
# No part or pin assignment is guessed. Supply a reviewed board master XDC
# narrowed to clk, reset_n and uart_tx; debug outputs may be left internal via
# a custom board wrapper. This flow uses noc_board_top with just these I/Os.
if {$argc < 3} { error "Usage: PART XDC_PATH CLK_HZ ?FAST?" }
set part [lindex $argv 0]
set xdc [file normalize [lindex $argv 1]]
set hz [lindex $argv 2]
set fast 0
if {$argc > 3} { set fast [lindex $argv 3] }
if {![file exists $xdc]} { error "Supply actual reviewed board constraints" }
if {![string is integer -strict $hz] || $hz < 115200} { error "Invalid clock frequency" }
if {![file exists build/firmware.hex]} { error "Run make firmware first" }
file mkdir build/vivado
create_project -in_memory -part $part
set_property target_language Verilog [current_project]
set_property include_dirs [list [file normalize rtl]] [current_fileset]
read_verilog -sv [glob rtl/*.sv]
read_xdc $xdc
synth_design -top noc_board_top -part $part -generic [list CLK_HZ=$hz FAST=$fast]
# Create a clock only if the provided board XDC has not defined it.
if {[llength [get_clocks -quiet -of_objects [get_ports clk]]] == 0} {
    create_clock -name sys_clk -period [expr {1.0e9/$hz}] [get_ports clk]
}
report_utilization -hierarchical -file build/vivado/post_synth_utilization.rpt
write_checkpoint -force build/vivado/post_synth.dcp
opt_design
place_design
phys_opt_design
route_design
report_utilization -file build/vivado/utilization.rpt
report_timing_summary -delay_type min_max -check_timing_verbose -file build/vivado/timing.rpt
report_drc -file build/vivado/drc.rpt
report_methodology -file build/vivado/methodology.rpt
report_clock_interaction -file build/vivado/clocks.rpt
report_io -file build/vivado/io.rpt
write_checkpoint -force build/vivado/routed.dcp
set worst [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $worst]==0 || [get_property SLACK $worst]<0} { error "Setup timing failed" }
if {[llength $hold]==0 || [get_property SLACK $hold]<0} { error "Hold timing failed" }
foreach port [get_ports] {
    if {[get_property PACKAGE_PIN $port] eq "" || [get_property IOSTANDARD $port] eq "DEFAULT"} {
        error "Unconstrained board port: $port"
    }
}
write_bitstream -force build/vivado/noc.bit
