// 文件类型：.scala。两路 INT32 × 逐通道乘数，在宽整数域合并固定偏置。
// P=16；配置按完整通道组加载；仅在合并后执行一次 RNE 和 INT8 限幅。
import spinal.core._
import spinal.lib._

case class ElementAddConfig() {
  val P = 16
  val ACC_BITS = 32
  // 当前三套冻结包的双路 merge 最大乘数 1398725，signed 22 bit 足够。
  val MULT_BITS = 22
  val PRODUCT_BITS = ACC_BITS + MULT_BITS
  val SUM_BITS = 66 // 含 INT64 偏置和保护位，不提前截断/饱和。
  val MAX_WORDS = 512 * 512
  val COUNT_BITS = log2Up(MAX_WORDS + 1)
  val MAX_GROUPS = 32
  val GROUP_BITS = log2Up(MAX_GROUPS + 1)
}

case class ElementAddRunConfig(c: ElementAddConfig) extends Bundle {
  val words = UInt(c.COUNT_BITS bits)                         // 当前组像素数
  val group = UInt(c.GROUP_BITS bits)                         // 通道组号 0..31
  val last_group = Bool()                                    // 是否为任务末组
  val multiplier_a = Vec(SInt(c.MULT_BITS bits), c.P)
  val multiplier_b = Vec(SInt(c.MULT_BITS bits), c.P)
  val bias_fixed = Vec(SInt(64 bits), c.P)                    // 两路偏置已合并，不能再加各路浮点偏置
  val shift = UInt(6 bits)                                   // 0..63；当前冻结包为 24
  val clamp_min = SInt(8 bits)                               // 普通 INT8=-128；ReLU6=0
  val clamp_max = SInt(8 bits)                               // min(127, RNE(6 / output_scale))
}

case class ElementAddWord(c: ElementAddConfig) extends Bundle {
  val data = Bits(c.P * 8 bits)
  val group = UInt(c.GROUP_BITS bits)
  val group_last = Bool()
}

class ElementAdd(c: ElementAddConfig) extends Component {
  val io = new Bundle {
    val cfg_i = slave Stream(ElementAddRunConfig(c))          // 组末输出排空后才接收下一配置
    val busy_o = out Bool()
    val done_o = out Bool()                                  // 每组完成后单拍
    val a_i = slave Stream(Bits(c.P * c.ACC_BITS bits))       // 两路按相同组/像素顺序，低 32 bit 为 lane 0
    val b_i = slave Stream(Bits(c.P * c.ACC_BITS bits))
    val output_o = master Stream(Fragment(ElementAddWord(c)))
  }

  val config_r = Reg(ElementAddRunConfig(c))
  val busy_r = Reg(Bool()) init(False)
  val active_r = Reg(Bool()) init(False)
  val index_r = Reg(UInt(c.COUNT_BITS bits)) init(0)
  val done_r = Reg(Bool()) init(False)
  io.cfg_i.ready := !busy_r && io.cfg_i.words =/= 0 && io.cfg_i.words <= c.MAX_WORDS &&
    io.cfg_i.group < c.MAX_GROUPS && io.cfg_i.clamp_min <= io.cfg_i.clamp_max
  io.busy_o := busy_r
  io.done_o := done_r
  done_r := False
  // 空闲时跟随配置，握手拍锁定；合法性比较不再驱动宽参数寄存器CE。
  val configCapture_w = !busy_r
  configCapture_w.addAttribute("max_fanout", 64)
  when(configCapture_w) {
    config_r := io.cfg_i.payload
  }
  when(io.cfg_i.fire) {
    busy_r := True
    active_r := True
    index_r := 0
  }

  // 原生 join：一侧先到时保持等待，不单独消费任一路数据。
  val joined = StreamJoin(io.a_i, io.b_i).haltWhen(!active_r)
  val inputPayload_w = new Bundle {
    val a = Bits(c.P * c.ACC_BITS bits)
    val b = Bits(c.P * c.ACC_BITS bits)
    val group_last = Bool()
  }
  inputPayload_w.a := joined.payload._1
  inputPayload_w.b := joined.payload._2
  inputPayload_w.group_last := index_r === config_r.words - U(1, c.COUNT_BITS bits)
  val input_w = joined.translateWith(inputPayload_w).m2sPipe()
  when(joined.fire) {
    index_r := index_r + U(1, c.COUNT_BITS bits)
    when(index_r === config_r.words - U(1, c.COUNT_BITS bits)) { active_r := False }
  }

  // 输入和乘积各打一拍，构成两级乘法路径；宽数据寄存器无复位。
  val productsPayload_w = new Bundle {
    val a = Vec(SInt(c.PRODUCT_BITS bits), c.P)
    val b = Vec(SInt(c.PRODUCT_BITS bits), c.P)
    val group_last = Bool()
  }
  productsPayload_w.group_last := input_w.group_last
  for (lane <- 0 until c.P) {
    productsPayload_w.a(lane) := input_w.a(lane * c.ACC_BITS, c.ACC_BITS bits).asSInt * config_r.multiplier_a(lane)
    productsPayload_w.b(lane) := input_w.b(lane * c.ACC_BITS, c.ACC_BITS bits).asSInt * config_r.multiplier_b(lane)
  }
  val products_r = input_w.translateWith(productsPayload_w).m2sPipe().s2mPipe()

  val sumPayload_w = new Bundle {
    val value = Vec(SInt(c.PRODUCT_BITS + 1 bits), c.P)
    val group_last = Bool()
  }
  sumPayload_w.group_last := products_r.group_last
  for (lane <- 0 until c.P) {
    sumPayload_w.value(lane) := products_r.a(lane).resize(c.PRODUCT_BITS + 1) + products_r.b(lane).resize(c.PRODUCT_BITS + 1)
  }
  val sum_r = products_r.translateWith(sumPayload_w).m2sPipe()
  val numeratorPayload_w = new Bundle {
    val value = Vec(SInt(c.SUM_BITS bits), c.P)
    val group_last = Bool()
  }
  numeratorPayload_w.group_last := sum_r.group_last
  for (lane <- 0 until c.P) {
    numeratorPayload_w.value(lane) := sum_r.value(lane).resize(c.SUM_BITS) + config_r.bias_fixed(lane).resize(c.SUM_BITS)
  }
  val numerator_r = sum_r.translateWith(numeratorPayload_w).m2sPipe()

  // 对负数用 floor 商与非负余数，避免 abs(INT64_MIN) 溢出。
  val half_w = Mux(config_r.shift === 0, U(0, c.SUM_BITS bits),
    U(1, c.SUM_BITS bits) |<< (config_r.shift - U(1, 6 bits)))
  val dividePayload_w = new Bundle {
    val whole = Vec(SInt(c.SUM_BITS bits), c.P)
    val guard = Bits(c.P bits)
    val sticky = Bits(c.P bits)
    val group_last = Bool()
  }
  dividePayload_w.group_last := numerator_r.group_last
  for (lane <- 0 until c.P) {
    dividePayload_w.whole(lane) := numerator_r.value(lane) >> config_r.shift
    dividePayload_w.guard(lane) := (numerator_r.value(lane).asUInt & half_w).orR
    dividePayload_w.sticky(lane) := (numerator_r.value(lane).asUInt & (half_w - U(1, c.SUM_BITS bits))).orR
  }
  val divide_r = numerator_r.translateWith(dividePayload_w).m2sPipe().s2mPipe()
  // 比较余数与半值单独一拍，不与66位加一串接。
  val decisionPayload_w = new Bundle {
    val whole = Vec(SInt(c.SUM_BITS bits), c.P)
    val increment = Bits(c.P bits)
    val group_last = Bool()
  }
  decisionPayload_w.whole := divide_r.whole
  decisionPayload_w.group_last := divide_r.group_last
  for (lane <- 0 until c.P) {
    decisionPayload_w.increment(lane) := config_r.shift =/= 0 &&
      divide_r.guard(lane) && (divide_r.sticky(lane) || divide_r.whole(lane)(0))
  }
  val decision_r = divide_r.translateWith(decisionPayload_w).m2sPipe()
  val roundedPayload_w = new Bundle {
    val value = Vec(SInt(c.SUM_BITS bits), c.P)
    val group_last = Bool()
  }
  roundedPayload_w.group_last := decision_r.group_last
  for (lane <- 0 until c.P) {
    roundedPayload_w.value(lane) := decision_r.whole(lane) + decision_r.increment(lane).asUInt.resize(c.SUM_BITS).asSInt
  }
  val rounded_r = decision_r.translateWith(roundedPayload_w).m2sPipe()
  val outputPayload_w = Fragment(ElementAddWord(c))
  outputPayload_w.fragment.group := config_r.group
  outputPayload_w.fragment.group_last := rounded_r.group_last
  outputPayload_w.last := rounded_r.group_last && config_r.last_group
  for (lane <- 0 until c.P) {
    val value_w = rounded_r.value(lane)
    outputPayload_w.fragment.data(lane * 8, 8 bits) := Mux(value_w < config_r.clamp_min.resize(c.SUM_BITS), config_r.clamp_min,
      Mux(value_w > config_r.clamp_max.resize(c.SUM_BITS), config_r.clamp_max, value_w.resize(8))).asBits
  }
  io.output_o << rounded_r.translateWith(outputPayload_w).m2sPipe()
  when(io.output_o.fire && io.output_o.fragment.group_last) {
    busy_r := False
    done_r := True
  }
}
