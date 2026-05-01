pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "tts_reader"
include(":app")
include(":sherpa_onnx")

project(":sherpa_onnx").projectDir =
    file("third_party/sherpa-onnx/android/SherpaOnnxAar/sherpa_onnx")
