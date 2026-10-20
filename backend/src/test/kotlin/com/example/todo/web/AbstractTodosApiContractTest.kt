package com.example.todo.web

import com.atlassian.oai.validator.OpenApiInteractionValidator
import com.atlassian.oai.validator.whitelist.ValidationErrorsWhitelist
import com.atlassian.oai.validator.mockmvc.OpenApiValidationMatchers.openApi
import java.io.File
import org.hamcrest.Matchers.endsWith
import org.hamcrest.Matchers.hasSize
import org.hamcrest.Matchers.matchesPattern
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.http.MediaType
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.ResultActions
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.content
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.header
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.status

/**
 * Drives the real HTTP stack and checks every request and response against contract/openapi.yaml,
 * so the server cannot drift from the contract the clients and the mock are built on.
 *
 * Runs once per storage backend: see [TodosApiContractMemoryTest] and [TodosApiContractPostgresTest].
 */
abstract class AbstractTodosApiContractTest {

    @Autowired lateinit var mvc: MockMvc

    /** Empties the store the application under test uses. */
    abstract fun resetStore()

    /** Request and response both conform to the contract. */
    private val matchesContract = openApi().isValid(contractValidator)

    /** Only the response is checked: for tests that send an invalid request on purpose. */
    private val responseMatchesContract = openApi().isValid(responseOnlyValidator)

    private companion object {
        val contractUri: String by lazy {
            val path = requireNotNull(System.getProperty("todo.contract")) { "todo.contract system property not set" }
            File(path).toURI().toString()
        }
        val contractValidator: OpenApiInteractionValidator by lazy {
            OpenApiInteractionValidator.createFor(contractUri).build()
        }
        val responseOnlyValidator: OpenApiInteractionValidator by lazy {
            OpenApiInteractionValidator.createFor(contractUri)
                .withWhitelist(
                    ValidationErrorsWhitelist.create().withRule("negative tests send invalid requests on purpose") {
                        message, _, _, _ -> message.key.startsWith("validation.request.")
                    },
                )
                .build()
        }
        const val UNKNOWN_ID = "00000000-0000-0000-0000-000000000000"
    }

    @BeforeEach
    fun reset() = resetStore()

    private fun createTodo(body: String): ResultActions =
        mvc.perform(post("/api/v1/todos").contentType(MediaType.APPLICATION_JSON).content(body))

    private fun createdId(body: String): String {
        val json = createTodo(body).andReturn().response.contentAsString
        return Regex(""""id":"([^"]+)"""").find(json)!!.groupValues[1]
    }

    private fun patchTodo(id: String, body: String): ResultActions =
        mvc.perform(patch("/api/v1/todos/$id").contentType(MediaType.APPLICATION_JSON).content(body))

    @Test
    fun `list is empty at first`() {
        mvc.perform(get("/api/v1/todos"))
            .andExpect(status().isOk)
            .andExpect(jsonPath("$", hasSize<Any>(0)))
            .andExpect(matchesContract)
    }

    @Test
    fun `create returns 201 with location and an open todo`() {
        createTodo("""{"title":"Buy groceries","notes":"Milk, eggs, coffee"}""")
            .andExpect(status().isCreated)
            .andExpect(header().string("Location", matchesPattern(".*/api/v1/todos/[0-9a-f-]{36}")))
            .andExpect(jsonPath("$.title").value("Buy groceries"))
            .andExpect(jsonPath("$.notes").value("Milk, eggs, coffee"))
            .andExpect(jsonPath("$.completed").value(false))
            .andExpect(jsonPath("$.createdAt").value(endsWith("Z")))
            .andExpect(matchesContract)
    }

    @Test
    fun `todos without notes omit the property`() {
        createTodo("""{"title":"No notes"}""")
            .andExpect(status().isCreated)
            .andExpect(jsonPath("$.notes").doesNotExist())
            .andExpect(matchesContract)
    }

    @Test
    fun `list returns todos in creation order`() {
        listOf("one", "two", "three").forEach { createdId("""{"title":"$it"}""") }

        mvc.perform(get("/api/v1/todos"))
            .andExpect(status().isOk)
            .andExpect(jsonPath("$", hasSize<Any>(3)))
            .andExpect(jsonPath("$[0].title").value("one"))
            .andExpect(jsonPath("$[1].title").value("two"))
            .andExpect(jsonPath("$[2].title").value("three"))
            .andExpect(matchesContract)
    }

    @Test
    fun `get returns the todo`() {
        val id = createdId("""{"title":"Find me"}""")

        mvc.perform(get("/api/v1/todos/$id"))
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.id").value(id))
            .andExpect(matchesContract)
    }

    @Test
    fun `patch updates only the given fields`() {
        val id = createdId("""{"title":"Original","notes":"keep me"}""")

        patchTodo(id, """{"completed":true}""")
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.title").value("Original"))
            .andExpect(jsonPath("$.notes").value("keep me"))
            .andExpect(jsonPath("$.completed").value(true))
            .andExpect(matchesContract)
    }

    @Test
    fun `patch with empty notes clears them`() {
        val id = createdId("""{"title":"A","notes":"gone soon"}""")

        patchTodo(id, """{"notes":""}""")
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.notes").doesNotExist())
            .andExpect(matchesContract)
    }

    @Test
    fun `delete returns 204 and the todo is gone`() {
        val id = createdId("""{"title":"Short lived"}""")

        mvc.perform(delete("/api/v1/todos/$id"))
            .andExpect(status().isNoContent)
            .andExpect(matchesContract)
        mvc.perform(get("/api/v1/todos/$id"))
            .andExpect(status().isNotFound)
            .andExpect(matchesContract)
    }

    @Test
    fun `unknown id is a 404 problem for get, patch and delete`() {
        val problem = content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON)

        mvc.perform(get("/api/v1/todos/$UNKNOWN_ID"))
            .andExpect(status().isNotFound).andExpect(problem)
            .andExpect(jsonPath("$.detail").value("Todo $UNKNOWN_ID does not exist."))
            .andExpect(matchesContract)
        patchTodo(UNKNOWN_ID, """{"completed":true}""")
            .andExpect(status().isNotFound).andExpect(problem).andExpect(matchesContract)
        mvc.perform(delete("/api/v1/todos/$UNKNOWN_ID"))
            .andExpect(status().isNotFound).andExpect(problem).andExpect(matchesContract)
    }

    @Test
    fun `an id that is not a uuid is a 404`() {
        mvc.perform(get("/api/v1/todos/not-a-uuid"))
            .andExpect(status().isNotFound)
            .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
    }

    @Test
    fun `blank title is a 400 problem with a field error`() {
        createTodo("""{"title":"   "}""")
            .andExpect(status().isBadRequest)
            .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
            .andExpect(jsonPath("$.errors[0].field").value("title"))
            .andExpect(jsonPath("$.instance").value("/api/v1/todos"))
            .andExpect(responseMatchesContract)
    }

    @Test
    fun `title and notes length limits are enforced`() {
        createTodo("""{"title":"${"x".repeat(200)}"}""").andExpect(status().isCreated)
        createTodo("""{"title":"${"x".repeat(201)}"}""").andExpect(status().isBadRequest)
        createTodo("""{"title":"ok","notes":"${"n".repeat(2001)}"}""").andExpect(status().isBadRequest)
    }

    @Test
    fun `titles with whitespace, newlines and punctuation are valid`() {
        createTodo("""{"title":"  padded \"quoted\" & co\nsecond line  "}""")
            .andExpect(status().isCreated)
            .andExpect(matchesContract)
    }

    @Test
    fun `invalid bodies are 400 problems`() {
        listOf(
            "{}", // missing title
            """{"title":null}""",
            """{"title":"x","unexpected":true}""", // additionalProperties: false
            """{"title":""" + "", // malformed JSON
            "",
        ).forEach { body ->
            createTodo(body)
                .andExpect(status().isBadRequest)
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(responseMatchesContract)
        }
    }

    @Test
    fun `patch with no changes or a blank title is a 400`() {
        val id = createdId("""{"title":"A"}""")

        patchTodo(id, "{}").andExpect(status().isBadRequest).andExpect(responseMatchesContract)
        patchTodo(id, """{"title":"  "}""").andExpect(status().isBadRequest).andExpect(responseMatchesContract)
        patchTodo(id, """{"completed":"yes"}""").andExpect(status().isBadRequest).andExpect(responseMatchesContract)
    }

    @Test
    fun `errors stay problem+json even when the client only accepts application json`() {
        mvc.perform(get("/api/v1/todos/$UNKNOWN_ID").accept(MediaType.APPLICATION_JSON))
            .andExpect(status().isNotFound)
            .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
    }

    @Test
    fun `unsupported methods are problem documents too`() {
        mvc.perform(put("/api/v1/todos"))
            .andExpect(status().isMethodNotAllowed)
            .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
            .andExpect(jsonPath("$.status").value(405))
    }
}
