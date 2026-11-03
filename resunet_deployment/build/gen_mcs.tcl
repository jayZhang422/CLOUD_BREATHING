# Make a QSPI flash image (top.mcs / top.prm) from a bitstream.
#
#   vivado -mode batch -source build/gen_mcs.tcl
#   vivado -mode batch -source build/gen_mcs.tcl -tclargs <top.bit> <out_dir>
#
# Settings follow the original top.prm: MCS, SPIx4, 64 MB, start address 0x0.
# Flash device on the RK-XCKU5P-F board: mx25u51245g (512 Mb).
# Programming the bitstream directly with build/flash/program_qspi.bat does not need this file.

set script_dir [file dirname [file normalize [info script]]]
set bit [expr {[llength $argv] > 0 ? [file normalize [lindex $argv 0]] : [file join $script_dir flash top.bit]}]
set out [expr {[llength $argv] > 1 ? [file normalize [lindex $argv 1]] : [file join $script_dir out]}]
file mkdir $out

write_cfgmem -force -format mcs -size 64 -interface SPIx4 \
    -loadbit "up 0x00000000 $bit" \
    -file [file join $out top.mcs]
puts "INFO: wrote [file join $out top.mcs]"
