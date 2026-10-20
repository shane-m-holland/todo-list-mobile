package com.example.todo.web

import com.example.todo.testsupport.PostgresTestConfig
import org.junit.jupiter.api.condition.EnabledIf
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.context.annotation.Import
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.test.context.ActiveProfiles

/** The same contract suite against a real PostgreSQL (Testcontainers), with Flyway-built schema. */
@SpringBootTest(properties = ["todo.seed.enabled=false"])
@AutoConfigureMockMvc
@ActiveProfiles("postgres")
@Import(PostgresTestConfig::class)
@EnabledIf("com.example.todo.testsupport.SharedPostgres#dockerAvailable", disabledReason = "no container runtime")
class TodosApiContractPostgresTest : AbstractTodosApiContractTest() {

    @Autowired lateinit var jdbc: JdbcTemplate

    override fun resetStore() = jdbc.execute("TRUNCATE TABLE todos")
}
