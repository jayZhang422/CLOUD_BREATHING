ThisBuild / scalaVersion := "2.13.14"

val spinalVersion = "1.12.3"

libraryDependencies ++= Seq(
  "com.github.spinalhdl" %% "spinalhdl-core" % spinalVersion,
  "com.github.spinalhdl" %% "spinalhdl-lib"  % spinalVersion,
  compilerPlugin(
    "com.github.spinalhdl" %% "spinalhdl-idsl-plugin" % spinalVersion
  )
)

fork := true
javaOptions += "-Xmx2G"

Compile / unmanagedSources ++= Seq(
  baseDirectory.value / "tb/maxpoolsim.scala",
  baseDirectory.value / "../../../../src/scala/maxpool/maxpool2d.scala",
  baseDirectory.value / "../../../../src/scala/maxpool/maxpoolgen.scala"
)
