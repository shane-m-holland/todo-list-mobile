package com.example.todo.data

import com.example.todo.network.apis.TodosApi
import com.example.todo.network.client.TodoJson
import com.example.todo.network.models.CreateTodo
import com.example.todo.network.models.ProblemDetails
import com.example.todo.network.models.UpdateTodo
import java.io.IOException
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import retrofit2.Response
import com.example.todo.network.models.Todo as TodoDto

class NetworkTodoRepository @Inject constructor(
    private val api: TodosApi,
) : TodoRepository {

    override suspend fun list(): List<Todo> =
        call { api.listTodos() }.map { it.toDomain() }

    override suspend fun create(title: String, notes: String?): Todo =
        call { api.createTodo(CreateTodo(title = title, notes = notes?.takeIf { it.isNotBlank() })) }
            .toDomain()

    override suspend fun update(id: String, title: String?, notes: String?, completed: Boolean?): Todo =
        call { api.updateTodo(id.toUuid(), UpdateTodo(title = title, notes = notes, completed = completed)) }
            .toDomain()

    override suspend fun delete(id: String) {
        call { api.deleteTodo(id.toUuid()) }
    }

    private suspend fun <T> call(block: suspend () -> Response<T>): T {
        val response = try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (e: IOException) {
            throw TodoError.Network(e)
        } catch (e: Exception) {
            throw TodoError.Unexpected(e)
        }
        if (response.isSuccessful) {
            @Suppress("UNCHECKED_CAST")
            return response.body() ?: Unit as T
        }
        throw response.toError()
    }

    private fun Response<*>.toError(): TodoError {
        val problem = errorBody()?.string()?.let {
            runCatching { TodoJson.decodeFromString<ProblemDetails>(it) }.getOrNull()
        }
        val detail = problem?.detail
        return when (code()) {
            400 -> TodoError.Validation(detail, problem?.errors.orEmpty().associate { it.field to it.message })
            404 -> TodoError.NotFound(detail)
            else -> TodoError.Server(code(), detail)
        }
    }
}

private fun String.toUuid(): UUID =
    runCatching { UUID.fromString(this) }.getOrElse { throw TodoError.NotFound("Invalid todo id: $this") }

private fun TodoDto.toDomain() = Todo(
    id = id.toString(),
    title = title,
    notes = notes,
    completed = completed,
    createdAt = createdAt.toInstant(),
    updatedAt = updatedAt.toInstant(),
)
