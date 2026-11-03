// 文件类型：.scala。P=16 宽字同步 RAM + 共享控制，运行时尺寸/分组，零补边窗口。
import spinal.core._
import spinal.lib._

case class LineBufferConfig(maxWidth: Int = 512, maxHeight: Int = 512, k: Int = 3, maxGroups: Int = 32) {
  require(maxWidth > 0 && maxHeight > 0 && maxGroups > 0)
  require(k == 3 || k == 5)
  val P = 16
  val DW = 8
  val WORD_BITS = P * DW
  val PAD = k / 2
  val LINES = k - 1
  val X_BITS = log2Up(maxWidth + k)
  val Y_BITS = log2Up(maxHeight + k)
  val GROUP_BITS = log2Up(maxGroups + 1)
}

case class LineBufferRunConfig(config: LineBufferConfig) extends Bundle {
  val width = UInt(log2Up(config.maxWidth + 1) bits)
  val height = UInt(log2Up(config.maxHeight + 1) bits)
  val groups = UInt(config.GROUP_BITS bits)
}

case class LineBufferWindow(config: LineBufferConfig) extends Bundle {
  val window = Vec(Vec(Bits(config.WORD_BITS bits), config.k), config.k)
  val group = UInt(config.GROUP_BITS bits)
  val group_last = Bool()
}

class LineBuffer(config: LineBufferConfig) extends Component {
  val io = new Bundle {
    val cfg_i    = slave Stream(LineBufferRunConfig(config))        // 运行配置，仅空闲且参数合法时接收
    val busy_o   = out Bool()                                      // 包含最后窗口排空阶段
    val done_o   = out Bool()                                      // 任务末窗口握手后的单拍脉冲
    val input_i  = slave Stream(Bits(config.WORD_BITS bits))         // [组][行][列][16 通道]，低字节为 lane 0
    val output_o = master Stream(Fragment(LineBufferWindow(config))) // 行优先窗口、组号与边界
  }

  val width_r = Reg(UInt(config.X_BITS bits)) init(0)
  val height_r = Reg(UInt(config.Y_BITS bits)) init(0)
  val groups_r = Reg(UInt(config.GROUP_BITS bits)) init(0)
  val busy_r = Reg(Bool()) init(False)
  val active_r = Reg(Bool()) init(False)
  val done_r = Reg(Bool()) init(False)
  val x_r = Reg(UInt(config.X_BITS bits)) init(0)
  val y_r = Reg(UInt(config.Y_BITS bits)) init(0)
  val bank_r = Reg(UInt(log2Up(config.LINES) bits)) init(0)
  val group_r = Reg(UInt(config.GROUP_BITS bits)) init(0)
  val paddedWidth_w = width_r + U(config.k - 1, config.X_BITS bits)
  val paddedHeight_w = height_r + U(config.k - 1, config.Y_BITS bits)
  val realColumn_w = x_r >= U(config.PAD, config.X_BITS bits) &&
    x_r < width_r + U(config.PAD, config.X_BITS bits)
  val realPixel_w = realColumn_w && y_r >= U(config.PAD, config.Y_BITS bits) &&
    y_r < height_r + U(config.PAD, config.Y_BITS bits)
  val groupLast_w = x_r === paddedWidth_w - U(1, config.X_BITS bits) &&
    y_r === paddedHeight_w - U(1, config.Y_BITS bits)
  val lastGroup_w = group_r === groups_r - U(1, config.GROUP_BITS bits)
  io.cfg_i.ready := !busy_r && io.cfg_i.width =/= 0 && io.cfg_i.width <= config.maxWidth &&
    io.cfg_i.height =/= 0 && io.cfg_i.height <= config.maxHeight &&
    io.cfg_i.groups =/= 0 && io.cfg_i.groups <= config.maxGroups
  io.busy_o := busy_r
  io.done_o := done_r
  done_r := False

  // 原生反压缓冲切断尺寸比较到调度器及其他算子CE的组合ready链。
  val input = io.input_i.haltWhen(!active_r).s2mPipe()
  val request = Stream(new Bundle {
    val pixel = Bits(config.WORD_BITS bits)
    val address = UInt(log2Up(config.maxWidth max 2) bits)
    val bank = UInt(log2Up(config.LINES) bits)
    val emit = Bool()
    val real_column = Bool()
    val group = UInt(config.GROUP_BITS bits)
    val group_last = Bool()
    val last = Bool()
  })
  request.valid := active_r && (!realPixel_w || input.valid)
  request.pixel := Mux(realPixel_w, input.payload, B(0, config.WORD_BITS bits))
  request.address := x_r.resize(request.address.getWidth) - U(config.PAD, request.address.getWidth bits)
  request.bank := bank_r
  request.emit := x_r >= U(config.k - 1, config.X_BITS bits) && y_r >= U(config.k - 1, config.Y_BITS bits)
  request.real_column := realColumn_w
  request.group := group_r
  request.group_last := groupLast_w
  request.last := groupLast_w && lastGroup_w
  input.ready := active_r && realPixel_w && request.ready

  // RAM 数据与元数据同拍推进/保持。RAM 只保存真实列，不为左右补边扩容。
  // 尺寸/坐标比较及补零选择先寄存，再驱动 RAM 的数据、地址与使能。
  val memoryRequest = request.m2sPipe()
  val response = memoryRequest.m2sPipe()
  val history_w = Vec((0 until config.LINES).map { b =>
    val memory = Mem(Bits(config.WORD_BITS bits), config.maxWidth)
    memory.setName(s"lineMem_$b")
    memory.addAttribute("ram_style", "block")
    memory.write(memoryRequest.address, memoryRequest.pixel, memoryRequest.fire && memoryRequest.real_column && memoryRequest.bank === b)
    memory.readSync(memoryRequest.address, memoryRequest.fire && memoryRequest.real_column, readUnderWrite = readFirst)
  })

  when(request.fire) {
    when(x_r === paddedWidth_w - U(1, config.X_BITS bits)) {
      x_r := 0
      bank_r := bank_r + U(1, bank_r.getWidth bits)
      when(y_r === paddedHeight_w - U(1, config.Y_BITS bits)) {
        y_r := 0
        bank_r := 0
        when(lastGroup_w) { active_r := False } otherwise {
          group_r := group_r + U(1, config.GROUP_BITS bits)
        }
      } otherwise {
        y_r := y_r + U(1, config.Y_BITS bits)
      }
    } otherwise {
      x_r := x_r + U(1, config.X_BITS bits)
    }
  }

  // 环形 RAM 的覆盖位置是最旧行；read-first 保留覆盖前的像素。
  // 数据寄存器不复位：每行前 K-1 列及每帧前 K-1 行负责自然预热。
  val horizontal_r = Vec.fill(config.k)(Vec.fill(config.k - 1)(Reg(Bits(config.WORD_BITS bits))))
  val window = Stream(Fragment(LineBufferWindow(config)))
  window.valid := response.valid && response.emit
  window.fragment.group := response.group
  window.fragment.group_last := response.group_last
  window.last := response.last
  response.ready := !response.emit || window.ready
  // 每行局部复制移位使能，避免单根握手网络广播到2560个数据寄存器。
  val horizontalStep_w = response.fire
  horizontalStep_w.addAttribute("max_fanout", 64)
  for (row <- 0 until config.k) {
    val pixel_w = Bits(config.WORD_BITS bits)
    if (row < config.LINES) {
      val index_w = (response.bank + U(row, response.bank.getWidth bits)).resize(response.bank.getWidth)
      pixel_w := Mux(response.real_column, history_w(index_w), B(0, config.WORD_BITS bits))
    } else {
      pixel_w := response.pixel
    }
    for (col <- 0 until config.k - 1) {
      window.fragment.window(row)(col) := horizontal_r(row)(col)
      when(horizontalStep_w) {
        if (col == config.k - 2) horizontal_r(row)(col) := pixel_w
        else horizontal_r(row)(col) := horizontal_r(row)(col + 1)
      }
    }
    window.fragment.window(row)(config.k - 1) := pixel_w
  }

  // 一项半速缓冲：局部空闲位控制宽窗口寄存器，切断writer.ready到数千个CE。
  // 最大窗口接收率为每两拍一个；DDR串行读取的现有调度不依赖逐拍窗口吞吐。
  io.output_o << window.halfPipe()
  when(io.output_o.fire && io.output_o.last) {
    busy_r := False
    done_r := True
  }
  // 等旧窗口全部排空后才能锁存下一次配置；组切换通过补边自然清除旧数据。
  when(io.cfg_i.fire) {
    width_r := io.cfg_i.width.resized
    height_r := io.cfg_i.height.resized
    groups_r := io.cfg_i.groups
    x_r := 0
    y_r := 0
    bank_r := 0
    group_r := 0
    busy_r := True
    active_r := True
  }
}
