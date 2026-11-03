import spinal.core._
import spinal.core.sim._
import java.io.{File, PrintWriter}
import scala.collection.mutable.ArrayBuffer
import scala.io.Source

class DwJoinTop extends Component {
  val dw3 = new Dw3x3(Dw3x3Config())
  val dw5 = new Dw5x5(Dw5x5Config())
  val merge = new ElementAdd(ElementAddConfig())

  // The wrapper is simulation-only and has no user-facing IO; keep all driven/observed streams visible.
  dw3.io.cfg_i.simPublic()
  dw3.io.weights_i.simPublic()
  dw3.io.params_i.simPublic()
  dw3.io.input_i.simPublic()
  dw3.io.output_o.simPublic()
  dw3.io.busy_o.simPublic()
  dw3.io.done_o.simPublic()
  dw5.io.cfg_i.simPublic()
  dw5.io.weights_i.simPublic()
  dw5.io.params_i.simPublic()
  dw5.io.input_i.simPublic()
  dw5.io.output_o.simPublic()
  dw5.io.busy_o.simPublic()
  dw5.io.done_o.simPublic()
  merge.io.cfg_i.simPublic()
  merge.io.a_i.simPublic()
  merge.io.b_i.simPublic()
  merge.io.output_o.simPublic()
  merge.io.busy_o.simPublic()
  merge.io.done_o.simPublic()
}

object DwJoinSim extends App {
  val root = new File("verification")
  val vectors = new File(root, "vectors")
  val dw3Vectors = new File("../DW3x3/verification/vectors")
  val dw5Vectors = new File("../DW5x5/verification/vectors")
  root.mkdirs()
  vectors.mkdirs()

  def loadHex(file: File): Vector[BigInt] = {
    val source = Source.fromFile(file)
    try source.getLines().filter(_.nonEmpty).map(s => BigInt(s.trim, 16)).toVector
    finally source.close()
  }
  def signed(value: BigInt, width: Int): BigInt = {
    val masked = value & ((BigInt(1) << width) - 1)
    if (masked.testBit(width - 1)) masked - (BigInt(1) << width) else masked
  }
  val stimulus3 = loadHex(new File(dw3Vectors, "stimulus.hex"))
  val stimulus5 = loadHex(new File(dw5Vectors, "stimulus.hex"))
  val golden3 = loadHex(new File(dw3Vectors, "golden_mac.hex"))
  val golden5 = loadHex(new File(dw5Vectors, "golden_mac.hex"))
  val weights3 = loadHex(new File(dw3Vectors, "weights.hex"))
  val weights5 = loadHex(new File(dw5Vectors, "weights.hex"))
  val params3 = loadHex(new File(dw3Vectors, "params.hex"))
  val params5 = loadHex(new File(dw5Vectors, "params.hex"))
  val mergeGolden = loadHex(new File(vectors, "merge_golden.hex"))
  val mergeParamsA = loadHex(new File(vectors, "merge_params_a.hex"))
  val mergeParamsB = loadHex(new File(vectors, "merge_params_b.hex"))
  val mergeBias = loadHex(new File(vectors, "merge_bias.hex"))
  val groups = 8
  val height = 4
  val width = 4
  val wordsPerGroup = height * width
  val total = groups * wordsPerGroup
  require(stimulus3 == stimulus5, "DW3 and DW5 are not using the same expand stimulus")
  require(golden3.size == total && golden5.size == total && mergeGolden.size == total)
  require(weights3.size == groups && weights5.size == groups && params3.size == groups && params5.size == groups)

  val log = new PrintWriter(new File(root, "run.log"))
  val csv = new PrintWriter(new File(root, "sim_trace.csv"))
  val result = new PrintWriter(new File(root, "result.json"))
  csv.println("cycle,dw3_in_valid,dw3_in_ready,dw5_in_valid,dw5_in_ready,dw3_out_valid,dw3_out_ready,dw5_out_valid,dw5_out_ready,merge_out_valid,merge_out_ready,dw3_index,dw5_index,merge_index")

  var cycle = 0L
  var sent = 0
  var acceptedA = false
  var acceptedB = false
  var received3 = 0
  var received5 = 0
  var receivedMerge = 0
  var feed3 = 0
  var feed5 = 0
  var inputStalls = 0
  var outputStalls = 0
  var mergeStalls = 0
  var currentMergeGroup = 0
  var nextMergeConfig = 0
  val inputCycle3 = Array.fill[Long](total)(-1L)
  val inputCycle5 = Array.fill[Long](total)(-1L)
  val branchMac3 = Array.fill[BigInt](total)(BigInt(0))
  val branchMac5 = Array.fill[BigInt](total)(BigInt(0))
  val latency3 = ArrayBuffer[Int]()
  val latency5 = ArrayBuffer[Int]()
  var held3: Option[Vector[BigInt]] = None
  var held5: Option[Vector[BigInt]] = None
  var heldMerge: Option[Vector[BigInt]] = None

  def fail(message: String): Nothing = {
    log.println(s"FAIL cycle=$cycle sent=$sent dw3=$received3 dw5=$received5 merge=$receivedMerge $message")
    log.flush()
    simFailure(message)
  }

  def driveWindow(dut: DwJoinTop, index: Int): Unit = {
    val group = index / wordsPerGroup
    val pixel = index % wordsPerGroup
    val row = pixel / width
    val col = pixel % width
    for (r <- 0 until 3; c <- 0 until 3)
      dut.dw3.io.input_i.window(r)(c) #= sampleWord(stimulus3(group * wordsPerGroup + 0), group, row + r - 1, col + c - 1, 3)
    for (r <- 0 until 5; c <- 0 until 5)
      dut.dw5.io.input_i.window(r)(c) #= sampleWord(stimulus5(group * wordsPerGroup + 0), group, row + r - 2, col + c - 2, 5)
    dut.dw3.io.input_i.tag.group #= group
    dut.dw3.io.input_i.tag.row #= row
    dut.dw3.io.input_i.tag.col #= col
    dut.dw3.io.input_i.tag.group_last #= (pixel == wordsPerGroup - 1)
    dut.dw3.io.input_i.tag.last #= (index == total - 1)
    dut.dw5.io.input_i.tag.group #= group
    dut.dw5.io.input_i.tag.row #= row
    dut.dw5.io.input_i.tag.col #= col
    dut.dw5.io.input_i.tag.group_last #= (pixel == wordsPerGroup - 1)
    dut.dw5.io.input_i.tag.last #= (index == total - 1)
  }

  def sampleWord(words: BigInt, group: Int, row: Int, col: Int, k: Int): BigInt = {
    if (row < 0 || row >= height || col < 0 || col >= width) BigInt(0)
    else {
      val source = if (k == 3) stimulus3 else stimulus5
      source(group * wordsPerGroup + row * width + col)
    }
  }

  def branchSnapshot3(dut: DwJoinTop): Vector[BigInt] =
    Vector(dut.dw3.io.output_o.tag.group.toBigInt, dut.dw3.io.output_o.tag.row.toBigInt,
      dut.dw3.io.output_o.tag.col.toBigInt, dut.dw3.io.output_o.tag.last.toBoolean match {
        case true => BigInt(1)
        case false => BigInt(0)
      }) ++ (0 until 16).map(i => dut.dw3.io.output_o.mac(i).toBigInt)

  def branchSnapshot5(dut: DwJoinTop): Vector[BigInt] =
    Vector(dut.dw5.io.output_o.tag.group.toBigInt, dut.dw5.io.output_o.tag.row.toBigInt,
      dut.dw5.io.output_o.tag.col.toBigInt, dut.dw5.io.output_o.tag.last.toBoolean match {
        case true => BigInt(1)
        case false => BigInt(0)
      }) ++ (0 until 16).map(i => dut.dw5.io.output_o.mac(i).toBigInt)

  def mergeSnapshot(dut: DwJoinTop): Vector[BigInt] =
    Vector(dut.merge.io.output_o.fragment.group.toBigInt,
      if (dut.merge.io.output_o.fragment.group_last.toBoolean) BigInt(1) else BigInt(0),
      if (dut.merge.io.output_o.last.toBoolean) BigInt(1) else BigInt(0),
      dut.merge.io.output_o.fragment.data.toBigInt)

  def configureDw3(dut: DwJoinTop): Unit = {
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
  }

  def configureDw5(dut: DwJoinTop): Unit = {
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

  def configureMerge(dut: DwJoinTop, group: Int): Unit = {
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
    dut.clockDomain.waitSampling()
    if (!dut.merge.io.cfg_i.ready.toBoolean) fail(s"merge config $group not accepted")
    dut.clockDomain.waitFallingEdge()
    dut.merge.io.cfg_i.valid #= false
    currentMergeGroup = group
  }

  SimConfig.withFstWave.compile(new DwJoinTop).doSim { dut =>
    dut.clockDomain.forkStimulus(period = 10)
    dut.dw3.io.cfg_i.valid #= false
    dut.dw3.io.weights_i.valid #= false
    dut.dw3.io.params_i.valid #= false
    dut.dw3.io.input_i.valid #= false
    dut.dw3.io.output_o.ready #= false
    dut.dw5.io.cfg_i.valid #= false
    dut.dw5.io.weights_i.valid #= false
    dut.dw5.io.params_i.valid #= false
    dut.dw5.io.input_i.valid #= false
    dut.dw5.io.output_o.ready #= false
    dut.merge.io.cfg_i.valid #= false
    dut.merge.io.a_i.valid #= false
    dut.merge.io.b_i.valid #= false
    dut.merge.io.output_o.ready #= false
    dut.clockDomain.waitSampling(5)

    configureDw3(dut)
    configureDw5(dut)

    // Phase 1: one shared expand stream, with a proper two-consumer fork.
    var pending = true
    var pendingIndex = 0
    while (received3 < total || received5 < total) {
      dut.clockDomain.waitFallingEdge()
      if (pending) driveWindow(dut, pendingIndex)
      val valid3 = pending && !acceptedA
      val valid5 = pending && !acceptedB
      dut.dw3.io.input_i.valid #= valid3
      dut.dw5.io.input_i.valid #= valid5
      val ready3 = received3 < 8 || (cycle % 7 != 3) || received3 == total - 1
      val ready5 = received5 < 8 || (cycle % 11 != 5) || received5 == total - 1
      dut.dw3.io.output_o.ready #= ready3
      dut.dw5.io.output_o.ready #= ready5
      dut.merge.io.a_i.valid #= false
      dut.merge.io.b_i.valid #= false
      dut.merge.io.output_o.ready #= false
      dut.clockDomain.waitSampling()
      cycle += 1

      val fireIn3 = valid3 && dut.dw3.io.input_i.ready.toBoolean
      val fireIn5 = valid5 && dut.dw5.io.input_i.ready.toBoolean
      if (fireIn3) inputCycle3(pendingIndex) = cycle
      if (fireIn5) inputCycle5(pendingIndex) = cycle
      if (valid3 && !dut.dw3.io.input_i.ready.toBoolean) inputStalls += 1
      if (valid5 && !dut.dw5.io.input_i.ready.toBoolean) inputStalls += 1
      val nextA = acceptedA || fireIn3
      val nextB = acceptedB || fireIn5
      if (nextA && nextB) {
        sent += 1
        pendingIndex += 1
        pending = sent < total
        acceptedA = false
        acceptedB = false
      } else {
        acceptedA = nextA
        acceptedB = nextB
      }

      val fire3 = dut.dw3.io.output_o.valid.toBoolean && dut.dw3.io.output_o.ready.toBoolean
      val fire5 = dut.dw5.io.output_o.valid.toBoolean && dut.dw5.io.output_o.ready.toBoolean
      if (fire3) {
        val index = received3
        val expected = golden3(index)
        val group = dut.dw3.io.output_o.tag.group.toInt
        val pixel = index % wordsPerGroup
        if (group != index / wordsPerGroup || dut.dw3.io.output_o.tag.row.toInt != pixel / width || dut.dw3.io.output_o.tag.col.toInt != pixel % width)
          fail(s"DW3 tag mismatch index=$index")
        if (dut.dw3.io.output_o.tag.group_last.toBoolean != (pixel == wordsPerGroup - 1) || dut.dw3.io.output_o.tag.last.toBoolean != (index == total - 1)) fail("DW3 boundary mismatch")
        for (lane <- 0 until 16) if (signed(dut.dw3.io.output_o.mac(lane).toBigInt, 32) != signed(expected >> (32 * lane), 32)) fail(s"DW3 Golden mismatch index=$index lane=$lane")
        var packed = BigInt(0)
        for (lane <- 0 until 16) packed |= (dut.dw3.io.output_o.mac(lane).toBigInt & ((BigInt(1) << 32) - 1)) << (32 * lane)
        branchMac3(index) = packed
        if (inputCycle3(index) >= 0 && latency3.size < 8) latency3 += (cycle - inputCycle3(index)).toInt
        received3 += 1
      }
      if (fire5) {
        val index = received5
        val expected = golden5(index)
        val group = dut.dw5.io.output_o.tag.group.toInt
        val pixel = index % wordsPerGroup
        if (group != index / wordsPerGroup || dut.dw5.io.output_o.tag.row.toInt != pixel / width || dut.dw5.io.output_o.tag.col.toInt != pixel % width)
          fail(s"DW5 tag mismatch index=$index")
        if (dut.dw5.io.output_o.tag.group_last.toBoolean != (pixel == wordsPerGroup - 1) || dut.dw5.io.output_o.tag.last.toBoolean != (index == total - 1)) fail("DW5 boundary mismatch")
        for (lane <- 0 until 16) if (signed(dut.dw5.io.output_o.mac(lane).toBigInt, 32) != signed(expected >> (32 * lane), 32)) fail(s"DW5 Golden mismatch index=$index lane=$lane")
        var packed = BigInt(0)
        for (lane <- 0 until 16) packed |= (dut.dw5.io.output_o.mac(lane).toBigInt & ((BigInt(1) << 32) - 1)) << (32 * lane)
        branchMac5(index) = packed
        if (inputCycle5(index) >= 0 && latency5.size < 8) latency5 += (cycle - inputCycle5(index)).toInt
        received5 += 1
      }
      if (dut.dw3.io.output_o.valid.toBoolean && !ready3) {
        val snap = branchSnapshot3(dut)
        held3.foreach(previous => if (snap != previous) fail("DW3 output changed during backpressure"))
        held3 = Some(snap)
      } else held3 = None
      if (dut.dw5.io.output_o.valid.toBoolean && !ready5) {
        val snap = branchSnapshot5(dut)
        held5.foreach(previous => if (snap != previous) fail("DW5 output changed during backpressure"))
        held5 = Some(snap)
      } else held5 = None
      csv.println(s"$cycle,$valid3,${dut.dw3.io.input_i.ready.toBoolean},$valid5,${dut.dw5.io.input_i.ready.toBoolean},${dut.dw3.io.output_o.valid.toBoolean},$ready3,${dut.dw5.io.output_o.valid.toBoolean},$ready5,false,false,$received3,$received5,0")
      csv.flush()
      if (cycle > 100000) fail("DW joint phase watchdog timeout")
    }

    // Phase 2: merge the captured DW3/DW5 MAC words through the real wide-domain ElementAdd.
    configureMerge(dut, 0)
    var offerA = true
    var offerB = true
    var mergeIndexA = 0
    var mergeIndexB = 0
    while (receivedMerge < total || mergeIndexA < total || mergeIndexB < total) {
      dut.clockDomain.waitFallingEdge()
      dut.dw3.io.input_i.valid #= false
      dut.dw5.io.input_i.valid #= false
      dut.dw3.io.output_o.ready #= false
      dut.dw5.io.output_o.ready #= false
      val mergeReady = receivedMerge < wordsPerGroup || (cycle % 9 != 4) || receivedMerge == total - 1
      dut.merge.io.output_o.ready #= mergeReady
      dut.merge.io.a_i.valid #= offerA
      dut.merge.io.b_i.valid #= offerB
      if (offerA) dut.merge.io.a_i.payload #= branchMac3(mergeIndexA)
      if (offerB) dut.merge.io.b_i.payload #= branchMac5(mergeIndexB)
      dut.clockDomain.waitSampling()
      cycle += 1
      val fireA = offerA && dut.merge.io.a_i.ready.toBoolean
      val fireB = offerB && dut.merge.io.b_i.ready.toBoolean
      if (fireA) { mergeIndexA += 1; offerA = false }
      if (fireB) { mergeIndexB += 1; offerB = false }
      if (!offerA && mergeIndexA < total && cycle % 3 != 0) offerA = true
      if (!offerB && mergeIndexB < total && cycle % 4 != 1) offerB = true
      val fireMerge = dut.merge.io.output_o.valid.toBoolean && mergeReady
      if (dut.merge.io.output_o.valid.toBoolean && !mergeReady) {
        mergeStalls += 1
        val snap = mergeSnapshot(dut)
        heldMerge.foreach(previous => if (snap != previous) fail("merge output changed during backpressure"))
        heldMerge = Some(snap)
      } else heldMerge = None
      if (fireMerge) {
        val index = receivedMerge
        val expected = mergeGolden(index)
        val actual = dut.merge.io.output_o.fragment.data.toBigInt
        if (actual != expected) fail(s"merge Golden mismatch index=$index expected=0x${expected.toString(16)} actual=0x${actual.toString(16)}")
        val end = index % wordsPerGroup == wordsPerGroup - 1
        if (dut.merge.io.output_o.fragment.group.toInt != currentMergeGroup || dut.merge.io.output_o.fragment.group_last.toBoolean != end || dut.merge.io.output_o.last.toBoolean != (end && currentMergeGroup == groups - 1))
          fail(s"merge boundary mismatch index=$index")
        receivedMerge += 1
        if (end && currentMergeGroup < groups - 1) nextMergeConfig = currentMergeGroup + 1
      }
      csv.println(s"$cycle,false,false,false,false,false,false,false,false,${dut.merge.io.output_o.valid.toBoolean},$mergeReady,$received3,$received5,$receivedMerge")
      csv.flush()
      if (nextMergeConfig != 0) {
        val group = nextMergeConfig
        nextMergeConfig = 0
        dut.merge.io.a_i.valid #= false
        dut.merge.io.b_i.valid #= false
        dut.merge.io.output_o.ready #= false
        configureMerge(dut, group)
      }
      if (cycle > 100000) fail("merge phase watchdog timeout")
    }
    dut.clockDomain.waitSampling(5)
    if (sent != total || received3 != total || received5 != total || receivedMerge != total) fail("joint counts incomplete")
    if (latency3.distinct.size != 1 || latency5.distinct.size != 1) fail(s"unstalled latency not constant dw3=$latency3 dw5=$latency5")
    if (mergeStalls == 0 || inputStalls == 0) fail("backpressure coverage missing")
  }

  log.println(s"[TB PASSED] shared_input_windows=$total dw3_values=${total * 16} dw5_values=${total * 16} merge_values=${total * 16} dw3_latency=${latency3.head} dw5_latency=${latency5.head} input_stalls=$inputStalls merge_output_stalls=$mergeStalls")
  log.close()
  csv.close()
  result.println(s"{\"status\":\"PASS\",\"shared_input_windows\":$total,\"dw3_values\":${total * 16},\"dw5_values\":${total * 16},\"merge_values\":${total * 16},\"dw3_latency\":${latency3.head},\"dw5_latency\":${latency5.head},\"input_stalls\":$inputStalls,\"merge_output_stalls\":$mergeStalls}")
  result.close()
  println(s"[TB PASSED] shared_input_windows=$total dw3_values=${total * 16} dw5_values=${total * 16} merge_values=${total * 16} dw3_latency=${latency3.head} dw5_latency=${latency5.head} input_stalls=$inputStalls merge_output_stalls=$mergeStalls")
}

