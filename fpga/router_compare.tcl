# vivado -mode batch -source fpga/router_compare.tcl -tclargs ACTUAL_PART PERIOD_NS
# Matched out-of-context constraints for baseline/fast/ESPRESSO comparisons.
if {$argc!=2} { error "Usage: ACTUAL_PART PERIOD_NS" }
set part [lindex $argv 0]
set period [lindex $argv 1]
foreach spec {{baseline 0 0} {fast 1 0} {espresso 0 1}} {
    lassign $spec name fast minimized
    set dir build/vivado_router/$name
    file mkdir $dir
    create_project -in_memory -part $part
    set_property include_dirs [list [file normalize rtl]] [current_fileset]
    read_verilog -sv [glob rtl/*.sv]
    synth_design -mode out_of_context -top noc_router -part $part \
        -generic [list X=1 Y=1 FAST=$fast MINIMIZED=$minimized]
    create_clock -name router_clock -period $period [get_ports clk]
    set_input_delay [expr {$period*0.2}] -clock router_clock [get_ports {rst in_flit* in_valid* out_credit*}]
    set_output_delay [expr {$period*0.2}] -clock router_clock [get_ports {out_flit* out_valid* in_credit*}]
    opt_design
    place_design
    phys_opt_design
    route_design
    report_utilization -file $dir/utilization.rpt
    report_timing_summary -delay_type min_max -file $dir/timing.rpt
    write_checkpoint -force $dir/routed.dcp
    close_project
}
