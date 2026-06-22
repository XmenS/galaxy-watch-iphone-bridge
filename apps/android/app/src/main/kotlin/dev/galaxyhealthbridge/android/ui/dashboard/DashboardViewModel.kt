package dev.galaxyhealthbridge.android.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.galaxyhealthbridge.android.data.repository.SyncRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class DashboardState(
    val busy: Boolean = false,
    val lastResult: String? = null,
    val totalUploaded: Int = 0,
    val totalDuplicates: Int = 0,
    val error: String? = null,
)

@HiltViewModel
class DashboardViewModel @Inject constructor(
    private val repo: SyncRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(DashboardState())
    val state: StateFlow<DashboardState> = _state

    fun syncNow() {
        _state.update { it.copy(busy = true, error = null) }
        viewModelScope.launch {
            try {
                val o = repo.runOnce()
                _state.update {
                    it.copy(
                        busy = false,
                        lastResult = "uploaded ${o.uploaded}, dupes ${o.duplicates}",
                        totalUploaded = it.totalUploaded + o.uploaded,
                        totalDuplicates = it.totalDuplicates + o.duplicates,
                    )
                }
            } catch (e: Throwable) {
                _state.update { it.copy(busy = false, error = e.message) }
            }
        }
    }
}
