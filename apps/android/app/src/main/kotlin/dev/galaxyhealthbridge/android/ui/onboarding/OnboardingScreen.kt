package dev.galaxyhealthbridge.android.ui.onboarding

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.health.connect.client.PermissionController
import androidx.hilt.navigation.compose.hiltViewModel
import dev.galaxyhealthbridge.android.health.connect.HealthConnectReader

@androidx.compose.runtime.Composable
fun OnboardingScreen(
    onDone: () -> Unit,
    vm: OnboardingViewModel = hiltViewModel(),
) {
    val state by vm.state.collectAsState()

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = PermissionController.createRequestPermissionResultContract()
    ) { granted ->
        vm.onPermissionResult(granted)
    }

    Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Galaxy Health Bridge", style = androidx.compose.material3.MaterialTheme.typography.headlineMedium)
        Text("Step 1: Sign up or log in", style = androidx.compose.material3.MaterialTheme.typography.titleMedium)

        OutlinedTextField(
            value = state.email,
            onValueChange = vm::onEmail,
            label = { Text("Email") },
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = state.password,
            onValueChange = vm::onPassword,
            label = { Text("Password (≥12 chars)") },
            modifier = Modifier.fillMaxWidth(),
        )
        Button(onClick = vm::signupOrLogin, enabled = !state.busy) { Text("Continue") }

        if (state.signedIn) {
            Text("Step 2: Health Connect access", style = androidx.compose.material3.MaterialTheme.typography.titleMedium)
            Button(onClick = { permissionLauncher.launch(vm.requiredPermissions) }) {
                Text("Grant Health Connect")
            }
        }

        state.pairCode?.let { code ->
            Text("Step 3: Open iPhone and enter this code", style = androidx.compose.material3.MaterialTheme.typography.titleMedium)
            Text(code, style = androidx.compose.material3.MaterialTheme.typography.displaySmall)
        }

        if (state.hasPermissions && state.signedIn && state.pairCode == null) {
            Button(onClick = vm::generatePairCode) { Text("Generate pair code") }
        }

        state.error?.let { Text(it, color = androidx.compose.ui.graphics.Color.Red) }

        if (state.hasPermissions && state.signedIn) {
            Button(onClick = onDone) { Text("Open dashboard") }
        }
    }
}
