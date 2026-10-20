package com.example.todo.testsupport

import org.springframework.boot.test.context.TestConfiguration
import org.springframework.boot.testcontainers.service.connection.ServiceConnection
import org.springframework.context.annotation.Bean
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.PostgreSQLContainer

/** One PostgreSQL container for the whole test run, shared by every Spring context that needs it. */
object SharedPostgres {
    val container: PostgreSQLContainer<*> by lazy {
        PostgreSQLContainer("postgres:17-alpine").also { it.start() }
    }

    /** Postgres tests are skipped, not failed, on a machine with no container runtime. */
    @JvmStatic
    fun dockerAvailable(): Boolean = DockerClientFactory.instance().isDockerAvailable
}

/** Points the `postgres` profile's DataSource at the shared container (via `@ServiceConnection`). */
@TestConfiguration(proxyBeanMethods = false)
class PostgresTestConfig {
    @Bean
    @ServiceConnection
    fun postgres(): PostgreSQLContainer<*> = SharedPostgres.container
}
