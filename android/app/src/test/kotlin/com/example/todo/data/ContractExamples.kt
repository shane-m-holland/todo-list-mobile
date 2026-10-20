package com.example.todo.data

import java.io.File
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.snakeyaml.engine.v2.api.Load
import org.snakeyaml.engine.v2.api.LoadSettings

/**
 * Reads `components.examples.<name>.value` from `contract/openapi.yaml` as JSON, so tests exercise
 * the exact payloads the contract documents. The path is passed in by Gradle (`todo.contract`).
 */
object ContractExamples {
    private val examples: Map<*, *> by lazy {
        val path = requireNotNull(System.getProperty("todo.contract")) { "todo.contract system property not set" }
        val spec = Load(LoadSettings.builder().build()).loadFromString(File(path).readText()) as Map<*, *>
        (spec["components"] as Map<*, *>)["examples"] as Map<*, *>
    }

    fun json(name: String): String {
        val example = requireNotNull(examples[name] as? Map<*, *>) { "No example '$name' in contract" }
        return toJson(example["value"]).toString()
    }

    private fun toJson(value: Any?): JsonElement = when (value) {
        null -> JsonNull
        is Map<*, *> -> JsonObject(value.entries.associate { (k, v) -> k.toString() to toJson(v) })
        is List<*> -> JsonArray(value.map(::toJson))
        is Boolean -> JsonPrimitive(value)
        is Number -> JsonPrimitive(value)
        else -> JsonPrimitive(value.toString())
    }
}
