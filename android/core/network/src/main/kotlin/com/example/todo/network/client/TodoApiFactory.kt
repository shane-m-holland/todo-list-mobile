package com.example.todo.network.client

import com.example.todo.network.apis.TodosApi
import com.example.todo.network.infrastructure.Serializer
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory

/**
 * JSON configuration for the ToDo API.
 *
 * Reuses the generated contextual adapters (UUID, OffsetDateTime), but unlike the generated
 * `Serializer.kotlinxSerializationJson` it omits null and default-valued properties. The contract
 * treats an absent PATCH field as "unchanged" and rejects explicit nulls.
 */
val TodoJson: Json = Json {
    serializersModule = Serializer.kotlinxSerializationAdapters
    ignoreUnknownKeys = true
    encodeDefaults = false
    explicitNulls = false
}

object TodoApiFactory {
    /** [baseUrl] must include the API version prefix and end with `/`, e.g. `http://10.0.2.2:8080/api/v1/`. */
    fun create(baseUrl: String, client: OkHttpClient): TodosApi =
        Retrofit.Builder()
            .baseUrl(baseUrl)
            .client(client)
            .addConverterFactory(TodoJson.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(TodosApi::class.java)
}
