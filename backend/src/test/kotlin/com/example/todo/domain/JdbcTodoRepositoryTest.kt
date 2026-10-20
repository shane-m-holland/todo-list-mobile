package com.example.todo.domain

import com.example.todo.testsupport.PostgresTestConfig
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.condition.EnabledIf
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.context.annotation.Import
import org.springframework.dao.DataIntegrityViolationException
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.test.context.ActiveProfiles

/** The shared repository behavior, plus what only a real database can enforce. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE, properties = ["todo.seed.enabled=false"])
@ActiveProfiles("postgres")
@Import(PostgresTestConfig::class)
@EnabledIf("com.example.todo.testsupport.SharedPostgres#dockerAvailable", disabledReason = "no container runtime")
class JdbcTodoRepositoryTest : AbstractTodoRepositoryTest() {

    @Autowired lateinit var jdbcRepository: JdbcTodoRepository
    @Autowired lateinit var jdbc: JdbcTemplate

    override val repository: TodoRepository get() = jdbcRepository

    @BeforeEach
    fun clean() = jdbc.execute("TRUNCATE TABLE todos")

    @Test
    fun `flyway applied the schema`() {
        val version = jdbc.queryForObject(
            "SELECT version FROM flyway_schema_history WHERE success ORDER BY installed_rank DESC LIMIT 1",
            String::class.java,
        )
        assertEquals("1", version)
    }

    @Test
    fun `the database refuses blank titles and empty notes`() {
        assertFailsWith<DataIntegrityViolationException> { repository.insert(todo(title = "   ")) }
        assertFailsWith<DataIntegrityViolationException> { repository.insert(todo(notes = "")) }
        assertFailsWith<DataIntegrityViolationException> { repository.insert(todo(title = "x".repeat(201))) }
    }

    @Test
    fun `timestamps keep millisecond precision`() {
        val at = Instant.parse("2026-10-20T14:00:00.123Z")
        val stored = repository.insert(todo(at = at))

        assertEquals(at, repository.findById(stored.id)?.createdAt)
    }

    @Test
    fun `ids are stored as native uuids`() {
        val stored = repository.insert(todo())

        val type = jdbc.queryForObject(
            "SELECT data_type FROM information_schema.columns WHERE table_name = 'todos' AND column_name = 'id'",
            String::class.java,
        )
        assertEquals("uuid", type)
        assertEquals(stored.id, jdbc.queryForObject("SELECT id FROM todos", UUID::class.java))
    }
}
