import spinal.core._

object Dw5x5Gen extends App {
  SpinalConfig(
    targetDirectory = "rtl",
    defaultConfigForClockDomains = ClockDomainConfig(resetKind = ASYNC, resetActiveLevel = LOW)
  ).generateVerilog(new Dw5x5(Dw5x5Config()))
}
