package dev.galaxyhealthbridge.android.ui.onboarding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.galaxyhealthbridge.android.data.local.AuthStore
import dev.galaxyhealthbridge.android.data.remote.GhbApi
import dev.galaxyhealthbridge.android.data.remote.LoginBody
import dev.galaxyhealthbridge.android.data.remote.SignupBody
import dev.galaxyhealthbridge.android.health.connect.HealthConnectReader
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class OnboardingState(
    val email: String = "",
    val password: String = "",
    val busy: Boolean = false,
    val signedIn: Boolean = false,
    val hasPermissions: Boolean = false,
    val pairCode: String? = null,
    val error: String? = null,
)

@HiltViewModel
class OnboardingViewModel @Inject constructor(
    private val api: GhbApi,
    private val authStore: AuthStore,
    private val reader: HealthConnectReader,
) : ViewModel() {

    private val _state = MutableStateFlow(OnboardingState())
    val state: StateFlow<OnboardingState> = _state

    val requiredPermissions: Set<String> = reader.requiredPermissions

    fun onEmail(s: String)    = _state.update { it.copy(email = s) }
    fun onPassword(s: String) = _state.update { it.copy(password = s) }

    fun signupOrLogin() {
        val s = _state.value
        if (s.email.isBlank() || s.password.length < 12) {
            _state.update { it.copy(error = "Email + 12+ char password required") }
            return
        }
        _state.update { it.copy(busy = true, error = null) }
        viewModelScope.launch {
            try {
                val installId = authStore.installId()
                val pair = runCatching {
                    api.signup(SignupBody(s.email, s.password, installId))
                }.recoverCatching {
                    api.login(LoginBody(s.email, s.password, installId))
                }.getOrThrow()
                authStore.setTokens(pair.accessToken, pair.refreshToken)
                _state.update { it.copy(busy = false, signedIn = true) }
            } catch (e: Throwable) {
                _state.update { it.copy(busy = false, error = e.message) }
            }
        }
    }

    fun onPermissionResult(granted: Set<String>) {
        _state.update { it.copy(hasPermissions = granted.containsAll(requiredPermissions)) }
    }

    fun generatePairCode() {
        viewModelScope.launch {
            try {
                val r = api.pairCode()
                _state.update { it.copy(pairCode = r.code) }
            } catch (e: Throwable) {
                _state.update { it.copy(error = e.message) }
            }
        }
    }
}
