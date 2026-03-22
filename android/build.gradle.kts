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
    afterEvaluate {
        val project = this
        if (project.hasProperty("android")) {
            val android = project.extensions.findByName("android")
            if (android != null) {
                try {
                    // Force compileSdkVersion to 35 to resolve androidx.core:core-ktx:1.15.0 requirement
                    val setCompileSdk = android.javaClass.getMethod("setCompileSdkVersion", Int::class.java)
                    setCompileSdk.invoke(android, 35)
                } catch (e: Exception) {
                    try {
                        val setCompileSdkStr = android.javaClass.getMethod("setCompileSdkVersion", String::class.java)
                        setCompileSdkStr.invoke(android, "android-35")
                    } catch (e2: Exception) {}
                }

                try {
                    val getNamespace = android.javaClass.getMethod("getNamespace")
                    val currentNamespace = getNamespace.invoke(android)
                    if (currentNamespace == null) {
                        val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                        
                        // Parse AndroidManifest.xml if it exists to preserve precise legacy package name
                        var packageName = project.group.toString()
                        val manifestFile = project.file("src/main/AndroidManifest.xml")
                        if (manifestFile.exists()) {
                            val manifestContent = manifestFile.readText()
                            val packageRegex = Regex("""package="([^"]*)"""")
                            val matchResult = packageRegex.find(manifestContent)
                            if (matchResult != null) {
                                packageName = matchResult.groupValues[1]
                            }
                        }
                        
                        setNamespace.invoke(android, packageName)
                    }
                } catch (e: Exception) {
                    // Ignore
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
