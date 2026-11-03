`timescale 1ns/1ps
module tb_stream250_op12_compare;
wire af,aslow,bf,bs;
move_op12_runner #(.FAST(1)) after_fast(af);
move_op12_runner #(.FAST(0)) after_slow(aslow);
stream250_op12_before #(.FAST(1)) before_fast(bf);
stream250_op12_before #(.FAST(0)) before_slow(bs);
initial begin
 $dumpfile("waveform.vcd"); $dumpvars(0,after_fast.clk_i,after_fast.rst_n_i,after_fast.done_o,after_slow.done_o,before_fast.done_o,before_slow.done_o);
 wait(af && aslow && bf && bs);
 for(int i=0;i<2;i++) begin
  $display("[CYCLE COMPARE] op12 case=%0d fast_before=%0d fast_after=%0d slow_before=%0d slow_after=%0d",i,before_fast.run_cycles[i],after_fast.run_cycles[i],before_slow.run_cycles[i],after_slow.run_cycles[i]);
  if(after_fast.run_cycles[i]>before_fast.run_cycles[i] || after_slow.run_cycles[i]>before_slow.run_cycles[i]) begin $error("op12 cycle regression"); $stop; end
 end
 $display("[TB PASSED] op12 frozen baseline/current fast+slow DDR and full Golden"); $finish;
end
endmodule
