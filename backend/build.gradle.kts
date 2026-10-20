plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.spring)
    alias(libs.plugins.spring.boot)
    alias(libs.plugins.openapi.generator)
}

group = "com.example.todo"
version = "0.1.0"

val contract = layout.projectDirectory.file("../contract/openapi.yaml")
val generatedDir = layout.buildDirectory.dir("generated/openapi")

// Spring controller interfaces and DTOs are generated from the shared contract into build/.
// Controllers implement the generated interfaces, so a contract change that the server doesn't
// follow fails to compile.
openApiGenerate {
    generatorName.set("kotlin-spring")
    inputSpec.set(contract.asFile.absolutePath)
    outputDir.set(generatedDir)
    packageName.set("com.example.todo")
    apiPackage.set("com.example.todo.api")
    modelPackage.set("com.example.todo.api.model")
    generateApiTests.set(false)
    generateModelTests.set(false)
    generateApiDocumentation.set(false)
    generateModelDocumentation.set(false)
    // Only the controller interface and DTOs. The generator's own exception handler would
    // answer errors with plain sendError() instead of RFC 9457 problem documents.
    globalProperties.set(mapOf("apis" to "", "models" to ""))
    configOptions.set(
        mapOf(
            "interfaceOnly" to "true",
            "skipDefaultInterface" to "true",
            "useSpringBoot3" to "true",
            "useTags" to "true",
            "useBeanValidation" to "true",
            "documentationProvider" to "none",
            "annotationLibrary" to "none",
            "serializableModel" to "false",
            "sourceFolder" to "src/main/kotlin",
        ),
    )
}

tasks.openApiGenerate {
    inputs.file(contract)
}

kotlin {
    jvmToolchain(21)
    compilerOptions {
        freeCompilerArgs.add("-Xjsr305=strict")
    }
    sourceSets.main {
        kotlin.srcDir(tasks.openApiGenerate.map { generatedDir.get().dir("src/main/kotlin") })
    }
}

dependencies {
    implementation(platform(libs.spring.boot.dependencies))

    implementation(libs.spring.boot.starter.web)
    implementation(libs.spring.boot.starter.validation)
    implementation(libs.spring.boot.starter.actuator)
    implementation(libs.jackson.module.kotlin)
    implementation(libs.kotlin.reflect)

    testImplementation(libs.spring.boot.starter.test)
    testImplementation(kotlin("test-junit5"))
    testImplementation(libs.swagger.request.validator.mockmvc)
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test {
    useJUnitPlatform()
    // Tests validate real responses against the contract.
    inputs.file(contract).withPropertyName("contract")
    systemProperty("todo.contract", contract.asFile.absolutePath)
}
