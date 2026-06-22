package dev.galaxyhealthbridge.android.data.remote

import dev.galaxyhealthbridge.android.domain.model.CanonicalSample
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST

interface GhbApi {
    @POST("/v1/auth/signup")
    suspend fun signup(@Body body: SignupBody): TokenPair

    @POST("/v1/auth/login")
    suspend fun login(@Body body: LoginBody): TokenPair

    @POST("/v1/auth/refresh")
    suspend fun refresh(@Body body: RefreshBody): TokenPair

    @POST("/v1/devices/pair-code")
    suspend fun pairCode(): PairCodeResponse

    @POST("/v1/sync/ingest")
    suspend fun ingest(@Body body: IngestBody): IngestResponse

    @GET("/v1/auth/me")
    suspend fun me(): UserResponse
}

@Serializable data class SignupBody(
    val email: String,
    val password: String,
    @SerialName("install_id") val installId: String,
    @SerialName("device_kind") val deviceKind: String = "android",
    @SerialName("device_label") val deviceLabel: String? = null,
)

@Serializable data class LoginBody(
    val email: String,
    val password: String,
    @SerialName("install_id") val installId: String,
    @SerialName("device_kind") val deviceKind: String = "android",
)

@Serializable data class RefreshBody(@SerialName("refresh_token") val refreshToken: String)

@Serializable data class TokenPair(
    @SerialName("access_token") val accessToken: String,
    @SerialName("refresh_token") val refreshToken: String,
    @SerialName("access_expires_in") val accessExpiresIn: Int,
    @SerialName("refresh_expires_in") val refreshExpiresIn: Int,
)

@Serializable data class PairCodeResponse(val code: String, @SerialName("expires_at") val expiresAt: String)

@Serializable data class IngestBody(val source: String, val samples: List<CanonicalSample>)

@Serializable data class IngestResponse(
    @SerialName("job_id") val jobId: String,
    val accepted: Int,
    val duplicates: Int,
    val rejected: Int,
)

@Serializable data class UserResponse(
    val id: String,
    val email: String,
    val role: String,
)
