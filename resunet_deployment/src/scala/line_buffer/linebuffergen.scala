// 文件类型：.scala。生成 P=16、最大 512×512、运行时尺寸/分组的 3×3/5×5 Verilog。
import spinal.core._

object LineBufferGen extends App {
  for (k <- Seq(3, 5)) {
    SpinalConfig(
      targetDirectory = ".",
      defaultConfigForClockDomains = ClockDomainConfig(resetKind = ASYNC, resetActiveLevel = LOW)
    ).generateVerilog {
      val dut = new LineBuffer(LineBufferConfig(k = k))
      dut.setDefinitionName(s"LineBuffer_${k}x${k}")
      dut
    }
  }
}
