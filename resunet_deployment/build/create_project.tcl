# Recreate the Vivado project from the sources in this repository.
#
#   vivado -mode batch -source build/create_project.tcl
#   vivado -mode batch -source build/create_project.tcl -tclargs <project_dir>
#
# Tool: Vivado 2026.1.  Part: xcku5p-ffvb676-2-i.  Top: top.
# The project is written outside the source tree (default: build/vivado) and is not meant to be committed.

set script_dir [file dirname [file normalize [info script]]]
set root       [file normalize [file join $script_dir ..]]
set proj_dir   [expr {[llength $argv] > 0 ? [file normalize [lindex $argv 0]] : [file join $script_dir vivado]}]
set proj_name  Model_Deployment
set part       xcku5p-ffvb676-2-i

set rtl_dir    [file join $root src rtl]
set ip_dir     [file join $root src ip]
set xdc_dir    [file join $root src constraints]
set params_dir [file join $root src params]

file mkdir $proj_dir
create_project -force $proj_name $proj_dir -part $part
set_property target_language Verilog [current_project]
set_property default_lib xil_defaultlib [current_project]

# ---------------------------------------------------------------- RTL
# Plain Verilog (mostly SpinalHDL output) and SystemVerilog are read separately.
# pwmac.v (module PwMac / PwRequant) is kept in the project but disabled, as in the original project:
# the design instantiates PwMacShared only.
set v_files  [list]
set sv_files [list]
foreach f [glob -nocomplain -directory $rtl_dir -types f *.v *.sv] { lappend sv_files $f }
foreach sub {ddr ethernet/arp ethernet/udp ethernet/gmii_to_rgmii op/dw op/elementadd op/linebuffer op/maxpool op/pw op/upsample} {
    foreach f [glob -nocomplain -directory [file join $rtl_dir {*}[split $sub /]] -types f *.v] { lappend v_files $f }
}
foreach sub {ethernet ethernet/protocol op op/concat op/shuffle op/control} {
    foreach f [glob -nocomplain -directory [file join $rtl_dir {*}[split $sub /]] -types f *.sv] { lappend sv_files $f }
}
set sv_files [lsort -unique $sv_files]
add_files -norecurse -fileset sources_1 $v_files
add_files -norecurse -fileset sources_1 $sv_files
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sources_1] [file join $rtl_dir top.sv]]
foreach f $sv_files { set_property file_type SystemVerilog [get_files $f] }
set pwmac [get_files -quiet [file join $rtl_dir op pw pwmac.v]]
if {$pwmac ne ""} { set_property IS_ENABLED false $pwmac }
set_property top top [get_filesets sources_1]

# ---------------------------------------------------------------- IP (26 .xci)
# import_ip copies each .xci into the project, so the repository files are never modified by Vivado.
# quantized_params_rom.xci points at ../../params/quantized_params_rom.coe relative to its own folder, which no
# longer holds after the copy, so each .xci is staged first and that one path is made absolute in the staged copy.
set rom_coe [file normalize [file join $params_dir quantized_params_rom.coe]]
set stage [file join $proj_dir ip_stage]
file mkdir $stage
foreach xci [lsort [glob -directory $ip_dir -types f */*.xci]] {
    set name [file rootname [file tail $xci]]
    file mkdir [file join $stage $name]
    set fin [open $xci r]; set text [read $fin]; close $fin
    set text [string map [list "../../params/quantized_params_rom.coe" $rom_coe] $text]
    set staged [file join $stage $name $name.xci]
    set fout [open $staged w]; puts -nonewline $fout $text; close $fout
    import_ip $staged
}
generate_target all [get_ips]

# ---------------------------------------------------------------- constraints
set xdcs [list ethernet_ddr_constraint.xdc op_request_cdc_constraint.xdc op_coeff_rom_fanout.xdc spi_config.xdc]
foreach x $xdcs { add_files -norecurse -fileset constrs_1 [file join $xdc_dir $x] }
foreach x {ethernet_ddr_constraint.xdc spi_config.xdc} {
    set_property USED_IN {synthesis implementation} [get_files [file join $xdc_dir $x]]
}
foreach x {op_request_cdc_constraint.xdc op_coeff_rom_fanout.xdc} {
    set f [get_files [file join $xdc_dir $x]]
    set_property USED_IN {implementation} $f
    set_property PROCESSING_ORDER LATE $f
}
set_property target_constrs_file [file join $xdc_dir spi_config.xdc] [current_fileset -constrset]

update_compile_order -fileset sources_1
puts "INFO: project created at $proj_dir/$proj_name.xpr"
close_project
