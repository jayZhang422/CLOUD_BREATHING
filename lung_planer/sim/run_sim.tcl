# Run the four pre-build RTL regressions in XSim (behavioral) and record PASS/FAIL.
# Needs the project from build/create_project.tcl. Usage:
#   vivado -mode batch -source lung_planer/sim/run_sim.tcl
# Results: sim/results/results.txt and per-simset xvlog/elaborate/simulate logs.
# All benches have a watchdog and $finish; the full set takes about 3 minutes.
set origin [file normalize [file dirname [info script]]]
set root   [file normalize $origin/..]
set xpr    $root/build/work/lung_planner/lung_planner.xpr
set out    $origin/results
set vec    $root/data/sim_vectors
if {![file exists $xpr]} { error "missing $xpr; run build/create_project.tcl first" }
open_project $xpr
file mkdir $out

# The ray-mesh BVH bench runs only synthetic vectors (patient-derived cases 2/3 are skipped).
set_property -dict [list xsim.simulate.xsim.more_options \
    "-testplusarg RAY_MESH_SYNTHETIC_ONLY -testplusarg RAY_MESH_DIR=$vec/ray_mesh_bvh"] [get_filesets sim_ray_mesh]
set_property -dict [list xsim.simulate.xsim.more_options \
    "-testplusarg CL_DIR=$vec/centerline_distance"] [get_filesets sim_centerline_distance]

set started [clock seconds]
set manifest [open $out/results.txt w]
set failed {}
foreach {simset marker} {
    sim_ray_mesh            RAY_MESH_RTL_PASS
    sim_1                   DUAL_PLANE_MESH_RTL_GEOMETRY_PASS
    sim_centerline_distance CENTERLINE_DISTANCE_CORE_TEST_PASS
    sim_branch_batch        DUAL_PLANE_BATCH_RTL_PASS
} {
    set fs [get_filesets $simset]
    current_fileset -simset $fs
    set_property xsim.simulate.runtime all $fs
    set_property xsim.simulate.log_all_signals false $fs
    update_compile_order -fileset $simset
    set t [clock seconds]
    launch_simulation -simset $simset -mode behavioral -batch
    set dir [file join [get_property DIRECTORY [current_project]] lung_planner.sim $simset behav xsim]
    foreach logfile {xvlog.log xvhdl.log elaborate.log simulate.log} {
        if {[file exists $dir/$logfile]} { file copy -force $dir/$logfile $out/${simset}_$logfile }
    }
    set f [open $dir/simulate.log r]; set log [read $f]; close $f
    if {[string match *$marker* $log] && ![regexp -nocase {Fatal:|ERROR:|watchdog timeout} $log]} {
        set status PASS
    } else {
        set status FAIL; lappend failed $simset
    }
    puts $manifest "$simset $status seconds=[expr {[clock seconds]-$t}] marker=$marker"
    flush $manifest
    catch {close_sim -force}
}
puts $manifest "TOTAL_SECONDS [expr {[clock seconds]-$started}]"
close $manifest
if {[llength $failed]} { error "SIMULATION_FAILED $failed; inspect $out" }
puts "LUNG_PLANNER_SIMULATION_PASS seconds=[expr {[clock seconds]-$started}]"
