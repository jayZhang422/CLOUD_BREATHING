import spinal.core._
import spinal.core.sim._
import spinal.lib._
import java.io.{File, PrintWriter}
import scala.collection.mutable.ArrayBuffer
import scala.io.Source

/** Simulation-only cascade. Existing LineBuffer/DW/ElementAdd RTL is instantiated unchanged. */
class LineDwCascadeTop extends Component {
  val lb3 = new LineBuffer(LineBufferConfig(k = 3))
  val lb5 = new LineBuffer(LineBufferConfig(k = 5))
  val dw3 = new Dw3x3(Dw3x3Config())
  val dw5 = new Dw5x5(Dw5x5Config())
  val merge = new ElementAdd(ElementAddConfig())

  val lb3ToDw = Stream(Dw3x3Window(Dw3x3Config()))
  val lb5ToDw = Stream(Dw5x5Window(Dw5x5Config()))

  val row3_r = Reg(UInt(10 bits)) init(0)
  val col3_r = Reg(UInt(10 bits)) init(0)
  val row5_r = Reg(UInt(10 bits)) init(0)
  val col5_r = Reg(UInt(10 bits)) init(0)
  // This wrapper intentionally exercises the frozen 4x4 minimum cascade vector.
  val width_w = U(4, 10 bits)
  val height_w = U(4, 10 bits)

  lb3ToDw.valid := lb3.io.output_o.valid
  lb3.io.output_o.ready := lb3ToDw.ready
  lb3ToDw.payload.window := lb3.io.output_o.fragment.window
  lb3ToDw.payload.tag.group := lb3.io.output_o.fragment.group
  lb3ToDw.payload.tag.row := row3_r
  lb3ToDw.payload.tag.col := col3_r
  lb3ToDw.payload.tag.group_last := lb3.io.output_o.fragment.group_last
  lb3ToDw.payload.tag.last := lb3.io.output_o.last
  dw3.io.input_i << lb3ToDw
  when(lb3ToDw.fire) {
    when(col3_r === width_w - U(1, 10 bits)) {
      col3_r := 0
      when(row3_r === height_w - U(1, 10 bits)) { row3_r := 0 } otherwise { row3_r := row3_r + 1 }
    } otherwise { col3_r := col3_r + 1 }
  }

  lb5ToDw.valid := lb5.io.output_o.valid
  lb5.io.output_o.ready := lb5ToDw.ready
  lb5ToDw.payload.window := lb5.io.output_o.fragment.window
  lb5ToDw.payload.tag.group := lb5.io.output_o.fragment.group
  lb5ToDw.payload.tag.row := row5_r
  lb5ToDw.payload.tag.col := col5_r
  lb5ToDw.payload.tag.group_last := lb5.io.output_o.fragment.group_last
  lb5ToDw.payload.tag.last := lb5.io.output_o.last
  dw5.io.input_i << lb5ToDw
  when(lb5ToDw.fire) {
    when(col5_r === width_w - U(1, 10 bits)) {
      col5_r := 0
      when(row5_r === height_w - U(1, 10 bits)) { row5_r := 0 } otherwise { row5_r := row5_r + 1 }
    } otherwise { col5_r := col5_r + 1 }
  }

  merge.io.a_i.valid := dw3.io.output_o.valid
  dw3.io.output_o.ready := merge.io.a_i.ready
  merge.io.b_i.valid := dw5.io.output_o.valid
  dw5.io.output_o.ready := merge.io.b_i.ready
  for (lane <- 0 until 16) {
    merge.io.a_i.payload(lane * 32, 32 bits) := dw3.io.output_o.mac(lane).asBits
    merge.io.b_i.payload(lane * 32, 32 bits) := dw5.io.output_o.mac(lane).asBits
  }

  // No external IO exists in this simulation wrapper; retain all driven/observed leaf ports.
  for (io <- Seq(lb3.io.cfg_i, lb3.io.input_i, lb3.io.output_o,
                 lb5.io.cfg_i, lb5.io.input_i, lb5.io.output_o,
                 dw3.io.cfg_i, dw3.io.weights_i, dw3.io.params_i, dw3.io.input_i, dw3.io.output_o,
                 dw5.io.cfg_i, dw5.io.weights_i, dw5.io.params_i, dw5.io.input_i, dw5.io.output_o,
                 merge.io.cfg_i, merge.io.a_i, merge.io.b_i, merge.io.output_o)) io.simPublic()
  for (signal <- Seq(lb3.io.busy_o, lb3.io.done_o, lb5.io.busy_o, lb5.io.done_o,
                     dw3.io.busy_o, dw3.io.done_o, dw5.io.busy_o, dw5.io.done_o,
                     merge.io.busy_o, merge.io.done_o)) signal.simPublic()
}

object LineDwCascadeSim extends App {
  val root = new File("verification")
  root.mkdirs()
  val dw3Root = new File("../DW3x3/verification/vectors")
  val dw5Root = new File("../DW5x5/verification/vectors")
  val mergeRoot = new File("../DW_Join/verification/vectors")

  def loadHex(file: File): Vector[BigInt] = {
    val source = Source.fromFile(file)
    try source.getLines().filter(_.nonEmpty).map(s => BigInt(s.trim, 16)).toVector
    finally source.close()
  }
  def signed(value: BigInt, width: Int): BigInt = {
    val masked = value & ((BigInt(1) << width) - 1)
    if (masked.testBit(width - 1)) masked - (BigInt(1) << width) else masked
  }
  def bit(value: Boolean): BigInt = if (value) BigInt(1) else BigInt(0)

  val stimulus = loadHex(new File(dw3Root, "stimulus.hex"))
  require(stimulus == loadHex(new File(dw5Root, "stimulus.hex")), "DW3/DW5 stimulus differs")
  val golden3 = loadHex(new File(dw3Root, "golden_mac.hex"))
  val golden5 = loadHex(new File(dw5Root, "golden_mac.hex"))
  val weights3 = loadHex(new File(dw3Root, "weights.hex"))
  val weights5 = loadHex(new File(dw5Root, "weights.hex"))
  val params3 = loadHex(new File(dw3Root, "params.hex"))
  val params5 = loadHex(new File(dw5Root, "params.hex"))
  val mergeGolden = loadHex(new File(mergeRoot, "merge_golden.hex"))
  val mergeParamsA = loadHex(new File(mergeRoot, "merge_params_a.hex"))
  val mergeParamsB = loadHex(new File(mergeRoot, "merge_params_b.hex"))
  val mergeBias = loadHex(new File(mergeRoot, "merge_bias.hex"))

  val groups = 8
  val width = 4
  val height = 4
  val wordsPerGroup = width * height
  val total = groups * wordsPerGroup
  require(stimulus.size == total && golden3.size == total && golden5.size == total && mergeGolden.size == total)

  def sample(group: Int, row: Int, col: Int): BigInt =
    if (row < 0 || row >= height || col < 0 || col >= width) BigInt(0)
    else stimulus(group * wordsPerGroup + row * width + col)

  def expectedWindow(index: Int, k: Int): Vector[BigInt] = {
    val group = index / wordsPerGroup
    val pixel = index % wordsPerGroup
    val row = pixel / width
    val col = pixel % width
    (for (r <- 0 until k; c <- 0 until k) yield sample(group, row + r - k / 2, col + c - k / 2)).toVector
  }

  val log = new PrintWriter(new File(root, "run.log"))
  val result = new PrintWriter(new File(root, "result.json"))
  val csv = new PrintWriter(new File(root, "sim_trace.csv"))
  csv.println("cycle,in_valid3,in_ready3,in_valid5,in_ready5,lb3_valid,lb3_ready,lb5_valid,lb5_ready,dw3_valid,dw3_ready,dw5_valid,dw5_ready,merge_valid,merge_ready,lb3_count,lb5_count,dw3_count,dw5_count,merge_count")

  var cycle = 0L
  var sent3 = 0
  var sent5 = 0
  var sent = 0
  var acceptedWords3 = 0
  var acceptedWords5 = 0
  var lbCount3 = 0
  var lbCount5 = 0
  var dwCount3 = 0
  var dwCount5 = 0
  var mergeCount = 0
  var currentMergeGroup = 0
  var nextMergeGroup = -1
  var inputStalls = 0
  var lbStalls = 0
  var dwStalls = 0
  var mergeStalls = 0
  var lineLatency3 = ArrayBuffer[Int]()
  var lineLatency5 = ArrayBuffer[Int]()
  val inputCycle3 = Array.fill[Long](total)(-1L)
  val inputCycle5 = Array.fill[Long](total)(-1L)
  var heldLb3: Option[Vector[BigInt]] = None
  var heldLb5: Option[Vector[BigInt]] = None
  var heldDw3: Option[Vector[BigInt]] = None
  var heldDw5: Option[Vector[BigInt]] = None
  var heldMerge: Option[Vector[BigInt]] = None

  def fail(message: String): Nothing = {
    log.println(s"FAIL cycle=$cycle sent3=$sent3 sent5=$sent5 lb3=$lbCount3 lb5=$lbCount5 dw3=$dwCount3 dw5=$dwCount5 merge=$mergeCount $message")
    log.flush()
    simFailure(message)
  }

  def configureLine(dut: LineDwCascadeTop, k: Int): Unit = {
    val cfg = if (k == 3) dut.lb3.io.cfg_i else dut.lb5.io.cfg_i
    cfg.payload.width #= width
    cfg.payload.height #= height
    cfg.payload.groups #= groups
    cfg.valid #= true
    dut.clockDomain.waitSampling()
    if (!cfg.ready.toBoolean) fail(s"LineBuffer $k config not accepted")
    dut.clockDomain.waitFallingEdge()
    cfg.valid #= false
  }

  def configureDw(dut: LineDwCascadeTop, k: Int): Unit = {
    if (k == 3) {
      dut.dw3.io.cfg_i.groups #= groups
      dut.dw3.io.cfg_i.raw #= true
      dut.dw3.io.cfg_i.valid #= true
      dut.clockDomain.waitSampling()
      if (!dut.dw3.io.cfg_i.ready.toBoolean) fail("DW3 config not accepted")
      dut.clockDomain.waitFallingEdge()
      dut.dw3.io.cfg_i.valid #= false
      for (g <- 0 until groups) {
        dut.dw3.io.weights_i.payload #= weights3(g)
        dut.dw3.io.params_i.payload #= params3(g)
        dut.dw3.io.weights_i.valid #= true
        dut.dw3.io.params_i.valid #= true
        while (!(dut.dw3.io.weights_i.ready.toBoolean && dut.dw3.io.params_i.ready.toBoolean)) dut.clockDomain.waitSampling()
        dut.clockDomain.waitSampling()
        dut.dw3.io.weights_i.valid #= false
        dut.dw3.io.params_i.valid #= false
      }
    } else {
      dut.dw5.io.cfg_i.groups #= groups
      dut.dw5.io.cfg_i.raw #= true
      dut.dw5.io.cfg_i.valid #= true
      dut.clockDomain.waitSampling()
      if (!dut.dw5.io.cfg_i.ready.toBoolean) fail("DW5 config not accepted")
      dut.clockDomain.waitFallingEdge()
      dut.dw5.io.cfg_i.valid #= false
      for (g <- 0 until groups) {
        dut.dw5.io.weights_i.payload #= weights5(g)
        dut.dw5.io.params_i.payload #= params5(g)
        dut.dw5.io.weights_i.valid #= true
        dut.dw5.io.params_i.valid #= true
        while (!(dut.dw5.io.weights_i.ready.toBoolean && dut.dw5.io.params_i.ready.toBoolean)) dut.clockDomain.waitSampling()
        dut.clockDomain.waitSampling()
        dut.dw5.io.weights_i.valid #= false
        dut.dw5.io.params_i.valid #= false
      }
    }
  }

  def driveMergeConfig(dut: LineDwCascadeTop, group: Int): Unit = {
    for (lane <- 0 until 16) {
      dut.merge.io.cfg_i.multiplier_a(lane) #= signed((mergeParamsA(group) >> (22 * lane)) & ((BigInt(1) << 22) - 1), 22)
      dut.merge.io.cfg_i.multiplier_b(lane) #= signed((mergeParamsB(group) >> (22 * lane)) & ((BigInt(1) << 22) - 1), 22)
      dut.merge.io.cfg_i.bias_fixed(lane) #= signed((mergeBias(group) >> (64 * lane)) & ((BigInt(1) << 64) - 1), 64)
    }
    dut.merge.io.cfg_i.words #= wordsPerGroup
    dut.merge.io.cfg_i.group #= group
    dut.merge.io.cfg_i.last_group #= group == groups - 1
    dut.merge.io.cfg_i.shift #= 24
    dut.merge.io.cfg_i.clamp_min #= 0
    dut.merge.io.cfg_i.clamp_max #= 127
    dut.merge.io.cfg_i.valid #= true
  }

  def configureMerge(dut: LineDwCascadeTop, group: Int): Unit = {
    driveMergeConfig(dut, group)
    dut.clockDomain.waitSampling()
    if (!dut.merge.io.cfg_i.ready.toBoolean) fail(s"merge config $group not accepted")
    dut.clockDomain.waitFallingEdge()
    dut.merge.io.cfg_i.valid #= false
    currentMergeGroup = group
  }

  def lineSnapshot3(dut: LineDwCascadeTop): Vector[BigInt] =
    Vector(dut.lb3.io.output_o.fragment.group.toBigInt,
      bit(dut.lb3.io.output_o.fragment.group_last.toBoolean), bit(dut.lb3.io.output_o.last.toBoolean)) ++
      (for (r <- 0 until 3; c <- 0 until 3) yield dut.lb3.io.output_o.fragment.window(r)(c).toBigInt)

  def lineSnapshot5(dut: LineDwCascadeTop): Vector[BigInt] =
    Vector(dut.lb5.io.output_o.fragment.group.toBigInt,
      bit(dut.lb5.io.output_o.fragment.group_last.toBoolean), bit(dut.lb5.io.output_o.last.toBoolean)) ++
      (for (r <- 0 until 5; c <- 0 until 5) yield dut.lb5.io.output_o.fragment.window(r)(c).toBigInt)

  def dwSnapshot3(dut: LineDwCascadeTop): Vector[BigInt] =
    Vector(dut.dw3.io.output_o.tag.group.toBigInt, dut.dw3.io.output_o.tag.row.toBigInt,
      dut.dw3.io.output_o.tag.col.toBigInt, bit(dut.dw3.io.output_o.tag.group_last.toBoolean),
      bit(dut.dw3.io.output_o.tag.last.toBoolean)) ++ (0 until 16).map(i => dut.dw3.io.output_o.mac(i).toBigInt)

  def dwSnapshot5(dut: LineDwCascadeTop): Vector[BigInt] =
    Vector(dut.dw5.io.output_o.tag.group.toBigInt, dut.dw5.io.output_o.tag.row.toBigInt,
      dut.dw5.io.output_o.tag.col.toBigInt, bit(dut.dw5.io.output_o.tag.group_last.toBoolean),
      bit(dut.dw5.io.output_o.tag.last.toBoolean)) ++ (0 until 16).map(i => dut.dw5.io.output_o.mac(i).toBigInt)

  def mergeSnapshot(dut: LineDwCascadeTop): Vector[BigInt] =
    Vector(dut.merge.io.output_o.fragment.group.toBigInt,
      bit(dut.merge.io.output_o.fragment.group_last.toBoolean), bit(dut.merge.io.output_o.last.toBoolean),
      dut.merge.io.output_o.fragment.data.toBigInt)

  SimConfig.withFstWave.compile(new LineDwCascadeTop).doSim { dut =>
    dut.clockDomain.forkStimulus(period = 10)
    dut.lb3.io.cfg_i.valid #= false
    dut.lb5.io.cfg_i.valid #= false
    dut.lb3.io.input_i.valid #= false
    dut.lb5.io.input_i.valid #= false
    dut.dw3.io.cfg_i.valid #= false
    dut.dw3.io.weights_i.valid #= false
    dut.dw3.io.params_i.valid #= false
    dut.dw5.io.cfg_i.valid #= false
    dut.dw5.io.weights_i.valid #= false
    dut.dw5.io.params_i.valid #= false
    dut.merge.io.cfg_i.valid #= false
    dut.merge.io.output_o.ready #= false
    dut.clockDomain.waitSampling(5)

    configureLine(dut, 3)
    configureLine(dut, 5)
    configureDw(dut, 3)
    configureDw(dut, 5)
    configureMerge(dut, 0)

    var outputReady = true
    while (sent3 < total || sent5 < total || lbCount3 < total || lbCount5 < total || dwCount3 < total || dwCount5 < total || mergeCount < total) {
      dut.clockDomain.waitFallingEdge()
      // 配置换组也走统一采样循环，不能漏计这期间的输入/窗口握手。
      val configuringMerge = nextMergeGroup >= 0
      if (configuringMerge) driveMergeConfig(dut, nextMergeGroup)
      else dut.merge.io.cfg_i.valid #= false
      val valid3 = sent3 < total
      val valid5 = sent5 < total
      if (valid3) dut.lb3.io.input_i.payload #= stimulus(sent3)
      if (valid5) dut.lb5.io.input_i.payload #= stimulus(sent5)
      dut.lb3.io.input_i.valid #= valid3
      dut.lb5.io.input_i.valid #= valid5
      outputReady = !configuringMerge && ((cycle % 13 != 6) || mergeCount == total - 1)
      dut.merge.io.output_o.ready #= outputReady
      dut.clockDomain.waitSampling()
      cycle += 1
      if (configuringMerge && dut.merge.io.cfg_i.ready.toBoolean) {
        currentMergeGroup = nextMergeGroup
        nextMergeGroup = -1
      }

      val lineReady3 = dut.lb3.io.output_o.ready.toBoolean
      val lineReady5 = dut.lb5.io.output_o.ready.toBoolean
      val fireIn3 = valid3 && dut.lb3.io.input_i.ready.toBoolean
      val fireIn5 = valid5 && dut.lb5.io.input_i.ready.toBoolean
      if (fireIn3) {
        if (dut.lb3.io.input_i.payload.toBigInt != stimulus(acceptedWords3)) fail(s"LineBuffer3 input sequence mismatch index=$acceptedWords3")
        inputCycle3(sent3) = cycle
        sent3 += 1
        acceptedWords3 += 1
      }
      if (fireIn5) {
        if (dut.lb5.io.input_i.payload.toBigInt != stimulus(acceptedWords5)) fail(s"LineBuffer5 input sequence mismatch index=$acceptedWords5")
        inputCycle5(sent5) = cycle
        sent5 += 1
        acceptedWords5 += 1
      }
      if (valid3 && !dut.lb3.io.input_i.ready.toBoolean) inputStalls += 1
      if (valid5 && !dut.lb5.io.input_i.ready.toBoolean) inputStalls += 1
      sent = if (sent3 < sent5) sent3 else sent5

      val lbFire3 = dut.lb3.io.output_o.valid.toBoolean && lineReady3
      val lbFire5 = dut.lb5.io.output_o.valid.toBoolean && lineReady5
      if (dut.lb3.io.output_o.valid.toBoolean && !lineReady3) {
        lbStalls += 1
        val snap = lineSnapshot3(dut)
        heldLb3.foreach(previous => if (snap != previous) fail("LineBuffer3 window changed during backpressure"))
        heldLb3 = Some(snap)
      } else heldLb3 = None
      if (dut.lb5.io.output_o.valid.toBoolean && !lineReady5) {
        lbStalls += 1
        val snap = lineSnapshot5(dut)
        heldLb5.foreach(previous => if (snap != previous) fail("LineBuffer5 window changed during backpressure"))
        heldLb5 = Some(snap)
      } else heldLb5 = None
      if (lbFire3) {
        val index = lbCount3
        val group = index / wordsPerGroup
        val pixel = index % wordsPerGroup
        if (dut.lb3.io.output_o.fragment.group.toInt != group ||
            dut.lb3.io.output_o.fragment.group_last.toBoolean != (pixel == wordsPerGroup - 1) ||
            dut.lb3.io.output_o.last.toBoolean != (index == total - 1)) fail(s"LineBuffer3 boundary mismatch index=$index")
        val expected = expectedWindow(index, 3)
        for (r <- 0 until 3; c <- 0 until 3)
          if (dut.lb3.io.output_o.fragment.window(r)(c).toBigInt != expected(r * 3 + c)) {
            val actualWindow = (for (rr <- 0 until 3; cc <- 0 until 3) yield dut.lb3.io.output_o.fragment.window(rr)(cc).toBigInt.toString(16)).mkString("[", ",", "]")
            val acceptedCycles = inputCycle3.slice(16, 24).mkString("[", ",", "]")
            fail(s"LineBuffer3 padding/window mismatch index=$index group=$group row=${pixel / width} col=${pixel % width} cell=$r,$c expected=0x${expected(r * 3 + c).toString(16)} actual=0x${dut.lb3.io.output_o.fragment.window(r)(c).toBigInt.toString(16)} window=$actualWindow inputCycles=$acceptedCycles")
          }
        if (inputCycle3(index) >= 0 && lineLatency3.size < 8) lineLatency3 += (cycle - inputCycle3(index)).toInt
        lbCount3 += 1
      }
      if (lbFire5) {
        val index = lbCount5
        val group = index / wordsPerGroup
        val pixel = index % wordsPerGroup
        if (dut.lb5.io.output_o.fragment.group.toInt != group ||
            dut.lb5.io.output_o.fragment.group_last.toBoolean != (pixel == wordsPerGroup - 1) ||
            dut.lb5.io.output_o.last.toBoolean != (index == total - 1)) fail(s"LineBuffer5 boundary mismatch index=$index")
        val expected = expectedWindow(index, 5)
        for (r <- 0 until 5; c <- 0 until 5)
          if (dut.lb5.io.output_o.fragment.window(r)(c).toBigInt != expected(r * 5 + c))
            fail(s"LineBuffer5 padding/window mismatch index=$index group=$group row=${pixel / width} col=${pixel % width} cell=$r,$c expected=0x${expected(r * 5 + c).toString(16)} actual=0x${dut.lb5.io.output_o.fragment.window(r)(c).toBigInt.toString(16)}")
        if (inputCycle5(index) >= 0 && lineLatency5.size < 8) lineLatency5 += (cycle - inputCycle5(index)).toInt
        lbCount5 += 1
      }

      val dwFire3 = dut.dw3.io.output_o.valid.toBoolean && dut.dw3.io.output_o.ready.toBoolean
      val dwFire5 = dut.dw5.io.output_o.valid.toBoolean && dut.dw5.io.output_o.ready.toBoolean
      if (dut.dw3.io.output_o.valid.toBoolean && !dut.dw3.io.output_o.ready.toBoolean) {
        dwStalls += 1
        val snap = dwSnapshot3(dut)
        heldDw3.foreach(previous => if (snap != previous) fail("DW3 output changed during backpressure"))
        heldDw3 = Some(snap)
      } else heldDw3 = None
      if (dut.dw5.io.output_o.valid.toBoolean && !dut.dw5.io.output_o.ready.toBoolean) {
        dwStalls += 1
        val snap = dwSnapshot5(dut)
        heldDw5.foreach(previous => if (snap != previous) fail("DW5 output changed during backpressure"))
        heldDw5 = Some(snap)
      } else heldDw5 = None
      if (dwFire3) {
        val index = dwCount3
        val pixel = index % wordsPerGroup
        if (dut.dw3.io.output_o.tag.group.toInt != index / wordsPerGroup ||
            dut.dw3.io.output_o.tag.row.toInt != pixel / width || dut.dw3.io.output_o.tag.col.toInt != pixel % width ||
            dut.dw3.io.output_o.tag.group_last.toBoolean != (pixel == wordsPerGroup - 1) ||
            dut.dw3.io.output_o.tag.last.toBoolean != (index == total - 1)) fail(s"DW3 tag mismatch index=$index")
        val expected = golden3(index)
        for (lane <- 0 until 16) if (signed(dut.dw3.io.output_o.mac(lane).toBigInt, 32) != signed(expected >> (32 * lane), 32)) fail(s"DW3 Golden mismatch index=$index lane=$lane")
        dwCount3 += 1
      }
      if (dwFire5) {
        val index = dwCount5
        val pixel = index % wordsPerGroup
        if (dut.dw5.io.output_o.tag.group.toInt != index / wordsPerGroup ||
            dut.dw5.io.output_o.tag.row.toInt != pixel / width || dut.dw5.io.output_o.tag.col.toInt != pixel % width ||
            dut.dw5.io.output_o.tag.group_last.toBoolean != (pixel == wordsPerGroup - 1) ||
            dut.dw5.io.output_o.tag.last.toBoolean != (index == total - 1)) fail(s"DW5 tag mismatch index=$index")
        val expected = golden5(index)
        for (lane <- 0 until 16) if (signed(dut.dw5.io.output_o.mac(lane).toBigInt, 32) != signed(expected >> (32 * lane), 32)) fail(s"DW5 Golden mismatch index=$index lane=$lane")
        dwCount5 += 1
      }

      val mergeFire = dut.merge.io.output_o.valid.toBoolean && outputReady
      if (dut.merge.io.output_o.valid.toBoolean && !outputReady) {
        mergeStalls += 1
        val snap = mergeSnapshot(dut)
        heldMerge.foreach(previous => if (snap != previous) fail("merge output changed during backpressure"))
        heldMerge = Some(snap)
      } else heldMerge = None
      if (mergeFire) {
        val index = mergeCount
        if (dut.merge.io.output_o.fragment.data.toBigInt != mergeGolden(index)) fail(s"merge Golden mismatch index=$index")
        val pixel = index % wordsPerGroup
        if (dut.merge.io.output_o.fragment.group.toInt != currentMergeGroup ||
            dut.merge.io.output_o.fragment.group_last.toBoolean != (pixel == wordsPerGroup - 1) ||
            dut.merge.io.output_o.last.toBoolean != (index == total - 1)) fail(s"merge boundary mismatch index=$index")
        mergeCount += 1
        if (pixel == wordsPerGroup - 1 && currentMergeGroup < groups - 1) nextMergeGroup = currentMergeGroup + 1
      }

      csv.println(s"$cycle,$valid3,${dut.lb3.io.input_i.ready.toBoolean},$valid5,${dut.lb5.io.input_i.ready.toBoolean}," +
        s"${dut.lb3.io.output_o.valid.toBoolean},$lineReady3,${dut.lb5.io.output_o.valid.toBoolean},$lineReady5," +
        s"${dut.dw3.io.output_o.valid.toBoolean},${dut.dw3.io.output_o.ready.toBoolean},${dut.dw5.io.output_o.valid.toBoolean},${dut.dw5.io.output_o.ready.toBoolean}," +
        s"${dut.merge.io.output_o.valid.toBoolean},$outputReady,$lbCount3,$lbCount5,$dwCount3,$dwCount5,$mergeCount")
      csv.flush()
      if (cycle > 200000) fail("cascade watchdog timeout")
    }
    dut.clockDomain.waitSampling(5)
    if (sent3 != total || sent5 != total || lbCount3 != total || lbCount5 != total || dwCount3 != total || dwCount5 != total || mergeCount != total) fail("cascade counts incomplete")
    if (mergeStalls == 0 || inputStalls == 0 || lbStalls == 0) fail("backpressure coverage missing")
  }

  val summary = s"[TB PASSED] cascaded_windows=$total line3_latency=${lineLatency3.head} line5_latency=${lineLatency5.head} dw3_values=${total * 16} dw5_values=${total * 16} merge_values=${total * 16} input_stalls=$inputStalls linebuffer_stalls=$lbStalls dw_stalls=$dwStalls merge_output_stalls=$mergeStalls"
  log.println(summary)
  log.close()
  csv.close()
  result.println(s"{\"status\":\"PASS\",\"cascaded_windows\":$total,\"line3_latency\":${lineLatency3.head},\"line5_latency\":${lineLatency5.head},\"dw3_values\":${total * 16},\"dw5_values\":${total * 16},\"merge_values\":${total * 16},\"input_stalls\":$inputStalls,\"linebuffer_stalls\":$lbStalls,\"dw_stalls\":$dwStalls,\"merge_output_stalls\":$mergeStalls}")
  result.close()
  println(summary)
}
