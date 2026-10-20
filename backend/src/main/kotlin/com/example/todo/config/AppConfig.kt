package com.example.todo.config

import com.example.todo.api.TodosApi
import com.example.todo.domain.TodoService
import java.time.Clock
import org.springframework.beans.factory.annotation.Value
import org.springframework.boot.ApplicationRunner
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.web.servlet.config.annotation.PathMatchConfigurer
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer

/** The contract's `servers` URL ends in `/api/v1`, but its paths (and so the generated mappings) don't. */
const val API_BASE_PATH = "/api/v1"

@Configuration
class AppConfig : WebMvcConfigurer {

    override fun configurePathMatch(configurer: PathMatchConfigurer) {
        configurer.addPathPrefix(API_BASE_PATH) { TodosApi::class.java.isAssignableFrom(it) }
    }

    @Bean
    fun clock(): Clock = Clock.systemUTC()

    /** Same sample data as the WireMock mock's seed script, added only to an empty store. */
    @Bean
    @ConditionalOnProperty("todo.seed.enabled", havingValue = "true")
    fun seedTodos(service: TodoService) = ApplicationRunner {
        if (service.list().isNotEmpty()) return@ApplicationRunner
        service.create("Buy groceries", "Milk, eggs, coffee")
        service.create("Book dentist appointment", null)
        val passport = service.create("Renew passport", "Photos are in the desk drawer")
        service.update(passport.id, title = null, notes = null, completed = true)
    }
}
