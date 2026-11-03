import spinal.core._

object Dw3x3Gen extends App {
  SpinalConfig(
    targetDirectory = "rtl",
    defaultConfigForClockDomains = ClockDomainConfig(resetKind = ASYNC, resetActiveLevel = LOW)
  ).generateVerilog(new Dw3x3(Dw3x3Config()))
}
