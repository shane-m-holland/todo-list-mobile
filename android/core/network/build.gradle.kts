// Retrofit client and models generated from the shared OpenAPI contract.
// Generated sources live under build/ and are never committed.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.openapi.generator)
}

val contract = rootProject.layout.projectDirectory.file("../contract/openapi.yaml")
val generatedDir = layout.buildDirectory.dir("generated/openapi")

openApiGenerate {
    generatorName.set("kotlin")
    library.set("jvm-retrofit2")
    inputSpec.set(contract.asFile.absolutePath)
    outputDir.set(generatedDir.map { it.asFile.absolutePath })
    packageName.set("com.example.todo.network")
    generateApiTests.set(false)
    generateModelTests.set(false)
    generateApiDocumentation.set(false)
    generateModelDocumentation.set(false)
    configOptions.set(
        mapOf(
            "serializationLibrary" to "kotlinx_serialization",
            "useCoroutines" to "true",
            "dateLibrary" to "java8",
            "omitGradleWrapper" to "true",
            "omitGradlePluginVersions" to "true",
            "sourceFolder" to "src/main/kotlin",
        ),
    )
}

// Re-generate whenever the contract changes.
tasks.openApiGenerate {
    inputs.file(contract)
}

kotlin {
    jvmToolchain(17)
    sourceSets.main {
        kotlin.srcDir(tasks.openApiGenerate.map { generatedDir.get().dir("src/main/kotlin") })
    }
}

dependencies {
    api(libs.retrofit)
    api(libs.okhttp)
    api(libs.kotlinx.serialization.json)
    implementation(libs.retrofit.converter.kotlinx.serialization)
    implementation(libs.retrofit.converter.scalars)
    implementation(libs.okhttp.logging.interceptor)
}

dependencies {
    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
}
