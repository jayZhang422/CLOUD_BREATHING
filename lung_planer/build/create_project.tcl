# Recreate the lung_planner Vivado project (Vivado 2026.1, xck26-sfvc784-2LV-c, KV260).
# Minimal source set: only the RTL reachable from the four block-design modules
# (centerline_distance_axi, dual_plane_filter_axi, dual_plane_mesh_axi, lung_ray_mesh_axi)
# and the four FP64 IPs they instantiate.
# Usage (any working directory):
#   vivado -mode batch -source lung_planer/build/create_project.tcl                # project only
#   vivado -mode batch -source lung_planer/build/create_project.tcl -tclargs build # + bitstream
# The project is created in build/work/lung_planner; board files go to build/output.
set origin [file normalize [file dirname [info script]]]
set root   [file normalize $origin/..]
set proj   lung_planner
set work   $origin/work

create_project -force $proj $work/$proj -part xck26-sfvc784-2LV-c
set_property board_part xilinx.com:kv260_som:part0:2.0 [current_project]
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

proc addf {fs files} {
    global root
    foreach f $files { add_files -norecurse -fileset $fs $root/$f }
}

# ---- RTL ----
addf [get_filesets sources_1] {
    src/rtl/centerline_distance_axi.v src/rtl/centerline_distance_core.v
    src/rtl/centerline_lee_axis.v src/rtl/centerline_lee_candidate.v src/rtl/centerline_lee_tables.vh
    src/rtl/dual_plane_filter_axi.v src/rtl/dual_plane_batch_filter_core.v
    src/rtl/dual_plane_mesh_axi.v src/rtl/dual_plane_mesh_abi.vh src/rtl/dual_plane_boundary_extract.v
    src/rtl/dual_plane_bvh_classify.v src/rtl/dual_plane_fp64_accumulator.v src/rtl/dual_plane_fp64_alu.v
    src/rtl/dual_plane_mesh_geometry.v src/rtl/dual_plane_polygon_reduce.v
    src/rtl/dual_plane_segment_integral.v src/rtl/dual_plane_triangle_clip.v
    src/rtl/lung_ray_mesh_axi.v src/rtl/lung_ray_triangle_stage3_core.v src/rtl/lung_ray_union_core.v
    src/rtl/lung_ray_volume_core.v src/rtl/lung_ray_aabb_core.v src/rtl/lung_distance_math.v
    src/rtl/lung_point_aabb_distance_core.v src/rtl/lung_point_triangle_distance_core.v
    src/rtl/lung_unsigned_divider.v
}
set_property include_dirs [list $root/src/rtl] [get_filesets sources_1]

# ---- Simulation filesets (the four pre-build regressions, see sim/run_sim.tcl) ----
addf [get_filesets sim_1] {sim/tb/tb_dual_plane_mesh_axi.sv}
set_property top tb_dual_plane_mesh_axi [get_filesets sim_1]
create_fileset -simset sim_ray_mesh
addf [get_filesets sim_ray_mesh] {sim/tb/tb_lung_ray_mesh_bvh.v}
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_ray_mesh] tb_lung_ray_mesh_bvh.v]
set_property top tb_lung_ray_mesh_bvh [get_filesets sim_ray_mesh]
create_fileset -simset sim_centerline_distance
addf [get_filesets sim_centerline_distance] {sim/tb/tb_centerline_distance_core.sv}
set_property top tb_centerline_distance_axi [get_filesets sim_centerline_distance]
create_fileset -simset sim_branch_batch
addf [get_filesets sim_branch_batch] {sim/tb/tb_dual_plane_batch_filter_core.sv}
set_property top tb_dual_plane_batch_filter_core [get_filesets sim_branch_batch]

# ---- IEEE-754 double precision floating-point IPs (global synthesis) ----
proc make_fp {name operation} {
    create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 \
        -module_name $name -dir $::work/$::proj/$::proj.srcs/sources_1/ip
    set ip [get_ips $name]
    set_property -dict [list CONFIG.A_Precision_Type {Double} \
        CONFIG.Result_Precision_Type {Double} CONFIG.Operation_Type $operation \
        CONFIG.C_Optimization {Speed_Optimized} CONFIG.Flow_Control {Blocking} \
        CONFIG.Has_ARESETn true] $ip
    set_property GENERATE_SYNTH_CHECKPOINT false [get_files [get_property IP_FILE $ip]]
    generate_target all $ip
}
make_fp dpm_fp_add    Add_Subtract
make_fp dpm_fp_mul    Multiply
make_fp dpm_fp_divide Divide
make_fp dpm_fp_sqrt   Square_root

# ---- Block design (PS + AXI DMA + PL cores) and wrapper ----
update_compile_order -fileset sources_1
source $root/src/bd/lung_planner_system_bd.tcl
set_property synth_checkpoint_mode None [get_files lung_planner_system.bd]
generate_target all [get_files lung_planner_system.bd]
make_wrapper -files [get_files lung_planner_system.bd] -top
add_files -norecurse $work/$proj/$proj.gen/sources_1/bd/lung_planner_system/hdl/lung_planner_system_wrapper.v
set_property top lung_planner_system_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

# ---- Implementation strategy (same as the board-validated build) ----
set_property STEPS.INIT_DESIGN.TCL.PRE $origin/single_thread_hook.tcl [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE AltSpreadLogic_high [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AlternateCLBRouting [get_runs impl_1]
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]

if {[lsearch $argv build] >= 0} {
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "impl_1 failed" }
    source $origin/export_outputs.tcl
}
puts "LUNG_PLANNER_PROJECT_READY $work/$proj/$proj.xpr"
