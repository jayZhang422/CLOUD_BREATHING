# Stand-alone build of the Ethernet front end only (top = eth_rgmii_top), used to check the RGMII link
# without the compute core.  Not part of the main flow.
#
#   vivado -mode batch -nolog -nojournal -source build/build_ethernet.tcl
#
# Output goes to build/ethernet_only; the main project and build/flash/top.bit are left alone.
# Uses top_constraint.xdc (pin map of the Ethernet-only design), not the main project's constraints.

set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set out [file join $script_dir ethernet_only]
file mkdir $out
cd $out
set rtl [file join $root src rtl ethernet]
create_project -in_memory -part xcku5p-ffvb676-2-i
foreach dir {arp udp gmii_to_rgmii} {
    read_verilog [glob [file join $rtl $dir *.v]]
}
read_verilog -sv [glob [file join $rtl protocol *.sv]]
read_verilog -sv [file join $rtl eth_rgmii_top.sv]
read_xdc [file join $root src constraints top_constraint.xdc]
synth_design -top eth_rgmii_top -part xcku5p-ffvb676-2-i
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -report_unconstrained -file [file join $out timing_summary.rpt]
report_utilization -file [file join $out utilization.rpt]
report_drc -file [file join $out drc.rpt]
# Never present a timing-failing image as the ready-to-program artifact.
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup] == 0 || [llength $hold] == 0} {
    error "Missing timed paths; refusing to generate a bitstream"
}
if {[get_property SLACK $setup] < 0 || [get_property SLACK $hold] < 0} {
    error "Timing violations remain; see $out/timing_summary.rpt"
}
set timing_file [open [file join $out timing_summary.rpt] r]
set timing_text [read $timing_file]
close $timing_file
# Include pulse width and constraint coverage, not just setup/hold slack.
if {[string first "All user specified timing constraints are met." $timing_text] < 0} {
    error "Timing summary is not passing; refusing to generate a bitstream"
}
if {[regexp {checking (no_clock|constant_clock|unconstrained_internal_endpoints|multiple_clock|generated_clocks|loops|partial_input_delay|partial_output_delay|latch_loops) \(([1-9][0-9]*)\)} $timing_text]} {
    error "Incomplete or invalid timing constraints; see timing_summary.rpt"
}
foreach violation [get_drc_violations -quiet] {
    set severity [get_property SEVERITY $violation]
    if {[string match -nocase "*error*" $severity] || [string match -nocase "*critical*" $severity]} {
        error "DRC $severity remains; see drc.rpt"
    }
}
write_bitstream -force [file join $out eth_rgmii_top.bit]
