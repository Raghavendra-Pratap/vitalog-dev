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
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Plugins (file_picker, health, …) often pin compileSdk 34; Health Connect needs ≥35.
fun Project.forceCompileSdk36() {
    val android = extensions.findByName("android") ?: return
    try {
        android.javaClass.getMethod("setCompileSdk", Int::class.javaPrimitiveType).invoke(android, 36)
    } catch (_: Exception) {
        try {
            android.javaClass.getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType).invoke(android, 36)
        } catch (_: Exception) {
        }
    }
}

subprojects {
    pluginManager.withPlugin("com.android.library") {
        forceCompileSdk36()
    }
    // evaluationDependsOn(":app") may already have evaluated some projects.
    if (state.executed) {
        forceCompileSdk36()
    } else {
        afterEvaluate { forceCompileSdk36() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
