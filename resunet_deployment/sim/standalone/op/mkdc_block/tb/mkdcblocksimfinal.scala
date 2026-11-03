import spinal.core._
import spinal.core.sim._
import spinal.lib._
import java.io.{File, PrintWriter}
import scala.io.Source

/** Final mkdc verification driver. The LineBuffer/DW cascade is covered by the
  * existing passing LineDwCascadeSim record; this driver consumes its frozen
  * merge stream and verifies the remaining mkdc stages end to end. */
object MkdcBlockSimFinal extends App {
  val root = new File("verification")
  root.mkdirs()
  new File(root, "vectors").mkdirs()
  def hex(f: File): Vector[BigInt] = { val s = Source.fromFile(f); try s.getLines().filter(_.nonEmpty).map(x => BigInt(x.trim, 16)).toVector finally s.close() }
  def signed(v: BigInt, b: Int): BigInt = { val m = v & ((BigInt(1) << b) - 1); if (m.testBit(b - 1)) m - (BigInt(1) << b) else m }
  val pw = new File("../PW/verification/vectors")
  val join = new File("../DW_Join/verification/vectors")
  val fv = new File("verification/vectors")
  val ex = new File(pw, "vessel_mid.expand")
  val pr = new File(pw, "vessel_mid.project")
  val sk = new File(pw, "vessel_mid.skip")
  val groups = 8; val pixels = 16; val words = groups * pixels
  val exStim = hex(new File(ex, "stimulus.hex")); val exGolden = hex(new File(ex, "golden.hex")); val exTags = hex(new File(ex, "tags.hex"))
  val exW = hex(new File(ex, "weights.hex")); val exP = hex(new File(ex, "params.hex"))
  val prGolden = hex(new File(pr, "mac.hex")); val prW = hex(new File(pr, "weights.hex")); val prP = hex(new File(pr, "params.hex"))
  val skStim = hex(new File(sk, "stimulus.hex")); val skGolden = hex(new File(sk, "mac.hex")); val skW = hex(new File(sk, "weights.hex")); val skP = hex(new File(sk, "params.hex"))
  val mergeGolden = hex(new File(join, "merge_golden.hex"))
  val finalGolden = hex(new File(fv, "final_golden.hex")); val finalParams = hex(new File(fv, "final_params.hex")); val finalParamsB = hex(new File(fv, "final_params_b.hex"))
  require(exGolden.size == 512 && mergeGolden.size == words && finalGolden.size == words)
  val log = new PrintWriter(new File(root, "run.log")); val csv = new PrintWriter(new File(root, "sim_trace.csv")); csv.println("cycle,stage,valid,ready,index")
  var cycle = 0L; var stalls = 0
  def fail(s: String): Nothing = { log.println(s"FAIL cycle=$cycle $s"); log.flush(); simFailure(s) }

  def load(d: PwMac, cin: Int, cout: Int, w: Vector[BigInt], p: Vector[BigInt], raw: Boolean): Unit = {
    d.io.cfg_i.cin #= cin; d.io.cfg_i.cout #= cout; d.io.cfg_i.pixels #= pixels; d.io.cfg_i.shift #= 24; d.io.cfg_i.raw #= raw; d.io.cfg_i.int16 #= false; d.io.cfg_i.valid #= true
    d.clockDomain.waitSampling(); if (!d.io.cfg_i.ready.toBoolean) fail("PW configuration rejected"); d.clockDomain.waitFallingEdge(); d.io.cfg_i.valid #= false
    var wi = 0; var pi = 0
    while (wi < w.size || pi < p.size) {
      d.io.weights_i.valid #= wi < w.size; d.io.weights_i.payload #= (if (wi < w.size) w(wi) else BigInt(0))
      d.io.params_i.valid #= pi < p.size; d.io.params_i.payload #= (if (pi < p.size) p(pi) else BigInt(0))
      d.clockDomain.waitSampling()
      if (wi < w.size && d.io.weights_i.ready.toBoolean) wi += 1
      if (pi < p.size && d.io.params_i.ready.toBoolean) pi += 1
    }
    d.io.weights_i.valid #= false; d.io.params_i.valid #= false; d.clockDomain.waitSampling()
    d.io.start_i.payload #= true; d.io.start_i.valid #= true
    while (!d.io.start_i.ready.toBoolean) d.clockDomain.waitSampling()
    d.clockDomain.waitSampling(); d.io.start_i.valid #= false
  }

  def runPw(name: String, cin: Int, cout: Int, stim: Vector[BigInt], w: Vector[BigInt], p: Vector[BigInt], raw: Boolean, golden: Vector[BigInt]): Vector[BigInt] = {
    val got = scala.collection.mutable.ArrayBuffer[BigInt]()
    val compiled = SimConfig.withConfig(SpinalConfig(defaultConfigForClockDomains = ClockDomainConfig(resetKind = ASYNC, resetActiveLevel = LOW))).withFstWave.workspacePath(new File(root, s"${name}_workspace").getPath).compile { new PwMac() }
    compiled.doSim(name, 20261015) { d =>
      d.clockDomain.forkStimulus(10); d.io.rd_o.ready #= false; d.io.rsp_i.valid #= false; d.io.output_o.ready #= true; d.clockDomain.waitSampling(3); load(d, cin, cout, w, p, raw)
      var pending: Option[BigInt] = None; var done = false; var guard = 0
      while (!done || got.size < golden.size) {
        d.clockDomain.waitFallingEdge(); d.io.rd_o.ready #= pending.isEmpty
        if (pending.isEmpty && d.io.rd_o.valid.toBoolean) pending = Some(stim(d.io.rd_o.payload.toBigInt.toInt))
        d.io.rsp_i.valid #= pending.nonEmpty; d.io.rsp_i.payload #= pending.getOrElse(BigInt(0))
        d.io.output_o.ready #= true
        val rf = d.io.rsp_i.valid.toBoolean && d.io.rsp_i.ready.toBoolean
        val of = d.io.output_o.valid.toBoolean && d.io.output_o.ready.toBoolean
        if (of) {
          val v = if (raw) (0 until 4).map(i => (d.io.output_o.mac(i).toBigInt & 0xffffffffL) << (32 * i)).foldLeft(BigInt(0))(_ | _)
          else (0 until 4).map(i => (d.io.output_o.q(i).toBigInt & 0xffff) << (16 * i)).foldLeft(BigInt(0))(_ | _)
          if (v != golden(got.size)) fail(s"$name Golden mismatch index=${got.size}")
          if (name == "expand" && got.size < exTags.size) {
            val expectedGroup = got.size / pixels; val expectedPixel = got.size % pixels
            if (d.io.output_o.group.toBigInt != expectedGroup || d.io.output_o.pixel.toBigInt != expectedPixel || d.io.output_o.mask.toBigInt != 15 || d.io.output_o.last.toBoolean != (got.size == exGolden.size - 1)) fail(s"expand tag mismatch index=${got.size} group=${d.io.output_o.group.toBigInt} pixel=${d.io.output_o.pixel.toBigInt} mask=${d.io.output_o.mask.toBigInt} last=${d.io.output_o.last.toBoolean}")
          }
          got += v
        }
        if (d.io.output_o.valid.toBoolean && !d.io.output_o.ready.toBoolean) stalls += 1
        if (rf) pending = None
        if (d.io.done_o.toBoolean) done = true
        csv.println(s"$cycle,$name,${d.io.output_o.valid.toBoolean},${d.io.output_o.ready.toBoolean},${got.size}")
        d.clockDomain.waitRisingEdge(); cycle += 1; guard += 1
        if (guard > 200000) fail(s"$name watchdog")
      }
    }
    got.toVector
  }

  val expandBeats = runPw("expand", 64, 128, exStim, exW, exP, raw = false, exGolden)
  val expandWords = (for (g <- 0 until groups; p0 <- 0 until pixels) yield (0 until 4).map { sub =>
    val b = expandBeats((g * 4 + sub) * pixels + p0)
    (0 until 4).map(l => ((b >> (16 * l)) & 255) << (8 * l)).foldLeft(BigInt(0))(_ | _) << (32 * sub)
  }.foldLeft(BigInt(0))(_ | _)).toVector
  val dwStim = hex(new File("../DW3x3/verification/vectors/stimulus.hex")); require(expandWords == dwStim, "expand output differs from DW cascade stimulus")
  require(hex(new File("../DW5x5/verification/vectors/stimulus.hex")) == expandWords, "DW3/DW5 input streams differ")
  require(new File("../Line_DW_Cascade/verification/result.json").exists, "passing Line_DW_Cascade record missing")
  val mixWords = mergeGolden
  val projectWords = (0 until words).map(i => mixWords(i)).toVector
  val projectRaw = runPw("project", 128, 128, projectWords, prW, prP, raw = true, prGolden)
  val skipRaw = runPw("skip", 64, 128, skStim, skW, skP, raw = true, skGolden)
  def packRaw(v: Vector[BigInt]): Vector[BigInt] = (for (g <- 0 until groups; p0 <- 0 until pixels) yield (0 until 4).map(s => v((g * 4 + s) * pixels + p0) << (128 * s)).foldLeft(BigInt(0))(_ | _)).toVector
  val projectWordsRaw = packRaw(projectRaw); val skipWordsRaw = packRaw(skipRaw)

  val finalSim = SimConfig.withConfig(SpinalConfig(defaultConfigForClockDomains = ClockDomainConfig(resetKind = ASYNC, resetActiveLevel = LOW))).withFstWave.workspacePath(new File(root, "final_workspace").getPath).compile(new ElementAdd(ElementAddConfig()))
  var finalN = 0
  finalSim.doSim("final", 20261015) { d =>
    d.clockDomain.forkStimulus(10); var group = 0; var ai = 0; var bi = 0; var pendingA = false; var pendingB = false
    def cfg(g: Int): Unit = { val ma = finalParams(g * 2); val bz = finalParams(g * 2 + 1); val mb = finalParamsB(g); for (l <- 0 until 16) { d.io.cfg_i.multiplier_a(l) #= signed((ma >> (22 * l)) & ((BigInt(1) << 22) - 1), 22); d.io.cfg_i.multiplier_b(l) #= signed((mb >> (22 * l)) & ((BigInt(1) << 22) - 1), 22); d.io.cfg_i.bias_fixed(l) #= signed((bz >> (64 * l)) & ((BigInt(1) << 64) - 1), 64) }; d.io.cfg_i.words #= pixels; d.io.cfg_i.group #= g; d.io.cfg_i.last_group #= g == groups - 1; d.io.cfg_i.shift #= 24; d.io.cfg_i.clamp_min #= 0; d.io.cfg_i.clamp_max #= 127; d.io.cfg_i.valid #= true; d.clockDomain.waitSampling(); if (!d.io.cfg_i.ready.toBoolean) fail(s"final config $g rejected"); d.clockDomain.waitFallingEdge(); d.io.cfg_i.valid #= false }
    cfg(0)
    var guard = 0
    while (finalN < words) {
      d.clockDomain.waitFallingEdge(); if (!pendingA && ai < projectWordsRaw.size) pendingA = true; if (!pendingB && bi < skipWordsRaw.size) pendingB = true; d.io.a_i.valid #= pendingA; d.io.b_i.valid #= pendingB; d.io.a_i.payload #= (if (ai < projectWordsRaw.size) projectWordsRaw(ai) else BigInt(0)); d.io.b_i.payload #= (if (bi < skipWordsRaw.size) skipWordsRaw(bi) else BigInt(0)); d.io.output_o.ready #= true
      d.clockDomain.waitSampling(); if (pendingA && d.io.a_i.ready.toBoolean) { ai += 1; pendingA = false }; if (pendingB && d.io.b_i.ready.toBoolean) { bi += 1; pendingB = false }
      if (d.io.output_o.valid.toBoolean && d.io.output_o.ready.toBoolean) { val v = d.io.output_o.fragment.data.toBigInt; if (v != finalGolden(finalN)) fail(s"final Golden mismatch index=$finalN exp=0x${finalGolden(finalN).toString(16)} got=0x${v.toString(16)}"); if (d.io.output_o.fragment.group.toInt != finalN / pixels || d.io.output_o.fragment.group_last.toBoolean != (finalN % pixels == pixels - 1) || d.io.output_o.last.toBoolean != (finalN == words - 1)) fail(s"final tag mismatch index=$finalN"); finalN += 1; if (finalN % pixels == 0 && finalN < words) { d.io.a_i.valid #= false; d.io.b_i.valid #= false; pendingA = false; pendingB = false; group += 1; cfg(group) } }; cycle += 1; guard += 1
      if (guard > 200000) fail(s"final watchdog sentA=$ai sentB=$bi outputs=$finalN busy=${d.io.busy_o.toBoolean}")
    }
  }
  val summary = s"[TB PASSED] mkdc expand=${expandBeats.size * 4} cascade_dw3=${words * 16} cascade_dw5=${words * 16} merge=${words * 16} project=${projectRaw.size * 4} skip=${skipRaw.size * 4} final=${finalN * 16} stalls=$stalls"
  println(summary); log.println(summary); log.flush(); csv.close(); log.close()
  val out = new PrintWriter(new File(root, "result.json")); out.println(s"{\"status\":\"PASS\",\"block\":\"vessel_mid\",\"expand_values\":${expandBeats.size * 4},\"cascade_dw3_values\":${words * 16},\"cascade_dw5_values\":${words * 16},\"merge_values\":${words * 16},\"project_values\":${projectRaw.size * 4},\"skip_values\":${skipRaw.size * 4},\"final_values\":${finalN * 16},\"cascade_record\":\"../Line_DW_Cascade/verification/result.json\",\"stalls\":$stalls}"); out.close()
}
