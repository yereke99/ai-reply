package kz.yerek.aireply.ui.feature.account

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import kz.yerek.aireply.R
import kz.yerek.aireply.data.account.CountryDto
import kz.yerek.aireply.ui.LocalServices
import kz.yerek.aireply.ui.common.Footnote
import kz.yerek.aireply.ui.design.AppMark
import kz.yerek.aireply.ui.design.PrimaryButton
import kz.yerek.aireply.ui.design.ReadableColumn
import kz.yerek.aireply.ui.design.Spacing
import java.util.Locale

/**
 * Phone or e-mail entry: the first screen a new user sees.
 *
 * Кіру экраны: телефон нөмірі немесе пошта.
 *
 * The country list comes from the server, so adding a country is a backend
 * change rather than an app release. Validation is left to the server too: the
 * field accepts what the user types and the server answers with a precise
 * error, which is the only rule that cannot be bypassed.
 */
@Composable
fun SignInScreen() {
    val services = LocalServices.current
    val account = services.account
    val state by account.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var usePhone by remember { mutableStateOf(true) }
    var digits by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var country by remember { mutableStateOf<CountryDto?>(null) }
    var menuOpen by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { account.loadServerConfig() }
    LaunchedEffect(state.countries) {
        if (country == null && state.countries.isNotEmpty()) {
            val region = Locale.getDefault().country
            country = state.countries.firstOrNull { it.iso == region }
                ?: state.countries.firstOrNull { it.iso == "KZ" }
                ?: state.countries.first()
        }
    }

    val identifier = if (usePhone) (country?.dialCode.orEmpty() + digits) else email.trim()
    val complete = if (usePhone) digits.length >= 6 && country != null
    else email.contains('@') && email.length >= 6

    ReadableColumn {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
            AppMark(size = 56.dp)
            Text(
                stringResource(R.string.account_sign_in_title),
                style = MaterialTheme.typography.headlineSmall
            )
            Text(
                stringResource(R.string.account_sign_in_subtitle),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            SegmentedButton(
                selected = usePhone,
                onClick = { usePhone = true },
                shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2)
            ) { Text(stringResource(R.string.account_method_phone)) }
            SegmentedButton(
                selected = !usePhone,
                onClick = { usePhone = false },
                shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2)
            ) { Text(stringResource(R.string.account_method_email)) }
        }

        if (usePhone) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(Spacing.s),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    OutlinedButton(
                        onClick = { menuOpen = true },
                        enabled = state.countries.isNotEmpty()
                    ) {
                        Text(country?.let { "${it.flag} ${it.dialCode}" } ?: "+…")
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        state.countries.forEach { option ->
                            DropdownMenuItem(
                                text = { Text("${option.flag}  ${option.name}  ${option.dialCode}") },
                                onClick = { country = option; menuOpen = false }
                            )
                        }
                    }
                }
                OutlinedTextField(
                    value = digits,
                    // Keep only digits: a pasted "+7 (701) 123-45-67" should not
                    // become an error the user has to decipher.
                    onValueChange = { value -> digits = value.filter(Char::isDigit) },
                    label = { Text(stringResource(R.string.account_phone_placeholder)) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                    modifier = Modifier.fillMaxWidth()
                )
            }
            country?.example?.takeIf { it.isNotEmpty() }?.let { Footnote(it) }
        } else {
            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text(stringResource(R.string.account_email_placeholder)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                modifier = Modifier.fillMaxWidth()
            )
        }

        state.errorMessage?.let { message ->
            Text(
                stringResource(message),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error
            )
        }

        PrimaryButton(
            text = stringResource(R.string.account_continue),
            enabled = complete && !state.busy,
            onClick = {
                scope.launch {
                    account.requestCode(identifier, services.settings.effectiveAppLanguage.code)
                }
            }
        )

        Footnote(stringResource(R.string.account_legal_footer))
    }
}
