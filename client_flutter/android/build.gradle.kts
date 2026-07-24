allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    val configureNamespace = {
        if (plugins.hasPlugin("com.android.library")) {
            val androidExt = extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
            if (androidExt != null && androidExt.namespace == null) {
                val manifestFile = file("src/main/AndroidManifest.xml")
                var pkgName = "com.plugin.${project.name.replace('-', '_')}"
                if (manifestFile.exists()) {
                    val content = manifestFile.readText()
                    val match = Regex("""package="([^"]+)"""").find(content)
                    if (match != null) {
                        pkgName = match.groupValues[1]
                        manifestFile.writeText(content.replace(Regex("""package="[^"]*""""), ""))
                    }
                }
                androidExt.namespace = pkgName
            }
        }
    }
    if (state.executed) {
        configureNamespace()
    } else {
        afterEvaluate { configureNamespace() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
