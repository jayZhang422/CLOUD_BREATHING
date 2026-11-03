// 文件类型：.scala。独立INT64再量化自校验：正负tie、shift=0/62、上下界与反压/复位。
import spinal.core._
import spinal.core.sim._
import java.io.{File, PrintWriter}
import scala.io.Source
import scala.util.Random

object PwRequantSim extends App {
  val root = new File(sys.props.getOrElse("pw.verification.dir", "verification"))
  val source = Source.fromFile(new File(root,"quant_cases.csv"))
  val baseCases = try source.getLines().filter(_.nonEmpty).map(_.trim.split(",").map(BigInt(_))).toVector
    finally source.close()
  val cases=baseCases ++ baseCases.take(32)
  val compiled = SimConfig.withConfig(SpinalConfig(
    defaultConfigForClockDomains=ClockDomainConfig(resetKind=ASYNC,resetActiveLevel=LOW)))
    .withFstWave.workspacePath(new File(root,"quant_workspace").getPath).compile(new PwRequant)
  compiled.doSim("requant_boundaries",20261011) { dut =>
    dut.clockDomain.forkStimulus(10)
    fork { sleep(20000000L); println("[TB FAILED] independent time watchdog"); simFailure("time watchdog") }
    dut.io.input_i.valid #= false
    dut.io.output_o.ready #= false
    dut.io.input_i.tag.pixel #= 0
    dut.io.input_i.tag.group #= 0
    dut.io.input_i.tag.mask #= 15
    dut.io.input_i.tag.first #= true
    dut.io.input_i.tag.finalInput #= true
    dut.io.input_i.tag.tileLast #= false
    dut.io.input_i.tag.last #= false
    dut.io.input_i.raw #= false
    dut.io.input_i.int16 #= true
    dut.io.input_i.shift #= 0
    for(p<-0 until 4) {
      dut.io.input_i.mac(p) #= 0
      dut.io.input_i.multiplier(p) #= 0
      dut.io.input_i.bias(p) #= 0
      dut.io.input_i.lower(p) #= -128
      dut.io.input_i.upper(p) #= 127
    }
    dut.clockDomain.waitSampling(5)
    val csv = new PrintWriter(new File(root,"requant_sim_trace.csv"))
    csv.println("cycle,reset,in_valid,in_ready,shift,acc,mult,bias,out_valid,out_ready,out_pixel,out_mask,out_q0,out_mac0,sent,received")
    var cycles=0
    var sent=0
    var received=0
    var stalls=0
    var held:Option[Vector[BigInt]]=None
    def outputSnapshot:Vector[BigInt] = Vector(dut.io.output_o.pixel.toBigInt,
      dut.io.output_o.group.toBigInt,dut.io.output_o.mask.toBigInt,
      BigInt(if(dut.io.output_o.last.toBoolean)1 else 0),
      BigInt(if(dut.io.output_o.raw.toBoolean)1 else 0)) ++
      (0 until 4).map(dut.io.output_o.q(_).toBigInt) ++ (0 until 4).map(dut.io.output_o.mac(_).toBigInt)
    def check(ok:Boolean,message: => String):Unit = if(!ok) {
      csv.flush()
      println(s"[TB FAILED] REQUANT cycle=$cycles $message")
      simFailure(message)
    }
    dut.clockDomain.onSamplings {
      csv.println(s"$cycles,${dut.clockDomain.isResetAsserted},${dut.io.input_i.valid.toBoolean}," +
        s"${dut.io.input_i.ready.toBoolean},${dut.io.input_i.shift.toInt},${dut.io.input_i.mac(0).toBigInt}," +
        s"${dut.io.input_i.multiplier(0).toBigInt},${dut.io.input_i.bias(0).toBigInt}," +
        s"${dut.io.output_o.valid.toBoolean},${dut.io.output_o.ready.toBoolean},${dut.io.output_o.pixel.toBigInt}," +
        s"${dut.io.output_o.mask.toInt},${dut.io.output_o.q(0).toBigInt},${dut.io.output_o.mac(0).toBigInt},$sent,$received")
      csv.flush()
    }
    def drive(index:Int):Unit = {
      val c=cases(index)
      dut.io.input_i.tag.pixel #= index
      dut.io.input_i.tag.group #= index%32
      dut.io.input_i.tag.mask #= (if(index%7==0)5 else 15)
      dut.io.input_i.tag.last #= (index==cases.size-1)
      dut.io.input_i.raw #= (index>=baseCases.size)
      dut.io.input_i.shift #= c(3)
      for(p<-0 until 4) {
        dut.io.input_i.mac(p) #= c(0)
        dut.io.input_i.multiplier(p) #= c(1)
        dut.io.input_i.bias(p) #= c(2)
        dut.io.input_i.lower(p) #= c(4)
        dut.io.input_i.upper(p) #= c(5)
      }
    }
    val rng=new Random(611)
    try {
      // 先填充并阻塞流水，再异步复位，旧输出必须消失。
      for(i<-0 until 12) {
        dut.clockDomain.waitFallingEdge()
        dut.io.input_i.valid #= true
        drive(i min (cases.size-1))
        dut.io.output_o.ready #= false
        dut.clockDomain.waitRisingEdge(); sleep(1)
      }
      check(dut.io.output_o.valid.toBoolean,"pre-reset pipeline not filled")
      dut.clockDomain.assertReset()
      dut.io.input_i.valid #= false
      dut.clockDomain.waitRisingEdge(3); sleep(1)
      check(!dut.io.output_o.valid.toBoolean,"reset retained stale quant result")
      dut.clockDomain.deassertReset()
      dut.clockDomain.waitSampling(2)
      var pending=false
      var longStall=0
      while(received<cases.size) {
        dut.clockDomain.waitFallingEdge()
        if(!pending && sent<cases.size && rng.nextInt(4)!=0) pending=true
        dut.io.input_i.valid #= pending
        if(pending) drive(sent)
        val ready=if(longStall>0) {longStall-=1;false}
          else if(rng.nextInt(20)==0) {longStall=25;false}
          else rng.nextBoolean()
        dut.io.output_o.ready #= ready
        sleep(1)
        cycles+=1
        val inFire=pending && dut.io.input_i.ready.toBoolean
        val valid=dut.io.output_o.valid.toBoolean
        held.foreach(v=>check(valid && outputSnapshot==v,"requant output changed under backpressure"))
        held=if(valid && !ready) Some(outputSnapshot) else None
        if(valid && !ready) stalls+=1
        if(valid && ready) {
          check(received<sent+(if(inFire)1 else 0),"extra quant output")
          val c=cases(received)
          val mask=if(received%7==0)5 else 15
          check(dut.io.output_o.pixel.toInt==received && dut.io.output_o.group.toInt==received%32 &&
            dut.io.output_o.mask.toInt==mask,"quant tag mismatch")
          check(dut.io.output_o.raw.toBoolean==(received>=baseCases.size) &&
            dut.io.output_o.last.toBoolean==(received==cases.size-1),"quant control mismatch")
          for(p<-0 until 4) {
            val expected=if(received>=baseCases.size || (mask&(1<<p))==0) BigInt(0) else c(6)
            val expectedMac=if((mask&(1<<p))==0) BigInt(0) else c(0)
            check(dut.io.output_o.q(p).toBigInt==expected,
              s"RNE[$received][$p] shift=${c(3)} acc=${c(0)} multiplier=${c(1)} bias=${c(2)} expected=$expected actual=${dut.io.output_o.q(p).toBigInt}")
            check(dut.io.output_o.mac(p).toBigInt==expectedMac,"requant raw MAC changed")
          }
          received+=1
        }
        dut.clockDomain.waitRisingEdge(); sleep(1)
        if(inFire) {sent+=1;pending=false}
        check(cycles<20000,"requant watchdog")
      }
      dut.io.input_i.valid #= false
      dut.io.output_o.ready #= true
      dut.clockDomain.waitSampling(10); sleep(1)
      check(!dut.io.output_o.valid.toBoolean,"extra requant output after drain")
      println(s"[TB PASSED] REQUANT cases=$received numeric_boundaries=${baseCases.size} raw_cases=32 cycles=$cycles outputStalls=$stalls reset=1 signed_RNE=PASS")
    } finally csv.close()
  }
}
