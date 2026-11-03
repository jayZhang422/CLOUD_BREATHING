# Synthesis -> implementation -> bitstream for the project made by create_project.tcl.
#
#   vivado -mode batch -source build/run_flow.tcl
#   vivado -mode batch -source build/run_flow.tcl -tclargs <project_dir> <out_dir> <jobs>
#
# Defaults: project build/vivado, results build/out, 8 jobs.
# Strategy: Vivado defaults (the original project uses "Vivado Synthesis Defaults" / "Vivado Implementation Defaults").
# Runtime on the original machine: opt 11 min, place 38 min, route 30 min.
# The committed build/flash/top.bit is NOT touched; copy the new one over it yourself after checking timing.

set script_dir [file dirname [file normalize [info script]]]
set proj_dir [expr {[llength $argv] > 0 ? [file normalize [lindex $argv 0]] : [file join $script_dir vivado]}]
set out_dir  [expr {[llength $argv] > 1 ? [file normalize [lindex $argv 1]] : [file join $script_dir out]}]
set jobs     [expr {[llength $argv] > 2 ? [lindex $argv 2] : 8}]

file mkdir $out_dir
open_project [file join $proj_dir Model_Deployment.xpr]

reset_run synth_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "synth_1 failed: [get_property STATUS [get_runs synth_1]]" }

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "impl_1 failed: [get_property STATUS [get_runs impl_1]]" }

open_run impl_1
set run_dir [get_property DIRECTORY [get_runs impl_1]]
report_timing_summary -file [file join $out_dir top_timing_summary_routed.rpt]
report_utilization    -file [file join $out_dir top_utilization_placed.rpt]
report_power          -file [file join $out_dir top_power_routed.rpt]
report_route_status   -file [file join $out_dir top_route_status.rpt]
report_drc            -file [file join $out_dir top_drc_routed.rpt]

foreach f {top.bit top.ltx top.mmi} { file copy -force [file join $run_dir $f] $out_dir }

# Same gate as build_ethernet.tcl: do not hand out a timing-failing image.
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
puts "INFO: WNS=$wns ns  WHS=$whs ns"
if {$wns < 0 || $whs < 0} { error "Timing not met (WNS=$wns, WHS=$whs); do not program this bitstream." }
puts "INFO: done, results in $out_dir"
close_project
