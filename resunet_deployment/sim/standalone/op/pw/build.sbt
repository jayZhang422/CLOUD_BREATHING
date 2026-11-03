ThisBuild / scalaVersion := "2.13.14"
val spinalVersion = "1.12.3"
libraryDependencies ++= Seq(
  "com.github.spinalhdl" %% "spinalhdl-core" % spinalVersion,
  "com.github.spinalhdl" %% "spinalhdl-lib" % spinalVersion,
  compilerPlugin("com.github.spinalhdl" %% "spinalhdl-idsl-plugin" % spinalVersion)
)
Compile / unmanagedSourceDirectories += baseDirectory.value / "sim"
Compile / unmanagedSources += baseDirectory.value / "../../../../src/scala/pw/pwmac.scala"
fork := true
javaOptions ++= Seq("-Xmx3G", s"-Djava.io.tmpdir=${(baseDirectory.value / "verification/tmp").getAbsolutePath}")
javaOptions ++= sys.props.get("pw.verification.dir").toSeq.map(v => s"-Dpw.verification.dir=$v")
javaOptions ++= sys.props.get("pw.case.filter").toSeq.map(v => s"-Dpw.case.filter=$v")
