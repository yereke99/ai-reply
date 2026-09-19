package kz.yerek.aireply.ui.feature.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import kz.yerek.aireply.R
import kz.yerek.aireply.ui.common.Footnote
import kz.yerek.aireply.ui.design.AppCard
import kz.yerek.aireply.ui.design.AppMark
import kz.yerek.aireply.ui.design.LocalExtraColors
import kz.yerek.aireply.ui.design.PrimaryButton
import kz.yerek.aireply.ui.design.ReadableColumn
import kz.yerek.aireply.ui.design.SecondaryButton
import kz.yerek.aireply.ui.design.Spacing
import kz.yerek.aireply.ui.design.StepRow
import kz.yerek.aireply.ui.feature.setup.KeyboardSetupScreen

/**
 * First run.
 *
 * The first run covers setup that cannot be inferred from the account: enabling
 * the keyboard, granting optional voice access and learning the copy workflow.
 */
@Composable
fun OnboardingScreen(onFinished: () -> Unit) {
    var step by remember { mutableStateOf(Step.WELCOME) }

    fun advance() {
        val next = Step.entries.getOrNull(step.ordinal + 1)
        if (next == null) onFinished() else step = next
    }

    Column(modifier = Modifier.fillMaxSize()) {

        step.questionIndex?.let { index ->
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = Spacing.l, top = Spacing.s, end = Spacing.l),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                LinearProgressIndicator(
                    progress = { index.toFloat() / Step.QUESTION_COUNT },
                    modifier = Modifier.fillMaxWidth()
                )
                Text(
                    stringResource(R.string.onboarding_step, index, Step.QUESTION_COUNT),
                    style = MaterialTheme.typography.labelSmall,
                    color = LocalExtraColors.current.textSecondary,
                    modifier = Modifier.padding(top = Spacing.xxs)
                )
            }
        }

        Box(modifier = Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            AnimatedContent(targetState = step, label = "onboarding") { current ->
                ReadableColumn(verticalArrangement = Arrangement.spacedBy(Spacing.l)) {
                    when (current) {
                        Step.WELCOME -> WelcomeStep()
                        Step.KEYBOARD -> KeyboardStep()
                        Step.USAGE -> UsageStep()
                        Step.TEST -> TestStep()
                    }
                }
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(Spacing.l),
            horizontalArrangement = Arrangement.spacedBy(Spacing.s),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (step != Step.WELCOME) {
                SecondaryButton(stringResource(R.string.onboarding_back)) {
                    Step.entries.getOrNull(step.ordinal - 1)?.let { step = it }
                }
            }
            Spacer(Modifier.weight(1f))
            if (step != Step.WELCOME && step != Step.TEST) {
                SecondaryButton(stringResource(R.string.onboarding_skip)) { advance() }
            }
            PrimaryButton(
                text = stringResource(
                    when (step) {
                        Step.WELCOME -> R.string.onboarding_start
                        Step.TEST -> R.string.onboarding_finish
                        else -> R.string.onboarding_next
                    }
                ),
                onClick = { advance() },
                modifier = Modifier.weight(1.4f)
            )
        }
    }

}

enum class Step {
    WELCOME, KEYBOARD, USAGE, TEST;

    /** The welcome screen is not numbered: "Step 1 of 6" starts at the first real question. */
    val questionIndex: Int? get() = if (this == WELCOME) null else ordinal

    companion object {
        const val QUESTION_COUNT = 3
    }
}

// ------------------------------------------------------------------- steps

@Composable
private fun WelcomeStep() {
    AppMark(size = 72.dp)
    Text(stringResource(R.string.onboarding_welcome_title), style = MaterialTheme.typography.displaySmall)
    Footnote(stringResource(R.string.onboarding_welcome_body))
    AppCard {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
            FeatureRow(Icons.Filled.ContentCopy, stringResource(R.string.onboarding_welcome_point_copy))
            FeatureRow(Icons.Filled.Groups, stringResource(R.string.onboarding_welcome_point_templates))
            FeatureRow(Icons.Filled.Edit, stringResource(R.string.onboarding_welcome_point_edit))
        }
    }
}

@Composable
private fun KeyboardStep() {
    Title(
        stringResource(R.string.onboarding_keyboard_title),
        stringResource(R.string.onboarding_keyboard_prompt)
    )
    KeyboardSetupScreen(showsTitle = false)
}

@Composable
private fun UsageStep() {
    Title(
        stringResource(R.string.onboarding_usage_title),
        stringResource(R.string.onboarding_usage_prompt)
    )
    AppCard {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
            StepRow(1, stringResource(R.string.onboarding_usage_step_copy))
            StepRow(2, stringResource(R.string.onboarding_usage_step_open))
            StepRow(3, stringResource(R.string.onboarding_usage_step_template))
            StepRow(4, stringResource(R.string.onboarding_usage_step_insert))
        }
    }
    Footnote(stringResource(R.string.android_howitworks_clipboard))
}

@Composable
private fun TestStep() {
    var text by remember { mutableStateOf("") }
    AppMark(size = 64.dp)
    Text(stringResource(R.string.onboarding_done_title), style = MaterialTheme.typography.displaySmall)
    Footnote(stringResource(R.string.onboarding_done_body))
    AppCard {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
            Footnote(stringResource(R.string.onboarding_test_prompt))
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                placeholder = { Text(stringResource(R.string.onboarding_test_placeholder)) },
                modifier = Modifier.fillMaxWidth()
            )
            Footnote(stringResource(R.string.android_step_select))
        }
    }
}

// ------------------------------------------------------------------ pieces

@Composable
private fun Title(heading: String, prompt: String) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        Text(heading, style = MaterialTheme.typography.headlineMedium)
        Footnote(prompt)
    }
}

@Composable
private fun FeatureRow(icon: ImageVector, text: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(Spacing.s),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(20.dp)
        )
        Text(text, style = MaterialTheme.typography.bodyMedium)
    }
}
