// 文件类型：.scala。唯一使用 SpinalSim/Verilator；离线 Golden、FST 与逐周期 CSV。
import spinal.core._
import spinal.core.sim._
import java.io.{File, PrintWriter}
import scala.io.Source
import scala.util.Random

object LineBufferSim extends App {
  val root = new File(args.headOption.getOrElse("verification/deployment"))
  val manifest = Source.fromFile(new File(root, "cases.csv"))
  val cases = try manifest.getLines().drop(1).map(_.split(",")).toVector finally manifest.close()
  var totalWindows = 0L
  var totalCells = 0L
  var completedCases = 0
  val summary = new PrintWriter(new File(root, "results.csv"))
  summary.println("case,windows,int8_cells,cycles,input_stalls,output_stalls,first_output,last_output,status")

  def loadHex(file: File): Vector[BigInt] = {
    val source = Source.fromFile(file)
    try source.getLines().map(s => BigInt(s.trim, 16)).toVector finally source.close()
  }

  try for (k <- Seq(3, 5)) {
    val compiled = SimConfig
      .withConfig(SpinalConfig(defaultConfigForClockDomains = ClockDomainConfig(resetKind = ASYNC, resetActiveLevel = LOW)))
      .workspacePath(new File(root, s"compiled_k$k").getPath)
      .withFstWave
      .compile(new LineBuffer(LineBufferConfig(k = k)))

    // 同一 DUT 连续切换尺寸、组数；只在明确的复位用例中断任务。
    compiled.doSim(s"deployment_k$k", 20261011 + k) { dut =>
      var cycles = 0L
      var checking = false
      var csv: PrintWriter = null
      var stimulus = Vector.empty[BigInt]
      var golden = Vector.empty[BigInt]
      var name = "initial"
      var width = 1
      var height = 1
      var groups = 1
      var sent = 0
      var received = 0
      var configCount = 0
      var doneCount = 0
      var inputStalls = 0L
      var outputStalls = 0L
      var firstOutputCycle = -1L
      var lastOutputCycle = -1L
      var continuous = false
      var deadline = 0L
      var heldOutput: Option[(BigInt, Int, Boolean, Boolean)] = None
      var heldInput: Option[BigInt] = None

      def fail(message: String): Nothing = {
        if (csv != null) csv.flush()
        simFailure(s"$name cycle=$cycles time=${simTime()} $message")
      }
      def windowValue(): BigInt = {
        var value = BigInt(0)
        for (r <- 0 until k; c <- 0 until k)
          value |= dut.io.output_o.fragment.window(r)(c).toBigInt << (128 * (r * k + c))
        value
      }
      dut.io.cfg_i.valid #= false
      dut.io.cfg_i.width #= 1
      dut.io.cfg_i.height #= 1
      dut.io.cfg_i.groups #= 1
      dut.io.input_i.valid #= false
      dut.io.input_i.payload #= 0
      dut.io.output_o.ready #= false
      dut.clockDomain.forkStimulus(period = 10)
      dut.clockDomain.onSamplings {
        val reset = dut.clockDomain.isResetAsserted
        val valid = dut.io.output_o.valid.toBoolean
        val ready = dut.io.output_o.ready.toBoolean
        val inValid = dut.io.input_i.valid.toBoolean
        val inReady = dut.io.input_i.ready.toBoolean
        val input = dut.io.input_i.payload.toBigInt
        val value = windowValue()
        val group = dut.io.output_o.fragment.group.toInt
        val groupLast = dut.io.output_o.fragment.group_last.toBoolean
        val last = dut.io.output_o.last.toBoolean
        if (csv != null) csv.println(s"$cycles,$reset,$checking,$sent,$received," +
          s"${dut.io.cfg_i.valid.toBoolean},${dut.io.cfg_i.ready.toBoolean},${dut.io.busy_o.toBoolean}," +
          s"${dut.io.done_o.toBoolean},$inValid,$inReady,${input.toString(16)},$valid,$ready,$group,$groupLast,$last,${value.toString(16)}")
        if (!reset && dut.io.cfg_i.valid.toBoolean && dut.io.cfg_i.ready.toBoolean) configCount += 1
        if (checking && !reset) {
          if (dut.io.done_o.toBoolean) doneCount += 1
          if (dut.io.busy_o.toBoolean && dut.io.cfg_i.ready.toBoolean) fail("busy 期间允许了新配置")
          heldInput.foreach(previous => if (!inValid || !(input == previous)) fail("输入反压时 valid/data 改变"))
          heldInput = if (inValid && !inReady) Some(input) else None
          val snapshot = (value, group, groupLast, last)
          heldOutput.foreach(previous => if (!valid || !(snapshot == previous)) fail("输出反压时窗口/组号/边界改变"))
          heldOutput = if (valid && !ready) Some(snapshot) else None
          if (inValid && !inReady) inputStalls += 1
          if (valid && !ready) outputStalls += 1
          if (valid && ready) {
            if (received >= golden.size) fail("额外输出窗口")
            val pixels = width * height
            val expectedGroup = received / pixels
            val expectedGroupLast = received % pixels == pixels - 1
            val expectedLast = received == golden.size - 1
            if (!(group == expectedGroup && groupLast == expectedGroupLast && last == expectedLast))
              fail(s"边界 expected=($expectedGroup,$expectedGroupLast,$expectedLast) actual=($group,$groupLast,$last)")
            if (!(value == golden(received))) {
              // 只定位第一个错误 lane；参考运算全部来自离线文件。
              val index = (0 until k * k * 16).find(i => !(((value >> (8 * i)) & 255) == ((golden(received) >> (8 * i)) & 255))).get
              fail(s"window=$received group=$group center=(${received % pixels / width},${received % width}) " +
                s"cell=(${index / 16 / k},${index / 16 % k}) lane=${index % 16} " +
                s"expected=${(golden(received) >> (8 * index)) & 255} actual=${(value >> (8 * index)) & 255}")
            }
            if (continuous && received > 0 && received % pixels > 0) {
              val gap = if (received % width == 0) k else 1
              if (!(cycles - lastOutputCycle == gap)) fail(s"连续流间隔 expected=$gap actual=${cycles - lastOutputCycle}")
            }
            if (received == 0) firstOutputCycle = cycles
            lastOutputCycle = cycles
            received += 1
          }
          if (cycles > deadline) fail(s"看门狗超时 sent=$sent received=$received")
        }
        cycles += 1
      }
      fork {
        sleep(120000000L)
        fail("独立看门狗超时")
      }

      def configure(w: Int, h: Int, g: Int): Unit = {
        val before = configCount
        dut.clockDomain.waitFallingEdge()
        sleep(1)
        dut.io.cfg_i.width #= w
        dut.io.cfg_i.height #= h
        dut.io.cfg_i.groups #= g
        dut.io.cfg_i.valid #= true
        dut.clockDomain.waitSampling()
        dut.clockDomain.waitFallingEdge()
        sleep(1)
        if (!(configCount == before + 1)) fail("配置未被接收")
        dut.io.cfg_i.valid #= false
      }

      dut.clockDomain.waitSampling(10)
      // 不合法尺寸/组数必须拒绝，不能启动输入或输出。
      for ((w, h, g) <- Seq((0, 1, 1), (513, 1, 1), (1, 0, 1), (1, 513, 1), (1, 1, 0), (1, 1, 33))) {
        dut.clockDomain.waitFallingEdge()
        dut.io.cfg_i.width #= w
        dut.io.cfg_i.height #= h
        dut.io.cfg_i.groups #= g
        dut.io.cfg_i.valid #= true
        dut.clockDomain.waitSampling(2)
        if (dut.io.cfg_i.ready.toBoolean || dut.io.busy_o.toBoolean || dut.io.input_i.ready.toBoolean || dut.io.output_o.valid.toBoolean)
          fail(s"非法配置被接受 ($w,$h,$g)")
      }
      dut.clockDomain.waitFallingEdge()
      dut.io.cfg_i.valid #= false

      for (entry <- cases if entry(3).toInt == k) {
        val Array(caseName, widthText, heightText, _, groupsText, seedText, mode) = entry
        name = caseName
        width = widthText.toInt
        height = heightText.toInt
        groups = groupsText.toInt
        val random = new Random(seedText.toLong)
        val directory = new File(root, name)
        stimulus = loadHex(new File(directory, "stimulus.hex"))
        golden = loadHex(new File(directory, "golden.hex"))
        require(stimulus.size == width * height * groups && golden.size == stimulus.size)
        csv = new PrintWriter(new File(directory, "sim_trace.csv"))
        csv.println("cycle,reset,check,sent,received,cfg_valid,cfg_ready,busy,done,valid_i,ready_o,input,valid_o,ready_i,group,group_last,last,window")
        checking = false
        heldInput = None
        heldOutput = None
        dut.io.input_i.valid #= false
        dut.io.output_o.ready #= false
        try {
          if (mode.startsWith("reset_")) {
            configure(31, 17, 1)
            var warmSent = 0
            val warmCount = 31 * (k / 2 + 1) + k / 2 + 3
            while (warmSent < warmCount) {
              dut.clockDomain.waitFallingEdge()
              sleep(1)
              dut.io.input_i.valid #= true
              dut.io.input_i.payload #= stimulus(warmSent % stimulus.size)
              dut.io.output_o.ready #= true
              dut.clockDomain.waitSampling()
              if (dut.io.input_i.ready.toBoolean) warmSent += 1
            }
            dut.clockDomain.waitFallingEdge()
            dut.io.input_i.valid #= false
            if (mode == "reset_stalled") {
              dut.io.output_o.ready #= false
              dut.clockDomain.waitSampling(4)
              if (!dut.io.output_o.valid.toBoolean) fail("复位前未形成被反压的窗口")
            }
            dut.clockDomain.waitFallingEdge()
            dut.clockDomain.assertReset()
            dut.clockDomain.waitRisingEdge(5)
            dut.clockDomain.waitFallingEdge()
            dut.clockDomain.deassertReset()
            dut.clockDomain.waitSampling(2)
            if (dut.io.busy_o.toBoolean || dut.io.output_o.valid.toBoolean || dut.io.done_o.toBoolean)
              fail("复位未清除控制/旧窗口")
          }
          sent = 0
          received = 0
          doneCount = 0
          inputStalls = 0
          outputStalls = 0
          firstOutputCycle = -1
          lastOutputCycle = -1
          continuous = mode == "continuous"
          deadline = cycles + 16L * groups * (width + k - 1) * (height + k - 1) + 2000
          checking = true
          configure(width, height, groups)
          val taskConfigCount = configCount
          // 已锁存配置应独立于 valid=0 时的外部配置变化。
          dut.io.cfg_i.width #= 7
          dut.io.cfg_i.height #= 3
          dut.io.cfg_i.groups #= 1
          var pending = false
          var driveCycle = 0
          var finalStall = 0
          while (sent < stimulus.size || received < golden.size) {
            dut.clockDomain.waitFallingEdge()
            sleep(1)
            dut.io.output_o.ready #= (continuous || (driveCycle % 211 >= 35 && random.nextInt(5) > 0))
            // 收尾反压时尝试新配置，旧任务最后一个窗口未握手前必须拒绝。
            if (!continuous && received == golden.size - 1 && dut.io.output_o.valid.toBoolean && finalStall < 10) {
              dut.io.output_o.ready #= false
              dut.io.cfg_i.valid #= true
              finalStall += 1
            } else dut.io.cfg_i.valid #= false
            if (!pending && sent < stimulus.size && (continuous || random.nextInt(4) > 0)) pending = true
            dut.io.input_i.valid #= pending
            if (pending) dut.io.input_i.payload #= stimulus(sent)
            dut.clockDomain.waitSampling()
            if (pending && dut.io.input_i.ready.toBoolean) {
              sent += 1
              pending = false
            }
            driveCycle += 1
          }
          dut.clockDomain.waitFallingEdge()
          dut.io.cfg_i.valid #= false
          dut.io.input_i.valid #= false
          dut.io.output_o.ready #= true
          dut.clockDomain.waitSampling(5)
          if (!(received == golden.size && doneCount == 1) || dut.io.busy_o.toBoolean)
            fail(s"结束计数 received=$received done=$doneCount")
          if (!(configCount == taskConfigCount)) fail("收尾反压期间错误接收新配置")
          if (!continuous && !(finalStall == 10)) fail("末窗口反压覆盖不足")
          if (!continuous && !(inputStalls > 0 && outputStalls > 0)) fail("反压覆盖不足")
          val cells = received.toLong * k * k * 16
          totalWindows += received
          totalCells += cells
          completedCases += 1
          summary.println(s"$name,$received,$cells,$cycles,$inputStalls,$outputStalls,$firstOutputCycle,$lastOutputCycle,PASS")
          summary.flush()
          println(s"[TB PASSED] $name 全部数据验证一致 windows=$received int8Cells=$cells cycles=$cycles inputStalls=$inputStalls outputStalls=$outputStalls")
        } finally {
          checking = false
          csv.close()
          csv = null
        }
      }
      simSuccess()
    }
  } finally summary.close()
  require(completedCases == 26, "测试用例未全部完成")
  println(s"[TB PASSED] ALL cases=$completedCases windows=$totalWindows int8Cells=$totalCells")
}
