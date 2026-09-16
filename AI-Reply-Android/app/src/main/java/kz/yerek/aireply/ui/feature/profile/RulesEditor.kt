package kz.yerek.aireply.ui.feature.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import kz.yerek.aireply.R
import kz.yerek.aireply.domain.model.BusinessContext
import kz.yerek.aireply.ui.common.Footnote
import kz.yerek.aireply.ui.design.AppCard
import kz.yerek.aireply.ui.design.AppSection
import kz.yerek.aireply.ui.design.Spacing

/**
 * The "things the assistant must never promise" list, shared by the profile and
 * every template editor.
 *
 * A list of short lines rather than one paragraph, because that is what the
 * model follows most reliably and what the user can edit one item at a time.
 */
@Composable
fun RulesEditor(
    business: BusinessContext,
    onChange: (BusinessContext) -> Unit,
    footnote: String,
    modifier: Modifier = Modifier
) {
    AppSection(stringResource(R.string.profile_rules), modifier) {
        AppCard {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                business.rules.forEachIndexed { index, rule ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(Spacing.xs)
                    ) {
                        OutlinedTextField(
                            value = rule,
                            onValueChange = { onChange(business.withRule(it, index)) },
                            placeholder = { Text(stringResource(R.string.profile_rules_placeholder)) },
                            modifier = Modifier.weight(1f)
                        )
                        IconButton(onClick = { onChange(business.removingRule(index)) }) {
                            Icon(
                                Icons.Filled.Close,
                                contentDescription = stringResource(R.string.cd_delete),
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }
                }

                if (business.rules.size < BusinessContext.MAX_RULES) {
                    TextButton(onClick = { onChange(business.addingRule()) }) {
                        Icon(
                            Icons.Filled.Add,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp)
                        )
                        Text(
                            stringResource(R.string.profile_rules_add),
                            modifier = Modifier.padding(start = Spacing.xs)
                        )
                    }
                }
            }
        }
        Footnote(footnote)
    }
}
