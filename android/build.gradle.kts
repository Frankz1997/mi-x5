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
    // Keep the widget's broad transitive ranges compatible with this Flutter SDK.
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "androidx.work") useVersion("2.9.1")
            if (requested.group == "androidx.glance") useVersion("1.1.1")
            if (requested.group == "org.jetbrains.kotlinx" && requested.name.startsWith("kotlinx-coroutines")) useVersion("1.7.3")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
