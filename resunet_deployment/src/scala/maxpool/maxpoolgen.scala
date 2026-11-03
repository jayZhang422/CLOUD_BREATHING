// 文件类型：.scala。生成 P=16、运行时尺寸/组数的 MaxPool2d Verilog。
import spinal.core._

object MaxPoolGen extends App {
  SpinalConfig(
    targetDirectory = ".",
    defaultConfigForClockDomains = ClockDomainConfig(resetKind = ASYNC, resetActiveLevel = LOW)
  ).generateVerilog {
    val dut = new MaxPool2d(MaxPoolConfig())
    dut.setDefinitionName("MaxPool2d_512x512_c16")
    dut
  }
}
