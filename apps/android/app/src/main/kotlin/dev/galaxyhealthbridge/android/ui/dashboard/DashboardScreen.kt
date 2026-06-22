package dev.galaxyhealthbridge.android.ui.dashboard

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

@Composable
fun DashboardScreen(vm: DashboardViewModel = hiltViewModel()) {
    val state by vm.state.collectAsState()
    Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Dashboard", style = MaterialTheme.typography.headlineMedium)
        Text("Last upload: ${state.lastResult ?: "—"}")
        Text("Total uploaded (session): ${state.totalUploaded}")
        Text("Total duplicates: ${state.totalDuplicates}")
        Button(onClick = vm::syncNow, modifier = Modifier.fillMaxWidth()) {
            Text(if (state.busy) "Syncing…" else "Sync now")
        }
        state.error?.let { Text("Error: $it", color = androidx.compose.ui.graphics.Color.Red) }
    }
}
