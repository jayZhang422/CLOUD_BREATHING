// 文件类型：.scala。P16 INT8 最近邻 2×，单行同步 RAM，组优先光栅流。
import spinal.core._
import spinal.lib._

case class UpsampleConfig(maxWidth: Int = 256, maxHeight: Int = 256, maxGroups: Int = 32) {
  require(maxWidth >= 2 && maxHeight >= 1 && maxGroups >= 1 && maxGroups <= 32)
  val X_BITS = log2Up(maxWidth + 1)
  val Y_BITS = log2Up(maxHeight + 1)
  val G_BITS = log2Up(maxGroups + 1)
  val A_BITS = log2Up(maxWidth)
}
case class UpsampleRunConfig(c: UpsampleConfig) extends Bundle {
  val width = UInt(c.X_BITS bits)
  val height = UInt(c.Y_BITS bits)
  val groups = UInt(c.G_BITS bits)
}
case class UpsampleTag(c: UpsampleConfig) extends Bundle {
  val group = UInt(c.G_BITS bits)
  val row = UInt(c.Y_BITS + 1 bits)
  val col = UInt(c.X_BITS + 1 bits)
  val group_last = Bool()
}
case class UpsampleWord(c: UpsampleConfig) extends Bundle {
  val data = Bits(128 bits)                                    // lane 0 位于最低字节
  val group = UInt(c.G_BITS bits)
  val row = UInt(c.Y_BITS + 1 bits)
  val col = UInt(c.X_BITS + 1 bits)
  val group_last = Bool()
}
class Upsample(c: UpsampleConfig = UpsampleConfig()) extends Component {
  val io = new Bundle {
    val cfg_i = slave Stream(UpsampleRunConfig(c))              // 仅空闲且合法时握手
    val busy_o = out Bool()                                    // 包含输出排空
    val done_o = out Bool()                                    // 末输出握手后一拍脉冲
    val input_i = slave Stream(Bits(128 bits))                  // [组][行][列][lane]
    val output_o = master Stream(Fragment(UpsampleWord(c)))    // 坐标、组末、任务末同步输出
  }
  object State extends SpinalEnum { val IDLE, FILL, EMIT, DRAIN = newElement() }
  val state_r = Reg(State()) init(State.IDLE)
  val state_nxt = State()
  val endX_r = Reg(UInt(c.X_BITS bits)) init(0)
  val endY_r = Reg(UInt(c.Y_BITS bits)) init(0)
  val endGroup_r = Reg(UInt(c.G_BITS bits)) init(0)
  val x_r = Reg(UInt(c.X_BITS bits)) init(0)
  val y_r = Reg(UInt(c.Y_BITS bits)) init(0)
  val group_r = Reg(UInt(c.G_BITS bits)) init(0)
  val col_r = Reg(UInt(c.X_BITS + 1 bits)) init(0)
  val repeatRow_r = Reg(Bool()) init(False)
  val address_r = Reg(UInt(c.A_BITS bits)) init(0)
  val done_r = Reg(Bool()) init(False)
  done_r := False
  io.done_o := done_r
  io.busy_o := state_r =/= State.IDLE
  io.cfg_i.ready := state_r === State.IDLE && io.cfg_i.width =/= 0 &&
    io.cfg_i.width <= c.maxWidth && io.cfg_i.height =/= 0 &&
    io.cfg_i.height <= c.maxHeight && io.cfg_i.groups =/= 0 && io.cfg_i.groups <= c.maxGroups
  io.input_i.ready := state_r === State.FILL

  val lineMem = Mem(Bits(128 bits), c.maxWidth)
  lineMem.addAttribute("ram_style", "block")
  lineMem.write(x_r.resize(c.A_BITS), io.input_i.payload, io.input_i.fire)

  // 地址递增；拼接只布线，不产生可变移位或乘法器。
  val endCol_w = (endX_r.asBits ## True).asUInt
  val rowEnd_w = col_r === endCol_w
  val request = Stream(Fragment(UpsampleTag(c)))
  request.valid := state_r === State.EMIT
  request.fragment.group := group_r
  request.fragment.row := (y_r.asBits ## repeatRow_r).asUInt
  request.fragment.col := col_r
  request.fragment.group_last := rowEnd_w && repeatRow_r && y_r === endY_r
  request.last := request.fragment.group_last && group_r === endGroup_r
  val ramData_w = lineMem.readSync(address_r, request.fire)
  val response = request.m2sPipe()
  val result = Stream(Fragment(UpsampleWord(c)))
  result.valid := response.valid
  response.ready := result.ready
  result.fragment.data := ramData_w
  result.fragment.group := response.fragment.group
  result.fragment.row := response.fragment.row
  result.fragment.col := response.fragment.col
  result.fragment.group_last := response.fragment.group_last
  result.last := response.last
  // 标准 skid buffer 切断外部 ready；末级寄存器隔离 RAM 数据路径。
  io.output_o << result.s2mPipe().m2sPipe()
  val drained_w = io.output_o.fire && io.output_o.fragment.col === endCol_w && io.output_o.fragment.row(0)

  // 三段式状态机：现态寄存器、组合次态、时序数据/控制输出。
  state_r := state_nxt
  state_nxt := state_r
  switch(state_r) {
    is(State.IDLE) { when(io.cfg_i.fire) { state_nxt := State.FILL } }
    is(State.FILL) { when(io.input_i.fire && x_r === endX_r) { state_nxt := State.EMIT } }
    is(State.EMIT) { when(request.fire && rowEnd_w && repeatRow_r) { state_nxt := State.DRAIN } }
    is(State.DRAIN) {
      when(drained_w) {
        state_nxt := State.FILL
        when(io.output_o.last) { state_nxt := State.IDLE }
      }
    }
  }
  when(io.cfg_i.fire) {
    endX_r := io.cfg_i.width - U(1, c.X_BITS bits)
    endY_r := io.cfg_i.height - U(1, c.Y_BITS bits)
    endGroup_r := io.cfg_i.groups - U(1, c.G_BITS bits)
    x_r := 0; y_r := 0; group_r := 0
    col_r := 0; repeatRow_r := False; address_r := 0
  }
  when(io.input_i.fire) {
    x_r := x_r + U(1, c.X_BITS bits)
    when(x_r === endX_r) { x_r := 0 }
  }
  when(request.fire) {
    col_r := col_r + U(1, c.X_BITS + 1 bits)
    when(col_r(0)) { address_r := address_r + U(1, c.A_BITS bits) }
    when(rowEnd_w) {
      col_r := 0
      address_r := 0
      repeatRow_r := !repeatRow_r
    }
  }
  when(drained_w) {
    y_r := y_r + U(1, c.Y_BITS bits)
    when(y_r === endY_r) {
      y_r := 0
      group_r := group_r + U(1, c.G_BITS bits)
    }
    when(io.output_o.last) { done_r := True }
  }
}

object UpsampleGen extends App {
  SpinalConfig(targetDirectory = "rtl", defaultConfigForClockDomains =
    ClockDomainConfig(resetKind = ASYNC, resetActiveLevel = LOW)).generateVerilog(new Upsample())
}
