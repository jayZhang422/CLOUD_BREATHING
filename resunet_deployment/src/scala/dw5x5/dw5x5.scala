// 文件类型：.scala。DW5x5 唯一可综合源实现，生成 Verilog 供工程引用。
// 16 lane 并行；5x5 窗口由现有 LineBuffer_5x5 提供，padding=2 已在窗口端完成。
import spinal.core._
import spinal.lib._

case class Dw5x5Config(maxGroups: Int = 32, lanes: Int = 16, shift: Int = 24) {
  require(maxGroups > 0 && maxGroups <= 32)
  require(lanes == 16)
  require(shift == 24)
  val WORD_BITS = lanes * 8
  val GROUP_BITS = log2Up(maxGroups + 1)
  val PARAM_BITS = lanes * (32 + 64 + 16 + 16)
  val WEIGHT_BITS = lanes * 25 * 8
}

case class Dw5x5Tag(config: Dw5x5Config) extends Bundle {
  val group = UInt(config.GROUP_BITS bits)
  val row = UInt(10 bits)
  val col = UInt(10 bits)
  val group_last = Bool()
  val last = Bool()
}

case class Dw5x5Window(config: Dw5x5Config) extends Bundle {
  val window = Vec(Vec(Bits(config.WORD_BITS bits), 5), 5)
  val tag = Dw5x5Tag(config)
}

case class Dw5x5Run(config: Dw5x5Config) extends Bundle {
  val groups = UInt(config.GROUP_BITS bits)
  val raw = Bool()
}

case class Dw5Products(config: Dw5x5Config) extends Bundle {
  val tag = Dw5x5Tag(config)
  val params = Bits(config.PARAM_BITS bits)
  val values = Vec(Vec(SInt(16 bits), 25), config.lanes)
}

case class Dw5Reduce(config: Dw5x5Config, count: Int, width: Int) extends Bundle {
  val tag = Dw5x5Tag(config)
  val params = Bits(config.PARAM_BITS bits)
  val values = Vec(Vec(SInt(width bits), count), config.lanes)
}

case class Dw5QuantInput(config: Dw5x5Config) extends Bundle {
  val tag = Dw5x5Tag(config)
  val raw = Bool()
  val mac = Vec(SInt(32 bits), config.lanes)
  val params = Bits(config.PARAM_BITS bits)
}

case class Dw5QuantProduct(config: Dw5x5Config) extends Bundle {
  val tag = Dw5x5Tag(config)
  val raw = Bool()
  val mac = Vec(SInt(32 bits), config.lanes)
  val params = Bits(config.PARAM_BITS bits)
  val value = Vec(SInt(64 bits), config.lanes)
}

case class Dw5QuantSum(config: Dw5x5Config) extends Bundle {
  val tag = Dw5x5Tag(config)
  val raw = Bool()
  val mac = Vec(SInt(32 bits), config.lanes)
  val params = Bits(config.PARAM_BITS bits)
  val value = Vec(SInt(64 bits), config.lanes)
}

case class Dw5QuantDivide(config: Dw5x5Config) extends Bundle {
  val tag = Dw5x5Tag(config)
  val raw = Bool()
  val mac = Vec(SInt(32 bits), config.lanes)
  val params = Bits(config.PARAM_BITS bits)
  val whole = Vec(SInt(40 bits), config.lanes)
  val remainder = Vec(UInt(64 bits), config.lanes)
}

case class Dw5QuantDecision(config: Dw5x5Config) extends Bundle {
  val tag = Dw5x5Tag(config)
  val raw = Bool()
  val mac = Vec(SInt(32 bits), config.lanes)
  val params = Bits(config.PARAM_BITS bits)
  val whole = Vec(SInt(40 bits), config.lanes)
  val increment = Bits(config.lanes bits)
}

case class Dw5Result(config: Dw5x5Config) extends Bundle {
  val tag = Dw5x5Tag(config)
  val mac = Vec(SInt(32 bits), config.lanes)
  val q = Vec(SInt(8 bits), config.lanes)
}

class Dw5x5(config: Dw5x5Config = Dw5x5Config()) extends Component {
  addAttribute("use_dsp", "yes")
  val io = new Bundle {
    val cfg_i = slave Stream(Dw5x5Run(config))
    val weights_i = slave Stream(Bits(config.WEIGHT_BITS bits))
    val params_i = slave Stream(Bits(config.PARAM_BITS bits))
    val input_i = slave Stream(Dw5x5Window(config))
    val output_o = master Stream(Dw5Result(config))
    val busy_o = out Bool()
    val done_o = out Bool()
  }

  val IDLE = U(0, 2 bits)
  val LOAD = U(1, 2 bits)
  val RUN = U(2, 2 bits)
  val state_r = Reg(UInt(2 bits)) init(IDLE)
  val run_r = Reg(Dw5x5Run(config))
  val weightCount_r = Reg(UInt(config.GROUP_BITS bits)) init(0)
  val paramCount_r = Reg(UInt(config.GROUP_BITS bits)) init(0)
  val done_r = Reg(Bool()) init(False)

  val weightMem = Mem(Bits(config.WEIGHT_BITS bits), config.maxGroups)
  val paramMem = Mem(Bits(config.PARAM_BITS bits), config.maxGroups)
  weightMem.addAttribute("ram_style", "block")
  paramMem.addAttribute("ram_style", "block")

  io.busy_o := state_r =/= IDLE
  io.done_o := done_r
  done_r := False
  io.cfg_i.ready := state_r === IDLE && io.cfg_i.groups =/= 0 && io.cfg_i.groups <= config.maxGroups
  io.weights_i.ready := state_r === LOAD && weightCount_r < run_r.groups
  io.params_i.ready := state_r === LOAD && paramCount_r < run_r.groups

  // 先锁存写端口，地址和宽权重不再从调度/计数器直接跨区驱动BRAM。
  val weightWriteValid_r = RegNext(io.weights_i.fire) init(False)
  val weightWriteAddress_r = RegNext(weightCount_r.resize(log2Up(config.maxGroups)))
  val weightWriteData_r = RegNext(io.weights_i.payload)
  weightWriteValid_r.addAttribute("max_fanout", 16)
  weightWriteAddress_r.addAttribute("max_fanout", 8)
  weightMem.write(weightWriteAddress_r, weightWriteData_r, weightWriteValid_r)

  when(io.cfg_i.fire) {
    run_r := io.cfg_i.payload
    weightCount_r := 0
    paramCount_r := 0
    state_r := LOAD
  }
  when(io.weights_i.fire) {
    weightCount_r := weightCount_r + 1
  }
  when(io.params_i.fire) {
    paramMem.write(paramCount_r.resize(log2Up(config.maxGroups)), io.params_i.payload, io.params_i.fire)
    paramCount_r := paramCount_r + 1
  }
  when(state_r === LOAD && weightCount_r === run_r.groups && paramCount_r === run_r.groups) {
    state_r := RUN
  }

  val req_valid_r = Reg(Bool()) init(False)
  val req_payload_r = Reg(Dw5x5Window(config))
  val groupAddress_w = io.input_i.payload.tag.group.resize(log2Up(config.maxGroups))
  val weight_q = weightMem.readSync(groupAddress_w, io.input_i.fire)
  val param_q = paramMem.readSync(groupAddress_w, io.input_i.fire)
  val operands = Stream(new Bundle {
    val window = Vec(Vec(Bits(config.WORD_BITS bits), 5), 5)
    val tag = Dw5x5Tag(config)
    val weights = Bits(config.WEIGHT_BITS bits)
    val params = Bits(config.PARAM_BITS bits)
  })
  operands.valid := req_valid_r
  operands.weights := weight_q
  operands.params := param_q
  operands.tag := req_payload_r.tag
  operands.window := req_payload_r.window
  io.input_i.ready := state_r === RUN && (!req_valid_r || operands.ready)
  when(io.input_i.fire) {
    req_payload_r := io.input_i.payload
    req_valid_r := True
  } elsewhen(operands.fire) {
    req_valid_r := False
  }

  // BRAM输出先寄存，再进入DSP；s2mPipe切断向上游广播的组合ready。
  val multiplyInput = operands.m2sPipe().s2mPipe()
  val products_w = Dw5Products(config)
  products_w.tag := multiplyInput.tag
  products_w.params := multiplyInput.params
  for (lane <- 0 until config.lanes; tap <- 0 until 25) {
    val row = tap / 5
    val col = tap % 5
    val pixel = multiplyInput.window(row)(col)(lane * 8, 8 bits).asSInt
    val weight = multiplyInput.weights((lane * 25 + tap) * 8, 8 bits).asSInt
    products_w.values(lane)(tap).addAttribute("use_dsp", "yes")
    products_w.values(lane)(tap) := pixel * weight
  }
  val products = multiplyInput.translateWith(products_w).m2sPipe()

  // 25 项平衡归约：13 -> 7 -> 4 -> 2 -> 1，每级独立寄存器切断组合路径。
  val reduce13_w = Dw5Reduce(config, 13, 17)
  reduce13_w.tag := products.tag
  reduce13_w.params := products.params
  for (lane <- 0 until config.lanes; i <- 0 until 12)
    reduce13_w.values(lane)(i) := products.values(lane)(2 * i).resize(17) + products.values(lane)(2 * i + 1).resize(17)
  for (lane <- 0 until config.lanes) reduce13_w.values(lane)(12) := products.values(lane)(24).resize(17)
  val reduce13 = products.translateWith(reduce13_w).m2sPipe()

  val reduce7_w = Dw5Reduce(config, 7, 18)
  reduce7_w.tag := reduce13.tag
  reduce7_w.params := reduce13.params
  for (lane <- 0 until config.lanes; i <- 0 until 6)
    reduce7_w.values(lane)(i) := reduce13.values(lane)(2 * i).resize(18) + reduce13.values(lane)(2 * i + 1).resize(18)
  for (lane <- 0 until config.lanes) reduce7_w.values(lane)(6) := reduce13.values(lane)(12).resize(18)
  val reduce7 = reduce13.translateWith(reduce7_w).m2sPipe()

  val reduce4_w = Dw5Reduce(config, 4, 19)
  reduce4_w.tag := reduce7.tag
  reduce4_w.params := reduce7.params
  for (lane <- 0 until config.lanes; i <- 0 until 3)
    reduce4_w.values(lane)(i) := reduce7.values(lane)(2 * i).resize(19) + reduce7.values(lane)(2 * i + 1).resize(19)
  for (lane <- 0 until config.lanes) reduce4_w.values(lane)(3) := reduce7.values(lane)(6).resize(19)
  val reduce4 = reduce7.translateWith(reduce4_w).m2sPipe().s2mPipe()

  val reduce2_w = Dw5Reduce(config, 2, 20)
  reduce2_w.tag := reduce4.tag
  reduce2_w.params := reduce4.params
  for (lane <- 0 until config.lanes) {
    reduce2_w.values(lane)(0) := reduce4.values(lane)(0).resize(20) + reduce4.values(lane)(1).resize(20)
    reduce2_w.values(lane)(1) := reduce4.values(lane)(2).resize(20) + reduce4.values(lane)(3).resize(20)
  }
  val reduce2 = reduce4.translateWith(reduce2_w).m2sPipe()

  val dot_w = Dw5Reduce(config, 1, 21)
  dot_w.tag := reduce2.tag
  dot_w.params := reduce2.params
  for (lane <- 0 until config.lanes)
    dot_w.values(lane)(0) := reduce2.values(lane)(0).resize(21) + reduce2.values(lane)(1).resize(21)
  val dot = reduce2.translateWith(dot_w).m2sPipe()

  val quantInput_w = Dw5QuantInput(config)
  quantInput_w.tag := dot.tag
  quantInput_w.raw := run_r.raw
  for (lane <- 0 until config.lanes) quantInput_w.mac(lane) := dot.values(lane)(0).resize(32)
  quantInput_w.params := dot.params
  val quantInput = dot.translateWith(quantInput_w).m2sPipe().s2mPipe()

  val product_w = Dw5QuantProduct(config)
  product_w.tag := quantInput.tag
  product_w.raw := quantInput.raw
  product_w.mac := quantInput.mac
  product_w.params := quantInput.params
  for (lane <- 0 until config.lanes) {
    val multiplier = quantInput.params((lane * 128), 32 bits).asSInt
    product_w.value(lane).addAttribute("use_dsp", "yes")
    product_w.value(lane) := quantInput.mac(lane) * multiplier
  }
  val product = quantInput.translateWith(product_w).m2sPipe()

  val sum_w = Dw5QuantSum(config)
  sum_w.tag := product.tag
  sum_w.raw := product.raw
  sum_w.mac := product.mac
  sum_w.params := product.params
  for (lane <- 0 until config.lanes) {
    val bias = product.params((lane * 128) + 32, 64 bits).asSInt
    sum_w.value(lane) := product.value(lane) + bias
  }
  val sum = product.translateWith(sum_w).m2sPipe()

  val divide_w = Dw5QuantDivide(config)
  divide_w.tag := sum.tag
  divide_w.raw := sum.raw
  divide_w.mac := sum.mac
  divide_w.params := sum.params
  val mask = (BigInt(1) << config.shift) - 1
  for (lane <- 0 until config.lanes) {
    divide_w.whole(lane) := sum.value(lane)(63 downto config.shift)
    divide_w.remainder(lane) := sum.value(lane).asUInt & U(mask, 64 bits)
  }
  val divide = sum.translateWith(divide_w).m2sPipe()

  val decision_w = Dw5QuantDecision(config)
  decision_w.tag := divide.tag
  decision_w.raw := divide.raw
  decision_w.mac := divide.mac
  decision_w.params := divide.params
  val half = U(BigInt(1) << (config.shift - 1), 64 bits)
  for (lane <- 0 until config.lanes) {
    decision_w.whole(lane) := divide.whole(lane)
    decision_w.increment(lane) := divide.remainder(lane) > half ||
      (divide.remainder(lane) === half && divide.whole(lane)(0))
  }
  val decision = divide.translateWith(decision_w).m2sPipe()

  val rounded_w = Dw5QuantSum(config)
  rounded_w.tag := decision.tag
  rounded_w.raw := decision.raw
  rounded_w.mac := decision.mac
  rounded_w.params := decision.params
  for (lane <- 0 until config.lanes)
    rounded_w.value(lane) := (decision.whole(lane).resize(64) + decision.increment(lane).asUInt.resize(64).asSInt).resize(64)
  val rounded = decision.translateWith(rounded_w).m2sPipe()

  val result_w = Dw5Result(config)
  result_w.tag := rounded.tag
  result_w.mac := rounded.mac
  for (lane <- 0 until config.lanes) {
    val lower = rounded.params((lane * 128) + 96, 16 bits).asSInt
    val upper = rounded.params((lane * 128) + 112, 16 bits).asSInt
    val clipped = SInt(8 bits)
    clipped := rounded.value(lane).resize(8)
    when(rounded.value(lane) < lower.resize(64)) { clipped := lower.resize(8) }
      .elsewhen(rounded.value(lane) > upper.resize(64)) { clipped := upper.resize(8) }
    result_w.q(lane) := Mux(rounded.raw, S(0, 8 bits), clipped)
  }
  io.output_o << rounded.translateWith(result_w).m2sPipe()
  Seq(operands, multiplyInput, products, reduce13, reduce7, reduce4, reduce2, dot, quantInput, product, sum, divide, decision, rounded)
    .foreach(_.ready.addAttribute("max_fanout", 64))
  when(io.output_o.fire && io.output_o.tag.last) {
    state_r := IDLE
    done_r := True
  }
}
