# Functional simulation without board selection. Run from repository root.
# vivado -mode batch -source fpga/xsim.tcl
if {![file exists build/firmware.hex]} { error "Run make firmware first" }
create_project -in_memory
set_property include_dirs [list [file normalize rtl]] [current_fileset]
add_files [glob rtl/*.sv]
add_files -fileset sim_1 [list tb/tb_soc.sv tb/tb_axi.sv]
set_property xsim.simulate.runtime all [get_filesets sim_1]
# readmemh is relative to the simulator working directory: supply an absolute
# path through the testbench parameter instead of relying on XSim's cwd.
set_property generic [list MEM_FILE=\"[file normalize build/firmware.hex]\"] [get_filesets sim_1]
set_property top tb_soc [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
set_property top tb_axi [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
