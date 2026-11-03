// 文件类型：.scala。生成 P=16 部署用可综合 Verilog。
import spinal.core._

object ElementAddGen extends App {
  SpinalConfig(
    targetDirectory = ".",
    defaultConfigForClockDomains = ClockDomainConfig(resetKind = ASYNC, resetActiveLevel = LOW)
  ).generateVerilog {
    val dut = new ElementAdd(ElementAddConfig())
    dut.setDefinitionName("ElementAdd_p16")
    dut
  }
}
