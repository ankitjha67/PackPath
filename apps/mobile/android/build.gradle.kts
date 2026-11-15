allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // AGP 8+ requires every Android module to declare a `namespace`. Some older
    // Flutter plugins (e.g. flutter_nearby_connections 1.1.2) predate that and
    // omit it, failing configuration under AGP 8.11. Inject the namespace from
    // the module's Gradle group (which matches its legacy AndroidManifest
    // package) when missing. Registered here — before the evaluationDependsOn
    // block below eagerly evaluates :app — and via reflection so no AGP types
    // are needed on the root classpath.
    afterEvaluate {
        val androidExt = project.extensions.findByName("android") ?: return@afterEvaluate
        val current = runCatching {
            androidExt.javaClass.methods
                .firstOrNull { it.name == "getNamespace" && it.parameterCount == 0 }
                ?.invoke(androidExt) as? String
        }.getOrNull()
        if (current.isNullOrEmpty()) {
            val group = project.group.toString()
            if (group.isNotEmpty()) {
                androidExt.javaClass.methods
                    .firstOrNull { it.name == "setNamespace" && it.parameterCount == 1 }
                    ?.invoke(androidExt, group)
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
