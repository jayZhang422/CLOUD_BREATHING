// 文件类型：.scala。独立联合验证壳：原算子复用；缓存/阶段调度由 SpinalSim 提供。
import spinal.core._
import spinal.lib._

case class DecoderConcatConfig() extends Bundle {
  val base1 = UInt(32 bits)
  val base2 = UInt(32 bits)
  val words1 = UInt(32 bits)
  val words2 = UInt(32 bits)
}
case class DecoderRead() extends Bundle {
  val source = Bool()
  val address = UInt(32 bits)
}
// 包装现有唯一 Concat RTL，不重写调度器，不引入官方 IP。
class DecoderConcat(rtlPath: String) extends BlackBox {
  val io = new Bundle {
    val clk_i = in Bool()
    val rst_n_i = in Bool()
    val cfg_valid_i = in Bool()
    val cfg_ready_o = out Bool()
    val busy_o = out Bool()
    val done_o = out Bool()
    val rd_valid_o = out Bool()
    val rd_ready_i = in Bool()
    val rsp_valid_i = in Bool()
    val rsp_ready_o = out Bool()
    val valid_o = out Bool()
    val ready_i = in Bool()
    val last_o = out Bool()
    val cfg_base1_i = in UInt(32 bits)
    val cfg_base2_i = in UInt(32 bits)
    val cfg_words1_i = in UInt(32 bits)
    val cfg_words2_i = in UInt(32 bits)
    val rd_source_o = out Bool()
    val rd_addr_o = out UInt(32 bits)
    val rsp_data_i = in Bits(128 bits)
    val data_o = out Bits(128 bits)
  }
  noIoPrefix()
  setBlackBoxName("concat")
  addRTLPath(rtlPath)
  mapClockDomain(clockDomain = ClockDomain.current, clock = io.clk_i,
    reset = io.rst_n_i, resetActiveLevel = LOW)
}

class DecoderD3Harness(concatPath: String) extends Component {
  val io = new Bundle {
    val up_cfg_i = slave Stream(UpsampleRunConfig(UpsampleConfig()))
    val up_input_i = slave Stream(Bits(128 bits))
    val up_output_o = master Stream(Fragment(UpsampleWord(UpsampleConfig())))
    val up_done_o = out Bool()
    val cat_cfg_i = slave Stream(DecoderConcatConfig())
    val cat_rd_o = master Stream(DecoderRead())
    val cat_rsp_i = slave Stream(Bits(128 bits))
    val cat_output_o = master Stream(Fragment(Bits(128 bits)))
    val cat_done_o = out Bool()
    val pw_cfg_i = slave Stream(PwRun())
    val pw_weights_i = slave Stream(Bits(512 bits))
    val pw_params_i = slave Stream(Bits(512 bits))
    val pw_start_i = slave Stream(Bool())
    val pw_rd_o = master Stream(UInt(32 bits))
    val pw_rsp_i = slave Stream(Bits(128 bits))
    val pw_output_o = master Stream(PwResult())
    val pw_done_o = out Bool()
    val lb3_cfg_i = slave Stream(LineBufferRunConfig(LineBufferConfig(k = 3)))
    val lb5_cfg_i = slave Stream(LineBufferRunConfig(LineBufferConfig(k = 5)))
    val lb3_input_i = slave Stream(Bits(128 bits))
    val lb5_input_i = slave Stream(Bits(128 bits))
    val dw3_cfg_i = slave Stream(Dw3x3Run(Dw3x3Config()))
    val dw5_cfg_i = slave Stream(Dw5x5Run(Dw5x5Config()))
    val dw3_weights_i = slave Stream(Bits(1152 bits))
    val dw5_weights_i = slave Stream(Bits(3200 bits))
    val dw3_params_i = slave Stream(Bits(2048 bits))
    val dw5_params_i = slave Stream(Bits(2048 bits))
    val mix_cfg_i = slave Stream(ElementAddRunConfig(ElementAddConfig()))
    val mix_output_o = master Stream(Fragment(ElementAddWord(ElementAddConfig())))
    val mix_done_o = out Bool()
    val final_cfg_i = slave Stream(ElementAddRunConfig(ElementAddConfig()))
    val final_a_i = slave Stream(Bits(512 bits))
    val final_b_i = slave Stream(Bits(512 bits))
    val final_output_o = master Stream(Fragment(ElementAddWord(ElementAddConfig())))
    val final_done_o = out Bool()
  }
  val up = new Upsample()
  up.io.cfg_i << io.up_cfg_i
  up.io.input_i << io.up_input_i
  io.up_output_o << up.io.output_o
  io.up_done_o := up.io.done_o

  val cat = new DecoderConcat(concatPath)
  cat.io.cfg_valid_i := io.cat_cfg_i.valid
  io.cat_cfg_i.ready := cat.io.cfg_ready_o
  cat.io.cfg_base1_i := io.cat_cfg_i.base1
  cat.io.cfg_base2_i := io.cat_cfg_i.base2
  cat.io.cfg_words1_i := io.cat_cfg_i.words1
  cat.io.cfg_words2_i := io.cat_cfg_i.words2
  io.cat_rd_o.valid := cat.io.rd_valid_o
  io.cat_rd_o.source := cat.io.rd_source_o
  io.cat_rd_o.address := cat.io.rd_addr_o
  cat.io.rd_ready_i := io.cat_rd_o.ready
  cat.io.rsp_valid_i := io.cat_rsp_i.valid
  cat.io.rsp_data_i := io.cat_rsp_i.payload
  io.cat_rsp_i.ready := cat.io.rsp_ready_o
  io.cat_output_o.valid := cat.io.valid_o
  io.cat_output_o.fragment := cat.io.data_o
  io.cat_output_o.last := cat.io.last_o
  cat.io.ready_i := io.cat_output_o.ready
  io.cat_done_o := cat.io.done_o

  // 按层分时复用同一 PW，PE4 输出由测试缓存按标签组装为 P16。
  val pw = new PwMac() // 沿用已验证默认容量；实际 cin/cout 在任务配置中限制。
  pw.io.cfg_i << io.pw_cfg_i
  pw.io.weights_i << io.pw_weights_i
  pw.io.params_i << io.pw_params_i
  pw.io.start_i << io.pw_start_i
  io.pw_rd_o << pw.io.rd_o
  pw.io.rsp_i << io.pw_rsp_i
  io.pw_output_o << pw.io.output_o
  io.pw_done_o := pw.io.done_o

  val lb3 = new LineBuffer(LineBufferConfig(k = 3))
  val lb5 = new LineBuffer(LineBufferConfig(k = 5))
  val dw3 = new Dw3x3()
  val dw5 = new Dw5x5()
  val mix = new ElementAdd(ElementAddConfig())
  lb3.io.cfg_i << io.lb3_cfg_i
  lb5.io.cfg_i << io.lb5_cfg_i
  lb3.io.input_i << io.lb3_input_i
  lb5.io.input_i << io.lb5_input_i
  dw3.io.cfg_i << io.dw3_cfg_i
  dw5.io.cfg_i << io.dw5_cfg_i
  dw3.io.weights_i << io.dw3_weights_i
  dw5.io.weights_i << io.dw5_weights_i
  dw3.io.params_i << io.dw3_params_i
  dw5.io.params_i << io.dw5_params_i

  // LineBuffer 与 DW/merge 是直接硬件 Stream 连接。尺寸随各自配置锁存。
  val width3_r = Reg(UInt(10 bits)) init(1)
  val height3_r = Reg(UInt(10 bits)) init(1)
  val width5_r = Reg(UInt(10 bits)) init(1)
  val height5_r = Reg(UInt(10 bits)) init(1)
  val row3_r = Reg(UInt(10 bits)) init(0)
  val col3_r = Reg(UInt(10 bits)) init(0)
  val row5_r = Reg(UInt(10 bits)) init(0)
  val col5_r = Reg(UInt(10 bits)) init(0)
  when(io.lb3_cfg_i.fire) {
    width3_r := io.lb3_cfg_i.width.resized; height3_r := io.lb3_cfg_i.height.resized
    row3_r := 0; col3_r := 0
  }
  when(io.lb5_cfg_i.fire) {
    width5_r := io.lb5_cfg_i.width.resized; height5_r := io.lb5_cfg_i.height.resized
    row5_r := 0; col5_r := 0
  }
  dw3.io.input_i.valid := lb3.io.output_o.valid
  lb3.io.output_o.ready := dw3.io.input_i.ready
  dw3.io.input_i.window := lb3.io.output_o.fragment.window
  dw3.io.input_i.tag.group := lb3.io.output_o.fragment.group
  dw3.io.input_i.tag.row := row3_r; dw3.io.input_i.tag.col := col3_r
  dw3.io.input_i.tag.group_last := lb3.io.output_o.fragment.group_last
  dw3.io.input_i.tag.last := lb3.io.output_o.last
  dw5.io.input_i.valid := lb5.io.output_o.valid
  lb5.io.output_o.ready := dw5.io.input_i.ready
  dw5.io.input_i.window := lb5.io.output_o.fragment.window
  dw5.io.input_i.tag.group := lb5.io.output_o.fragment.group
  dw5.io.input_i.tag.row := row5_r; dw5.io.input_i.tag.col := col5_r
  dw5.io.input_i.tag.group_last := lb5.io.output_o.fragment.group_last
  dw5.io.input_i.tag.last := lb5.io.output_o.last
  for ((stream, row, col, width, height) <- Seq(
    (lb3.io.output_o, row3_r, col3_r, width3_r, height3_r),
    (lb5.io.output_o, row5_r, col5_r, width5_r, height5_r))) {
    when(stream.fire) {
      col := col + U(1, 10 bits)
      when(col === width - U(1, 10 bits)) {
        col := 0
        row := row + U(1, 10 bits)
        when(row === height - U(1, 10 bits)) { row := 0 }
      }
    }
  }
  mix.io.cfg_i << io.mix_cfg_i
  mix.io.a_i.valid := dw3.io.output_o.valid
  mix.io.b_i.valid := dw5.io.output_o.valid
  dw3.io.output_o.ready := mix.io.a_i.ready
  dw5.io.output_o.ready := mix.io.b_i.ready
  for (lane <- 0 until 16) {
    mix.io.a_i.payload(lane * 32, 32 bits) := dw3.io.output_o.mac(lane).asBits
    mix.io.b_i.payload(lane * 32, 32 bits) := dw5.io.output_o.mac(lane).asBits
  }
  io.mix_output_o << mix.io.output_o
  io.mix_done_o := mix.io.done_o
  val finalAdd = new ElementAdd(ElementAddConfig())
  finalAdd.io.cfg_i << io.final_cfg_i
  finalAdd.io.a_i << io.final_a_i
  finalAdd.io.b_i << io.final_b_i
  io.final_output_o << finalAdd.io.output_o
  io.final_done_o := finalAdd.io.done_o
}
