package kz.yerek.aireply.ui.feature.templates

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kz.yerek.aireply.R
import kz.yerek.aireply.core.lang.TemplateNaming
import kz.yerek.aireply.ui.LocalServices
import kz.yerek.aireply.ui.common.AppScreen
import kz.yerek.aireply.ui.common.Footnote
import kz.yerek.aireply.ui.common.RowDividerIndented
import kz.yerek.aireply.ui.common.RowGroup
import kz.yerek.aireply.ui.design.AppSection
import kz.yerek.aireply.ui.design.LocalExtraColors
import kz.yerek.aireply.ui.design.ReadableColumn
import kz.yerek.aireply.ui.design.SecondaryButton
import kz.yerek.aireply.ui.design.Spacing
import kz.yerek.aireply.ui.feature.profile.toneResource

/**
 * The template list: reorder, hide, edit, create and delete.
 *
 * REORDERING IS EXPLICIT BUTTONS, not drag-and-drop. iOS gets reordering free
 * from `List` + `EditButton`; Compose has no equivalent, and a hand-rolled
 * drag-and-drop in a list this short would be more code than the rest of the
 * screen and worse for anyone using a screen reader or a switch device. Two
 * arrows do the same job and are reachable by everyone.
 */
@Composable
fun TemplateListScreen(onBack: () -> Unit, onEdit: (String) -> Unit) {
    val services = LocalServices.current
    val context = LocalContext.current
    val configuration by services.configuration.configuration.collectAsStateWithLifecycle()

    var adding by remember { mutableStateOf(false) }
    var newName by remember { mutableStateOf("") }

    val templates = configuration.orderedTemplates

    AppScreen(title = stringResource(R.string.templates_title), onBack = onBack) {
        ReadableColumn {
            AppSection(stringResource(R.string.templates_title)) {
                RowGroup {
                    templates.forEachIndexed { index, template ->
                        if (index > 0) RowDividerIndented()
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onEdit(template.id) }
                                .padding(horizontal = Spacing.m, vertical = Spacing.s),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    TemplateNaming.displayName(context, template),
                                    style = MaterialTheme.typography.bodyLarge
                                )
                                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xxs)) {
                                    Text(
                                        stringResource(toneResource(template.tone)),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = LocalExtraColors.current.textSecondary
                                    )
                                    if (!template.isVisible) {
                                        Text(
                                            "· " + stringResource(R.string.templates_hidden),
                                            style = MaterialTheme.typography.labelSmall,
                                            color = LocalExtraColors.current.textSecondary
                                        )
                                    }
                                }
                            }

                            if (!template.isVisible) {
                                Icon(
                                    Icons.Filled.VisibilityOff,
                                    contentDescription = null,
                                    tint = LocalExtraColors.current.textSecondary,
                                    modifier = Modifier.size(18.dp)
                                )
                            }

                            IconButton(
                                onClick = { services.configuration.move(index, index - 1) },
                                enabled = index > 0
                            ) {
                                Icon(
                                    Icons.Filled.ArrowUpward,
                                    contentDescription = stringResource(R.string.cd_move_up),
                                    modifier = Modifier.size(18.dp)
                                )
                            }
                            IconButton(
                                onClick = { services.configuration.move(index, index + 1) },
                                enabled = index < templates.lastIndex
                            ) {
                                Icon(
                                    Icons.Filled.ArrowDownward,
                                    contentDescription = stringResource(R.string.cd_move_down),
                                    modifier = Modifier.size(18.dp)
                                )
                            }
                        }
                    }
                }
                Footnote(stringResource(R.string.templates_reorder))
                Footnote(stringResource(R.string.templates_builtin_footer))
            }

            SecondaryButton(
                text = stringResource(R.string.templates_add),
                onClick = {
                    newName = ""
                    adding = true
                },
                modifier = Modifier.fillMaxWidth()
            )
        }
    }

    if (adding) {
        AlertDialog(
            onDismissRequest = { adding = false },
            title = { Text(stringResource(R.string.templates_add)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
                    Text(stringResource(R.string.templates_add_prompt))
                    OutlinedTextField(
                        value = newName,
                        onValueChange = { newName = it },
                        label = { Text(stringResource(R.string.templates_name)) },
                        singleLine = true
                    )
                }
            },
            confirmButton = {
                TextButton(
                    enabled = newName.isNotBlank(),
                    onClick = {
                        services.configuration.addCustomTemplate(newName.trim())
                        adding = false
                    }
                ) { Text(stringResource(R.string.common_add)) }
            },
            dismissButton = {
                TextButton(onClick = { adding = false }) {
                    Text(stringResource(R.string.common_cancel))
                }
            }
        )
    }
}
