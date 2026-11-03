// 文件类型：.scala。SpinalSim + Verilator，自校验冻结MAC/Golden、重载/复位/反压。
// 数学参考在 tools/generate_vectors.py；本测试仅负责协议驱动和文件比对。
import spinal.core._
import spinal.core.sim._
import java.io.{File, PrintWriter}
import scala.io.Source
import scala.util.Random

object PwMacSim extends App {
  val root = new File(sys.props.getOrElse("pw.verification.dir", "verification"))
  val caseFilter = sys.props.get("pw.case.filter").map(_.split(",").filter(_.nonEmpty).toSet)
  def lines(file: File): Vector[String] = {
    val source = Source.fromFile(file)
    try source.getLines().filter(_.nonEmpty).toVector finally source.close()
  }
  def hex(file: File): Vector[BigInt] = lines(file).map(v => BigInt(v.trim,16))
  case class Test(name: String, cin: Int, cout: Int, pixels: Int, shift: Int, raw: Boolean, int16: Boolean)
  val allTests = lines(new File(root,"vectors/cases.csv")).map { line =>
    val a=line.trim.split(",")
    Test(a(0),a(1).toInt,a(2).toInt,a(3).toInt,a(4).toInt,a(5)=="1",a(6)=="1")
  }
  caseFilter.foreach(names => require(names.subsetOf(allTests.map(_.name).toSet), s"unknown PW case: ${names.diff(allTests.map(_.name).toSet)}"))
  val tests = allTests.filter(t => caseFilter.forall(_.contains(t.name)))
  require(tests.nonEmpty, "no PW cases selected")
  val compiled = SimConfig.withConfig(SpinalConfig(
      defaultConfigForClockDomains=ClockDomainConfig(resetKind=ASYNC,resetActiveLevel=LOW)))
    .withFstWave.workspacePath(new File(root,"mac_workspace").getPath)
    .compile {
      val dut = new PwMac()
      dut.state_r.simPublic()
      dut
    }
  val summary = new PrintWriter(new File(root,"mac_results.csv"))
  summary.println("case,outputs,cycles,request_stalls,output_stalls,status")
  var totalOutputs=0L
  var totalCycles=0L
  var completed=0
  try compiled.doSim("pw_all_cases",20261011) { dut =>
    dut.clockDomain.forkStimulus(10)
    fork { sleep(100000000L); println("[TB FAILED] independent time watchdog"); simFailure("time watchdog") }
    dut.io.cfg_i.valid #= false
    dut.io.cfg_i.cin #= 1
    dut.io.cfg_i.cout #= 1
    dut.io.cfg_i.pixels #= 1
    dut.io.cfg_i.shift #= 0
    dut.io.cfg_i.raw #= false
    dut.io.cfg_i.raw16 #= false
    dut.io.cfg_i.int16 #= false
    dut.io.weights_i.valid #= false
    dut.io.weights_i.payload #= 0
    dut.io.params_i.valid #= false
    dut.io.params_i.payload #= 0
    dut.io.start_i.valid #= false
    dut.io.start_i.payload #= true
    dut.io.rd_o.ready #= false
    dut.io.rsp_i.valid #= false
    dut.io.rsp_i.payload #= 0
    dut.io.output_o.ready #= false
    dut.clockDomain.waitSampling(5)

    var csv: PrintWriter=null
    var cycle=0L
    var caseCycle=0
    var inputDone=0
    var outputDone=0
    var outStalls=0
    var reqStalls=0
    var expectedMac=Vector.empty[BigInt]
    var expectedQ=Vector.empty[BigInt]
    var expectedTags=Vector.empty[BigInt]
    var expectedRequests=Vector.empty[BigInt]
    var checking=false
    var running=false
    var expectedRaw=false
    var expectedInt16=false
    var heldOut: Option[(BigInt,BigInt,BigInt,Boolean,Boolean)]=None
    var heldRead: Option[BigInt]=None
    var heldWeight: Option[BigInt]=None
    var heldParam: Option[BigInt]=None
    def packedMac = (0 until 4).map(p => (dut.io.output_o.mac(p).toBigInt & ((BigInt(1)<<32)-1)) << (32*p)).reduce(_|_)
    def packedQ = (0 until 4).map(p => (dut.io.output_o.q(p).toBigInt & 65535) << (16*p)).reduce(_|_)
    def packedTag = dut.io.output_o.pixel.toBigInt | (dut.io.output_o.group.toBigInt<<19) |
      (dut.io.output_o.mask.toBigInt<<26) | (BigInt(if(dut.io.output_o.last.toBoolean) 1 else 0)<<30)
    def outSnapshot = (packedMac,packedQ,packedTag,dut.io.output_o.raw.toBoolean,dut.io.output_o.int16.toBoolean)
    def fail(message: String): Nothing = {
      if(csv != null) csv.flush()
      println(s"[TB FAILED] cycle=$cycle caseCycle=$caseCycle $message")
      simFailure(message)
    }
    def check(condition: Boolean, message: => String): Unit = if(!condition) fail(message)
    // 黑匣子必须按每个时钟采样导出，失败无需人工查看波形。
    dut.clockDomain.onSamplings {
      if(csv != null) {
        csv.println(s"$cycle,$caseCycle,${dut.clockDomain.isResetAsserted},${dut.state_r.toInt}," +
          s"${dut.io.cfg_i.valid.toBoolean},${dut.io.cfg_i.ready.toBoolean}," +
          s"${dut.io.weights_i.valid.toBoolean},${dut.io.weights_i.ready.toBoolean}," +
          s"${dut.io.params_i.valid.toBoolean},${dut.io.params_i.ready.toBoolean}," +
          s"${dut.io.rd_o.valid.toBoolean},${dut.io.rd_o.ready.toBoolean},${dut.io.rd_o.payload.toBigInt}," +
          s"${dut.io.rsp_i.valid.toBoolean},${dut.io.rsp_i.ready.toBoolean},${dut.io.rsp_i.payload.toBigInt.toString(16)}," +
          s"${dut.io.output_o.valid.toBoolean},${dut.io.output_o.ready.toBoolean},${packedTag.toString(16)}," +
          s"${packedMac.toString(16)},${packedQ.toString(16)},$inputDone,$outputDone")
        csv.flush()
      }
    }
    // tick 对上升沿前稳定值做全字段比对；CSV 钩子记录同一采样周期。
    def tick(drive: => Unit): (Boolean,Boolean,Boolean,Boolean,Boolean) = {
      dut.clockDomain.waitFallingEdge()
      drive
      sleep(1)
      cycle+=1
      caseCycle+=1
      val reset=dut.clockDomain.isResetAsserted
      val cfgFire=dut.io.cfg_i.valid.toBoolean && dut.io.cfg_i.ready.toBoolean
      val weightFire=dut.io.weights_i.valid.toBoolean && dut.io.weights_i.ready.toBoolean
      val paramFire=dut.io.params_i.valid.toBoolean && dut.io.params_i.ready.toBoolean
      val startFire=dut.io.start_i.valid.toBoolean && dut.io.start_i.ready.toBoolean
      val readFire=dut.io.rd_o.valid.toBoolean && dut.io.rd_o.ready.toBoolean
      val rspFire=dut.io.rsp_i.valid.toBoolean && dut.io.rsp_i.ready.toBoolean
      val outValid=dut.io.output_o.valid.toBoolean
      val outReady=dut.io.output_o.ready.toBoolean
      if(!reset) {
        heldOut.foreach(v => check(outValid && outSnapshot==v,s"output changed under backpressure expected=$v actual=$outSnapshot"))
        heldRead.foreach(v => check(dut.io.rd_o.valid.toBoolean && dut.io.rd_o.payload.toBigInt==v,"read address changed under backpressure"))
        heldWeight.foreach(v => check(dut.io.weights_i.valid.toBoolean && dut.io.weights_i.payload.toBigInt==v,"driver weight changed while stalled"))
        heldParam.foreach(v => check(dut.io.params_i.valid.toBoolean && dut.io.params_i.payload.toBigInt==v,"driver parameter changed while stalled"))
        heldOut=if(outValid && !outReady) Some(outSnapshot) else None
        heldRead=if(dut.io.rd_o.valid.toBoolean && !dut.io.rd_o.ready.toBoolean) Some(dut.io.rd_o.payload.toBigInt) else None
        heldWeight=if(dut.io.weights_i.valid.toBoolean && !dut.io.weights_i.ready.toBoolean) Some(dut.io.weights_i.payload.toBigInt) else None
        heldParam=if(dut.io.params_i.valid.toBoolean && !dut.io.params_i.ready.toBoolean) Some(dut.io.params_i.payload.toBigInt) else None
        if(running) check(!dut.io.cfg_i.ready.toBoolean && !dut.io.weights_i.ready.toBoolean &&
          !dut.io.params_i.ready.toBoolean && !dut.io.start_i.ready.toBoolean,
          "configuration/loading/start not blocked while running")
        if(checking && readFire) {
          check(inputDone<expectedRequests.size,"extra read request")
          check(dut.io.rd_o.payload.toBigInt==expectedRequests(inputDone),
            s"read[$inputDone] expected=${expectedRequests(inputDone)} actual=${dut.io.rd_o.payload.toBigInt}")
          inputDone+=1
        }
        if(checking && outValid && outReady) {
          check(outputDone<expectedMac.size,"extra output")
          check(packedMac==expectedMac(outputDone),s"MAC[$outputDone] expected=0x${expectedMac(outputDone).toString(16)} actual=0x${packedMac.toString(16)}")
          check(packedQ==expectedQ(outputDone),s"Q[$outputDone] expected=0x${expectedQ(outputDone).toString(16)} actual=0x${packedQ.toString(16)}")
          check(packedTag==expectedTags(outputDone),s"tag[$outputDone] expected=0x${expectedTags(outputDone).toString(16)} actual=0x${packedTag.toString(16)}")
          check(dut.io.output_o.raw.toBoolean==expectedRaw && dut.io.output_o.int16.toBoolean==expectedInt16,"output mode mismatch")
          outputDone+=1
        }
        if(dut.io.done_o.toBoolean && checking)
          check(outputDone==expectedMac.size,"premature done")
        if(outValid && !outReady) outStalls+=1
        if(dut.io.rd_o.valid.toBoolean && !dut.io.rd_o.ready.toBoolean) reqStalls+=1
      }
      dut.clockDomain.waitRisingEdge()
      sleep(1)
      check(caseCycle<2000000,"watchdog timeout")
      (cfgFire,weightFire,paramFire,startFire,readFire)
    }
    def resetDut(): Unit = {
      checking=false
      running=false
      heldOut=None; heldRead=None; heldWeight=None; heldParam=None
      dut.clockDomain.assertReset()
      tick {
        dut.io.cfg_i.valid #= false
        dut.io.weights_i.valid #= false
        dut.io.params_i.valid #= false
        dut.io.start_i.valid #= false
        dut.io.rsp_i.valid #= false
        dut.io.rd_o.ready #= false
        dut.io.output_o.ready #= false
      }
      tick {}; tick {}
      check(!dut.io.output_o.valid.toBoolean && !dut.io.rd_o.valid.toBoolean,"reset did not cancel outputs/requests")
      dut.clockDomain.deassertReset()
      tick {}
      check(!dut.io.start_i.ready.toBoolean,"reset retained loaded parameters")
    }
    def configure(t: Test): Unit = {
      var accepted=false
      while(!accepted) accepted=tick {
        dut.io.cfg_i.valid #= true
        dut.io.cfg_i.cin #= t.cin
        dut.io.cfg_i.cout #= t.cout
        dut.io.cfg_i.pixels #= t.pixels
        dut.io.cfg_i.shift #= t.shift
        dut.io.cfg_i.raw #= t.raw
        dut.io.cfg_i.raw16 #= false
        dut.io.cfg_i.int16 #= t.int16
        dut.io.start_i.valid #= false
        dut.io.weights_i.valid #= false
        dut.io.params_i.valid #= false
      }._1
      tick { dut.io.cfg_i.valid #= false }
    }
    val rng=new Random(20261011)
    def runCase(t: Test, requestedName: String="", reload: Boolean=true, abort: String=""): Boolean = {
      val name=if(requestedName.isEmpty) t.name else requestedName
      val dir=new File(root,"vectors/"+t.name)
      val logDir=new File(root,"cases/"+name); logDir.mkdirs()
      csv=new PrintWriter(new File(logDir,"sim_trace.csv"))
      csv.println("cycle,case_cycle,reset,state,cfg_valid,cfg_ready,weight_valid,weight_ready,param_valid,param_ready,rd_valid,rd_ready,rd_addr,rsp_valid,rsp_ready,rsp_data,out_valid,out_ready,out_tag,out_mac,out_q,reads,outputs")
      caseCycle=0; inputDone=0; outputDone=0; outStalls=0; reqStalls=0
      expectedMac=hex(new File(dir,"mac.hex")); expectedQ=hex(new File(dir,"golden.hex"))
      expectedTags=hex(new File(dir,"tags.hex"))
      expectedRequests=(for {
        tile <- 0 until ((t.pixels + 15) / 16)
        inputGroup <- 0 until ((t.cin + 15) / 16)
        pixel <- tile * 16 until (t.pixels min (tile * 16 + 16))
      } yield BigInt(inputGroup * t.pixels + pixel)).toVector
      expectedRaw=t.raw; expectedInt16=t.int16
      val weights=hex(new File(dir,"weights.hex")); val params=hex(new File(dir,"params.hex"))
      val stimulus=hex(new File(dir,"stimulus.hex"))
      try {
        if(reload) {
          configure(t)
          // 未加载齐时启动必须被拒绝。
          tick { dut.io.start_i.valid #= true }
          check(!dut.io.start_i.ready.toBoolean,"start accepted before complete loading")
          tick { dut.io.start_i.valid #= false }
          var wi=0; var pi=0
          var wPending=false; var pPending=false
          while(wi<weights.size || pi<params.size) {
            if(!wPending && wi<weights.size && rng.nextInt(4)!=0) wPending=true
            if(!pPending && pi<params.size && rng.nextInt(4)!=0) pPending=true
            val fires=tick {
              dut.io.weights_i.valid #= wPending
              dut.io.weights_i.payload #= weights(wi min (weights.size-1))
              dut.io.params_i.valid #= pPending
              dut.io.params_i.payload #= params(pi min (params.size-1))
            }
            if(fires._2) { wi+=1; wPending=false }
            if(fires._3) { pi+=1; pPending=false }
            if(abort=="loading" && wi>=1) { resetDut(); return false }
          }
          tick { dut.io.weights_i.valid #= false; dut.io.params_i.valid #= false }
        }
        var started=false
        while(!started) started=tick { dut.io.start_i.valid #= true }._4
        tick { dut.io.start_i.valid #= false }
        checking=true; running=true
        var pending: Option[(BigInt,Int)]=None
        var responsePresented=false
        var responseAccepted=false
        var longStall=0
        var aborted=false
        while(outputDone<expectedMac.size && !aborted) {
          if(responseAccepted) { pending=None; responsePresented=false; responseAccepted=false }
          if(pending.exists(_._2<=caseCycle)) responsePresented=true
          val fullFrame=t.name=="full_frame_512"
          val readReady=fullFrame || rng.nextInt(4)!=0
          val ready=if(fullFrame) true else if(abort=="output" || abort=="compute") false
            else if(longStall>0) { longStall-=1; false }
            else if(rng.nextInt(100)==0) { longStall=40; false }
            else rng.nextInt(4)!=0
          var sampledAddress=BigInt(0)
          var rspHandshake=false
          val fires=tick {
            dut.io.rd_o.ready #= readReady
            dut.io.rsp_i.valid #= responsePresented
            dut.io.rsp_i.payload #= pending.map(p=>stimulus(p._1.toInt)).getOrElse(BigInt(0))
            dut.io.output_o.ready #= ready
          }
          // 请求地址用独立请求Golden定位，不依赖可能已前进的组合地址。
          if(fires._5) {
            check(pending.isEmpty,"more than one outstanding read")
            sampledAddress=expectedRequests(inputDone-1)
            pending=Some((sampledAddress,caseCycle+1+(if(fullFrame) 0 else rng.nextInt(5))))
          }
          // tick 前返回握手可从状态转移确认：waiting→下个请求/ISSUE。
          if(responsePresented && pending.nonEmpty && !dut.io.rsp_i.ready.toBoolean) responseAccepted=true
          if(abort=="request" && pending.nonEmpty ||
             abort=="compute" && dut.state_r.toInt==4 ||
             abort=="output" && dut.io.output_o.valid.toBoolean) {
            resetDut()
            aborted=true
          }
        }
        if(aborted) return false
        running=false
        checking=true
        tick {
          dut.io.rd_o.ready #= false; dut.io.rsp_i.valid #= false; dut.io.output_o.ready #= true
        }
        check(dut.io.start_i.ready.toBoolean,"not ready after final output")
        check(inputDone==expectedRequests.size,"missing input requests")
        check(outStalls>0 || expectedMac.size==1 || t.name=="full_frame_512","output backpressure not exercised")
        totalOutputs+=outputDone; totalCycles+=caseCycle; completed+=1
        summary.println(s"$name,$outputDone,$caseCycle,$reqStalls,$outStalls,PASS"); summary.flush()
        println(s"[TB PASSED] $name outputs=$outputDone cycles=$caseCycle requestStalls=$reqStalls outputStalls=$outStalls")
        true
      } finally { csv.close(); csv=null; checking=false; running=false }
    }
    resetDut()
    // 非法配置不接收，覆盖零值、越界与非法 shift。
    for((cin,cout,pixels,shift)<-Seq((0,1,1,0),(769,1,1,0),(1,0,1,0),(1,513,1,0),(1,1,0,0),(1,1,262145,0),(1,1,1,63))) {
      val fire=tick {
        dut.io.cfg_i.valid #= true; dut.io.cfg_i.cin #= cin; dut.io.cfg_i.cout #= cout
        dut.io.cfg_i.pixels #= pixels; dut.io.cfg_i.shift #= shift
      }._1
      check(!fire,"invalid configuration accepted")
    }
    tick { dut.io.cfg_i.valid #= false }
    // 全部模型层共用同一已编译DUT，模型/层切换不复位。
    tests.foreach(t=>runCase(t))
    if(caseFilter.isEmpty) {
      val replay=tests.find(_.name=="shift0_signed_saturation").get
      runCase(replay,"reload_before_reuse")
      runCase(replay,"reuse_without_reload",false)
      val resetTest=tests.find(_.name=="directed_192_128_33").get
      for(phase<-Seq("loading","request","compute","output")) {
        runCase(resetTest,"reset_"+phase,abort=phase)
        runCase(resetTest,"recovery_"+phase)
      }
    }
    checking=false
    for(_<-0 until 30) {
      tick { dut.io.output_o.ready #= true }
      check(!dut.io.output_o.valid.toBoolean,"stray old output")
    }
    if(caseFilter.isEmpty)
      println(s"[TB PASSED] ALL MAC cases=$completed outputs=$totalOutputs cycles=$totalCycles reset_phases=4 frozen_layers=66")
    else
      println(s"[TB PASSED] FILTERED MAC cases=$completed outputs=$totalOutputs cycles=$totalCycles selected=${caseFilter.get.toSeq.sorted.mkString(",")}")
  } finally { summary.close() }
}
