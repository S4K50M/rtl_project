# vivado -mode batch -source fpga/program.tcl -tclargs build/vivado/noc.bit
if {$argc != 1 || ![file exists [lindex $argv 0]]} { error "Supply bitstream" }
open_hw_manager
connect_hw_server
open_hw_target
set devices [get_hw_devices]
if {[llength $devices]!=1} { error "Select the intended FPGA explicitly; expected one device" }
set dev [lindex $devices 0]
current_hw_device $dev
refresh_hw_device $dev
set_property PROGRAM.FILE [file normalize [lindex $argv 0]] $dev
program_hw_devices $dev
refresh_hw_device $dev
