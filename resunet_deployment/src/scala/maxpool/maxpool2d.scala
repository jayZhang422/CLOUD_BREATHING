// 文件类型：.scala。P=16、signed INT8，2×2/stride=2 同步 RAM 池化。
// 运行时尺寸/组数；输入顺序 [组][行][列][lane]，奇数尾行/尾列丢弃。
import spinal.core._
import spinal.lib._

case class MaxPoolConfig(maxWidth: Int = 512, maxHeight: Int = 512, maxGroups: Int = 32) {
  require(maxWidth >= 2 && maxHeight >= 2 && maxGroups > 0)
  val P = 16
  val DW = 8
  val X_BITS = log2Up(maxWidth + 1)
  val Y_BITS = log2Up(maxHeight + 1)
  val GROUP_BITS = log2Up(maxGroups + 1)
  val ADDRESS_BITS = log2Up((maxWidth / 2) max 2)
}

case class MaxPoolRunConfig(config: MaxPoolConfig) extends Bundle {
  val width = UInt(config.X_BITS bits)
  val height = UInt(config.Y_BITS bits)
  val groups = UInt(config.GROUP_BITS bits)                     // 1..32 个 P16 组
}

case class MaxPoolWord(config: MaxPoolConfig) extends Bundle {
  val data = Bits(config.P * config.DW bits)
  val group = UInt(config.GROUP_BITS bits)                       // 0..31
  val group_last = Bool()
}

class MaxPool2d(config: MaxPoolConfig) extends Component {
  val io = new Bundle {
    val cfg_i    = slave Stream(MaxPoolRunConfig(config))       // 空闲时接收合法运行配置
    val busy_o   = out Bool()                                   // 包含奇数尾部及流水排空
    val done_o   = out Bool()                                   // 输入/输出均完成后的单拍脉冲
    val input_i  = slave Stream(Bits(config.P * config.DW bits)) // 低字节为组内 lane 0
    val output_o = master Stream(Fragment(MaxPoolWord(config))) // 池化值、组号与边界
  }

  val width_r = Reg(UInt(config.X_BITS bits)) init(0)
  val height_r = Reg(UInt(config.Y_BITS bits)) init(0)
  val groups_r = Reg(UInt(config.GROUP_BITS bits)) init(0)
  val x_r = Reg(UInt(config.X_BITS bits)) init(0)
  val y_r = Reg(UInt(config.Y_BITS bits)) init(0)
  val group_r = Reg(UInt(config.GROUP_BITS bits)) init(0)
  val active_r = Reg(Bool()) init(False)
  val busy_r = Reg(Bool()) init(False)
  val outputDone_r = Reg(Bool()) init(False)
  val done_r = Reg(Bool()) init(False)
  io.cfg_i.ready := !busy_r && io.cfg_i.width >= 2 && io.cfg_i.width <= config.maxWidth &&
    io.cfg_i.height >= 2 && io.cfg_i.height <= config.maxHeight &&
    io.cfg_i.groups =/= 0 && io.cfg_i.groups <= config.maxGroups
  io.busy_o := busy_r
  io.done_o := done_r
  done_r := False

  val leftPixel_r = Vec.fill(config.P)(Reg(SInt(config.DW bits)))
  val pairMax_w = Vec.fill(config.P)(SInt(config.DW bits))
  for (lane <- 0 until config.P) {
    val pixel_w = io.input_i.payload(lane * config.DW, config.DW bits).asSInt
    pairMax_w(lane) := Mux(leftPixel_r(lane) > pixel_w, leftPixel_r(lane), pixel_w)
    when(io.input_i.fire && !x_r(0)) { leftPixel_r(lane) := pixel_w }
  }

  // 输出边界在最后一个完整 2×2 上，而非可能被丢弃的奇数尾行/列上。
  val outputEndX_w = width_r - Mux(width_r(0), U(2, config.X_BITS bits), U(1, config.X_BITS bits))
  val outputEndY_w = height_r - Mux(height_r(0), U(2, config.Y_BITS bits), U(1, config.Y_BITS bits))
  val lastGroup_w = group_r === groups_r - U(1, config.GROUP_BITS bits)

  val request = Stream(new Bundle {
    val pair = Vec(SInt(config.DW bits), config.P)
    val emit = Bool()
    val group = UInt(config.GROUP_BITS bits)
    val group_last = Bool()
    val last = Bool()
  })
  request.valid := active_r && io.input_i.valid
  request.pair := pairMax_w
  request.emit := x_r(0) && y_r(0)
  request.group := group_r
  request.group_last := x_r === outputEndX_w && y_r === outputEndY_w
  request.last := request.group_last && lastGroup_w
  io.input_i.ready := active_r && request.ready

  // 单份 256×128-bit 顶行横向最大值缓存；偶数行写、奇数行同步读。
  val topPairMem = Mem(Bits(config.P * config.DW bits), config.maxWidth / 2)
  topPairMem.addAttribute("ram_style", "block")
  val pairIndex_w = x_r(config.ADDRESS_BITS downto 1)
  topPairMem.write(pairIndex_w, pairMax_w.asBits, request.fire && x_r(0) && !y_r(0))
  val topPair_w = topPairMem.readSync(pairIndex_w, request.fire && request.emit)
  val response = request.m2sPipe()

  val pooled = Stream(Fragment(MaxPoolWord(config)))
  val pooledMax_w = Vec.fill(config.P)(SInt(config.DW bits))
  for (lane <- 0 until config.P) {
    val top_w = topPair_w(lane * config.DW, config.DW bits).asSInt
    pooledMax_w(lane) := Mux(top_w > response.pair(lane), top_w, response.pair(lane))
  }
  pooled.valid := response.valid && response.emit
  pooled.fragment.data := pooledMax_w.asBits
  pooled.fragment.group := response.group
  pooled.fragment.group_last := response.group_last
  pooled.last := response.last
  response.ready := !response.emit || pooled.ready
  io.output_o << pooled.m2sPipe()

  when(request.fire) {
    when(x_r === width_r - U(1, config.X_BITS bits)) {
      x_r := 0
      when(y_r === height_r - U(1, config.Y_BITS bits)) {
        y_r := 0
        when(lastGroup_w) { active_r := False } otherwise {
          group_r := group_r + U(1, config.GROUP_BITS bits)
        }
      } otherwise { y_r := y_r + U(1, config.Y_BITS bits) }
    } otherwise { x_r := x_r + U(1, config.X_BITS bits) }
  }
  when(io.output_o.fire && io.output_o.last) { outputDone_r := True }
  // 奇数尺寸的末输出可能先于最后输入完成，必须等待两者。
  when(busy_r && !active_r && outputDone_r) {
    busy_r := False
    done_r := True
  }
  when(io.cfg_i.fire) {
    width_r := io.cfg_i.width
    height_r := io.cfg_i.height
    groups_r := io.cfg_i.groups
    x_r := 0
    y_r := 0
    group_r := 0
    active_r := True
    busy_r := True
    outputDone_r := False
  }
}
