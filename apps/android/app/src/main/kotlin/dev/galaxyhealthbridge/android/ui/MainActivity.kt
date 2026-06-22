package dev.galaxyhealthbridge.android.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import dagger.hilt.android.AndroidEntryPoint
import dev.galaxyhealthbridge.android.ui.dashboard.DashboardScreen
import dev.galaxyhealthbridge.android.ui.onboarding.OnboardingScreen

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface {
                    val nav = rememberNavController()
                    NavHost(navController = nav, startDestination = "onboarding") {
                        composable("onboarding") { OnboardingScreen(onDone = { nav.navigate("dashboard") }) }
                        composable("dashboard")  { DashboardScreen() }
                    }
                }
            }
        }
    }
}
