package kz.yerek.aireply.ui.feature.account

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import kz.yerek.aireply.R
import kz.yerek.aireply.ai.AITransportMode
import kz.yerek.aireply.ui.LocalServices
import kz.yerek.aireply.ui.common.Footnote
import kz.yerek.aireply.ui.common.NavigationRow
import kz.yerek.aireply.ui.common.RowDividerIndented
import kz.yerek.aireply.ui.common.RowGroup
import kz.yerek.aireply.ui.design.AppCard
import kz.yerek.aireply.ui.design.AppSection
import kz.yerek.aireply.ui.design.SecondaryButton
import kz.yerek.aireply.ui.design.Spacing

/**
 * Chooses where replies are generated: this device's own key, or our service.
 *
 * Жауап қайда жасалады: құрылғыдағы кілт пе, әлде біздің сервер ме.
 *
 * The switch is here rather than behind a build flag because both modes are
 * real products. Direct mode is what an individual with their own API key
 * wants; service mode is what everyone else wants, and the only one where an
 * account, a plan and a quota mean anything.
 */
@Composable
fun ServiceModeEditor(mode: AITransportMode, onModeChange: (AITransportMode) -> Unit) {
    val services = LocalServices.current
    var url by remember { mutableStateOf(services.aiConfiguration.backendBaseUrlString) }
    var invalid by remember { mutableStateOf(false) }

    fun save() {
        services.aiConfiguration.setBackendBaseUrl(url.trim())
        invalid = url.isNotBlank() && services.aiConfiguration.backendBaseUrl == null
    }

    // Committed on the way out as well, so an address typed without pressing
    // done is not silently discarded.
    DisposableEffect(Unit) { onDispose { save() } }

    AppSection(stringResource(R.string.settings_service)) {
        AppCard {
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                SegmentedButton(
                    selected = mode == AITransportMode.DIRECT,
                    onClick = {
                        services.aiConfiguration.setMode(AITransportMode.DIRECT)
                        onModeChange(AITransportMode.DIRECT)
                    },
                    shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2)
                ) { Text(stringResource(R.string.settings_service_direct)) }
                SegmentedButton(
                    selected = mode == AITransportMode.BACKEND,
                    onClick = {
                        services.aiConfiguration.setMode(AITransportMode.BACKEND)
                        onModeChange(AITransportMode.BACKEND)
                    },
                    shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2)
                ) { Text(stringResource(R.string.settings_service_backend)) }
            }

            if (mode == AITransportMode.BACKEND) {
                OutlinedTextField(
                    value = url,
                    onValueChange = { url = it; invalid = false },
                    label = { Text(stringResource(R.string.settings_service_url)) },
                    singleLine = true,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = Spacing.s)
                )
                if (invalid) {
                    Text(
                        stringResource(R.string.settings_service_url_invalid),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
        }
        Footnote(stringResource(R.string.settings_service_footer))
    }
}

/**
 * The account block inside Settings.
 *
 * Баптаулардағы тіркелгі бөлімі: тариф, квота, шығу.
 *
 * Shows what the user needs to recognise their account and nothing more: the
 * masked identifier the server sent back, the plan, what is left today, and the
 * way out.
 */
@Composable
fun AccountSection(onOpenSubscription: () -> Unit) {
    val services = LocalServices.current
    val account = services.account
    val state by account.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var confirming by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { account.refresh() }

    AppSection(stringResource(R.string.settings_account)) {
        if (state.isSignedIn) {
            AppCard {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        stringResource(R.string.settings_account_identifier),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        account.displayIdentifier,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            RowGroup {
                NavigationRow(
                    Icons.Filled.CreditCard,
                    stringResource(R.string.settings_account_plan),
                    value = planSummary(state, services.settings.effectiveAppLanguage.code)
                ) { onOpenSubscription() }
                RowDividerIndented()
                NavigationRow(
                    Icons.AutoMirrored.Filled.Logout,
                    stringResource(R.string.settings_account_sign_out)
                ) { confirming = true }
            }
        } else {
            AppCard {
                Text(
                    stringResource(R.string.settings_account_signed_out),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        Footnote(stringResource(R.string.settings_account_footer))
    }

    if (confirming) {
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text(stringResource(R.string.settings_account_sign_out_confirm)) },
            confirmButton = {
                TextButton(onClick = {
                    confirming = false
                    scope.launch { account.signOut() }
                }) { Text(stringResource(R.string.settings_account_sign_out)) }
            },
            dismissButton = {
                TextButton(onClick = { confirming = false }) {
                    Text(stringResource(R.string.common_cancel))
                }
            }
        )
    }
}

private fun planSummary(state: AccountController.State, language: String): String {
    val plan = state.subscription?.plan ?: return ""
    val name = plan.localizedName(language)
    if (state.usage.dailyLimit <= 0) return name
    return "$name · ${state.usage.remainingToday}/${state.usage.dailyLimit}"
}
