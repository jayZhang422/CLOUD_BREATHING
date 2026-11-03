import spinal.core._
import spinal.core.sim._
import java.io.{File, PrintWriter}
import scala.io.Source
import scala.util.Random

object Dw5x5Sim extends App {
  val root = new File("verification")
  val vectors = new File(root, "vectors")
  root.mkdirs()
  vectors.mkdirs()

  def loadHex(name: String): Vector[BigInt] = {
    val source = Source.fromFile(new File(vectors, name))
    try source.getLines().filter(_.nonEmpty).map(s => BigInt(s.trim, 16)).toVector
    finally source.close()
  }
  def signed(value: BigInt, width: Int): BigInt = {
    val masked = value & ((BigInt(1) << width) - 1)
    if (masked.testBit(width - 1)) masked - (BigInt(1) << width) else masked
  }

  val stimulus = loadHex("stimulus.hex")
  val golden = loadHex("golden_mac.hex")
  val weights = loadHex("weights.hex")
  val params = loadHex("params.hex")
  val groups = 8
  val height = 4
  val width = 4
  require(stimulus.size == groups * height * width)
  require(golden.size == stimulus.size && weights.size == groups && params.size == groups)

  val log = new PrintWriter(new File(root, "run.log"))
  val csv = new PrintWriter(new File(root, "sim_trace.csv"))
  val summary = new PrintWriter(new File(root, "result.json"))
  csv.println("cycle,valid_i,ready_i,valid_o,ready_o,group,row,col,last")
  var cycles = 0L
  var sent = 0
  var received = 0
  var checked = 0
  var inputStalls = 0
  var outputStalls = 0
  var heldOutput: Option[Vector[BigInt]] = None
  val random = new Random(20261015L)

  def fail(message: String): Nothing = {
    log.println(s"FAIL cycle=$cycles sent=$sent received=$received $message")
    log.flush()
    simFailure(message)
  }

  def sampleWord(group: Int, row: Int, col: Int): BigInt =
    if (row < 0 || row >= height || col < 0 || col >= width) BigInt(0)
    else stimulus(group * height * width + row * width + col)

  def driveWindow(dut: Dw5x5, index: Int): Unit = {
    val group = index / (height * width)
    val pixel = index % (height * width)
    val row = pixel / width
    val col = pixel % width
    for (r <- 0 until 5; c <- 0 until 5)
      dut.io.input_i.window(r)(c) #= sampleWord(group, row + r - 2, col + c - 2)
    dut.io.input_i.tag.group #= group
    dut.io.input_i.tag.row #= row
    dut.io.input_i.tag.col #= col
    dut.io.input_i.tag.group_last #= (pixel == height * width - 1)
    dut.io.input_i.tag.last #= (index == golden.size - 1)
  }

  def outputSnapshot(dut: Dw5x5): Vector[BigInt] =
    Vector(dut.io.output_o.tag.group.toBigInt, dut.io.output_o.tag.row.toBigInt,
      dut.io.output_o.tag.col.toBigInt,
      if (dut.io.output_o.tag.group_last.toBoolean) BigInt(1) else BigInt(0),
      if (dut.io.output_o.tag.last.toBoolean) BigInt(1) else BigInt(0)) ++
      (0 until 16).map(i => dut.io.output_o.mac(i).toBigInt)

  SimConfig.withFstWave.compile(new Dw5x5(Dw5x5Config())).doSim { dut =>
    dut.clockDomain.forkStimulus(period = 10)
    dut.io.cfg_i.valid #= false
    dut.io.weights_i.valid #= false
    dut.io.params_i.valid #= false
    dut.io.input_i.valid #= false
    dut.io.output_o.ready #= false
    dut.clockDomain.waitSampling(5)

    dut.io.cfg_i.groups #= groups
    dut.io.cfg_i.raw #= true
    dut.io.cfg_i.valid #= true
    dut.clockDomain.waitSampling()
    if (!dut.io.cfg_i.ready.toBoolean) fail("配置未被接受")
    dut.clockDomain.waitFallingEdge()
    dut.io.cfg_i.valid #= false

    for (g <- 0 until groups) {
      dut.io.weights_i.payload #= weights(g)
      dut.io.params_i.payload #= params(g)
      dut.io.weights_i.valid #= true
      dut.io.params_i.valid #= true
      while (!(dut.io.weights_i.ready.toBoolean && dut.io.params_i.ready.toBoolean)) dut.clockDomain.waitSampling()
      dut.clockDomain.waitSampling()
      dut.io.weights_i.valid #= false
      dut.io.params_i.valid #= false
    }

    var pending = true
    dut.io.input_i.valid #= true
    driveWindow(dut, 0)
    while (received < golden.size) {
      dut.clockDomain.waitFallingEdge()
      val ready = (cycles % 7 != 3) || received == golden.size - 1
      dut.io.output_o.ready #= ready
      if (!pending && sent < golden.size && random.nextInt(4) != 0) {
        pending = true
        dut.io.input_i.valid #= true
        driveWindow(dut, sent)
      }
      if (pending) {
        dut.io.input_i.valid #= true
        driveWindow(dut, sent)
      } else dut.io.input_i.valid #= false
      dut.clockDomain.waitSampling()
      cycles += 1

      val outValid = dut.io.output_o.valid.toBoolean
      csv.println(s"$cycles,${if (pending) 1 else 0},${if (dut.io.input_i.ready.toBoolean) 1 else 0},${if (outValid) 1 else 0},${if (ready) 1 else 0},${dut.io.output_o.tag.group.toInt},${dut.io.output_o.tag.row.toInt},${dut.io.output_o.tag.col.toInt},${if (dut.io.output_o.tag.last.toBoolean) 1 else 0}")
      if (outValid && !ready) {
        outputStalls += 1
        val snap = outputSnapshot(dut)
        heldOutput.foreach(previous => if (snap != previous) fail("输出反压期间 payload/标签改变"))
        heldOutput = Some(snap)
      } else heldOutput = None

      if (pending && dut.io.input_i.ready.toBoolean) {
        sent += 1
        pending = sent < golden.size
        if (pending) driveWindow(dut, sent) else dut.io.input_i.valid #= false
      } else if (pending) inputStalls += 1

      if (outValid && ready) {
        val expectedIndex = received
        val group = dut.io.output_o.tag.group.toInt
        val row = dut.io.output_o.tag.row.toInt
        val col = dut.io.output_o.tag.col.toInt
        val expectedGroup = expectedIndex / (height * width)
        val expectedPixel = expectedIndex % (height * width)
        if (group != expectedGroup || row != expectedPixel / width || col != expectedPixel % width)
          fail(s"标签错误 expected=($expectedGroup,${expectedPixel / width},${expectedPixel % width}) actual=($group,$row,$col)")
        if (dut.io.output_o.tag.group_last.toBoolean != (expectedPixel == height * width - 1)) fail("group_last 错误")
        if (dut.io.output_o.tag.last.toBoolean != (expectedIndex == golden.size - 1)) fail("last 错误")
        val expected = golden(expectedIndex)
        for (lane <- 0 until 16) {
          val actual = signed(dut.io.output_o.mac(lane).toBigInt, 32)
          val want = signed(expected >> (lane * 32), 32)
          if (actual != want) fail(s"MAC mismatch window=$expectedIndex lane=$lane expected=$want actual=$actual")
        }
        checked += 16
        received += 1
      }
      if (cycles > 100000) fail("watchdog timeout")
    }
    dut.clockDomain.waitSampling(4)
    if (sent != golden.size || dut.io.busy_o.toBoolean) fail("任务未排空")
  }

  log.println(s"[TB PASSED] windows=${golden.size} int32_values=$checked cycles=$cycles input_stalls=$inputStalls output_stalls=$outputStalls")
  log.close()
  csv.close()
  summary.println(s"{\"status\":\"PASS\",\"windows\":${golden.size},\"int32_values\":$checked,\"cycles\":$cycles,\"input_stalls\":$inputStalls,\"output_stalls\":$outputStalls}")
  summary.close()
  println(s"[TB PASSED] windows=${golden.size} int32_values=$checked cycles=$cycles input_stalls=$inputStalls output_stalls=$outputStalls")
}
