package com.example.todo.web

import com.example.todo.api.model.FieldError as FieldErrorDto
import com.example.todo.domain.InvalidTodoRequestException
import com.example.todo.domain.TodoNotFoundException
import org.slf4j.LoggerFactory
import org.springframework.beans.TypeMismatchException
import org.springframework.http.HttpHeaders
import org.springframework.http.HttpStatus
import org.springframework.http.HttpStatusCode
import org.springframework.http.MediaType
import org.springframework.http.ProblemDetail
import org.springframework.http.ResponseEntity
import org.springframework.http.converter.HttpMessageNotReadableException
import org.springframework.web.bind.MethodArgumentNotValidException
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice
import org.springframework.web.context.request.WebRequest
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler

/**
 * Turns every failure into an RFC 9457 `application/problem+json` document shaped like the
 * contract's `ProblemDetails`: `title` and `status` always, `detail` and `instance` when known,
 * and an `errors` list of `{field, message}` on validation failures.
 */
@RestControllerAdvice
class ProblemExceptionHandler : ResponseEntityExceptionHandler() {

    private val log = LoggerFactory.getLogger(javaClass)

    @ExceptionHandler(TodoNotFoundException::class)
    fun notFound(ex: TodoNotFoundException): ResponseEntity<Any> =
        problem(HttpStatus.NOT_FOUND, ex.message)

    @ExceptionHandler(InvalidTodoRequestException::class)
    fun invalid(ex: InvalidTodoRequestException): ResponseEntity<Any> =
        problem(HttpStatus.BAD_REQUEST, ex.message)

    @ExceptionHandler(Exception::class)
    fun unexpected(ex: Exception): ResponseEntity<Any> {
        log.error("Unhandled exception", ex)
        return problem(HttpStatus.INTERNAL_SERVER_ERROR, "Unexpected server error.")
    }

    override fun handleMethodArgumentNotValid(
        ex: MethodArgumentNotValidException,
        headers: HttpHeaders,
        status: HttpStatusCode,
        request: WebRequest,
    ): ResponseEntity<Any>? {
        val errors = ex.bindingResult.fieldErrors
            .map { FieldErrorDto(field = it.field, message = it.defaultMessage ?: "is invalid") }
        return problem(HttpStatus.BAD_REQUEST, "Request body failed validation against the contract.", errors)
    }

    override fun handleHttpMessageNotReadable(
        ex: HttpMessageNotReadableException,
        headers: HttpHeaders,
        status: HttpStatusCode,
        request: WebRequest,
    ): ResponseEntity<Any>? = problem(HttpStatus.BAD_REQUEST, "Request body is missing or malformed.")

    /** A path id that isn't a UUID can't name an existing todo: the contract documents 404, not 400. */
    override fun handleTypeMismatch(
        ex: TypeMismatchException,
        headers: HttpHeaders,
        status: HttpStatusCode,
        request: WebRequest,
    ): ResponseEntity<Any>? =
        if (ex is MethodArgumentTypeMismatchException && ex.name == "todoId") {
            problem(HttpStatus.NOT_FOUND, "Todo ${ex.value} does not exist.")
        } else {
            problem(HttpStatus.BAD_REQUEST, "Invalid value for '${(ex as? MethodArgumentTypeMismatchException)?.name}'.")
        }

    /** Everything the base class handles (405, 415, 406, ...) also leaves as a problem+json document. */
    override fun handleExceptionInternal(
        ex: Exception,
        body: Any?,
        headers: HttpHeaders,
        statusCode: HttpStatusCode,
        request: WebRequest,
    ): ResponseEntity<Any>? {
        val response = super.handleExceptionInternal(ex, body, headers, statusCode, request) ?: return null
        return ResponseEntity.status(response.statusCode)
            .headers(response.headers)
            .contentType(PROBLEM_JSON)
            .body(response.body)
    }

    private fun problem(status: HttpStatus, detail: String?, errors: List<FieldErrorDto>? = null): ResponseEntity<Any> {
        val body = ProblemDetail.forStatusAndDetail(status, detail)
        body.title = status.reasonPhrase
        // Set explicitly: the content type must not depend on the client's Accept header.
        if (!errors.isNullOrEmpty()) body.setProperty("errors", errors)
        return ResponseEntity.status(status).contentType(PROBLEM_JSON).body(body)
    }

    private companion object {
        val PROBLEM_JSON: MediaType = MediaType.APPLICATION_PROBLEM_JSON
    }
}
