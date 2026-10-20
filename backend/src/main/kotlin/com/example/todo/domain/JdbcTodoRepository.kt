package com.example.todo.domain

import java.sql.ResultSet
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID
import org.springframework.context.annotation.Profile
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository
import org.springframework.transaction.annotation.Transactional

/** PostgreSQL storage. The schema lives in `db/migration` and is applied by Flyway. */
@Repository
@Profile("postgres")
class JdbcTodoRepository(private val jdbc: JdbcClient) : TodoRepository {

    override fun findAll(): List<Todo> =
        jdbc.sql("SELECT $COLUMNS FROM todos ORDER BY created_at, seq")
            .query(::toTodo)
            .list()

    override fun findById(id: UUID): Todo? =
        jdbc.sql("SELECT $COLUMNS FROM todos WHERE id = :id")
            .param("id", id)
            .query(::toTodo)
            .optional()
            .orElse(null)

    override fun insert(todo: Todo): Todo {
        jdbc.sql(
            """
            INSERT INTO todos (id, title, notes, completed, created_at, updated_at)
            VALUES (:id, :title, :notes, :completed, :createdAt, :updatedAt)
            """,
        )
            .param("id", todo.id)
            .param("title", todo.title)
            .param("notes", todo.notes)
            .param("completed", todo.completed)
            .param("createdAt", todo.createdAt.toOffsetDateTime())
            .param("updatedAt", todo.updatedAt.toOffsetDateTime())
            .update()
        return todo
    }

    /** Locks the row for the read-modify-write, so concurrent updates apply one after another. */
    @Transactional
    override fun update(id: UUID, transform: (Todo) -> Todo): Todo? {
        val current = jdbc.sql("SELECT $COLUMNS FROM todos WHERE id = :id FOR UPDATE")
            .param("id", id)
            .query(::toTodo)
            .optional()
            .orElse(null) ?: return null
        val updated = transform(current)
        jdbc.sql(
            """
            UPDATE todos
            SET title = :title, notes = :notes, completed = :completed, updated_at = :updatedAt
            WHERE id = :id
            """,
        )
            .param("id", id)
            .param("title", updated.title)
            .param("notes", updated.notes)
            .param("completed", updated.completed)
            .param("updatedAt", updated.updatedAt.toOffsetDateTime())
            .update()
        return updated
    }

    override fun delete(id: UUID): Boolean =
        jdbc.sql("DELETE FROM todos WHERE id = :id").param("id", id).update() > 0

    private fun toTodo(rs: ResultSet, @Suppress("UNUSED_PARAMETER") row: Int) = Todo(
        id = rs.getObject("id", UUID::class.java),
        title = rs.getString("title"),
        notes = rs.getString("notes"),
        completed = rs.getBoolean("completed"),
        createdAt = rs.getObject("created_at", OffsetDateTime::class.java).toInstant(),
        updatedAt = rs.getObject("updated_at", OffsetDateTime::class.java).toInstant(),
    )

    private fun java.time.Instant.toOffsetDateTime(): OffsetDateTime = atOffset(ZoneOffset.UTC)

    private companion object {
        const val COLUMNS = "id, title, notes, completed, created_at, updated_at"
    }
}
