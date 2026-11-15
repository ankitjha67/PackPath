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

        // Align JVM targets across every module. Some older Flutter plugins
        // (e.g. flutter_nearby_connections 1.1.2) pin Java compatibility to 1.8,
        // while under JDK 21 + Kotlin 2.2 the Kotlin compiler defaults to the
        // toolchain (21). Kotlin 2.2 now fails the build on that mismatch instead
        // of warning. Force both Java and Kotlin to 17 everywhere so they agree.
        // Reflection keeps AGP/Kotlin types off the root classpath.
        val java17 = JavaVersion.VERSION_17
        runCatching {
            val compileOptions = androidExt.javaClass.methods
                .firstOrNull { it.name == "getCompileOptions" && it.parameterCount == 0 }
                ?.invoke(androidExt)
            if (compileOptions != null) {
                compileOptions.javaClass.methods
                    .firstOrNull {
                        it.name == "setSourceCompatibility" && it.parameterCount == 1 &&
                            it.parameterTypes[0].isAssignableFrom(JavaVersion::class.java)
                    }
                    ?.invoke(compileOptions, java17)
                compileOptions.javaClass.methods
                    .firstOrNull {
                        it.name == "setTargetCompatibility" && it.parameterCount == 1 &&
                            it.parameterTypes[0].isAssignableFrom(JavaVersion::class.java)
                    }
                    ?.invoke(compileOptions, java17)
            }
        }
        runCatching {
            val kotlinCompileClass =
                Class.forName("org.jetbrains.kotlin.gradle.tasks.KotlinCompile")
            project.tasks.withType(kotlinCompileClass).configureEach { task ->
                val kotlinOptions = task.javaClass.methods
                    .firstOrNull { it.name == "getKotlinOptions" && it.parameterCount == 0 }
                    ?.invoke(task)
                if (kotlinOptions != null) {
                    kotlinOptions.javaClass.methods
                        .firstOrNull {
                            it.name == "setJvmTarget" && it.parameterCount == 1 &&
                                it.parameterTypes[0] == String::class.java
                        }
                        ?.invoke(kotlinOptions, "17")
                }
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
