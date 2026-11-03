// 文件类型：.scala。同一 DUT/时钟下，实际输出缓存驱动下一级，Golden 只供质检。
import spinal.core._
import spinal.core.sim._
import spinal.lib._
import java.io.{File, PrintWriter}
import scala.io.Source
import scala.util.Random
import scala.collection.mutable

object DecoderD3Sim extends App {
  val root = new File(args(0)).getCanonicalFile
  val concatPath = new File(args(1)).getCanonicalPath
  val vectors = new File(root, "vectors")
  def hex(name: String): Vector[BigInt] = {
    val f = Source.fromFile(new File(vectors, name + ".hex"))
    try f.getLines().map(s => BigInt(s.trim, 16)).toVector finally f.close()
  }
  def pack(v: scala.collection.Seq[BigInt], bits: Int): BigInt = v.zipWithIndex.map { case (x,i) =>
    (x & ((BigInt(1) << bits)-1)) << (i*bits)
  }.foldLeft(BigInt(0))(_ | _)
  def signed(x: BigInt, bits: Int): BigInt = {
    val v = x & ((BigInt(1) << bits)-1)
    if (v.testBit(bits-1)) v - (BigInt(1) << bits) else v
  }
  val mid = hex("mid")
  val encoderSkip = hex("encoder_skip")
  val golden = Seq("up", "concat", "expand", "mix", "final", "window3", "window5")
    .map(n => n -> hex(n + "_golden")).toMap
  val macGolden = Seq("expand", "dw3", "dw5", "project", "skip").map(n => n -> hex(n + "_mac")).toMap
  val params = Seq("expand", "project", "skip", "dw3", "dw5").map(n =>
    n -> (hex(n + "_weights"), hex(n + "_params"))).toMap
  val mergeParams = Seq("mix", "out").map(n => n -> Seq("a", "b", "bias").map(s => hex(n + "_" + s))).toMap
  val cfgFile = Source.fromFile(new File(vectors,"merge_config.csv"))
  val mergeCfg = try cfgFile.getLines().map { s => val a=s.split(","); a(0)->a.drop(1).map(_.toInt) }.toMap finally cfgFile.close()
  require(mid.size == 128 && encoderSkip.size == 256 && golden("final").size == 256)
  val summary = new PrintWriter(new File(root,"results.csv"))
  summary.println("trial,seed,phase,cycles,outputs,output_stalls,status")
  var trialsPassed = 0
  val compiled = SimConfig.withConfig(SpinalConfig(defaultConfigForClockDomains =
    ClockDomainConfig(resetKind = ASYNC, resetActiveLevel = LOW)))
    .workspacePath(new File(root,"compiled").getPath).withFstWave.compile {
      val d = new DecoderD3Harness(concatPath)
      Seq(d.lb3.io.output_o,d.lb5.io.output_o,d.dw3.io.output_o,d.dw5.io.output_o).foreach(_.simPublic())
      d
    }
  try compiled.doSim("vessel_d3", 20261016) { d =>
    var cycle=0L; var phase="idle"; var trial=0
    var random = new Random(0)
    var continuous = true
    var deadline = Long.MaxValue
    var csv: PrintWriter = null
    var actualUp=Vector.empty[BigInt]; var actualCat=Vector.empty[BigInt]
    var actualExpand=Vector.empty[BigInt]; var actualMix=Vector.empty[BigInt]
    var actualProject=Vector.empty[BigInt]; var actualSkip=Vector.empty[BigInt]
    val collected = mutable.ArrayBuffer.empty[BigInt]
    val requests = mutable.ArrayBuffer.empty[(Boolean,Int)]
    var pwRaw = false; var pwCin = 192
    var pw8 = Array.fill[BigInt](256)(0); var pw32 = Array.fill[BigInt](256)(0)
    var written = Array.fill(256)(0)
    var phaseOutputs=0
    var upDone=0; var catDone=0; var pwDone=0; var mixDone=0; var finalDone=0
    def fail(msg:String):Nothing = {
      if(csv != null) csv.flush()
      simFailure(s"trial=$trial phase=$phase cycle=$cycle time=${simTime()} $msg")
    }
    def check(ok:Boolean,msg: => String):Unit = if(!ok) fail(msg)
    def value(data:Data):Vector[BigInt] = data.flatten.toVector.map {
      case b:Bool => if(b.toBoolean) BigInt(1) else BigInt(0)
      case b:Bits => b.toBigInt
      case u:UInt => u.toBigInt
      case s:SInt => s.toBigInt
      case other => throw new IllegalArgumentException(other.toString)
    }
    class Watch(val name:String,val stream:Stream[_ <: Data],val action:()=>Unit,val trace:Boolean) {
      var count=0; var stalls=0L; var held:Option[Vector[BigInt]]=None
      def sample():Unit = {
        val v=stream.valid.toBoolean; val r=stream.ready.toBoolean
        val payload=value(stream.payload)
        held.foreach(p => check(v && payload==p,s"$name changed valid/payload during stall"))
        held=if(v && !r) Some(payload) else None
        if(v && !r) stalls+=1
        if(v && r) { action(); count+=1 }
      }
    }
    val watches=mutable.ArrayBuffer.empty[Watch]
    def watch(name:String,s:Stream[_ <: Data],trace:Boolean=true)(f: => Unit):Watch = {
      val w=new Watch(name,s,()=>f,trace); watches+=w; w
    }
    def passive(name:String,s:Stream[_ <: Data]):Watch=watch(name,s,false){}
    def equalWord(stage:String,index:Int,actual:BigInt,expected:Vector[BigInt]):Unit = {
      check(index<expected.size,s"$stage extra output index=$index")
      check(actual==expected(index),s"$stage index=$index expected=0x${expected(index).toString(16)} actual=0x${actual.toString(16)}")
    }
    def grouped(index:Int,group:Int,gl:Boolean,last:Boolean):Unit = {
      check(group==index/64 && gl==(index%64==63) && last==(index==255),s"group tag index=$index actual=($group,$gl,$last)")
    }

    val upCfg=passive("up_cfg",d.io.up_cfg_i)
    val upIn=watch("up_in",d.io.up_input_i){}
    val upOut=watch("up_out",d.io.up_output_o) {
      val n=collected.size; val p=d.io.up_output_o.fragment
      check(phase=="up","unexpected Upsample output")
      equalWord("up",n,p.data.toBigInt,golden("up"))
      check(p.group.toInt==n/64 && p.row.toInt==n%64/8 && p.col.toInt==n%8 &&
        p.group_last.toBoolean==(n%64==63) && d.io.up_output_o.last.toBoolean==(n==511),s"up tag index=$n")
      collected+=p.data.toBigInt
    }
    val catCfg=passive("cat_cfg",d.io.cat_cfg_i)
    val catRd=watch("cat_rd",d.io.cat_rd_o) {
      val n=requests.size; val src=d.io.cat_rd_o.source.toBoolean; val addr=d.io.cat_rd_o.address.toBigInt.toInt
      check(phase=="concat" && n<768,"unexpected Concat request")
      check(src==(n>=512) && addr==(if(n<512)65521+n else 1048589+n-512),s"Concat route index=$n source=$src address=$addr")
      requests+=((src,addr))
    }
    val catRsp=watch("cat_rsp",d.io.cat_rsp_i){}
    val catOut=watch("cat_out",d.io.cat_output_o) {
      check(phase=="concat","unexpected Concat output")
      val n=collected.size
      equalWord("concat",n,d.io.cat_output_o.fragment.toBigInt,golden("concat"))
      check(d.io.cat_output_o.last.toBoolean==(n==767),s"Concat last index=$n")
      collected+=d.io.cat_output_o.fragment.toBigInt
    }
    val pwCfg=passive("pw_cfg",d.io.pw_cfg_i)
    val pwWeights=passive("pw_weights",d.io.pw_weights_i)
    val pwParams=passive("pw_params",d.io.pw_params_i)
    val pwStart=passive("pw_start",d.io.pw_start_i)
    val pwRd=watch("pw_rd",d.io.pw_rd_o) {
      val n=requests.size; val ig=pwCin/16
      val expected=(n%(ig*16)/16)*64+(n/(ig*16))*16+n%16
      val addr=d.io.pw_rd_o.payload.toBigInt.toInt
      check(Set("expand","project","skip")(phase) && n<ig*64 && addr==expected,s"PW request n=$n expected=$expected actual=$addr")
      requests+=((false,addr))
    }
    val pwRsp=watch("pw_rsp",d.io.pw_rsp_i){}
    val pwOut=watch("pw_out",d.io.pw_output_o) {
      val n=phaseOutputs; val p=d.io.pw_output_o.payload
      check(Set("expand","project","skip")(phase) && n<1024,"unexpected PW output")
      val g=(n%256)/16; val pixel=(n/256)*16+n%16
      check(p.group.toInt==g && p.pixel.toInt==pixel && p.mask.toInt==15 && p.last.toBoolean==(n==1023) &&
        p.raw.toBoolean==pwRaw && !p.int16.toBoolean,s"PW tags index=$n actual group=${p.group.toInt} pixel=${p.pixel.toInt}")
      val index=(g/4)*64+pixel
      for(l<-0 until 4) {
        val lane=(g%4)*4+l
        val expected=signed(macGolden(phase)(index)>>(lane*32),32)
        val actual=p.mac(l).toBigInt
        check(actual==expected,s"$phase MAC group=$g pixel=$pixel lane=$l expected=$expected actual=$actual")
        check((written(index)&(1<<lane))==0,s"duplicate PW cache write index=$index lane=$lane")
        written(index)|=1<<lane
        pw32(index)|=(actual&0xffffffffL)<<(lane*32)
        if(!pwRaw) {
          val expectedQ=signed(golden("expand")(index)>>(lane*8),8)
          check(p.q(l).toBigInt==expectedQ,s"expand Q index=$index lane=$lane expected=$expectedQ actual=${p.q(l).toBigInt}")
          pw8(index)|=(p.q(l).toBigInt&255)<<(lane*8)
        } else check(p.q(l).toInt==0,"raw PW unexpectedly quantized")
      }
      phaseOutputs+=1
    }
    val lb3Cfg=passive("lb3_cfg",d.io.lb3_cfg_i); val lb5Cfg=passive("lb5_cfg",d.io.lb5_cfg_i)
    val lb3In=watch("lb3_in",d.io.lb3_input_i){}; val lb5In=watch("lb5_in",d.io.lb5_input_i){}
    var win3N=0; var win5N=0; var dw3N=0; var dw5N=0
    val lb3Out=watch("lb3_out",d.lb3.io.output_o,false) {
      check(phase=="cascade","unexpected LB3 window")
      val p=d.lb3.io.output_o.fragment
      equalWord("window3",win3N,pack((for(y<-0 until 3;x<-0 until 3)yield p.window(y)(x).toBigInt),128),golden("window3"))
      grouped(win3N,p.group.toInt,p.group_last.toBoolean,d.lb3.io.output_o.last.toBoolean); win3N+=1
    }
    val lb5Out=watch("lb5_out",d.lb5.io.output_o,false) {
      check(phase=="cascade","unexpected LB5 window")
      val p=d.lb5.io.output_o.fragment
      equalWord("window5",win5N,pack((for(y<-0 until 5;x<-0 until 5)yield p.window(y)(x).toBigInt),128),golden("window5"))
      grouped(win5N,p.group.toInt,p.group_last.toBoolean,d.lb5.io.output_o.last.toBoolean); win5N+=1
    }
    val dw3Cfg=passive("dw3_cfg",d.io.dw3_cfg_i); val dw5Cfg=passive("dw5_cfg",d.io.dw5_cfg_i)
    val dw3W=passive("dw3_weights",d.io.dw3_weights_i); val dw5W=passive("dw5_weights",d.io.dw5_weights_i)
    val dw3P=passive("dw3_params",d.io.dw3_params_i); val dw5P=passive("dw5_params",d.io.dw5_params_i)
    val dw3Out=watch("dw3_out",d.dw3.io.output_o) {
      check(phase=="cascade","unexpected DW3 output")
      val p=d.dw3.io.output_o.payload
      equalWord("dw3",dw3N,pack(p.mac.map(_.toBigInt),32),macGolden("dw3"))
      grouped(dw3N,p.tag.group.toInt,p.tag.group_last.toBoolean,p.tag.last.toBoolean)
      check(p.tag.row.toInt==dw3N%64/8 && p.tag.col.toInt==dw3N%8,"DW3 coordinates"); dw3N+=1
    }
    val dw5Out=watch("dw5_out",d.dw5.io.output_o) {
      check(phase=="cascade","unexpected DW5 output")
      val p=d.dw5.io.output_o.payload
      equalWord("dw5",dw5N,pack(p.mac.map(_.toBigInt),32),macGolden("dw5"))
      grouped(dw5N,p.tag.group.toInt,p.tag.group_last.toBoolean,p.tag.last.toBoolean)
      check(p.tag.row.toInt==dw5N%64/8 && p.tag.col.toInt==dw5N%8,"DW5 coordinates"); dw5N+=1
    }
    val mixCfg=passive("mix_cfg",d.io.mix_cfg_i)
    val mixOut=watch("mix_out",d.io.mix_output_o) {
      check(phase=="cascade","unexpected mix output")
      val n=collected.size; val p=d.io.mix_output_o.fragment
      equalWord("mix",n,p.data.toBigInt,golden("mix"))
      grouped(n,p.group.toInt,p.group_last.toBoolean,d.io.mix_output_o.last.toBoolean)
      collected+=p.data.toBigInt
    }
    val finalCfg=passive("final_cfg",d.io.final_cfg_i)
    val finalA=watch("final_a",d.io.final_a_i){}; val finalB=watch("final_b",d.io.final_b_i){}
    val finalOut=watch("final_out",d.io.final_output_o) {
      check(phase=="final","unexpected final output")
      val n=collected.size; val p=d.io.final_output_o.fragment
      equalWord("final",n,p.data.toBigInt,golden("final"))
      grouped(n,p.group.toInt,p.group_last.toBoolean,d.io.final_output_o.last.toBoolean)
      collected+=p.data.toBigInt
    }
    val inputs=Seq(d.io.up_cfg_i,d.io.up_input_i,d.io.cat_cfg_i,d.io.cat_rsp_i,d.io.pw_cfg_i,d.io.pw_weights_i,
      d.io.pw_params_i,d.io.pw_start_i,d.io.pw_rsp_i,d.io.lb3_cfg_i,d.io.lb5_cfg_i,d.io.lb3_input_i,d.io.lb5_input_i,
      d.io.dw3_cfg_i,d.io.dw5_cfg_i,d.io.dw3_weights_i,d.io.dw5_weights_i,d.io.dw3_params_i,d.io.dw5_params_i,
      d.io.mix_cfg_i,d.io.final_cfg_i,d.io.final_a_i,d.io.final_b_i)
    inputs.foreach { s => s.valid #= false; s.payload.flatten.foreach {
      case b:Bool => b #= false; case b:Bits => b #= 0; case u:UInt => u #= 0; case s:SInt => s #= 0
    }}
    Seq(d.io.up_output_o,d.io.cat_rd_o,d.io.cat_output_o,d.io.pw_rd_o,d.io.pw_output_o,d.io.mix_output_o,d.io.final_output_o)
      .foreach(_.ready #= false)
    d.clockDomain.forkStimulus(8)
    d.clockDomain.onSamplings {
      if(!d.clockDomain.isResetAsserted) {
        if(csv!=null) csv.println(s"$cycle,$trial,$phase,"+watches.filter(_.trace).map { w =>
          s"${w.stream.valid.toBoolean},${w.stream.ready.toBoolean},${value(w.stream.payload).map(_.toString(16)).mkString(":")}"
        }.mkString(","))
        check(cycle<deadline,"watchdog timeout")
        watches.foreach(_.sample())
        if(d.io.up_done_o.toBoolean) { check(upOut.count==512,"early Upsample done"); upDone+=1 }
        if(d.io.cat_done_o.toBoolean) { check(catOut.count==768,"early Concat done"); catDone+=1 }
        if(d.io.pw_done_o.toBoolean) { check(phaseOutputs==1024,"early PW done"); pwDone+=1 }
        if(d.io.mix_done_o.toBoolean) { mixDone+=1; check(mixOut.count==mixDone*64,"early mix done") }
        if(d.io.final_done_o.toBoolean) { finalDone+=1; check(finalOut.count==finalDone*64,"early final done") }
      }
      cycle+=1
    }
    fork { sleep(100000000L); fail("global watchdog") }
    def step(body: => Unit = ()):Unit = {
      d.clockDomain.waitFallingEdge(); body; sleep(1)
      d.clockDomain.waitSampling(); sleep(1)
    }
    def sendCfg(w:Watch)(body: => Unit):Unit = {
      val n=w.count
      step { body; w.stream.valid #= true }
      while(w.count==n) step()
      step { w.stream.valid #= false }
    }
    def sendWords(s:Stream[Bits],w:Watch,data:Vector[BigInt]):Unit = {
      val start=w.count
      while(w.count-start<data.size) step { s.valid #= true; s.payload #= data(w.count-start) }
      step { s.valid #= false }
    }
    def allow:Boolean=continuous || random.nextInt(4)>0
    def ready:Boolean=continuous || (cycle%127>=23 && random.nextInt(5)>0)
    def startPhase(n:String):Long = {
      phase=n; collected.clear(); requests.clear(); deadline=cycle+200000
      cycle
    }
    def save(name:String,data:Seq[BigInt],bits:Int=128):Unit = {
      val f=new PrintWriter(new File(root,s"trial_$trial/$name.actual.hex"))
      try data.foreach(x => f.println("0"*((bits+3)/4-x.toString(16).length)+x.toString(16))) finally f.close()
    }
    def endPhase(start:Long,w:Watch,outputs:Int):Unit = {
      check(w.count==outputs,s"${w.name} count ${w.count} expected=$outputs")
      if(!continuous) check(w.stalls>0,s"${w.name} missing backpressure coverage")
      summary.println(s"$trial,${20261016+trial},$phase,${cycle-start},$outputs,${w.stalls},PASS"); summary.flush()
      println(s"[STAGE PASSED] trial=$trial phase=$phase cycles=${cycle-start} outputs=$outputs stalls=${w.stalls}")
    }
    def driveMerge(s:Stream[ElementAddRunConfig],name:String,g:Int):Unit = {
      val p=mergeParams(name); val cfg=mergeCfg(name)
      s.words #= 64; s.group #= g; s.last_group #= (g==3)
      s.shift #= cfg(0); s.clamp_min #= cfg(1); s.clamp_max #= cfg(2)
      for(l<-0 until 16) {
        s.multiplier_a(l) #= signed(p(0)(g)>>(22*l),22)
        s.multiplier_b(l) #= signed(p(1)(g)>>(22*l),22)
        s.bias_fixed(l) #= signed(p(2)(g)>>(64*l),64)
      }
    }
    // 仿真缓存响应：至少一拍延迟、单在途，数据只来自本次实际输出缓存。
    def runMemory(cat:Boolean,memory:Vector[BigInt],outCount: => Int,total:Int):Unit = {
      var pending:Option[BigInt]=None; var delay=0; var presented=false; var heldLast=0
      val rd=if(cat)catRd else pwRd; val rsp=if(cat)catRsp else pwRsp
      while(outCount<total) {
        val rq=rd.count; val rp=rsp.count
        step {
          if(pending.nonEmpty && delay==0) presented=true
          // Concat 的 valid 由本拍 rsp.valid 组合产生，提前按末返回计数施加反压。
          val lastVisible=if(cat)outCount==total-1 && presented
            else d.io.pw_output_o.valid.toBoolean && d.io.pw_output_o.last.toBoolean
          val forceLast= !continuous && lastVisible && heldLast<9
          if(forceLast) heldLast+=1
          if(cat) {
            d.io.cat_rd_o.ready #= (pending.isEmpty && allow)
            d.io.cat_rsp_i.valid #= presented; d.io.cat_rsp_i.payload #= pending.getOrElse(BigInt(0))
            d.io.cat_output_o.ready #= (!forceLast && ready)
          } else {
            d.io.pw_rd_o.ready #= (pending.isEmpty && allow)
            d.io.pw_rsp_i.valid #= presented; d.io.pw_rsp_i.payload #= pending.getOrElse(BigInt(0))
            d.io.pw_output_o.ready #= (!forceLast && ready)
          }
        }
        if(rsp.count>rp) { pending=None; presented=false }
        if(rd.count>rq) {
          check(pending.isEmpty,"multiple outstanding cache reads")
          val (source,addr)=requests.last
          pending=Some(if(cat) { if(source) encoderSkip(addr-1048589) else memory(addr-65521) } else memory(addr))
          delay=if(continuous)0 else random.nextInt(5)
        } else if(delay>0) delay-=1
      }
      step {
        if(cat) { d.io.cat_rd_o.ready #= false; d.io.cat_rsp_i.valid #= false }
        else { d.io.pw_rd_o.ready #= false; d.io.pw_rsp_i.valid #= false }
      }
      check(pending.isEmpty,"cache response not consumed")
      if(!continuous) check(heldLast==9,"last-beat stall missing")
    }
    def runPw(name:String,cin:Int,memory:Vector[BigInt],raw:Boolean):Vector[BigInt] = {
      val start=startPhase(name); pwCin=cin; pwRaw=raw; phaseOutputs=0
      pwOut.count=0; pwOut.stalls=0; pwDone=0
      pw8=Array.fill[BigInt](256)(0); pw32=Array.fill[BigInt](256)(0); written=Array.fill(256)(0)
      sendCfg(pwCfg) {
        d.io.pw_cfg_i.cin #= cin; d.io.pw_cfg_i.cout #= 64; d.io.pw_cfg_i.pixels #= 64
        d.io.pw_cfg_i.shift #= 24; d.io.pw_cfg_i.raw #= raw; d.io.pw_cfg_i.int16 #= false
      }
      sendWords(d.io.pw_weights_i,pwWeights,params(name)._1)
      sendWords(d.io.pw_params_i,pwParams,params(name)._2)
      sendCfg(pwStart) { d.io.pw_start_i.payload #= true }
      runMemory(false,memory,phaseOutputs,1024)
      step(); step()
      check(written.forall(_==65535) && requests.size==cin/16*64 && pwDone==1,s"$name coverage/cache completion")
      save(name+"_mac",pw32.toVector,512)
      if(!raw) save(name,pw8.toVector)
      endPhase(start,pwOut,1024)
      if(raw)pw32.toVector else pw8.toVector
    }
    d.clockDomain.waitSampling(10)
    for(t<-0 until 3) {
      trial=t; continuous=t==0; random=new Random(20261016+t)
      val directory=new File(root,s"trial_$trial"); directory.mkdirs()
      csv=new PrintWriter(new File(directory,"sim_trace.csv"))
      csv.println("cycle,trial,phase,"+watches.filter(_.trace).flatMap(w=>Seq(w.name+"_valid",w.name+"_ready",w.name+"_payload")).mkString(","))
      watches.foreach { w=>check(w.held.isEmpty,s"unfinished stalled stream ${w.name}"); w.count=0; w.stalls=0 }
      upDone=0; catDone=0; mixDone=0; finalDone=0
      val skipBefore=encoderSkip.map(identity)
      try {
        var start=startPhase("up")
        sendCfg(upCfg) { d.io.up_cfg_i.width #= 4; d.io.up_cfg_i.height #= 4; d.io.up_cfg_i.groups #= 8 }
        var pending=false; var lastHold=0
        while(upOut.count<512) {
          val before=upIn.count
          step {
            if(!pending && upIn.count<128 && allow) pending=true
            d.io.up_input_i.valid #= pending
            if(pending)d.io.up_input_i.payload #= mid(upIn.count)
            val hold= !continuous && d.io.up_output_o.valid.toBoolean && d.io.up_output_o.last.toBoolean && lastHold<9
            if(hold)lastHold+=1
            d.io.up_output_o.ready #= (!hold && ready)
          }
          if(upIn.count>before)pending=false
        }
        step { d.io.up_input_i.valid #= false }; step()
        check(upIn.count==128 && upDone==1,"Upsample completion")
        actualUp=collected.toVector; save("up",actualUp); endPhase(start,upOut,512)

        start=startPhase("concat")
        sendCfg(catCfg) {
          d.io.cat_cfg_i.base1 #= 65521; d.io.cat_cfg_i.base2 #= 1048589
          d.io.cat_cfg_i.words1 #= 512; d.io.cat_cfg_i.words2 #= 256
        }
        runMemory(true,actualUp,collected.size,768); step()
        check(requests.size==768 && catDone==1,"Concat completion")
        actualCat=collected.toVector
        check(actualCat.take(512)==actualUp && actualCat.drop(512)==encoderSkip,"Concat changed source order/skip bytes")
        check(encoderSkip==skipBefore,"encoder skip modified")
        save("concat",actualCat); endPhase(start,catOut,768)

        actualExpand=runPw("expand",192,actualCat,false)
        start=startPhase("cascade"); win3N=0; win5N=0; dw3N=0; dw5N=0
        sendCfg(lb3Cfg) { d.io.lb3_cfg_i.width #= 8; d.io.lb3_cfg_i.height #= 8; d.io.lb3_cfg_i.groups #= 4 }
        sendCfg(lb5Cfg) { d.io.lb5_cfg_i.width #= 8; d.io.lb5_cfg_i.height #= 8; d.io.lb5_cfg_i.groups #= 4 }
        sendCfg(dw3Cfg) { d.io.dw3_cfg_i.groups #= 4; d.io.dw3_cfg_i.raw #= true }
        sendCfg(dw5Cfg) { d.io.dw5_cfg_i.groups #= 4; d.io.dw5_cfg_i.raw #= true }
        sendWords(d.io.dw3_weights_i,dw3W,params("dw3")._1); sendWords(d.io.dw3_params_i,dw3P,params("dw3")._2)
        sendWords(d.io.dw5_weights_i,dw5W,params("dw5")._1); sendWords(d.io.dw5_params_i,dw5P,params("dw5")._2)
        var pending3=false; var pending5=false
        while(mixOut.count<256) {
          val in3=lb3In.count; val in5=lb5In.count
          step {
            if(!pending3 && in3<256 && allow)pending3=true
            if(!pending5 && in5<256 && allow)pending5=true
            d.io.lb3_input_i.valid #= pending3; if(pending3)d.io.lb3_input_i.payload #= actualExpand(in3)
            d.io.lb5_input_i.valid #= pending5; if(pending5)d.io.lb5_input_i.payload #= actualExpand(in5)
            d.io.mix_cfg_i.valid #= (mixCfg.count<4); driveMerge(d.io.mix_cfg_i,"mix",mixCfg.count min 3)
            d.io.mix_output_o.ready #= ready
          }
          if(lb3In.count>in3)pending3=false
          if(lb5In.count>in5)pending5=false
        }
        step { d.io.lb3_input_i.valid #= false; d.io.lb5_input_i.valid #= false; d.io.mix_cfg_i.valid #= false }; step()
        check(Seq(lb3In.count,lb5In.count,win3N,win5N,dw3N,dw5N).forall(_==256) && mixDone==4,"cascade completion")
        actualMix=collected.toVector; save("mix",actualMix); endPhase(start,mixOut,256)
        actualProject=runPw("project",64,actualMix,true)
        actualSkip=runPw("skip",192,actualCat,true)

        start=startPhase("final")
        var pendingA=false; var pendingB=false
        while(finalOut.count<256) {
          val a=finalA.count; val b=finalB.count
          step {
            if(!pendingA && a<256 && allow)pendingA=true
            if(!pendingB && b<256 && allow)pendingB=true
            d.io.final_a_i.valid #= pendingA; if(pendingA)d.io.final_a_i.payload #= actualProject(a)
            d.io.final_b_i.valid #= pendingB; if(pendingB)d.io.final_b_i.payload #= actualSkip(b)
            d.io.final_cfg_i.valid #= (finalCfg.count<4); driveMerge(d.io.final_cfg_i,"out",finalCfg.count min 3)
            d.io.final_output_o.ready #= ready
          }
          if(finalA.count>a)pendingA=false
          if(finalB.count>b)pendingB=false
        }
        step { d.io.final_a_i.valid #= false; d.io.final_b_i.valid #= false; d.io.final_cfg_i.valid #= false }
        for(_<-0 until 6)step()
        check(finalA.count==256 && finalB.count==256 && finalDone==4 && encoderSkip==skipBefore,"final/skip integrity")
        save("d3",collected.toVector); save("encoder_skip_after",encoderSkip)
        endPhase(start,finalOut,256)
        val protocol=new PrintWriter(new File(directory,"protocol.csv"))
        protocol.println("interface,handshakes,stall_cycles")
        try watches.foreach(w=>protocol.println(s"${w.name},${w.count},${w.stalls}")) finally protocol.close()
        println(s"[TB PASSED] trial=$trial seed=${20261016+trial} d3_values=4096 skip_words_intact=256 actual_chain=true")
        trialsPassed+=1
      } finally { csv.close(); csv=null }
    }
    phase="idle"; simSuccess()
  } finally summary.close()
  require(trialsPassed==3)
  println("[TB PASSED] ALL trials=3 stages=21 final_int8_values=12288 actual_chain=true golden_feedback=false")
}
