// 文件类型：.scala。SpinalSim/Verilator，自校验仅读取离线 Golden，不实现算术参考模型。
import spinal.core._
import spinal.core.sim._
import java.io.{File, PrintWriter}
import scala.collection.mutable
import scala.io.Source
import scala.util.Random

object ElementAddSim extends App {
  val root = new File(args.headOption.getOrElse("verification/deployment"))
  def lines(file: File): Vector[String] = {
    val source = Source.fromFile(file)
    try source.getLines().toVector finally source.close()
  }
  def hex(file: File): Vector[BigInt] = lines(file).map(s => BigInt(s.trim, 16))
  def signed(value: BigInt, bits: Int): BigInt = if (value.testBit(bits - 1)) value - (BigInt(1) << bits) else value
  val cases = lines(new File(root, "cases.csv")).drop(1).map(_.split(","))
  val summary = new PrintWriter(new File(root, "results.csv"))
  summary.println("case,groups,words,int8_values,input_a_stalls,input_b_stalls,output_stalls,status")
  var completed = 0
  var totalWords = 0L
  var frozenCases = 0
  val c = ElementAddConfig()
  val compiled = SimConfig
    .withConfig(SpinalConfig(defaultConfigForClockDomains = ClockDomainConfig(resetKind = ASYNC, resetActiveLevel = LOW)))
    .workspacePath(new File(root, "compiled").getPath)
    .withFstWave
    .compile(new ElementAdd(c))

  try compiled.doSim("deployment", 20261011) { dut =>
    var name = "initial"
    var cycle = 0L
    var csv: PrintWriter = null
    var checking = false
    var continuous = false
    var sentA = 0
    var sentB = 0
    var received = 0
    var words = 0
    var tag = 0
    var lastGroup = false
    var offset = 0
    var doneCount = 0
    var configCount = 0
    var deadline = 0L
    var golden = Vector.empty[BigInt]
    var heldA: Option[BigInt] = None
    var heldB: Option[BigInt] = None
    var heldOutput: Option[(BigInt, Int, Boolean, Boolean)] = None
    val acceptedCycles = mutable.Queue.empty[Long]
    var inputAStalls = 0L
    var inputBStalls = 0L
    var outputStalls = 0L
    var previousOutputCycle = -1L
    def fail(message: String): Nothing = {
      if (csv != null) csv.flush()
      simFailure(s"$name cycle=$cycle time=${simTime()} group=$tag output=$received $message")
    }

    dut.io.cfg_i.valid #= false
    dut.io.cfg_i.words #= 0
    dut.io.cfg_i.group #= 0
    dut.io.cfg_i.last_group #= false
    dut.io.cfg_i.shift #= 0
    dut.io.cfg_i.clamp_min #= -128
    dut.io.cfg_i.clamp_max #= 127
    for (i <- 0 until c.P) {
      dut.io.cfg_i.multiplier_a(i) #= 0
      dut.io.cfg_i.multiplier_b(i) #= 0
      dut.io.cfg_i.bias_fixed(i) #= 0
    }
    dut.io.a_i.valid #= false
    dut.io.b_i.valid #= false
    dut.io.a_i.payload #= 0
    dut.io.b_i.payload #= 0
    dut.io.output_o.ready #= false
    dut.clockDomain.forkStimulus(period = 10)
    dut.clockDomain.onSamplings {
      val reset = dut.clockDomain.isResetAsserted
      val av = dut.io.a_i.valid.toBoolean
      val ar = dut.io.a_i.ready.toBoolean
      val bv = dut.io.b_i.valid.toBoolean
      val br = dut.io.b_i.ready.toBoolean
      val a = dut.io.a_i.payload.toBigInt
      val b = dut.io.b_i.payload.toBigInt
      val ov = dut.io.output_o.valid.toBoolean
      val or = dut.io.output_o.ready.toBoolean
      val data = dut.io.output_o.fragment.data.toBigInt
      val group = dut.io.output_o.fragment.group.toInt
      val groupLast = dut.io.output_o.fragment.group_last.toBoolean
      val last = dut.io.output_o.last.toBoolean
      if (csv != null) csv.println(s"$cycle,$reset,$checking,$sentA,$sentB,$received," +
        s"${dut.io.cfg_i.valid.toBoolean},${dut.io.cfg_i.ready.toBoolean},${dut.io.busy_o.toBoolean},${dut.io.done_o.toBoolean}," +
        s"$av,$ar,${a.toString(16)},$bv,$br,${b.toString(16)},$ov,$or,$group,$groupLast,$last,${data.toString(16)}")
      if (!reset && dut.io.cfg_i.valid.toBoolean && dut.io.cfg_i.ready.toBoolean) configCount += 1
      if (checking && !reset) {
        if (dut.io.busy_o.toBoolean && dut.io.cfg_i.ready.toBoolean) fail("busy 期间配置可被接收")
        heldA.foreach(previous => if (!av || !(a == previous)) fail("A 输入反压时 valid/data 改变"))
        heldB.foreach(previous => if (!bv || !(b == previous)) fail("B 输入反压时 valid/data 改变"))
        heldA = if (av && !ar) Some(a) else None
        heldB = if (bv && !br) Some(b) else None
        val snapshot = (data, group, groupLast, last)
        heldOutput.foreach(previous => if (!ov || !(snapshot == previous)) fail("输出反压时 valid/data/边界改变"))
        heldOutput = if (ov && !or) Some(snapshot) else None
        if (!((av && ar) == (bv && br))) fail("两路未同时配对消费")
        if (av && !ar) inputAStalls += 1
        if (bv && !br) inputBStalls += 1
        if (ov && !or) outputStalls += 1
        if (av && ar) {
          if (sentA >= words) fail("超量接收输入")
          sentA += 1
          sentB += 1
          acceptedCycles.enqueue(cycle)
        }
        if (ov && or) {
          if (received >= words || acceptedCycles.isEmpty) fail("额外/无输入的输出")
          val expected = golden(offset + received)
          if (!(data == expected)) {
            val lane = (0 until c.P).find(i => !(((data >> (8 * i)) & 255) == ((expected >> (8 * i)) & 255))).get
            fail(s"lane=$lane expected=0x${expected.toString(16)} actual=0x${data.toString(16)}")
          }
          val end = received == words - 1
          if (!(group == tag && groupLast == end && last == (end && lastGroup)))
            fail(s"边界 expected=($tag,$end,${end && lastGroup}) actual=($group,$groupLast,$last)")
          val acceptedAt = acceptedCycles.dequeue()
          if (continuous) {
            if (!(cycle - acceptedAt == 7)) fail(s"流水延迟 expected=7 actual=${cycle - acceptedAt}")
            if (previousOutputCycle >= 0 && !(cycle - previousOutputCycle == 1)) fail("连续流吞吐非一字/拍")
          }
          previousOutputCycle = cycle
          received += 1
        }
        if (dut.io.done_o.toBoolean) {
          doneCount += 1
          if (!(received == words && sentA == words && sentB == words)) fail("提前 done")
        }
        if (cycle > deadline) fail("看门狗超时")
      }
      cycle += 1
    }
    fork { sleep(40000000L); fail("独立看门狗超时") }

    def configure(entry: Array[String]): Unit = {
      val Array(w, g, last, shift, lower, upper, ma, mb, bias) = entry
      dut.clockDomain.waitFallingEdge()
      sleep(1)
      dut.io.cfg_i.words #= w.toInt
      dut.io.cfg_i.group #= g.toInt
      dut.io.cfg_i.last_group #= (last == "1")
      dut.io.cfg_i.shift #= shift.toInt
      dut.io.cfg_i.clamp_min #= lower.toInt
      dut.io.cfg_i.clamp_max #= upper.toInt
      val a = BigInt(ma, 16)
      val b = BigInt(mb, 16)
      val z = BigInt(bias, 16)
      for (i <- 0 until c.P) {
        dut.io.cfg_i.multiplier_a(i) #= signed((a >> (c.MULT_BITS * i)) & ((BigInt(1) << c.MULT_BITS) - 1), c.MULT_BITS)
        dut.io.cfg_i.multiplier_b(i) #= signed((b >> (c.MULT_BITS * i)) & ((BigInt(1) << c.MULT_BITS) - 1), c.MULT_BITS)
        dut.io.cfg_i.bias_fixed(i) #= signed((z >> (64 * i)) & ((BigInt(1) << 64) - 1), 64)
      }
      dut.io.cfg_i.valid #= true
      val before = configCount
      dut.clockDomain.waitSampling()
      dut.clockDomain.waitFallingEdge()
      sleep(1)
      if (!(configCount == before + 1)) fail("配置未接收")
      dut.io.cfg_i.valid #= false
      // 改动外部配置，验证流水始终使用已锁存值。
      dut.io.cfg_i.shift #= 63
      dut.io.cfg_i.words #= 1
      dut.io.cfg_i.group #= 31
      for (i <- 0 until c.P) {
        dut.io.cfg_i.multiplier_a(i) #= 0
        dut.io.cfg_i.multiplier_b(i) #= 0
        dut.io.cfg_i.bias_fixed(i) #= 0
      }
    }
    dut.clockDomain.waitSampling(10)
    // 空闲状态的非法配置拒绝；不会误消费任一路输入。
    for ((w, g, lo, hi) <- Seq((0, 0, -128, 127), (262145, 0, -128, 127), (1, 32, -128, 127), (1, 0, 10, -10))) {
      dut.clockDomain.waitFallingEdge()
      dut.io.cfg_i.valid #= true
      dut.io.cfg_i.words #= w
      dut.io.cfg_i.group #= g
      dut.io.cfg_i.clamp_min #= lo
      dut.io.cfg_i.clamp_max #= hi
      dut.clockDomain.waitSampling(2)
      if (dut.io.cfg_i.ready.toBoolean || dut.io.busy_o.toBoolean || dut.io.a_i.ready.toBoolean || dut.io.b_i.ready.toBoolean)
        fail("非法配置被接受")
    }
    dut.clockDomain.waitFallingEdge()
    dut.io.cfg_i.valid #= false

    for (entry <- cases) {
      val Array(caseName, groupsText, totalText, mode) = entry
      name = caseName
      val directory = new File(root, name)
      val stimulus = hex(new File(directory, "stimulus.hex"))
      golden = hex(new File(directory, "golden.hex"))
      val configs = lines(new File(directory, "config.csv")).drop(1).map(_.split(","))
      require(stimulus.size == totalText.toInt && golden.size == stimulus.size && configs.size == groupsText.toInt)
      csv = new PrintWriter(new File(directory, "sim_trace.csv"))
      csv.println("cycle,reset,check,sent_a,sent_b,received,cfg_valid,cfg_ready,busy,done,a_valid,a_ready,a,b_valid,b_ready,b,out_valid,out_ready,group,group_last,last,data")
      checking = false
      inputAStalls = 0
      inputBStalls = 0
      outputStalls = 0
      try {
        if (mode.startsWith("reset_")) {
          val warm = configs.head.clone()
          warm(0) = "128"
          configure(warm)
          var warmSent = 0
          val warmWords = if (mode == "reset_stalled") 6 else 12
          while (warmSent < warmWords) {
            dut.clockDomain.waitFallingEdge()
            sleep(1)
            dut.io.a_i.valid #= true
            dut.io.b_i.valid #= true
            dut.io.a_i.payload #= (stimulus(warmSent) & ((BigInt(1) << 512) - 1))
            dut.io.b_i.payload #= (stimulus(warmSent) >> 512)
            dut.io.output_o.ready #= (mode != "reset_stalled")
            dut.clockDomain.waitSampling()
            if (dut.io.a_i.ready.toBoolean && dut.io.b_i.ready.toBoolean) warmSent += 1
          }
          dut.clockDomain.waitFallingEdge()
          dut.io.a_i.valid #= false
          dut.io.b_i.valid #= false
          dut.clockDomain.waitSampling(8)
          if (mode == "reset_stalled" && !dut.io.output_o.valid.toBoolean) fail("未形成反压输出就复位")
          dut.clockDomain.waitFallingEdge()
          dut.clockDomain.assertReset()
          dut.clockDomain.waitRisingEdge(4)
          dut.clockDomain.waitFallingEdge()
          dut.clockDomain.deassertReset()
          dut.clockDomain.waitSampling(2)
          if (dut.io.busy_o.toBoolean || dut.io.output_o.valid.toBoolean || dut.io.done_o.toBoolean) fail("复位未清除任务/有效位")
        }
        offset = 0
        for (config <- configs) {
          words = config(0).toInt
          tag = config(1).toInt
          lastGroup = config(2) == "1"
          sentA = 0
          sentB = 0
          received = 0
          doneCount = 0
          previousOutputCycle = -1
          heldA = None
          heldB = None
          heldOutput = None
          acceptedCycles.clear()
          continuous = mode == "continuous"
          deadline = cycle + 20L * words + 2000
          checking = true
          configure(config)
          val expectedConfigCount = configCount
          val random = new Random(20261011L + completed * 100 + tag)
          var pendingA = false
          var pendingB = false
          var driveCycle = 0
          var finalStall = 0
          while (sentA < words || sentB < words || received < words) {
            dut.clockDomain.waitFallingEdge()
            sleep(1)
            if (!pendingA && sentA < words && (continuous || random.nextInt(4) > 0)) pendingA = true
            if (!pendingB && sentB < words && (continuous || random.nextInt(5) > 0)) pendingB = true
            dut.io.a_i.valid #= pendingA
            dut.io.b_i.valid #= pendingB
            if (pendingA) dut.io.a_i.payload #= (stimulus(offset + sentA) & ((BigInt(1) << 512) - 1))
            if (pendingB) dut.io.b_i.payload #= (stimulus(offset + sentB) >> 512)
            dut.io.output_o.ready #= (continuous || (driveCycle % 211 >= 35 && random.nextInt(5) > 0))
            if (!continuous && received == words - 1 && dut.io.output_o.valid.toBoolean && finalStall < 10) {
              dut.io.output_o.ready #= false
              finalStall += 1
              if (!dut.io.busy_o.toBoolean || dut.io.cfg_i.ready.toBoolean) fail("末输出排空前允许新配置")
            }
            dut.clockDomain.waitSampling()
            if (pendingA && dut.io.a_i.ready.toBoolean) pendingA = false
            if (pendingB && dut.io.b_i.ready.toBoolean) pendingB = false
            driveCycle += 1
          }
          dut.clockDomain.waitFallingEdge()
          dut.io.a_i.valid #= false
          dut.io.b_i.valid #= false
          dut.io.output_o.ready #= true
          dut.clockDomain.waitSampling(4)
          if (!(doneCount == 1 && configCount == expectedConfigCount) || dut.io.busy_o.toBoolean || acceptedCycles.nonEmpty)
            fail("任务结束计数或配置隔离错误")
          if (!continuous && !(finalStall == 10)) fail("末输出反压覆盖不足")
          offset += words
          checking = false
        }
        if (!(offset == stimulus.size)) fail("输入/输出总数错误")
        if (!continuous && !(inputAStalls > 0 && inputBStalls > 0 && outputStalls > 0)) fail("独立输入与反压覆盖不足")
        completed += 1
        if (name.startsWith("lobe_") || name.startsWith("vessel_") || name.startsWith("airway_")) frozenCases += 1
        totalWords += offset
        summary.println(s"$name,${configs.size},$offset,${offset.toLong * c.P},$inputAStalls,$inputBStalls,$outputStalls,PASS")
        summary.flush()
        println(s"[TB PASSED] $name 全部数据验证一致 groups=${configs.size} words=$offset")
      } finally {
        checking = false
        csv.close()
        csv = null
      }
    }
    simSuccess()
  } finally summary.close()
  require(completed == cases.size && frozenCases == 42 && cases.size == 115, "用例未全部完成")
  println(s"[TB PASSED] ALL cases=$completed frozenNodes=$frozenCases words=$totalWords int8Values=${totalWords * c.P}")
}
