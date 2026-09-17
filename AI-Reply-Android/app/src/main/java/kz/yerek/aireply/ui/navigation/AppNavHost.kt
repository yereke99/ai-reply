package kz.yerek.aireply.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import kz.yerek.aireply.ui.LocalServices
import kz.yerek.aireply.ui.feature.account.AccountController
import kz.yerek.aireply.ui.feature.account.RegistrationStepScreen
import kz.yerek.aireply.ui.feature.account.SignInScreen
import kz.yerek.aireply.ui.feature.account.SubscriptionScreen
import kz.yerek.aireply.ui.feature.account.VerifyCodeScreen
import kz.yerek.aireply.ui.feature.compose.ComposeScreen
import kz.yerek.aireply.ui.feature.home.HomeScreen
import kz.yerek.aireply.ui.feature.hours.WorkingHoursScreen
import kz.yerek.aireply.ui.feature.onboarding.OnboardingScreen
import kz.yerek.aireply.ui.feature.profile.ProfileScreen
import kz.yerek.aireply.ui.feature.settings.SettingsScreen
import kz.yerek.aireply.ui.feature.setup.KeyboardSetupScreen
import kz.yerek.aireply.ui.feature.templates.TemplateEditorScreen
import kz.yerek.aireply.ui.feature.templates.TemplateListScreen

/**
 * @param deepLink a route the keyboard asked for, pushed on top of Home once
 *   onboarding is done. The "+" chip uses it to open the template editor.
 */
@Composable
fun AppNavHost(deepLink: String? = null) {
    val services = LocalServices.current
    val configuration by services.configuration.configuration.collectAsStateWithLifecycle()
    val navController = rememberNavController()

    // The account gate is transparent unless this build is pointed at our
    // service: a user with their own key never meets a sign-in screen, and an
    // existing install keeps the product it was installed as.
    if (services.aiConfiguration.requiresAccount) {
        val accountState by services.account.state.collectAsStateWithLifecycle()
        var completingRegistration by rememberSaveable { mutableStateOf(false) }

        LaunchedEffect(Unit) { services.account.refresh() }

        when {
            completingRegistration -> {
                RegistrationStepScreen(onFinished = { completingRegistration = false })
                return
            }
            accountState.phase is AccountController.Phase.SignedOut -> {
                SignInScreen()
                return
            }
            accountState.phase is AccountController.Phase.AwaitingCode -> {
                val phase = accountState.phase as AccountController.Phase.AwaitingCode
                VerifyCodeScreen(
                    masked = phase.masked,
                    demoMode = phase.demoMode,
                    onVerified = { isNewUser -> completingRegistration = isNewUser }
                )
                return
            }
        }
    }

    // Onboarding runs once. `hasCompletedOnboarding` lives with the profile, so
    // it survives relaunches, and Settings can put the user back through it
    // without losing a single answer.
    val start = if (configuration.profile.hasCompletedOnboarding) Routes.Home else Routes.Onboarding

    NavHost(navController = navController, startDestination = start) {

        composable(Routes.Onboarding) {
            OnboardingScreen(onFinished = { services.configuration.completeOnboarding() })
        }

        composable(Routes.Home) {
            HomeScreen(
                onOpen = { route -> navController.navigate(route) }
            )
        }

        composable(Routes.Compose) { ComposeScreen(onBack = navController::popBackStack) }
        composable(Routes.Profile) { ProfileScreen(onBack = navController::popBackStack) }
        composable(Routes.WorkingHours) { WorkingHoursScreen(onBack = navController::popBackStack) }
        composable(Routes.KeyboardSetup) { KeyboardSetupScreen(onBack = navController::popBackStack) }
        composable(Routes.Subscription) { SubscriptionScreen(onBack = navController::popBackStack) }

        composable(Routes.Templates) {
            TemplateListScreen(
                onBack = navController::popBackStack,
                onEdit = { id -> navController.navigate(Routes.templateEditor(id)) }
            )
        }

        composable(Routes.TemplateEditorPattern) { entry ->
            val id = entry.arguments?.getString(Routes.TemplateEditorArg).orEmpty()
            TemplateEditorScreen(templateId = id, onBack = navController::popBackStack)
        }

        composable(Routes.Settings) {
            SettingsScreen(
                onBack = navController::popBackStack,
                onOpen = { route -> navController.navigate(route) }
            )
        }
    }

    ApplyDeepLink(navController, deepLink, start)
}

@Composable
private fun ApplyDeepLink(
    navController: NavHostController,
    deepLink: String?,
    start: String
) {
    androidx.compose.runtime.LaunchedEffect(deepLink, start) {
        if (deepLink == null || start != Routes.Home) return@LaunchedEffect
        navController.navigate(deepLink)
    }
}
