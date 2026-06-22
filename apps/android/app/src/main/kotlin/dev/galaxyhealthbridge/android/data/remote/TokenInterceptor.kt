package dev.galaxyhealthbridge.android.data.remote

import dev.galaxyhealthbridge.android.data.local.AuthStore
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class TokenInterceptor @Inject constructor(
    private val authStore: AuthStore,
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val req = chain.request()
        // Skip auth for the auth endpoints themselves.
        if (req.url.encodedPath.startsWith("/v1/auth") || req.url.encodedPath.startsWith("/v1/devices/redeem")) {
            return chain.proceed(req)
        }
        val token = runBlocking { authStore.accessToken() } ?: return chain.proceed(req)
        return chain.proceed(req.newBuilder()
            .header("Authorization", "Bearer $token")
            .build())
    }
}
