package kz.yerek.aireply.ui.feature.account

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import kz.yerek.aireply.R
import kz.yerek.aireply.data.account.CountryDto
import kz.yerek.aireply.ui.LocalServices
import kz.yerek.aireply.ui.common.Footnote
import kz.yerek.aireply.ui.design.AppMark
import kz.yerek.aireply.ui.design.AuthColumn
import kz.yerek.aireply.ui.design.PrimaryButton
import kz.yerek.aireply.ui.design.Radius
import kz.yerek.aireply.ui.design.Spacing
import java.util.Locale

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

    val identifier = if (usePhone) country?.dialCode.orEmpty() + digits else email.trim()
    val complete = if (usePhone) {
        digits.length >= 6 && country != null
    } else {
        email.contains('@') && email.length >= 6
    }

    AuthColumn {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
            AppMark()
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
            Column {
                OutlinedTextField(
                    value = formatPhone(digits),
                    onValueChange = { digits = it.filter(Char::isDigit).take(15) },
                    label = { Text(stringResource(R.string.account_phone_placeholder)) },
                    leadingIcon = {
                        TextButton(
                            onClick = { menuOpen = true },
                            enabled = state.countries.isNotEmpty()
                        ) {
                            Text(country?.let { "${it.flag} ${it.dialCode}" } ?: "+")
                        }
                    },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                    shape = RoundedCornerShape(Radius.medium),
                    modifier = Modifier.fillMaxWidth()
                )
                DropdownMenu(
                    expanded = menuOpen,
                    onDismissRequest = { menuOpen = false }
                ) {
                    state.countries.forEach { option ->
                        DropdownMenuItem(
                            text = { Text("${option.flag}  ${option.name}  ${option.dialCode}") },
                            onClick = {
                                country = option
                                menuOpen = false
                            }
                        )
                    }
                }
            }
            country?.example?.takeIf(String::isNotEmpty)?.let { Footnote(it) }
        } else {
            OutlinedTextField(
                value = email,
                onValueChange = { email = it.trimStart() },
                label = { Text(stringResource(R.string.account_email_placeholder)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                shape = RoundedCornerShape(Radius.medium),
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

private fun formatPhone(value: String): String = value.chunked(3).joinToString(" ")
