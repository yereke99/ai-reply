package kz.yerek.aireply.ai

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.withContext
import java.io.IOException
import java.net.ConnectException
import java.net.HttpURLConnection
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException
import javax.net.ssl.SSLException
import kotlin.coroutines.coroutineContext

/** One generated reply. */
data class GeneratedReply(
    val text: String,
    /**
     * Advisory. The model chooses the language; this only reports what came
     * back, and nothing depends on it being right.
     */
    val detectedLanguage: String? = null
)

/**
 * What a reply source has to be able to do.
 *
 * The keyboard and app depend on this interface while production requests are
 * handled by the authenticated account transport.
 */
interface ReplyTransport {
    suspend fun generate(prompt: ReplyPromptBuilder.Prompt): GeneratedReply
}

/**
 * Shared HTTP plumbing.
 *
 * WHY HttpURLConnection AND NOT OkHttp/Retrofit. This code is loaded inside an
 * input method, where every class loaded is startup cost paid at the moment the
 * user has just switched keyboards and is waiting to see one. The app makes
 * exactly two kinds of POST request and needs no interceptors, no connection
 * pool tuning and no converters. A library here would be several thousand
 * classes to save about forty lines, and the iOS project reaches the same
 * conclusion by using URLSession directly.
 */
object ReplyNetworking {

    /**
     * Executes a JSON POST and returns the status and body.
     *
     * Cancellation is real, not cooperative-only: the connection is disconnected
     * as soon as the calling coroutine is cancelled, which unblocks the socket
     * read rather than leaving a request running for its full 25-second budget
     * after the keyboard has already closed.
     */
    suspend fun postJson(
        url: String,
        body: String,
        headers: Map<String, String>,
        timeoutMs: Int
    ): Pair<Int, String> = withContext(Dispatchers.IO) {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = timeoutMs
            readTimeout = timeoutMs
            doOutput = true
            // Nothing about a private message belongs in a cache.
            useCaches = false
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("Accept", "application/json")
            headers.forEach { (name, value) -> setRequestProperty(name, value) }
        }

        val disconnectOnCancel = coroutineContext[Job]?.invokeOnCompletion { cause ->
            if (cause != null) runCatching { connection.disconnect() }
        }

        try {
            connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }

            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
            status to text
        } finally {
            disconnectOnCancel?.dispose()
            runCatching { connection.disconnect() }
        }
    }

    /** Maps transport-level failures onto the closed error set. */
    fun mapError(throwable: Throwable): AIReplyError = when (throwable) {
        is CancellationException -> AIReplyError.Cancelled
        is AIReplyException -> throwable.error
        is SocketTimeoutException -> AIReplyError.TimedOut
        is UnknownHostException,
        is ConnectException,
        is NoRouteToHostException -> AIReplyError.Offline
        is SSLException -> AIReplyError.ServiceUnavailable
        is IOException -> AIReplyError.ServiceUnavailable
        else -> AIReplyError.ServiceUnavailable
    }

    /**
     * The status code alone decides what the user is told. The body may quote
     * the prompt back, so it is never read, never logged and never shown.
     */
    fun mapStatus(status: Int): AIReplyError = when (status) {
        401, 403 -> AIReplyError.AuthenticationFailed
        429 -> AIReplyError.RateLimited
        408, 504 -> AIReplyError.TimedOut
        else -> AIReplyError.ServiceUnavailable
    }

    /**
     * Removes a wrapper the model sometimes puts around a one-line answer.
     *
     * Conservative on purpose: only a matched pair enclosing the WHOLE reply is
     * removed, so a quotation inside a real sentence survives untouched.
     */
    fun unwrapQuotes(text: String): String {
        val pairs = listOf('"' to '"', '“' to '”', '«' to '»')
        for ((open, close) in pairs) {
            if (text.length > 2 && text.first() == open && text.last() == close) {
                val inner = text.substring(1, text.length - 1)
                if (!inner.contains(close)) return inner.trim()
            }
        }
        return text
    }
}
