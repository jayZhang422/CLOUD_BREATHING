ThisBuild / scalaVersion := "2.13.14"

val spinalVersion = "1.12.3"

libraryDependencies ++= Seq(
  "com.github.spinalhdl" %% "spinalhdl-core" % spinalVersion,
  "com.github.spinalhdl" %% "spinalhdl-lib" % spinalVersion,
  compilerPlugin("com.github.spinalhdl" %% "spinalhdl-idsl-plugin" % spinalVersion)
)

fork := true
javaOptions += "-Xmx2G"

Compile / unmanagedSources ++= Seq(
  baseDirectory.value / "tb/dwjoinsim.scala",
  baseDirectory.value / "../../../../src/scala/dw3x3/dw3x3.scala",
  baseDirectory.value / "../../../../src/scala/dw5x5/dw5x5.scala",
  baseDirectory.value / "../../../../src/scala/element_add/elementadd.scala"
)
