ThisBuild / scalaVersion := "2.13.14"
val spinalVersion = "1.12.3"
libraryDependencies ++= Seq(
  "com.github.spinalhdl" %% "spinalhdl-core" % spinalVersion,
  "com.github.spinalhdl" %% "spinalhdl-lib" % spinalVersion,
  compilerPlugin("com.github.spinalhdl" %% "spinalhdl-idsl-plugin" % spinalVersion)
)
fork := true
javaOptions += "-Xmx3G"
val decoderRepo = file(sys.env.getOrElse("DECODER_REPO", "../../../.."))
Compile / unmanagedSources ++= Seq(
  "upsample/upsample.scala", "pw/pwmac.scala", "line_buffer/linebuffer.scala",
  "dw3x3/dw3x3.scala", "dw5x5/dw5x5.scala", "element_add/elementadd.scala",
  "decoder_d3/decoderd3harness.scala"
).map(decoderRepo / "src/scala" / _) :+
  (decoderRepo / "sim/standalone/op/decoder_d3/tb/decoderd3sim.scala")
