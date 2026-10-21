# vitis_hls -f hls/run.tcl (set FPGA_PART and HLS_CLOCK_NS from selected board).
if {![info exists ::env(FPGA_PART)] || ![info exists ::env(HLS_CLOCK_NS)]} {
    error "Set actual FPGA_PART and HLS_CLOCK_NS"
}
open_project -reset build/welford_hls
set_top welford
add_files hls/welford.cpp
add_files -tb hls/test_welford.cpp
open_solution -reset solution
set_part $::env(FPGA_PART)
create_clock -period $::env(HLS_CLOCK_NS)
csim_design
csynth_design
export_design -format ip_catalog
exit
