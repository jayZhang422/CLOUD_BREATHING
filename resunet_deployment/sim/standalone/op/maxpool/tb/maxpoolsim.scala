// 文件类型：.scala。SpinalSim/Verilator，独立 Golden、FST 和逐周期 CSV。
import spinal.core._
import spinal.core.sim._
import java.io.{File, PrintWriter}
import scala.io.Source
import scala.util.Random

object MaxPoolSim extends App {
  val root = new File(args.headOption.getOrElse("verification/deployment"))
  val manifest = Source.fromFile(new File(root, "cases.csv"))
  val cases = try manifest.getLines().drop(1).map(_.split(",")).toVector finally manifest.close()
  var totalInputs = 0L
  var totalOutputs = 0L
  var completedCases = 0
  val summary = new PrintWriter(new File(root, "results.csv"))
  summary.println("case,inputs,outputs,int8_values,cycles,input_stalls,output_stalls,status")
  def loadHex(file: File): Vector[BigInt] = {
    val source = Source.fromFile(file)
    try source.getLines().map(s => BigInt(s.trim, 16)).toVector finally source.close()
  }

  val compiled = SimConfig
    .withConfig(SpinalConfig(defaultConfigForClockDomains = ClockDomainConfig(resetKind = ASYNC, resetActiveLevel = LOW)))
    .workspacePath(new File(root, "compiled").getPath)
    .withFstWave
    .compile(new MaxPool2d(MaxPoolConfig()))
  try compiled.doSim("deployment", 20261011) { dut =>
    var cycle = 0L
    var checking = false
    var csv: PrintWriter = null
    var stimulus = Vector.empty[BigInt]
    var golden = Vector.empty[BigInt]
    var name = "initial"
    var width = 2
    var height = 2
    var sent = 0
    var received = 0
    var configCount = 0
    var doneCount = 0
    var inputStalls = 0L
    var outputStalls = 0L
    var deadline = 0L
    var heldInput: Option[BigInt] = None
    var heldOutput: Option[(BigInt, Int, Boolean, Boolean)] = None
    var continuous = false
    var inputIndexAtEdge = 0
    var lastOutputInput = -1
    var firstOutputCycle = -1L
    var lastOutputCycle = -1L

    def fail(message: String): Nothing = {
      if (csv != null) csv.flush()
      simFailure(s"$name cycle=$cycle time=${simTime()} $message")
    }
    dut.io.cfg_i.valid #= false
    dut.io.cfg_i.width #= 2
    dut.io.cfg_i.height #= 2
    dut.io.cfg_i.groups #= 1
    dut.io.input_i.valid #= false
    dut.io.input_i.payload #= 0
    dut.io.output_o.ready #= false
    dut.clockDomain.forkStimulus(period = 10)
    dut.clockDomain.onSamplings {
      val reset = dut.clockDomain.isResetAsserted
      val inValid = dut.io.input_i.valid.toBoolean
      val inReady = dut.io.input_i.ready.toBoolean
      val input = dut.io.input_i.payload.toBigInt
      val valid = dut.io.output_o.valid.toBoolean
      val ready = dut.io.output_o.ready.toBoolean
      val data = dut.io.output_o.fragment.data.toBigInt
      val group = dut.io.output_o.fragment.group.toInt
      val groupLast = dut.io.output_o.fragment.group_last.toBoolean
      val last = dut.io.output_o.last.toBoolean
      if (csv != null) csv.println(s"$cycle,$reset,$checking,$sent,$received," +
        s"${dut.io.cfg_i.valid.toBoolean},${dut.io.cfg_i.ready.toBoolean},${dut.io.busy_o.toBoolean}," +
        s"${dut.io.done_o.toBoolean},$inValid,$inReady,${input.toString(16)},$valid,$ready,$group,$groupLast,$last,${data.toString(16)}")
      if (!reset && dut.io.cfg_i.valid.toBoolean && dut.io.cfg_i.ready.toBoolean) configCount += 1
      if (checking && !reset) {
        if (dut.io.done_o.toBoolean) {
          doneCount += 1
          if (!(sent == stimulus.size && received == golden.size)) fail("输入或输出未完成时提前 done")
        }
        if (dut.io.busy_o.toBoolean && dut.io.cfg_i.ready.toBoolean) fail("busy 期间接收新配置")
        heldInput.foreach(previous => if (!inValid || !(input == previous)) fail("输入反压时 valid/data 改变"))
        heldInput = if (inValid && !inReady) Some(input) else None
        val snapshot = (data, group, groupLast, last)
        heldOutput.foreach(previous => if (!valid || !(snapshot == previous)) fail("输出反压时数据/组号/边界改变"))
        heldOutput = if (valid && !ready) Some(snapshot) else None
        if (inValid && !inReady) inputStalls += 1
        if (valid && !ready) outputStalls += 1
        if (valid && ready) {
          if (received >= golden.size) fail("额外输出")
          val pixels = width / 2 * (height / 2)
          val expectedGroup = received / pixels
          val expectedGroupLast = received % pixels == pixels - 1
          val expectedLast = received == golden.size - 1
          if (!(group == expectedGroup && groupLast == expectedGroupLast && last == expectedLast))
            fail(s"边界 expected=($expectedGroup,$expectedGroupLast,$expectedLast) actual=($group,$groupLast,$last)")
          if (!(data == golden(received))) {
            val lane = (0 until 16).find(i => !(((data >> (8 * i)) & 255) == ((golden(received) >> (8 * i)) & 255))).get
            fail(s"output=$received group=$group lane=$lane expected=${(golden(received) >> (8 * lane)) & 255} actual=${(data >> (8 * lane)) & 255}")
          }
          if (continuous && received > 0 && received % pixels > 0) {
            val expectedGap = if (received % (width / 2) == 0) width + 2 else 2
            if (!(cycle - lastOutputCycle == expectedGap)) fail(s"连续流间隔 expected=$expectedGap actual=${cycle - lastOutputCycle}")
          }
          if (received == 0) firstOutputCycle = cycle
          lastOutputCycle = cycle
          lastOutputInput = inputIndexAtEdge
          received += 1
        }
        if (cycle > deadline) fail(s"看门狗超时 sent=$sent received=$received")
      }
      cycle += 1
    }
    fork { sleep(160000000L); fail("独立看门狗超时") }

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
    for ((w, h, g) <- Seq((0, 2, 1), (1, 2, 1), (513, 2, 1), (2, 0, 1), (2, 1, 1), (2, 513, 1), (2, 2, 0), (2, 2, 33))) {
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

    for (entry <- cases) {
      val Array(caseName, widthText, heightText, groupsText, seedText, mode) = entry
      name = caseName
      width = widthText.toInt
      height = heightText.toInt
      val groups = groupsText.toInt
      val random = new Random(seedText.toLong)
      val directory = new File(root, name)
      stimulus = loadHex(new File(directory, "stimulus.hex"))
      golden = loadHex(new File(directory, "golden.hex"))
      require(stimulus.size == width * height * groups && golden.size == width / 2 * (height / 2) * groups)
      csv = new PrintWriter(new File(directory, "sim_trace.csv"))
      csv.println("cycle,reset,check,sent,received,cfg_valid,cfg_ready,busy,done,valid_i,ready_o,input,valid_o,ready_i,group,group_last,last,data")
      checking = false
      heldInput = None
      heldOutput = None
      dut.io.input_i.valid #= false
      dut.io.output_o.ready #= false
      try {
        if (mode.startsWith("reset_")) {
          configure(32, 16, 1)
          var warmSent = 0
          val count = if (mode == "reset_stalled") 36 else 75
          while (warmSent < count) {
            dut.clockDomain.waitFallingEdge()
            sleep(1)
            dut.io.input_i.valid #= true
            dut.io.input_i.payload #= stimulus(warmSent % stimulus.size)
            dut.io.output_o.ready #= (mode != "reset_stalled")
            dut.clockDomain.waitSampling()
            if (dut.io.input_i.ready.toBoolean) warmSent += 1
          }
          dut.clockDomain.waitFallingEdge()
          dut.io.input_i.valid #= false
          dut.clockDomain.waitSampling(4)
          if (mode == "reset_stalled" && !dut.io.output_o.valid.toBoolean) fail("复位前未形成被反压输出")
          dut.clockDomain.waitFallingEdge()
          dut.clockDomain.assertReset()
          dut.clockDomain.waitRisingEdge(5)
          dut.clockDomain.waitFallingEdge()
          dut.clockDomain.deassertReset()
          dut.clockDomain.waitSampling(2)
          if (dut.io.busy_o.toBoolean || dut.io.output_o.valid.toBoolean || dut.io.done_o.toBoolean) fail("复位未丢弃旧任务")
        }
        sent = 0
        received = 0
        inputIndexAtEdge = 0
        doneCount = 0
        inputStalls = 0
        outputStalls = 0
        firstOutputCycle = -1
        lastOutputCycle = -1
        lastOutputInput = -1
        continuous = mode == "continuous"
        deadline = cycle + 20L * stimulus.size + 2000
        checking = true
        configure(width, height, groups)
        val taskConfigCount = configCount
        dut.io.cfg_i.width #= 7
        dut.io.cfg_i.height #= 3
        dut.io.cfg_i.groups #= 1
        var pending = false
        var driveCycle = 0
        var finalStall = 0
        var tailWait = 0
        while (sent < stimulus.size || received < golden.size) {
          dut.clockDomain.waitFallingEdge()
          sleep(1)
          dut.io.output_o.ready #= (continuous || (driveCycle % 211 >= 35 && random.nextInt(5) > 0))
          val holdLast = !continuous && mode != "tail_stall" && received == golden.size - 1 &&
            dut.io.output_o.valid.toBoolean && finalStall < 10
          if (holdLast) {
            dut.io.output_o.ready #= false
            dut.io.cfg_i.valid #= true
            finalStall += 1
          } else dut.io.cfg_i.valid #= false
          // 奇数最后一行暂停输入，让最后输出先完成；busy/done 仍须等待尾部。
          val holdTail = mode == "tail_stall" && sent == width * (height - 1) && tailWait < 20
          if (holdTail) {
            tailWait += 1
            dut.io.output_o.ready #= true
            if (dut.io.done_o.toBoolean || !dut.io.busy_o.toBoolean) fail("丢弃尾行未输入完就结束任务")
          }
          if (!pending && sent < stimulus.size && !holdTail && (continuous || random.nextInt(4) > 0)) pending = true
          dut.io.input_i.valid #= pending
          if (pending) dut.io.input_i.payload #= stimulus(sent)
          inputIndexAtEdge = sent
          dut.clockDomain.waitSampling()
          if (pending && dut.io.input_i.ready.toBoolean) { sent += 1; pending = false }
          driveCycle += 1
        }
        dut.clockDomain.waitFallingEdge()
        dut.io.cfg_i.valid #= false
        dut.io.input_i.valid #= false
        dut.io.output_o.ready #= true
        dut.clockDomain.waitSampling(6)
        if (!(received == golden.size && doneCount == 1 && configCount == taskConfigCount) || dut.io.busy_o.toBoolean)
          fail(s"结束计数 received=$received done=$doneCount")
        if (!continuous && mode != "tail_stall" && !(inputStalls > 0 && outputStalls > 0 && finalStall == 10)) fail("反压覆盖不足")
        if (mode == "tail_stall" && !(tailWait == 20 && lastOutputInput < stimulus.size)) fail("奇数尾行覆盖不足")
        totalInputs += sent
        totalOutputs += received
        completedCases += 1
        summary.println(s"$name,$sent,$received,${received.toLong * 16},$cycle,$inputStalls,$outputStalls,PASS")
        summary.flush()
        println(s"[TB PASSED] $name 全部数据验证一致 inputs=$sent outputs=$received cycles=$cycle inputStalls=$inputStalls outputStalls=$outputStalls firstOutputCycle=$firstOutputCycle lastOutputCycle=$lastOutputCycle")
      } finally {
        checking = false
        csv.close()
        csv = null
      }
    }
    simSuccess()
  } finally summary.close()
  require(completedCases == 16, "用例未全部完成")
  // 总 PASS 不在 finally 中，任何失败均不能误报成功。
  println(s"[TB PASSED] ALL cases=$completedCases inputs=$totalInputs outputs=$totalOutputs int8Values=${totalOutputs * 16}")
}
