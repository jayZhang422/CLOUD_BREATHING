// 文件类型：.scala。仅驱动握手/核对离线 Golden；FST + CSV 供失败现场定位。
import spinal.core._
import spinal.core.sim._
import java.io.{BufferedInputStream, DataInputStream, File, FileInputStream, PrintWriter}
import java.util.zip.GZIPInputStream
import scala.io.Source
import scala.util.Random

object UpsampleSim extends App {
  val root = new File(args(0))
  val manifest = Source.fromFile(new File(root, "cases.csv"))
  val cases = try manifest.getLines().drop(1).map(_.split(",")).toVector finally manifest.close()
  def openWords(file: File) = new DataInputStream(new BufferedInputStream(new GZIPInputStream(new FileInputStream(file))))
  def word(stream: DataInputStream): BigInt = {
    val bytes = new Array[Byte](16)
    stream.readFully(bytes)
    BigInt(1, bytes.reverse)
  }
  val summary = new PrintWriter(new File(root, "results.csv"))
  summary.println("case,inputs,outputs,int8_values,cycles,input_stalls,output_stalls,first_latency,status")
  var completed = 0
  var totalInputs = 0L
  var totalOutputs = 0L
  val compiled = SimConfig.withConfig(SpinalConfig(defaultConfigForClockDomains =
    ClockDomainConfig(resetKind = ASYNC, resetActiveLevel = LOW)))
    .workspacePath(new File(root, "compiled").getPath).withFstWave.compile(new Upsample())
  try compiled.doSim("regression", 20261016) { dut =>
    var cycle = 0L
    var checking = false
    var csv: PrintWriter = null
    var golden: DataInputStream = null
    var name = "initial"
    var width = 1; var height = 1; var groups = 1
    var sent = 0; var received = 0; var doneCount = 0; var cfgCount = 0
    var inputStalls = 0L; var outputStalls = 0L
    var deadline = 0L; var lastInputRowCycle = 0L; var firstLatency = -1L
    var previousOutputCycle = 0L
    var continuous = false
    var heldInput: Option[BigInt] = None
    var heldOutput: Option[(BigInt, Int, Int, Int, Boolean, Boolean)] = None
    def fail(message: String): Nothing = {
      if (csv != null) csv.flush()
      simFailure(s"$name cycle=$cycle time=${simTime()} sent=$sent received=$received $message")
    }
    dut.io.cfg_i.valid #= false
    dut.io.cfg_i.width #= 1; dut.io.cfg_i.height #= 1; dut.io.cfg_i.groups #= 1
    dut.io.input_i.valid #= false; dut.io.input_i.payload #= 0
    dut.io.output_o.ready #= false
    dut.clockDomain.forkStimulus(period = 8) // 125 MHz 仅为仿真时钟，非 STA 证据
    dut.clockDomain.onSamplings {
      val reset = dut.clockDomain.isResetAsserted
      val iv = dut.io.input_i.valid.toBoolean; val ir = dut.io.input_i.ready.toBoolean
      val id = dut.io.input_i.payload.toBigInt
      val ov = dut.io.output_o.valid.toBoolean; val or = dut.io.output_o.ready.toBoolean
      val od = dut.io.output_o.fragment.data.toBigInt
      val og = dut.io.output_o.fragment.group.toInt
      val oy = dut.io.output_o.fragment.row.toInt; val ox = dut.io.output_o.fragment.col.toInt
      val gl = dut.io.output_o.fragment.group_last.toBoolean; val last = dut.io.output_o.last.toBoolean
      if (csv != null) csv.println(s"$cycle,$reset,$checking,$sent,$received,$iv,$ir,${id.toString(16)},$ov,$or,${od.toString(16)},$og,$oy,$ox,$gl,$last,${dut.io.busy_o.toBoolean},${dut.io.done_o.toBoolean}")
      if (!reset && dut.io.cfg_i.valid.toBoolean && dut.io.cfg_i.ready.toBoolean) cfgCount += 1
      if (checking && !reset) {
        if (cycle > deadline) fail("watchdog timeout")
        if (dut.io.busy_o.toBoolean && dut.io.cfg_i.ready.toBoolean) fail("busy accepted config")
        if (dut.io.done_o.toBoolean) {
          doneCount += 1
          if (!(received == width * height * groups * 4 && sent == width * height * groups)) fail("early done")
        }
        heldInput.foreach(p => if (!iv || !(id == p)) fail("input changed under stall"))
        heldInput = if (iv && !ir) Some(id) else None
        val snapshot = (od, og, oy, ox, gl, last)
        heldOutput.foreach(p => if (!ov || !(snapshot == p)) fail("output changed under stall"))
        heldOutput = if (ov && !or) Some(snapshot) else None
        if (iv && !ir) inputStalls += 1
        if (ov && !or) outputStalls += 1
        if (iv && ir) {
          sent += 1
          if (sent % width == 0) lastInputRowCycle = cycle
        }
        if (ov && or) {
          val pixels = width * height * 4
          if (received >= pixels * groups) fail("extra output")
          val eg = received / pixels; val ey = received % pixels / (width * 2); val ex = received % (width * 2)
          val egl = received % pixels == pixels - 1; val el = received == pixels * groups - 1
          if (!(og == eg && oy == ey && ox == ex && gl == egl && last == el))
            fail(s"tag expected=($eg,$ey,$ex,$egl,$el) actual=($og,$oy,$ox,$gl,$last)")
          val expected = word(golden)
          if (!(od == expected)) {
            val lane = (0 until 16).find(i => !(((od >> (8*i)) & 255) == ((expected >> (8*i)) & 255))).get
            fail(s"lane=$lane expected=0x${expected.toString(16)} actual=0x${od.toString(16)}")
          }
          if (received == 0) firstLatency = cycle - lastInputRowCycle
          if (continuous) {
            if (received % (width * 4) == 0) {
              if (!(cycle - lastInputRowCycle == 3)) fail(s"row latency=${cycle-lastInputRowCycle}, expected=3")
            } else if (!(cycle - previousOutputCycle == 1)) fail("non-contiguous output row pair")
          }
          previousOutputCycle = cycle
          received += 1
        }
      }
      cycle += 1
    }
    fork { sleep(2000000000L); fail("global watchdog timeout") }

    def configure(w: Int, h: Int, g: Int): Unit = {
      val before = cfgCount
      dut.clockDomain.waitFallingEdge(); sleep(1)
      dut.io.cfg_i.width #= w; dut.io.cfg_i.height #= h; dut.io.cfg_i.groups #= g
      dut.io.cfg_i.valid #= true
      dut.clockDomain.waitSampling()
      dut.clockDomain.waitFallingEdge(); sleep(1)
      if (!(cfgCount == before + 1)) fail("config handshake missing")
      dut.io.cfg_i.valid #= false
    }
    dut.clockDomain.waitSampling(10)
    for ((w,h,g) <- Seq((0,1,1),(257,1,1),(1,0,1),(1,257,1),(1,1,0),(1,1,33))) {
      dut.clockDomain.waitFallingEdge()
      dut.io.cfg_i.width #= w; dut.io.cfg_i.height #= h; dut.io.cfg_i.groups #= g
      dut.io.cfg_i.valid #= true
      dut.clockDomain.waitSampling(3)
      if (dut.io.cfg_i.ready.toBoolean || dut.io.busy_o.toBoolean || dut.io.input_i.ready.toBoolean || dut.io.output_o.valid.toBoolean)
        fail(s"invalid config accepted ($w,$h,$g)")
    }
    dut.clockDomain.waitFallingEdge(); dut.io.cfg_i.valid #= false
    println("[TB PASSED] invalid_config cases=6")

    for (entry <- cases) {
      val Array(caseName, wt, ht, gt, st, mode) = entry
      name = caseName; width = wt.toInt; height = ht.toInt; groups = gt.toInt
      val random = new Random(st.toLong)
      val directory = new File(root, name)
      val stimulus = openWords(new File(directory, "stimulus.bin.gz"))
      golden = openWords(new File(directory, "golden.bin.gz"))
      csv = new PrintWriter(new File(directory, "sim_trace.csv"))
      csv.println("cycle,reset,checking,sent,received,valid_i,ready_o,input,valid_o,ready_i,data,group,row,col,group_last,last,busy,done")
      checking = false; heldInput = None; heldOutput = None
      dut.io.input_i.valid #= false; dut.io.output_o.ready #= false
      try {
        if (mode.startsWith("reset_")) {
          configure(8, 3, 2)
          var warmSent = 0; var warmReceived = 0; var steps = 0
          var target = false
          while (!target && steps < 1000) {
            dut.clockDomain.waitFallingEdge(); sleep(1)
            dut.io.input_i.valid #= (warmSent < 48)
            dut.io.input_i.payload #= BigInt("80ff7f0102030405060708090a0b0c0d", 16)
            val stop = mode == "reset_stalled" || (mode == "reset_last" && warmReceived == 191)
            dut.io.output_o.ready #= !stop
            dut.clockDomain.waitSampling()
            if (dut.io.input_i.valid.toBoolean && dut.io.input_i.ready.toBoolean) warmSent += 1
            if (dut.io.output_o.valid.toBoolean && dut.io.output_o.ready.toBoolean) warmReceived += 1
            target = mode match {
              case "reset_fill" => warmSent == 3
              case "reset_emit" => warmReceived == 5
              case "reset_stalled" => dut.io.output_o.valid.toBoolean && steps > 20
              case "reset_last" => dut.io.output_o.valid.toBoolean && dut.io.output_o.last.toBoolean && stop
            }
            steps += 1
          }
          if (!target) fail("reset phase not reached")
          dut.clockDomain.waitFallingEdge()
          dut.io.input_i.valid #= false; dut.clockDomain.assertReset()
          dut.clockDomain.waitRisingEdge(5)
          dut.clockDomain.waitFallingEdge(); dut.clockDomain.deassertReset()
          dut.io.output_o.ready #= true
          dut.clockDomain.waitSampling(5)
          if (dut.io.busy_o.toBoolean || dut.io.output_o.valid.toBoolean || dut.io.done_o.toBoolean) fail("stale state after reset")
          println(s"[RESET CHECK] $name aborted inputs=$warmSent outputs=$warmReceived")
        }
        sent = 0; received = 0; doneCount = 0; inputStalls = 0; outputStalls = 0
        continuous = mode == "continuous"; firstLatency = -1
        deadline = cycle + width.toLong * height * groups * 30 + 5000
        checking = true
        val start = cycle
        configure(width, height, groups)
        val taskConfigs = cfgCount
        // 配置握手后任意改变引脚，确认已锁存。
        dut.io.cfg_i.width #= 2; dut.io.cfg_i.height #= 2; dut.io.cfg_i.groups #= 1
        val count = width * height * groups
        var pending = false; var inputWord = BigInt(0); var drive = 0; var finalStall = 0
        while (sent < count || received < count * 4) {
          dut.clockDomain.waitFallingEdge(); sleep(1)
          if (!pending && sent < count && (continuous || random.nextInt(4) > 0)) {
            inputWord = word(stimulus); pending = true
          }
          dut.io.input_i.valid #= pending
          if (pending) dut.io.input_i.payload #= inputWord
          val stallLast = !continuous && dut.io.output_o.valid.toBoolean && dut.io.output_o.last.toBoolean && finalStall < 17
          dut.io.output_o.ready #= (continuous || (!stallLast && drive % 211 >= 31 && random.nextInt(5) > 0))
          dut.io.cfg_i.valid #= stallLast
          if (stallLast) finalStall += 1
          val before = sent
          dut.clockDomain.waitSampling()
          sleep(1) // 让采样回调完成，下一下降沿前完成驱动状态更新
          if (sent > before) pending = false
          drive += 1
        }
        dut.io.input_i.valid #= false; dut.io.cfg_i.valid #= false; dut.io.output_o.ready #= true
        dut.clockDomain.waitSampling(6)
        dut.clockDomain.waitFallingEdge()
        if (!(doneCount == 1 && cfgCount == taskConfigs) || dut.io.busy_o.toBoolean) fail("completion/config count")
        if (!continuous && !(outputStalls > 0 && finalStall == 17)) fail("stall coverage missing")
        if (!(stimulus.read() == -1 && golden.read() == -1)) fail("vector length mismatch")
        val elapsed = cycle - start
        totalInputs += sent; totalOutputs += received; completed += 1
        summary.println(s"$name,$sent,$received,${received.toLong*16},$elapsed,$inputStalls,$outputStalls,$firstLatency,PASS")
        summary.flush()
        println(s"[TB PASSED] $name inputs=$sent outputs=$received cycles=$elapsed stalls=$outputStalls firstLatency=$firstLatency")
      } finally {
        checking = false; stimulus.close(); golden.close(); csv.close(); csv = null
      }
    }
    simSuccess()
  } finally summary.close()
  require(completed == cases.size && completed == 29)
  println(s"[TB PASSED] ALL cases=$completed inputs=$totalInputs outputs=$totalOutputs int8Values=${totalOutputs*16}")
}
