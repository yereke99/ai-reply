package kz.yerek.aireply.ui.feature.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import kz.yerek.aireply.R
import kz.yerek.aireply.core.text.clampToCodePoints
import kz.yerek.aireply.domain.model.BusinessContext
import kz.yerek.aireply.domain.model.UserProfile
import kz.yerek.aireply.domain.model.WorkingHours
import kz.yerek.aireply.ui.LocalServices
import kz.yerek.aireply.ui.common.Footnote
import kz.yerek.aireply.ui.design.AppCard
import kz.yerek.aireply.ui.design.AppMark
import kz.yerek.aireply.ui.design.LocalExtraColors
import kz.yerek.aireply.ui.design.PrimaryButton
import kz.yerek.aireply.ui.design.ReadableColumn
import kz.yerek.aireply.ui.design.SecondaryButton
import kz.yerek.aireply.ui.design.Spacing
import kz.yerek.aireply.ui.design.StepRow
import kz.yerek.aireply.ui.feature.settings.ApiKeyEditor
import kz.yerek.aireply.ui.feature.setup.KeyboardSetupScreen
import kz.yerek.aireply.ui.feature.voice.DictationSheet

/**
 * First run.
 *
 * Six screens after the welcome, in the iOS order: what this is, who you are,
 * when you work, connecting the AI, adding the keyboard, how copy-to-reply
 * works, and a field to try it in.
 *
 * Every question screen is skippable and every answer is written as the user
 * leaves it, so quitting halfway loses nothing and a user who skips everything
 * still gets a working keyboard with the default templates.
 */
@Composable
fun OnboardingScreen(onFinished: () -> Unit) {
    val services = LocalServices.current
    val stored = remember { services.configuration.profile }

    var step by remember { mutableStateOf(Step.WELCOME) }
    var role by remember { mutableStateOf(stored.role) }
    var offering by remember { mutableStateOf(stored.business.offering) }
    var about by remember { mutableStateOf(stored.descriptionText) }
    var hours by remember { mutableStateOf(stored.workingHours) }
    var dictating by remember { mutableStateOf(false) }

    fun persistCurrentStep() {
        when (step) {
            Step.PROFILE -> services.configuration.updateProfile { profile ->
                profile.withRole(role)
                    .withDescription(about)
                    .copy(business = profile.business.withOffering(offering))
            }
            Step.HOURS -> services.configuration.updateProfile { it.copy(workingHours = hours) }
            else -> Unit
        }
    }

    fun advance() {
        persistCurrentStep()
        val next = Step.entries.getOrNull(step.ordinal + 1)
        if (next == null) onFinished() else step = next
    }

    Column(modifier = Modifier.fillMaxSize()) {

        step.questionIndex?.let { index ->
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = Spacing.l, top = Spacing.s),
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
                        Step.PROFILE -> ProfileStep(
                            role = role,
                            onRole = { role = it.clampToCodePoints(UserProfile.MAX_ROLE) },
                            offering = offering,
                            onOffering = {
                                offering = it.clampToCodePoints(BusinessContext.MAX_OFFERING)
                            },
                            about = about,
                            onAbout = {
                                about = it.clampToCodePoints(UserProfile.MAX_DESCRIPTION)
                            },
                            onDictate = { dictating = true }
                        )
                        Step.HOURS -> HoursStep(hours) { hours = it }
                        Step.KEY -> KeyStep()
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

    if (dictating) {
        DictationSheet(
            language = services.settings.effectiveAppLanguage,
            onDismiss = { dictating = false },
            onAccept = { transcript ->
                val addition = transcript.trim()
                if (addition.isNotEmpty()) {
                    val separator = if (about.isEmpty()) "" else " "
                    about = (about + separator + addition)
                        .clampToCodePoints(UserProfile.MAX_DESCRIPTION)
                }
            }
        )
    }
}

enum class Step {
    WELCOME, PROFILE, HOURS, KEY, KEYBOARD, USAGE, TEST;

    /** The welcome screen is not numbered: "Step 1 of 6" starts at the first real question. */
    val questionIndex: Int? get() = if (this == WELCOME) null else ordinal

    companion object {
        const val QUESTION_COUNT = 6
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

/**
 * Normal questions, not a prompt editor. Nothing here asks the user to write an
 * instruction for a model; the app turns these answers into context itself.
 */
@Composable
private fun ProfileStep(
    role: String,
    onRole: (String) -> Unit,
    offering: String,
    onOffering: (String) -> Unit,
    about: String,
    onAbout: (String) -> Unit,
    onDictate: () -> Unit
) {
    Title(
        stringResource(R.string.onboarding_profile_title),
        stringResource(R.string.onboarding_profile_prompt)
    )
    AppCard {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
            OutlinedTextField(
                value = role,
                onValueChange = onRole,
                label = { Text(stringResource(R.string.profile_role)) },
                placeholder = { Text(stringResource(R.string.profile_role_placeholder)) },
                modifier = Modifier.fillMaxWidth()
            )
            OutlinedTextField(
                value = offering,
                onValueChange = onOffering,
                label = { Text(stringResource(R.string.profile_offering)) },
                placeholder = { Text(stringResource(R.string.profile_offering_placeholder)) },
                modifier = Modifier.fillMaxWidth()
            )
            OutlinedTextField(
                value = about,
                onValueChange = onAbout,
                label = { Text(stringResource(R.string.profile_about)) },
                placeholder = { Text(stringResource(R.string.onboarding_profile_placeholder)) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(130.dp)
            )
            TextButton(onClick = onDictate) {
                Icon(Icons.Filled.Mic, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(
                    stringResource(R.string.profile_dictate),
                    modifier = Modifier.padding(start = Spacing.xs)
                )
            }
        }
    }
}

@Composable
private fun HoursStep(hours: WorkingHours, onChange: (WorkingHours) -> Unit) {
    Title(
        stringResource(R.string.onboarding_hours_title),
        stringResource(R.string.onboarding_hours_prompt)
    )
    AppCard {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.hours_enable),
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.weight(1f)
            )
            Switch(
                checked = hours.isEnabled,
                onCheckedChange = { onChange(hours.copy(isEnabled = it)) }
            )
        }
    }
    Footnote(stringResource(R.string.onboarding_hours_footer))
}

@Composable
private fun KeyStep() {
    Title(
        stringResource(R.string.onboarding_key_title),
        stringResource(R.string.onboarding_key_prompt)
    )
    AppCard { ApiKeyEditor() }
    Footnote(stringResource(R.string.settings_ai_key_footer))
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
