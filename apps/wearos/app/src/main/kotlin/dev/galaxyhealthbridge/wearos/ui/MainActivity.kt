package dev.galaxyhealthbridge.wearos.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import dev.galaxyhealthbridge.wearos.ble.BleState
import dev.galaxyhealthbridge.wearos.service.SyncService

class MainActivity : ComponentActivity() {

    private val permissions: Array<String> = buildList {
        add(Manifest.permission.BODY_SENSORS)
        add(Manifest.permission.ACTIVITY_RECOGNITION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            add(Manifest.permission.BLUETOOTH_ADVERTISE)
            add(Manifest.permission.BLUETOOTH_CONNECT)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            add(Manifest.permission.POST_NOTIFICATIONS)
        }
    }.toTypedArray()

    private val permLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { results ->
        if (results.values.all { it }) {
            Handler(Looper.getMainLooper()).postDelayed({ startSync() }, 250)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MainScreen(onStart = ::ensurePermissionsThenStart, onStop = ::stopSync)
        }
        Handler(Looper.getMainLooper()).postDelayed({ ensurePermissionsThenStart() }, 300)
    }

    private fun ensurePermissionsThenStart() {
        val missing = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) startSync() else permLauncher.launch(missing.toTypedArray())
    }

    private fun startSync() {
        ContextCompat.startForegroundService(
            this,
            Intent(this, SyncService::class.java).setAction(SyncService.ACTION_START),
        )
    }

    private fun stopSync() {
        startService(Intent(this, SyncService::class.java).setAction(SyncService.ACTION_STOP))
    }
}

@Composable
private fun MainScreen(onStart: () -> Unit, onStop: () -> Unit) {
    val status by BleState.status.collectAsState()
    val steps by BleState.stepsThisSession.collectAsState()
    val hr by BleState.lastHrBpm.collectAsState()
    val warning by BleState.sensorWarning.collectAsState()
    val running = status != "Idle" && !status.startsWith("ERR")

    MaterialTheme {
        Scaffold(
            timeText = { TimeText() },
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.radialGradient(
                            colors = listOf(
                                Color(0xFF1A1230),
                                Color(0xFF0A0410),
                            ),
                        ),
                    ),
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 14.dp, vertical = 24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text(
                        "HealthBridge",
                        color = Color(0xFFE5D6FF),
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 14.sp,
                    )
                    Spacer(Modifier.height(10.dp))

                    Row(verticalAlignment = Alignment.CenterVertically) {
                        StatChip(
                            icon = { PulseHeart() },
                            value = hr?.toString() ?: "--",
                            unit = "bpm",
                            tint = Color(0xFFFF5C7A),
                        )
                        Spacer(Modifier.width(8.dp))
                        StatChip(
                            icon = {
                                Icon(
                                    Icons.Filled.DirectionsRun,
                                    contentDescription = null,
                                    tint = Color(0xFF7CFFB2),
                                    modifier = Modifier.size(14.dp),
                                )
                            },
                            value = steps.toString(),
                            unit = "steps",
                            tint = Color(0xFF7CFFB2),
                        )
                    }

                    Spacer(Modifier.height(10.dp))

                    Text(
                        status,
                        color = if (running) Color(0xFF7CFFB2) else Color(0xFFB0A8C0),
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Medium,
                    )

                    warning?.let {
                        Spacer(Modifier.height(4.dp))
                        Text(
                            it,
                            color = Color(0xFFFFD66B),
                            fontSize = 9.sp,
                        )
                    }

                    Spacer(Modifier.height(12.dp))

                    Button(
                        onClick = { if (running) onStop() else onStart() },
                        colors = ButtonDefaults.primaryButtonColors(
                            backgroundColor = if (running) Color(0xFF4A2A3A) else Color(0xFF6E3CFF),
                        ),
                        modifier = Modifier.size(48.dp),
                    ) {
                        Icon(
                            imageVector = if (running) Icons.Filled.Stop else Icons.Filled.PlayArrow,
                            contentDescription = if (running) "Stop" else "Start",
                            tint = Color.White,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun StatChip(
    icon: @Composable () -> Unit,
    value: String,
    unit: String,
    tint: Color,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .clip(RoundedCornerShape(12.dp))
            .background(Color(0x33000000))
            .padding(horizontal = 8.dp, vertical = 6.dp),
    ) {
        Box(
            modifier = Modifier
                .size(20.dp)
                .clip(CircleShape)
                .background(tint.copy(alpha = 0.2f)),
            contentAlignment = Alignment.Center,
        ) { icon() }
        Spacer(Modifier.width(6.dp))
        Column {
            Text(value, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold)
            Text(unit, color = Color(0xFF9B92AD), fontSize = 8.sp)
        }
    }
}

@Composable
private fun PulseHeart() {
    Icon(
        Icons.Filled.Favorite,
        contentDescription = null,
        tint = Color(0xFFFF5C7A),
        modifier = Modifier.size(14.dp),
    )
}
