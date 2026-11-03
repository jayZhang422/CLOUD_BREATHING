// 文件类型：.scala。PE32 × SIMD16 计算，P8/P16量化及P4 RAW兼容输出，16像素块复用。
// 借鉴 FINN MVAU 的 SIMD/PE 折叠思想，独立实现；无 HLS 源码复制。
import spinal.core._
import spinal.lib._

case class PwConfig(maxCin: Int = 768, maxCout: Int = 512, tilePixels: Int = 16) {
  require(maxCin > 0 && maxCin <= 768 && maxCout > 0 && maxCout <= 512)
  require(tilePixels > 0 && tilePixels <= 16)
  val SIMD = 16
  val PE = 32
  val EXTERNAL_PE = 4
  val WEIGHT_BANKS = PE / EXTERNAL_PE
  val IG = (maxCin + SIMD - 1) / SIMD
  val OG = (maxCout + PE - 1) / PE
  val PARAM_GROUPS = (maxCout + EXTERNAL_PE - 1) / EXTERNAL_PE
  val PARAM_PACK_GROUPS = (maxCout + 15) / 16
  val WEIGHT_DEPTH = IG * PARAM_GROUPS
  val WEIGHT_BANK_DEPTH = IG * OG
  val PARAM_BANK_DEPTH = OG
  val INPUT_DEPTH = IG * tilePixels
  // signed INT8 最坏正积 (-128)*(-128)=16384；Cin<=768 时 25 位覆盖全部部分和。
  val ACC_BITS = log2Up(maxCin * 16384 + 1) + 1
}
case class PwRun() extends Bundle {
  val cin = UInt(10 bits)      // 实际输入通道：1..768
  val cout = UInt(10 bits)     // 实际输出通道：1..512
  val pixels = UInt(19 bits)  // 特征图像素总数：1..262144
  val shift = UInt(6 bits)    // 冻结整数右移：0..62
  val raw = Bool()            // 残差分支只交付 INT32，不提前舍入
  val raw16 = Bool()          // 仅 op12 内部使用 P16 RAW；外部 RAW 保持 P4
  val int16 = Bool()          // 输出头标识，q 始终用 16 位符号扩展承载
  val legacyP4 = Bool()       // 调试量化旁路保持原 P4 输出节拍
}
case class PwTag() extends Bundle {
  val pixel = UInt(19 bits)
  val localPixel = UInt(4 bits) // 块内索引随流水携带，累加端不再减tileBase。
  val group = UInt(7 bits)
  // 量化输出粒度：0=P4（RAW/op12兼容），1=P8（INT16），2=P16（INT8）。
  val quantMode = UInt(2 bits)
  val paramGroup = UInt(5 bits) // 2048-bit参数包的P16组号
  val quantLaneBase = UInt(4 bits) // 当前P4/P8 token在P16组内的起始lane
  val resultHalf = Bool()     // PE32结果的低/高16路，与参数包选择一起流水
  val mask = Bits(16 bits)
  val first = Bool()
  val finalInput = Bool()
  val tileLast = Bool()
  val last = Bool()
}
case class PwResult() extends Bundle {
  val pixel = UInt(19 bits)
  val group = UInt(7 bits)     // 输出通道组，粒度随 P4/P8/P16 模式变化
  val mask = Bits(16 bits)
  val last = Bool()
  val raw = Bool()
  val int16 = Bool()
  val mac = Vec(SInt(32 bits), 16)
  val q = Vec(SInt(16 bits), 16)
}
case class PwQuantInput() extends Bundle {
  val tag = PwTag()
  val raw = Bool()
  val int16 = Bool()
  val shift = UInt(6 bits)
  val mac = Vec(SInt(32 bits), 16)
  val multiplier = Vec(SInt(32 bits), 16)
  val bias = Vec(SInt(64 bits), 16)
  val lower = Vec(SInt(16 bits), 16)
  val upper = Vec(SInt(16 bits), 16)
}
case class PwQuantMeta() extends Bundle {
  val tag = PwTag()
  val raw = Bool()
  val int16 = Bool()
  val shift = UInt(6 bits)
  val mac = Vec(SInt(32 bits), 16)
  val lower = Vec(SInt(16 bits), 16)
  val upper = Vec(SInt(16 bits), 16)
}
case class PwQuantWork() extends Bundle {
  val info = PwQuantMeta()
  val value = Vec(SInt(64 bits), 16)
}
// 单路再量化；宽域多分支合并在后续独立算子完成。
class PwRequant extends Component {
  val io = new Bundle {
    val input_i = slave Stream(PwQuantInput())
    val output_o = master Stream(PwResult())
  }
  val product_w = new Bundle {
    val info = PwQuantMeta()
    val bias = Vec(SInt(64 bits), 16)
    val value = Vec(SInt(64 bits), 16)
  }
  product_w.info.tag := io.input_i.tag
  product_w.info.raw := io.input_i.raw
  product_w.info.int16 := io.input_i.int16
  product_w.info.shift := io.input_i.shift
  product_w.info.mac := io.input_i.mac
  product_w.info.lower := io.input_i.lower
  product_w.info.upper := io.input_i.upper
  product_w.bias := io.input_i.bias
  for (p <- 0 until 16) product_w.value(p) := io.input_i.mac(p) * io.input_i.multiplier(p)
  val product = io.input_i.translateWith(product_w).m2sPipe()
  val sum_w = PwQuantWork()
  sum_w.info := product.info
  for (p <- 0 until 16) sum_w.value(p) := (product.value(p) + product.bias(p)).resize(64)
  val sum = product.translateWith(sum_w).m2sPipe()
  // 右移/余数、舍入判定、宽加一分别打拍，避免比较链串接64位进位链。
  val divide_w = new Bundle {
    val info = PwQuantMeta()
    val whole = Vec(SInt(64 bits), 16)
    val guard = Bits(16 bits)
    val sticky = Bits(16 bits)
  }
  divide_w.info := sum.info
  val half_w = U(1, 64 bits) |<< (sum.info.shift - U(1, 6 bits))
  val stickyMask_w = (half_w - U(1, 64 bits)).resize(64)
  for (p <- 0 until 16) {
    // 算术右移得到向下取整商；非负余数确保负数 tie 也按最近偶数舍入。
    divide_w.whole(p) := (sum.value(p) >> sum.info.shift).resize(64)
    divide_w.guard(p) := (sum.value(p).asUInt & half_w).orR
    divide_w.sticky(p) := (sum.value(p).asUInt & stickyMask_w).orR
  }
  val divide = sum.translateWith(divide_w).m2sPipe()
  val decision_w = new Bundle {
    val info = PwQuantMeta()
    val whole = Vec(SInt(64 bits), 16)
    val increment = Bits(16 bits)
  }
  decision_w.info := divide.info
  decision_w.whole := divide.whole
  for (p <- 0 until 16) {
    decision_w.increment(p) := divide.info.shift =/= 0 &&
      divide.guard(p) && (divide.sticky(p) || divide.whole(p)(0))
  }
  val decision = divide.translateWith(decision_w).m2sPipe()
  val round_w = PwQuantWork()
  round_w.info := decision.info
  for (p <- 0 until 16) {
    round_w.value(p) := (decision.whole(p) + decision.increment(p).asUInt.resize(64).asSInt).resize(64)
  }
  val rounded = decision.translateWith(round_w).m2sPipe()
  val result_w = PwResult()
  result_w.pixel := rounded.info.tag.pixel
  result_w.group := rounded.info.tag.group
  result_w.mask := rounded.info.tag.mask
  result_w.last := rounded.info.tag.last
  result_w.raw := rounded.info.raw
  result_w.int16 := rounded.info.int16
  for (p <- 0 until 16) {
    result_w.mac(p) := Mux(rounded.info.tag.mask(p), rounded.info.mac(p), S(0, 32 bits))
    val clipped_w = SInt(16 bits)
    clipped_w := rounded.value(p).resize(16)
    when(rounded.value(p) < rounded.info.lower(p).resize(64)) {
      clipped_w := rounded.info.lower(p)
    } elsewhen(rounded.value(p) > rounded.info.upper(p).resize(64)) {
      clipped_w := rounded.info.upper(p)
    }
    result_w.q(p) := Mux(rounded.info.raw || !rounded.info.tag.mask(p), S(0, 16 bits), clipped_w)
  }
  io.output_o << rounded.translateWith(result_w).m2sPipe()
}

// 工程生成入口使用官方 IP；独立 SpinalSim 仍使用可移植 Mem 行为实现。
class PwWeightUram extends BlackBox {
  val io = new Bundle {
    val clka = in Bool()
    val ena = in Bool()
    val wea = in Bits(1 bits)
    val addra = in UInt(13 bits)
    val dina = in Bits(512 bits)
    val clkb = in Bool()
    val enb = in Bool()
    val addrb = in UInt(13 bits)
    val doutb = out Bits(512 bits)
  }
  noIoPrefix()
  setBlackBoxName("pw_weight_uram")
  mapClockDomain(clockDomain = ClockDomain.current, clock = io.clka)
  mapClockDomain(clockDomain = ClockDomain.current, clock = io.clkb)
}
// 官方 BMG：128 位 × 2048 字，两个 tile 分别占一个 1024 字 bank。
// 同钟简单双口，无数据复位、无附加输出寄存器，读延迟固定一拍。
class PwInputTileRam extends BlackBox {
  val io = new Bundle {
    val clka = in Bool()
    val ena = in Bool()
    val wea = in Bits(1 bits)
    val addra = in UInt(11 bits)
    val dina = in Bits(128 bits)
    val clkb = in Bool()
    val enb = in Bool()
    val addrb = in UInt(11 bits)
    val doutb = out Bits(128 bits)
  }
  noIoPrefix()
  setBlackBoxName("pw_input_tile_bram")
  mapClockDomain(clockDomain = ClockDomain.current, clock = io.clka)
  mapClockDomain(clockDomain = ClockDomain.current, clock = io.clkb)
}
// 官方双口 BMG：两组最终累加结果，计算写当前 bank，量化读已完成 bank。
class PwResultRam extends BlackBox {
  val io = new Bundle {
    val clka = in Bool()
    val ena = in Bool()
    val wea = in Bits(1 bits)
    val addra = in UInt(5 bits)
    val dina = in Bits(400 bits)
    val clkb = in Bool()
    val enb = in Bool()
    val addrb = in UInt(5 bits)
    val doutb = out Bits(400 bits)
  }
  noIoPrefix()
  setBlackBoxName("pw_result_bram")
  mapClockDomain(clockDomain = ClockDomain.current, clock = io.clka)
  mapClockDomain(clockDomain = ClockDomain.current, clock = io.clkb)
}
// 官方 BMG：2048 位 × 32 组，每拍提供完整16路量化参数。
class PwParamBram extends BlackBox {
  val io = new Bundle {
    val clka = in Bool()
    val ena = in Bool()
    val wea = in Bits(1 bits)
    val addra = in UInt(5 bits)
    val dina = in Bits(2048 bits)
    val clkb = in Bool()
    val enb = in Bool()
    val addrb = in UInt(5 bits)
    val doutb = out Bits(2048 bits)
  }
  noIoPrefix()
  setBlackBoxName("pw_param_bram")
  mapClockDomain(clockDomain = ClockDomain.current, clock = io.clka)
  mapClockDomain(clockDomain = ClockDomain.current, clock = io.clkb)
}
class PwWeightBank(projectUram: Boolean = false) extends BlackBox {
  val io = new Bundle {
    val clka = in Bool()
    val ena = in Bool()
    val wea = in Bits(1 bits)
    val addra = in UInt(10 bits)
    val dina = in Bits(512 bits)
    val clkb = in Bool()
    val enb = in Bool()
    val addrb = in UInt(10 bits)
    val doutb = out Bits(512 bits)
  }
  noIoPrefix()
  setBlackBoxName(if (projectUram) "pw32_project_uram" else "pw32_weight_bank")
  mapClockDomain(clockDomain = ClockDomain.current, clock = io.clka)
  mapClockDomain(clockDomain = ClockDomain.current, clock = io.clkb)
}
// 点积入口/出口携带分支标签；标签与数据经过同一条反压流水。
case class PwOperands() extends Bundle {
  val tag = PwTag()
  val source = Bool()
  val input = Bits(128 bits)
  val weights = Vec(Bits(128 bits), 32)
  val mask = Bits(16 bits)
}
case class PwDotResult() extends Bundle {
  val tag = PwTag()
  val source = Bool()
  val values = Vec(Vec(SInt(20 bits), 1), 32)
}
object PwDotPipeline {
  def apply(operands: Stream[PwOperands]): Stream[PwDotResult] = {
    // 每个输入lane只做一次掩码，再寄存后扇出到32个PE，避免MUX直接接DSP。
    val masked_w = PwOperands()
    masked_w := operands.payload
    masked_w.input.allowOverride
    for (lane <- 0 until 16) {
      masked_w.input(lane * 8, 8 bits) := Mux(operands.mask(lane), operands.input(lane * 8, 8 bits), B(0, 8 bits))
    }
    val masked = operands.translateWith(masked_w).m2sPipe()
    case class Products() extends Bundle {
      val tag = PwTag()
      val source = Bool()
      val values = Vec(Vec(SInt(16 bits), 16), 32)
    }
    val products_w = Products()
    products_w.tag := masked.tag
    products_w.source := masked.source
    for (p <- 0 until 32; lane <- 0 until 16) {
      val input_w = masked.input(lane * 8, 8 bits).asSInt
      val weight_w = masked.weights(p)(lane * 8, 8 bits).asSInt
      products_w.values(p)(lane).addAttribute("use_dsp", "yes")
      products_w.values(p)(lane) := input_w * weight_w
    }
    val products = masked.translateWith(products_w).m2sPipe()
    case class Reduce(count: Int, width: Int) extends Bundle {
      val tag = PwTag()
      val source = Bool()
      val values = Vec(Vec(SInt(width bits), count), 32)
    }
    val reduce8_w = Reduce(8, 17)
    reduce8_w.tag := products.tag
    reduce8_w.source := products.source
    for (p <- 0 until 32; j <- 0 until 8)
      reduce8_w.values(p)(j) := products.values(p)(j * 2).resize(17) + products.values(p)(j * 2 + 1).resize(17)
    val reduce8 = products.translateWith(reduce8_w).m2sPipe()
    val reduce4_w = Reduce(4, 18)
    reduce4_w.tag := reduce8.tag
    reduce4_w.source := reduce8.source
    for (p <- 0 until 32; j <- 0 until 4)
      reduce4_w.values(p)(j) := reduce8.values(p)(j * 2).resize(18) + reduce8.values(p)(j * 2 + 1).resize(18)
    val reduce4 = reduce8.translateWith(reduce4_w).m2sPipe()
    val reduce2_w = Reduce(2, 19)
    reduce2_w.tag := reduce4.tag
    reduce2_w.source := reduce4.source
    for (p <- 0 until 32; j <- 0 until 2)
      reduce2_w.values(p)(j) := reduce4.values(p)(j * 2).resize(19) + reduce4.values(p)(j * 2 + 1).resize(19)
    val reduce2 = reduce4.translateWith(reduce2_w).m2sPipe()
    val dot_w = PwDotResult()
    dot_w.tag := reduce2.tag
    dot_w.source := reduce2.source
    for (p <- 0 until 32)
      dot_w.values(p)(0) := reduce2.values(p)(0).resize(20) + reduce2.values(p)(1).resize(20)
    reduce2.translateWith(dot_w).m2sPipe()
  }
}
case class PwHostIo(sharedDot: Boolean = false) extends Bundle {
    val cfg_i = slave Stream(PwRun())                   // 空闲时锁存新的层配置
    val weights_i = slave Stream(Bits(512 bits))        // [输出组][输入组]，PE 优先、lane0 低字节
    val params_i = slave Stream(Bits(512 bits))         // DDR 原布局：每拍4路量化参数
    val start_i = slave Stream(Bool())                 // 参数全部加载后接受启动，可重复使用当前参数
    val busy_o = out Bool()                             // 含加载、计算与末输出排空
    val done_o = out Bool()                             // 末输出握手后的单拍
    val rd_o = master Stream(UInt(32 bits))             // 128-bit 字偏移：[输入组][像素]
    val rsp_i = slave Stream(Bits(128 bits))            // 多笔保序返回，独立填入本地tile
    val output_o = master Stream(PwResult())            // 地址标签使块顺序输出可写回分组缓存
    val dotRequest_o = if (sharedDot) master Stream(PwOperands()) else null
    val dotResponse_i = if (sharedDot) slave Stream(PwDotResult()) else null
}
class PwMac(config: PwConfig = PwConfig(), useUramWeights: Boolean = false,
            projectUram: Boolean = false,
            sharedDot: Boolean = false, useParamMemory: Boolean = true) extends Component {
  val io = PwHostIo(sharedDot)
  if (sharedDot) setDefinitionName(if (projectUram) "PwProjectFrontend" else "PwMacFrontend")
  val IDLE = U(0, 4 bits)
  val LOAD = U(1, 4 bits)
  val READY = U(2, 4 bits)
  val FILL = U(3, 4 bits)
  val ISSUE = U(4, 4 bits)
  val DRAIN = U(5, 4 bits)
  val PREPARE = U(6, 4 bits) // 兼容旧状态编码；新 tile 直接进入 FILL
  val TILE_READY = U(7, 4 bits) // 兼容旧状态编码；不再经过该空状态
  val SERIALIZE = U(8, 4 bits)
  val OUTPUT_DRAIN = U(9, 4 bits)
  val state_r = Reg(UInt(4 bits)) init(0)
  val run_r = Reg(PwRun())
  // 组计数器保存总组数，标签计数器保存从零开始的组号。
  val igCount_r = Reg(UInt(log2Up(config.IG + 1) bits))
  val ogCount_r = Reg(UInt(log2Up(config.OG + 1) bits))
  val weightCount_r = Reg(UInt(log2Up(config.WEIGHT_DEPTH + 1) bits)) init(0)
  val paramCount_r = Reg(UInt(log2Up(config.PARAM_GROUPS + 1) bits)) init(0)
  val paramTotal_r = Reg(UInt(log2Up(config.PARAM_GROUPS + 1) bits))
  val weightTotal_r = Reg(UInt(log2Up(config.WEIGHT_DEPTH + 1) bits))
  val weightGroup_r = Reg(UInt(log2Up(config.PARAM_GROUPS + 1) bits)) init(0)
  val weightInput_r = Reg(UInt(log2Up(config.IG + 1) bits)) init(0)
  val weightWriteBase_r = Reg(UInt(log2Up(config.WEIGHT_BANK_DEPTH) bits)) init(0)
  val weightReadBase_r = Reg(UInt(log2Up(config.WEIGHT_BANK_DEPTH) bits)) init(0)
  val paramGroup_r = Reg(UInt(log2Up(config.PARAM_GROUPS + 1) bits)) init(0)
  val paramPack_r = Reg(Bits(2048 bits)) // 每组首拍主动清零，不复位宽数据寄存器。
  val tileBase_r = Reg(UInt(19 bits)) init(0)
  val tileCount_r = Reg(UInt(5 bits)) init(0)
  val remaining_r = Reg(UInt(19 bits))
  val tileLastPixel_r = Reg(UInt(19 bits))
  val fillGroupBase_r = Reg(UInt(32 bits))
  val fillReadAddr_r = Reg(UInt(32 bits))
  val fillGroup_r = Reg(UInt(log2Up(config.IG + 1) bits)) init(0)
  val fillPixel_r = Reg(UInt(5 bits)) init(0)
  val fillPending_r = Reg(UInt(4 bits)) init(0)
  val fillIssued_r = Reg(Bool()) init(False)
  val fillIssueGroup_r = Reg(UInt(log2Up(config.IG + 1) bits)) init(0)
  val fillIssuePixel_r = Reg(UInt(5 bits)) init(0)
  // 装载与计算各自持有 bank；满位到最后一次片上读取后才释放。
  val inputBank_r = Reg(Bool()) init(False)
  val fillBank_r = Reg(Bool()) init(False)
  val bankFull_r = Vec.fill(2)(Reg(Bool()) init(False))
  val fillEnabled_r = Reg(Bool()) init(False)
  val fillActive_r = Reg(Bool()) init(False)
  val fillCount_r = Reg(UInt(5 bits))
  val fillBase_r = Reg(UInt(19 bits))
  val fillRemaining_r = Reg(UInt(19 bits))
  val issueGroup_r = Reg(UInt(log2Up(config.OG max 2) bits)) init(0)
  val issueInput_r = Reg(UInt(log2Up(config.IG + 1) bits)) init(0)
  val issuePixel_r = Reg(UInt(5 bits)) init(0)
  val serialGroup_r = Reg(UInt(3 bits)) init(0)
  val serialGroupCount_r = Reg(UInt(4 bits)) init(0)
  val serialPixel_r = Reg(UInt(5 bits)) init(0)
  val serializeActive_r = Reg(Bool()) init(False)
  val resultPending_r = Reg(Bool()) init(False)
  val resultWriteBank_r = Reg(Bool()) init(False)
  val resultSerialBank_r = Reg(Bool()) init(False)
  val serialBase_r = Reg(UInt(19 bits))
  val serialCount_r = Reg(UInt(5 bits))
  val serialOutputGroup_r = Reg(UInt(log2Up(config.OG max 2) bits))
  val serialLast_r = Reg(Bool())
  val done_r = Reg(Bool()) init(False)
  done_r := False
  io.done_o := done_r
  io.busy_o := state_r =/= IDLE && state_r =/= READY
  val validConfig_w = io.cfg_i.cin =/= 0 && io.cfg_i.cin <= config.maxCin &&
    io.cfg_i.cout =/= 0 && io.cfg_i.cout <= config.maxCout &&
    io.cfg_i.pixels =/= 0 && io.cfg_i.pixels <= 262144 && io.cfg_i.shift <= 62
  io.cfg_i.ready := (state_r === IDLE || state_r === READY) && validConfig_w
  val cfgIg_w = ((io.cfg_i.cin.resize(10) + U(15, 10 bits)) >> 4).resize(log2Up(config.IG + 1))
  val cfgOg_w = ((io.cfg_i.cout.resize(10) + U(31, 10 bits)) >> 5).resize(log2Up(config.OG + 1))
  val cfgParamGroups_w = ((io.cfg_i.cout.resize(10) + U(3, 10 bits)) >> 2).resize(log2Up(config.PARAM_GROUPS + 1))
  when(io.cfg_i.fire) {
    run_r := io.cfg_i.payload
    igCount_r := cfgIg_w
    ogCount_r := cfgOg_w
    weightTotal_r := (cfgIg_w * cfgParamGroups_w).resize(weightTotal_r.getWidth)
    paramTotal_r := cfgParamGroups_w
    weightCount_r := 0
    weightGroup_r := 0
    weightInput_r := 0
    weightWriteBase_r := 0
    paramCount_r := 0
    paramGroup_r := 0
    state_r := LOAD
  }
  io.weights_i.ready := state_r === LOAD && weightCount_r < weightTotal_r
  // 配置握手时预存参数总组数，避免cout取整加法贯穿参数ready和外部装载CE。
  io.params_i.ready := state_r === LOAD && paramCount_r < paramTotal_r
  when(io.weights_i.fire) {
    weightCount_r := weightCount_r + 1
    when(weightInput_r === igCount_r - 1) {
      weightInput_r := 0
      weightGroup_r := weightGroup_r + 1
      when(weightGroup_r(2 downto 0) === 7) {
        weightWriteBase_r := weightWriteBase_r + igCount_r.resized
      }
    } otherwise { weightInput_r := weightInput_r + 1 }
  }
  when(io.params_i.fire) { paramCount_r := paramCount_r + 1; paramGroup_r := paramGroup_r + 1 }
  when(state_r === LOAD && weightCount_r === weightTotal_r && paramCount_r === paramTotal_r) {
    state_r := READY
  }
  io.start_i.ready := state_r === READY && !io.cfg_i.valid
  when(io.start_i.fire) {
    tileBase_r := 0
    remaining_r := run_r.pixels
    inputBank_r := False
    fillBank_r := False
    bankFull_r.foreach(_ := False)
    fillEnabled_r := True
    fillActive_r := False
    fillBase_r := 0
    fillRemaining_r := run_r.pixels
    fillPending_r := 0
    fillIssued_r := False
    serializeActive_r := False
    resultPending_r := False
    resultWriteBank_r := False
    resultSerialBank_r := False
    // 首 tile 的尺寸在 start 握手时即可确定，跳过独立准备拍。
    tileCount_r := Mux(run_r.pixels > config.tilePixels, U(config.tilePixels, 5 bits), run_r.pixels.resize(5))
    state_r := FILL
  }
  // tile 边界直接在切换拍锁存；FILL 只等待对应 bank 完整，避免空的准备状态。
  when(state_r === PREPARE) {
    tileCount_r := Mux(remaining_r > config.tilePixels, U(config.tilePixels, 5 bits), remaining_r.resize(5))
    state_r := FILL
  }

  // 请求与返回分别计数，最多8笔P16在途；最后返回后才发布完整bank。
  when(fillEnabled_r && !fillActive_r && fillRemaining_r =/= 0 && !bankFull_r(fillBank_r.asUInt)) {
    fillCount_r := Mux(fillRemaining_r > config.tilePixels, U(config.tilePixels, 5 bits), fillRemaining_r.resize(5))
    fillGroup_r := 0
    fillPixel_r := 0
    fillIssueGroup_r := 0
    fillIssuePixel_r := 0
    fillIssued_r := False
    fillGroupBase_r := fillBase_r.resized
    fillReadAddr_r := fillBase_r.resized
    fillActive_r := True
  }
  io.rd_o.valid := fillActive_r && !fillIssued_r && fillPending_r < 8
  io.rd_o.payload := fillReadAddr_r
  io.rsp_i.ready := fillActive_r && fillPending_r =/= 0
  when(io.rd_o.fire =/= io.rsp_i.fire) {
    when(io.rd_o.fire) { fillPending_r := fillPending_r + 1 }
      .otherwise { fillPending_r := fillPending_r - 1 }
  }
  when(io.rd_o.fire) {
    when(fillIssuePixel_r === fillCount_r - 1) {
      fillIssuePixel_r := 0
      when(fillIssueGroup_r === igCount_r - 1) { fillIssued_r := True } otherwise {
        fillIssueGroup_r := fillIssueGroup_r + 1
        fillGroupBase_r := fillGroupBase_r + run_r.pixels
        fillReadAddr_r := fillGroupBase_r + run_r.pixels
      }
    } otherwise {
      fillIssuePixel_r := fillIssuePixel_r + 1
      fillReadAddr_r := fillReadAddr_r + 1
    }
  }
  val inputBankBits = log2Up(config.INPUT_DEPTH)
  val fillOffset_w = (fillGroup_r * U(config.tilePixels, 5 bits) + fillPixel_r).resize(inputBankBits)
  val fillAddress_w = fillBank_r.asUInt @@ fillOffset_w
  when(io.rsp_i.fire) {
    when(fillPixel_r === fillCount_r - 1) {
      fillPixel_r := 0
      when(fillGroup_r === igCount_r - 1) {
        bankFull_r(fillBank_r.asUInt) := True
        fillActive_r := False
        fillBank_r := !fillBank_r
        fillBase_r := fillBase_r + fillCount_r
        fillRemaining_r := fillRemaining_r - fillCount_r
      } otherwise {
        fillGroup_r := fillGroup_r + 1
      }
    } otherwise {
      fillPixel_r := fillPixel_r + 1
    }
  }
  when(state_r === FILL && bankFull_r(inputBank_r.asUInt)) {
    issueGroup_r := 0
    weightReadBase_r := 0
    issueInput_r := 0
    issuePixel_r := 0
    state_r := ISSUE
  }

  case class ReadData() extends Bundle {
    val tag = PwTag()
    val inputGroup = UInt(log2Up(config.IG + 1) bits)
  }
  val request = Stream(ReadData())
  request.valid := state_r === ISSUE
  request.tag.pixel := tileBase_r + issuePixel_r
  request.tag.localPixel := issuePixel_r.resized
  request.tag.group := (issueGroup_r.resize(10) * 32).resize(7)
  val p4Mode_w = (run_r.raw && !run_r.raw16) || run_r.legacyP4
  request.tag.quantMode := Mux(p4Mode_w, U(0, 2 bits),
    Mux(!run_r.raw && run_r.int16, U(1, 2 bits), U(2, 2 bits)))
  request.tag.paramGroup := (issueGroup_r.resize(5) << 1).resize(5)
  request.tag.quantLaneBase := 0
  request.tag.resultHalf := False
  for (p <- 0 until 16)
    request.tag.mask(p) := (issueGroup_r.resize(10) * 32 + p) < run_r.cout.resize(10)
  request.tag.first := issueInput_r === 0
  request.tag.finalInput := issueInput_r === igCount_r - 1
  request.tag.tileLast := issuePixel_r === tileCount_r - 1 && issueInput_r === igCount_r - 1
  request.tag.last := request.tag.tileLast && issueGroup_r === ogCount_r - 1 && tileBase_r + tileCount_r === run_r.pixels
  request.inputGroup := issueInput_r
  val response = request.m2sPipe()
  // 最后一组最后一次同步RAM读取已发出，下一拍可安全复用旧bank。
  when(request.fire && request.tag.tileLast && issueGroup_r === ogCount_r - 1) {
    bankFull_r(inputBank_r.asUInt) := False
  }
  val inputOffset_w = (issueInput_r * U(config.tilePixels, 5 bits) + issuePixel_r).resize(inputBankBits)
  val inputAddress_w = inputBank_r.asUInt @@ inputOffset_w
  val inputData_w = if (useUramWeights) {
    val memory = new PwInputTileRam
    memory.io.ena := io.rsp_i.fire
    memory.io.wea := io.rsp_i.fire.asBits
    memory.io.addra := fillAddress_w.resize(11)
    memory.io.dina := io.rsp_i.payload
    memory.io.enb := request.fire
    memory.io.addrb := inputAddress_w.resize(11)
    memory.io.doutb
  } else {
    val memory = Mem(Bits(128 bits), 2 << inputBankBits)
    memory.addAttribute("ram_style", "block")
    memory.write(fillAddress_w, io.rsp_i.payload, io.rsp_i.fire)
    memory.readSync(inputAddress_w, request.fire)
  }
  val weightAddress_w = weightReadBase_r + issueInput_r.resized
  // 写使能、bank、地址和数据同拍寄存；末笔写入早于READY后的首笔计算读取。
  val weightWriteValid_r = RegNext(io.weights_i.fire) init(False)
  val weightWriteBank_r = RegNext(weightGroup_r(2 downto 0))
  val weightWriteAddress_r = RegNext(weightWriteBase_r + weightInput_r.resized)
  val weightWriteData_r = RegNext(io.weights_i.payload)
  // 两分支的数据相同也保留各自寄存器，禁止合并后跨URAM/BRAM远距离布线。
  weightWriteData_r.addAttribute("dont_touch", "true")
  weightWriteValid_r.addAttribute("max_fanout", 16)
  weightWriteAddress_r.addAttribute("max_fanout", 8)
  val weights_w = Vec((0 until config.WEIGHT_BANKS).map { bank =>
    if (useUramWeights) {
      // project七个URAM银行、一个BRAM银行；skip全BRAM，恢复切片性能配置。
      val memory = new PwWeightBank(projectUram && bank < 7)
      val selected = weightWriteBank_r === bank
      memory.io.ena := weightWriteValid_r && selected
      memory.io.wea := (weightWriteValid_r && selected).asBits
      memory.io.addra := weightWriteAddress_r.resize(10)
      memory.io.dina := weightWriteData_r
      memory.io.enb := request.fire
      memory.io.addrb := weightAddress_w.resize(10)
      memory.io.doutb
    } else {
      val memory = Mem(Bits(512 bits), config.WEIGHT_BANK_DEPTH)
      memory.setName(s"weightBank_$bank")
      memory.addAttribute("ram_style", "block")
      val selected = weightWriteBank_r === bank
      memory.write(weightWriteAddress_r, weightWriteData_r, weightWriteValid_r && selected)
      memory.readSync(weightAddress_w, request.fire)
    }
  })
  val weightsByPe_w = Vec((0 until config.PE).map { pe =>
    weights_w(pe / 4)(pe % 4 * 128, 128 bits)
  })
  when(request.fire) {
    when(issuePixel_r === tileCount_r - 1) {
      issuePixel_r := 0
      when(issueInput_r === igCount_r - 1) {
        issueInput_r := 0
        state_r := DRAIN
      } otherwise { issueInput_r := issueInput_r + 1 }
    } otherwise { issuePixel_r := issuePixel_r + 1 }
  }
  // 官方权重 IP 保持一拍读配置；在 IP 外捕获操作数和标签后再仲裁/乘法。
  val operands_w = PwOperands()
  operands_w.tag := response.tag
  operands_w.source := False
  operands_w.input := inputData_w
  operands_w.weights := weightsByPe_w
  for (lane <- 0 until 16)
    operands_w.mask(lane) := (response.inputGroup.resize(10) * 16 + lane) < run_r.cin.resize(10)
  val operands = response.translateWith(operands_w).m2sPipe()
  val dot = if (sharedDot) {
    io.dotRequest_o << operands
    io.dotResponse_i
  } else PwDotPipeline(operands)

  // 累加器只保留当前计算组；finalInput 结果写双 bank RAM，和下一组点积重叠。
  val acc_r = Vec((0 until config.PE).map(_ => Vec.fill(config.tilePixels)(Reg(SInt(config.ACC_BITS bits)))))
  val localPixel_w = dot.tag.localPixel.resize(log2Up(config.tilePixels max 2))
  val quantRequest = Stream(new Bundle {
    val tag = PwTag()
  })
  val resultWriteData_w = Bits(config.PE * config.ACC_BITS bits)
  dot.ready := True
  for (p <- 0 until config.PE) {
    val sum_w = Mux(dot.tag.first, S(0, config.ACC_BITS bits), acc_r(p)(localPixel_w)) + dot.values(p)(0).resize(config.ACC_BITS)
    resultWriteData_w(p * config.ACC_BITS, config.ACC_BITS bits) := sum_w.resize(config.ACC_BITS).asBits
    when(dot.fire) {
      acc_r(p)(localPixel_w) := sum_w.resize(config.ACC_BITS)
    }
  }
  when(dot.fire && dot.tag.tileLast) {
    resultPending_r := True
  }
  // 只有上一读 bank 已释放才移交，等待期间计算 bank 与上下文保持不变。
  when(resultPending_r && !serializeActive_r) {
    resultPending_r := False
    resultSerialBank_r := resultWriteBank_r
    resultWriteBank_r := !resultWriteBank_r
    serializeActive_r := True
    serialBase_r := tileBase_r
    serialCount_r := tileCount_r
    serialOutputGroup_r := issueGroup_r
    serialLast_r := issueGroup_r === ogCount_r - 1 && tileBase_r + tileCount_r === run_r.pixels
    serialGroup_r := 0
    serialPixel_r := 0
    val groupsPerPe_w = Mux(p4Mode_w, U(8, 10 bits),
      Mux(!run_r.raw && run_r.int16, U(4, 10 bits), U(2, 10 bits)))
    val externalGroups_w = Mux(p4Mode_w,
      (run_r.cout.resize(10) + U(3, 10 bits)) >> 2,
      Mux(!run_r.raw && run_r.int16, (run_r.cout.resize(10) + U(7, 10 bits)) >> 3,
        (run_r.cout.resize(10) + U(15, 10 bits)) >> 4))
    val groupsLeft_w = externalGroups_w - (issueGroup_r.resize(10) * groupsPerPe_w)
    serialGroupCount_r := Mux(groupsLeft_w > groupsPerPe_w, groupsPerPe_w.resize(4), groupsLeft_w.resize(4))
    when(issueGroup_r === ogCount_r - 1) {
      when(tileBase_r + tileCount_r === run_r.pixels) {
        state_r := OUTPUT_DRAIN
      } otherwise {
        inputBank_r := !inputBank_r
        tileBase_r := tileBase_r + tileCount_r
        remaining_r := remaining_r - tileCount_r
        tileCount_r := Mux((remaining_r - tileCount_r) > config.tilePixels,
          U(config.tilePixels, 5 bits), (remaining_r - tileCount_r).resize(5))
        state_r := FILL
      }
    } otherwise {
      issueGroup_r := issueGroup_r + 1
      weightReadBase_r := weightReadBase_r + igCount_r.resized
      issueInput_r := 0
      issuePixel_r := 0
      state_r := ISSUE
    }
  }
  quantRequest.valid := serializeActive_r
  quantRequest.tag.pixel := serialBase_r + serialPixel_r
  quantRequest.tag.localPixel := serialPixel_r.resized
  val quantMode_w = Mux(p4Mode_w, U(0, 2 bits),
    Mux(!run_r.raw && run_r.int16, U(1, 2 bits), U(2, 2 bits)))
  val quantLanes_w = Mux(quantMode_w === 0, U(4, 10 bits),
    Mux(quantMode_w === 1, U(8, 10 bits), U(16, 10 bits)))
  val quantGroupsPerPe_w = Mux(quantMode_w === 0, U(8, 10 bits),
    Mux(quantMode_w === 1, U(4, 10 bits), U(2, 10 bits)))
  quantRequest.tag.quantMode := quantMode_w
  val resultHalf_w = Mux(quantMode_w === 0, serialGroup_r(2),
    Mux(quantMode_w === 1, serialGroup_r(1), serialGroup_r(0)))
  quantRequest.tag.resultHalf := resultHalf_w
  quantRequest.tag.paramGroup := ((serialOutputGroup_r.resize(5) << 1).resize(5) + resultHalf_w.asUInt).resize(5)
  quantRequest.tag.quantLaneBase := Mux(quantMode_w === 0, (serialGroup_r.resize(4) << 2).resize(4),
    Mux(quantMode_w === 1, (serialGroup_r.resize(4) << 3).resize(4), U(0, 4 bits)))
  quantRequest.tag.group := (serialOutputGroup_r.resize(10) * quantGroupsPerPe_w + serialGroup_r).resize(7)
  for (p <- 0 until 16)
    quantRequest.tag.mask(p) := U(p, 10 bits) < quantLanes_w &&
      (quantRequest.tag.paramGroup.resize(10) * 16 + quantRequest.tag.quantLaneBase.resize(10) + p) < run_r.cout.resize(10)
  quantRequest.tag.first := False
  quantRequest.tag.finalInput := True
  quantRequest.tag.tileLast := serialGroup_r === serialGroupCount_r - 1 && serialPixel_r === serialCount_r - 1
  quantRequest.tag.last := quantRequest.tag.tileLast && serialLast_r
  when(quantRequest.fire) {
    when(serialPixel_r === serialCount_r - 1) {
      serialPixel_r := 0
      when(serialGroup_r === serialGroupCount_r - 1) { serializeActive_r := False }
        .otherwise { serialGroup_r := serialGroup_r + 1 }
    } otherwise { serialPixel_r := serialPixel_r + 1 }
  }
  val resultBankBits = log2Up(config.tilePixels max 2)
  val resultWriteAddress_w = resultWriteBank_r.asUInt @@ localPixel_w
  val resultReadAddress_w = resultSerialBank_r.asUInt @@ serialPixel_r.resize(resultBankBits)
  val resultWrite_w = dot.fire && dot.tag.finalInput
  val resultData_w = if (useUramWeights) {
    // 复用两片400-bit官方结果RAM，32路结果同步写入，量化端仍按P4/P8/P16交付。
    val halves = (0 until 2).map { half =>
      val memory = new PwResultRam
      memory.io.ena := resultWrite_w
      memory.io.wea := resultWrite_w.asBits
      memory.io.addra := resultWriteAddress_w.resize(5)
      memory.io.dina := resultWriteData_w(half * 400, 400 bits)
      memory.io.enb := quantRequest.fire
      memory.io.addrb := resultReadAddress_w.resize(5)
      memory.io.doutb
    }
    halves(1) ## halves(0)
  } else {
    val memory = Mem(Bits(config.PE * config.ACC_BITS bits), 2 << resultBankBits)
    memory.addAttribute("ram_style", "block")
    memory.write(resultWriteAddress_w, resultWriteData_w, resultWrite_w)
    memory.readSync(resultReadAddress_w, quantRequest.fire)
  }
  // 四个连续DDR参数拍合并为一个P16组；最后不满四拍时未用lane保持为零。
  val paramPackData_w = Bits(2048 bits)
  for (part <- 0 until 4) {
    val partSelect_w = paramGroup_r(1 downto 0) === U(part, 2 bits)
    val newGroup_w = paramGroup_r(1 downto 0) === U(0, 2 bits)
    val oldPart_w = Mux(newGroup_w, B(0, 512 bits), paramPack_r(part * 512, 512 bits))
    paramPackData_w(part * 512, 512 bits) := Mux(partSelect_w, io.params_i.payload, oldPart_w)
  }
  val paramPackEnd_w = paramGroup_r(1 downto 0) === U(3, 2 bits) || paramGroup_r === paramTotal_r - 1
  val paramPackAddress_w = (paramGroup_r >> 2).resize(log2Up(config.PARAM_PACK_GROUPS))
  when(io.params_i.fire) { paramPack_r := paramPackData_w }
  val paramData_w = if (!useParamMemory) B(0, 2048 bits) else if (useUramWeights) {
    val memory = new PwParamBram
    memory.io.ena := io.params_i.fire && paramPackEnd_w
    memory.io.wea := (io.params_i.fire && paramPackEnd_w).asBits
    memory.io.addra := paramPackAddress_w.resize(5)
    memory.io.dina := paramPackData_w
    memory.io.enb := quantRequest.fire
    memory.io.addrb := quantRequest.tag.paramGroup
    memory.io.doutb
  } else {
    val memory = Mem(Bits(2048 bits), config.PARAM_PACK_GROUPS)
    memory.setName("paramPackMemory")
    memory.addAttribute("ram_style", "block")
    memory.write(paramPackAddress_w, paramPackData_w, io.params_i.fire && paramPackEnd_w)
    memory.readSync(quantRequest.tag.paramGroup.resize(log2Up(config.PARAM_PACK_GROUPS)), quantRequest.fire)
  }
  val quantResponse = quantRequest.m2sPipe()
  val paramsSelected_w = paramData_w
  val paramWords_w = Vec((0 until 16).map(p => paramsSelected_w(p * 128, 128 bits)))
  val quantInput_w = PwQuantInput()
  quantInput_w.tag := quantResponse.tag
  quantInput_w.raw := run_r.raw
  quantInput_w.int16 := run_r.int16
  quantInput_w.shift := run_r.shift
  val resultPe_w = Vec((0 until config.PE).map(p => resultData_w(p * config.ACC_BITS, config.ACC_BITS bits).asSInt))
  for (p <- 0 until 16) {
    // 起始lane始终4对齐，固定低两位，限制为4选1，避免推导16选1宽MUX。
    val laneIndex_w = (quantResponse.tag.quantLaneBase(3 downto 2) + U(p / 4, 2 bits)) @@ U(p % 4, 2 bits)
    val param_w = paramWords_w(laneIndex_w)
    quantInput_w.mac(p) := resultPe_w(quantResponse.tag.resultHalf.asUInt @@ laneIndex_w).resize(32)
    quantInput_w.multiplier(p) := param_w(0, 32 bits).asSInt
    quantInput_w.bias(p) := param_w(32, 64 bits).asSInt
    quantInput_w.lower(p) := param_w(96, 16 bits).asSInt
    quantInput_w.upper(p) := param_w(112, 16 bits).asSInt
  }
  val quantPrepared = quantResponse.translateWith(quantInput_w).m2sPipe()
  val requant = new PwRequant
  if (sharedDot) requant.setDefinitionName("PwSharedRequant")
  requant.io.input_i << quantPrepared
  // 弹性缓存切断写回端到整个量化流水的ready链，数据和标签一起保持。
  io.output_o << requant.io.output_o.s2mPipe().m2sPipe()
  // 最后一次RAM读握手后才释放结果 bank；writer 的官方 FIFO 后台排空。
  // 最末输出仍须真实握手，才允许 done/重新配置，禁止仅凭入队提前完成。
  when(io.output_o.fire && io.output_o.last) {
    done_r := True
    state_r := READY
  }
}
// 两套已验证前端保留各自的权重/输入/累加状态；只有点积流水共享一份。
// 两分支可独立预取；结果仍按 project/skip 阶段交付，点积仲裁处理并发请求。
class PwMacShared extends Component {
  val io = new Bundle {
    val project = PwHostIo()
    val skip = PwHostIo()
  }
  val project = new PwMac(useUramWeights = true, projectUram = true, sharedDot = true)
  val skip = new PwMac(useUramWeights = true, sharedDot = true, useParamMemory = false)
  for ((core, port) <- Seq((project, io.project), (skip, io.skip))) {
    core.io.cfg_i << port.cfg_i
    core.io.weights_i << port.weights_i
    core.io.params_i << port.params_i
    core.io.start_i << port.start_i
    port.busy_o := core.io.busy_o
    port.done_o := core.io.done_o
    port.rd_o << core.io.rd_o
    core.io.rsp_i << port.rsp_i
    port.output_o << core.io.output_o
  }
  val projectRequest_w = PwOperands()
  projectRequest_w := project.io.dotRequest_o.payload
  projectRequest_w.source.allowOverride := False
  val skipRequest_w = PwOperands()
  skipRequest_w := skip.io.dotRequest_o.payload
  skipRequest_w.source.allowOverride := True
  val selected = StreamArbiterFactory.roundRobin.transactionLock.onArgs(
    project.io.dotRequest_o.translateWith(projectRequest_w),
    skip.io.dotRequest_o.translateWith(skipRequest_w))
  // 仲裁后的操作数单独打拍，避免 2048 位权重选择器直接串到 DSP 乘法入口。
  val operands = selected.m2sPipe()
  val dot = PwDotPipeline(operands)
  project.io.dotResponse_i.valid := dot.valid && !dot.source
  skip.io.dotResponse_i.valid := dot.valid && dot.source
  project.io.dotResponse_i.payload := dot.payload
  skip.io.dotResponse_i.payload := dot.payload
  dot.ready := Mux(dot.source, skip.io.dotResponse_i.ready, project.io.dotResponse_i.ready)
}
object PwGen extends App {
  SpinalConfig(targetDirectory = "rtl",
    defaultConfigForClockDomains = ClockDomainConfig(resetKind = ASYNC, resetActiveLevel = LOW))
    .generateVerilog(new PwMac(useUramWeights = true))
}
object PwSharedGen extends App {
  SpinalConfig(targetDirectory = "rtl",
    defaultConfigForClockDomains = ClockDomainConfig(resetKind = ASYNC, resetActiveLevel = LOW))
    .generateVerilog(new PwMacShared)
}
