package kz.yerek.aireply.ui.feature.account

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kz.yerek.aireply.R
import kz.yerek.aireply.ui.LocalServices
import kz.yerek.aireply.ui.design.AuthColumn
import kz.yerek.aireply.ui.design.PrimaryButton
import kz.yerek.aireply.ui.design.Spacing

private const val CODE_LENGTH = 4
private const val RESEND_SECONDS = 30

@Composable
fun VerifyCodeScreen(
    masked: String,
    onVerified: (isNewUser: Boolean) -> Unit
) {
    val services = LocalServices.current
    val account = services.account
    val state by account.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var code by remember { mutableStateOf("") }
    var secondsLeft by remember { mutableIntStateOf(RESEND_SECONDS) }

    LaunchedEffect(Unit) {
        while (secondsLeft > 0) {
            delay(1000)
            secondsLeft -= 1
        }
    }

    suspend fun submit() {
        val isNewUser = account.verify(code)
        if (account.state.value.isSignedIn) onVerified(isNewUser) else code = ""
    }

    AuthColumn {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            Text(
                stringResource(R.string.account_code_title),
                style = MaterialTheme.typography.headlineSmall
            )
            Text(
                stringResource(R.string.account_code_subtitle, masked),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        OutlinedTextField(
            value = code,
            onValueChange = { value ->
                code = value.filter(Char::isDigit).take(CODE_LENGTH)
                if (code.length == CODE_LENGTH && !state.busy) scope.launch { submit() }
            },
            singleLine = true,
            textStyle = TextStyle(fontSize = 28.sp, textAlign = TextAlign.Center),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            modifier = Modifier.fillMaxWidth()
        )

        state.errorMessage?.let { message ->
            Text(
                stringResource(message),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error
            )
        }

        PrimaryButton(
            text = stringResource(R.string.account_code_confirm),
            enabled = code.length == CODE_LENGTH && !state.busy,
            onClick = { scope.launch { submit() } }
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextButton(
                enabled = secondsLeft == 0 && !state.busy,
                onClick = {
                    scope.launch {
                        account.resendCode(services.settings.effectiveAppLanguage.code)
                        secondsLeft = RESEND_SECONDS
                    }
                }
            ) {
                Text(
                    if (secondsLeft > 0) {
                        stringResource(R.string.account_code_resend) + " · ${secondsLeft}s"
                    } else {
                        stringResource(R.string.account_code_resend)
                    }
                )
            }
            TextButton(onClick = account::cancelCodeEntry) {
                Text(stringResource(R.string.common_back))
            }
        }
    }
}
