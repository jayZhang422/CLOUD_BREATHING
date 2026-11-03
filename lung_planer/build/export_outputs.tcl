# Copy board files and implementation reports out of the generated project.
# Called by create_project.tcl after "build"; can also be sourced on its own:
#   vivado -mode batch -source lung_planer/build/export_outputs.tcl
#   build/output/lung_planner.bit      PYNQ Overlay bitstream
#   build/output/lung_planner.bit.bin  same bitstream for fpgautil/xmutil
#   build/output/lung_planner.hwh      PYNQ hardware handoff
#   build/reports/*.rpt                              synthesis and implementation reports
set origin [file normalize [file dirname [info script]]]
set proj   lung_planner
set name   lung_planner
set runs   $origin/work/$proj/$proj.runs
set impl   $runs/impl_1
set hwh    $origin/work/$proj/$proj.gen/sources_1/bd/lung_planner_system/hw_handoff/lung_planner_system.hwh
set out    $origin/output
set rpt    $origin/reports

foreach f [list $impl/lung_planner_system_wrapper.bit $impl/lung_planner_system_wrapper.bin $hwh] {
    if {![file exists $f]} { error "missing $f; run create_project.tcl -tclargs build first" }
}
file mkdir $out $rpt
file copy -force $impl/lung_planner_system_wrapper.bit $out/$name.bit
file copy -force $impl/lung_planner_system_wrapper.bin $out/$name.bit.bin
file copy -force $hwh $out/$name.hwh
foreach f [concat [glob -nocomplain $impl/*.rpt] [glob -nocomplain $runs/synth_1/*.rpt]] {
    file copy -force $f $rpt/[file tail $f]
}
puts "LUNG_PLANNER_BOARD_FILES_READY $out"
