ThisBuild / scalaVersion := "2.13.14"
val spinalVersion = "1.12.3"
libraryDependencies ++= Seq(
  "com.github.spinalhdl" %% "spinalhdl-core" % spinalVersion,
  "com.github.spinalhdl" %% "spinalhdl-lib" % spinalVersion,
  compilerPlugin("com.github.spinalhdl" %% "spinalhdl-idsl-plugin" % spinalVersion)
)
Compile / run / fork := true
Compile / run / javaOptions ++= Seq("-Xmx3G", "-Djava.io.tmpdir=verification/tmp")
Compile / unmanagedSources ++= Seq(
  baseDirectory.value / "tb/mkdcblocksim.scala",
  baseDirectory.value / "tb/mkdcblocksimfinal.scala"
)
Compile / unmanagedSources ++= Seq(
  baseDirectory.value / "../../../../src/scala/pw/pwmac.scala",
  baseDirectory.value / "../../../../src/scala/line_buffer/linebuffer.scala",
  baseDirectory.value / "../../../../src/scala/dw3x3/dw3x3.scala",
  baseDirectory.value / "../../../../src/scala/dw5x5/dw5x5.scala",
  baseDirectory.value / "../../../../src/scala/element_add/elementadd.scala",
  baseDirectory.value / "../Line_DW_Cascade/tb/linedwcascadesim.scala"
)
