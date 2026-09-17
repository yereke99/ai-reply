package kz.yerek.aireply.data.account

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Owns the token pair and hands out a usable access token.
 *
 * Access токен 15 минут жарамды; ескіргенде бір-ақ рет жаңартылады.
 *
 * WHY THE MUTEX. The app and the keyboard live in one process and can both ask
 * for a token at the same moment. Two parallel refreshes would rotate the
 * refresh token twice, and the server treats the second use of a rotated token
 * as theft and kills the whole session. One lock, one in-flight refresh, and
 * that cannot happen.
 */
class AccountSession(
    private val credentials: AccountCredentials,
    private val baseUrlProvider: () -> String?,
    private val deviceDescriptor: () -> DeviceDescriptor
) {

    private val refreshMutex = Mutex()

    val isSignedIn: Boolean get() = credentials.isSignedIn

    /** A token that is valid right now, refreshing first when needed. */
    suspend fun accessToken(): String {
        credentials.accessToken?.let { token ->
            if (credentials.isAccessTokenFresh) return token
        }
        return refreshAccessToken()
    }

    /** Forces a refresh — used after a 401 on a token we believed was fresh. */
    suspend fun refreshAccessToken(): String = refreshMutex.withLock {
        // Another coroutine may have refreshed while this one waited for the
        // lock; taking its result is both correct and one fewer rotation.
        credentials.accessToken?.let { token ->
            if (credentials.isAccessTokenFresh) return@withLock token
        }

        val baseUrl = baseUrlProvider() ?: ApiError.InvalidRequest.raise()
        val refreshToken = credentials.refreshToken ?: ApiError.Unauthorized.raise()
        val client = ApiClient(baseUrl)

        val payload = client.json.encodeToString(
            RefreshRequest.serializer(),
            RefreshRequest(refreshToken, deviceDescriptor())
        )

        val body = try {
            client.request("POST", "api/v1/auth/refresh", payload)
        } catch (exception: ApiException) {
            // The refresh token is gone, rotated or revoked. Nothing local can
            // fix that, so the session is cleared and the UI asks for sign-in.
            if (exception.error is ApiError.Unauthorized) credentials.clear()
            throw exception
        }

        val tokens = runCatching {
            client.json.decodeFromString(TokenPairDto.serializer(), body)
        }.getOrElse { ApiError.MalformedResponse.raise() }

        credentials.store(tokens.accessToken, tokens.refreshToken, tokens.expiresIn)
        tokens.accessToken
    }

    /** Stores a freshly issued session. */
    fun adopt(session: AccountSessionDto) {
        credentials.store(session.accessToken, session.refreshToken, session.expiresIn)
        if (session.deviceId.isNotEmpty()) credentials.deviceId = session.deviceId
        credentials.displayIdentifier = session.user.identifier
    }

    /**
     * Ends the session. The server call is best effort: the local tokens are
     * dropped either way, so a user on a plane can still sign out.
     */
    suspend fun signOut() {
        val baseUrl = baseUrlProvider()
        val refreshToken = credentials.refreshToken
        credentials.clear()

        if (baseUrl == null || refreshToken == null) return
        val client = ApiClient(baseUrl)
        runCatching {
            client.request(
                "POST", "api/v1/auth/logout",
                client.json.encodeToString(LogoutRequest.serializer(), LogoutRequest(refreshToken))
            )
        }
    }

    /**
     * Runs an authenticated call, refreshing once if the server rejects the
     * token. One retry, never a loop.
     */
    suspend fun <T> authenticated(work: suspend (String) -> T): T {
        val token = accessToken()
        return try {
            work(token)
        } catch (exception: ApiException) {
            if (exception.error !is ApiError.Unauthorized) throw exception
            work(refreshAccessToken())
        }
    }
}
