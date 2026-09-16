package kz.yerek.aireply.ui.feature.settings

import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.text.KeyboardOptions
import kz.yerek.aireply.R
import kz.yerek.aireply.ui.LocalServices
import kz.yerek.aireply.ui.design.LocalExtraColors
import kz.yerek.aireply.ui.design.Spacing

/**
 * Entry and management of the OpenAI key.
 *
 * The key is typed or pasted here and goes straight into the encrypted store. It
 * is never held in a saved state, never written to preferences in the clear,
 * never logged, and never displayed again after it is saved — only whether one
 * exists. Typing a 164-character key on a phone is unpleasant, so Paste is the
 * prominent action, exactly as on iOS.
 */
@Composable
fun ApiKeyEditor(onSaved: (() -> Unit)? = null) {
    val services = LocalServices.current
    val context = LocalContext.current

    var entry by remember { mutableStateOf("") }
    var hasKey by remember { mutableStateOf(services.credentials.hasApiKey()) }
    var message by remember { mutableStateOf<Int?>(null) }
    var messageIsError by remember { mutableStateOf(false) }

    fun show(resource: Int, isError: Boolean) {
        message = resource
        messageIsError = isError
    }

    fun save(value: String) {
        val trimmed = value.trim()
        // A shape check, not a validity check. Whether the key actually works is
        // answered by the first request, and reporting that honestly beats
        // pretending this can tell.
        if (!trimmed.startsWith("sk-") || trimmed.length <= 20) {
            show(R.string.onboarding_key_invalid, true)
            return
        }
        if (!services.credentials.setApiKey(trimmed)) {
            show(R.string.onboarding_key_savefailed, true)
            return
        }
        entry = ""
        hasKey = true
        show(R.string.onboarding_key_saved, false)
        onSaved?.invoke()
    }

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(Spacing.xs)
    ) {
        if (hasKey) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.xs)
            ) {
                Icon(
                    Icons.Filled.CheckCircle,
                    contentDescription = null,
                    tint = LocalExtraColors.current.success,
                    modifier = Modifier.size(18.dp)
                )
                Text(
                    stringResource(R.string.settings_ai_key_set),
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            TextButton(onClick = {
                services.credentials.deleteApiKey()
                hasKey = services.credentials.hasApiKey()
                entry = ""
                message = null
            }) {
                Text(
                    stringResource(R.string.settings_ai_key_remove),
                    color = MaterialTheme.colorScheme.error
                )
            }
        } else {
            OutlinedTextField(
                value = entry,
                onValueChange = { entry = it },
                label = { Text(stringResource(R.string.settings_ai_key)) },
                placeholder = { Text(stringResource(R.string.onboarding_key_placeholder)) },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false
                ),
                modifier = Modifier.fillMaxWidth()
            )

            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                TextButton(onClick = {
                    val pasted = readClipboardText(context)
                    if (pasted.isNullOrEmpty()) {
                        show(R.string.onboarding_key_clipboardempty, true)
                    } else {
                        entry = pasted
                        save(pasted)
                    }
                }) {
                    Icon(
                        Icons.Filled.ContentPaste,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Text(
                        stringResource(R.string.onboarding_key_paste),
                        modifier = Modifier.padding(start = Spacing.xs)
                    )
                }
                TextButton(onClick = { save(entry) }, enabled = entry.isNotBlank()) {
                    Text(stringResource(R.string.common_save))
                }
            }
        }

        message?.let { resource ->
            Text(
                stringResource(resource),
                style = MaterialTheme.typography.bodySmall,
                color = if (messageIsError) {
                    MaterialTheme.colorScheme.error
                } else {
                    LocalExtraColors.current.success
                }
            )
        }
    }
}

/**
 * Reads the clipboard for the paste button.
 *
 * This is an Activity, so Android permits the read while it has focus. It
 * happens only when the user taps Paste — the same rule the keyboard follows.
 */
private fun readClipboardText(context: Context): String? {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
    return runCatching {
        clipboard?.primaryClip
            ?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)
            ?.coerceToText(context)
            ?.toString()
            ?.trim()
    }.getOrNull()?.takeIf { it.isNotEmpty() }
}
