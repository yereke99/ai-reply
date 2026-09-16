package kz.yerek.aireply.keyboard.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kz.yerek.aireply.R
import kz.yerek.aireply.ai.AppStrings
import kz.yerek.aireply.domain.model.TemplateSummary
import kz.yerek.aireply.keyboard.KeyboardTheme
import kz.yerek.aireply.keyboard.input.KeyboardTextFieldState
import kz.yerek.aireply.keyboard.reply.ReplyStage
import kz.yerek.aireply.voice.VoiceFailure
import kz.yerek.aireply.voice.VoiceState

/** Which local field the keys are currently editing. */
enum class PanelFocus { INSTRUCTION, DRAFT }

/** Everything the panel draws, gathered by the service so this file holds no logic. */
data class ReplyPanelModel(
    val stage: ReplyStage,
    val chips: List<TemplateSummary>,
    val chipLanguageCode: String,
    val selectedTemplateName: String,
    val sourceMessage: String,
    val instruction: KeyboardTextFieldState,
    val draft: KeyboardTextFieldState,
    val focus: PanelFocus,
    val toast: String?,
    val voice: VoiceState,
    val isSecureField: Boolean,
    val sourceExpanded: Boolean
)

data class ReplyPanelActions(
    val onSelectTemplate: (String) -> Unit,
    val onAddTemplate: () -> Unit,
    val onClose: () -> Unit,
    val onGenerate: () -> Unit,
    val onRegenerate: () -> Unit,
    val onInsert: () -> Unit,
    val onFocus: (PanelFocus) -> Unit,
    val onCaret: (PanelFocus, Int) -> Unit,
    val onToggleSource: () -> Unit,
    val onMic: () -> Unit,
    val onConflict: (ConflictChoice) -> Unit
)

enum class ConflictChoice { REPLACE, APPEND, CANCEL }

/**
 * The contextual area above the keys.
 *
 * ONE RULE GOVERNS ITS GEOMETRY, and it is the rule the iOS build states most
 * emphatically: this area never takes height from the keys. The keyboard grows
 * instead. An earlier iOS version let the AI chrome eat the typing area, and the
 * whole layout here is arranged so that cannot happen — the panel wraps its
 * content, the key grid is sized independently, and the window is the sum.
 *
 * It is capped at [maxHeight] all the same, because an Android IME can grow
 * until it covers the conversation the user is replying to.
 */
@Composable
fun ReplyPanel(
    model: ReplyPanelModel,
    actions: ReplyPanelActions,
    strings: AppStrings,
    theme: KeyboardTheme,
    maxHeight: Dp,
    modifier: Modifier = Modifier
) {
    Box(modifier = modifier.fillMaxWidth().heightIn(max = maxHeight)) {
        when (model.stage) {
            ReplyStage.IDLE -> IdleRow(model, actions, strings, theme)
            else -> Composer(model, actions, strings, theme)
        }
    }
}

// ------------------------------------------------------------------- idle

@Composable
private fun IdleRow(
    model: ReplyPanelModel,
    actions: ReplyPanelActions,
    strings: AppStrings,
    theme: KeyboardTheme
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(IDLE_HEIGHT)
            .padding(horizontal = 8.dp),
        contentAlignment = Alignment.CenterStart
    ) {
        // A toast replaces the row rather than displacing it, so showing an
        // error never resizes the keyboard under the user's thumbs.
        AnimatedVisibility(visible = model.toast != null, enter = fadeIn(), exit = fadeOut()) {
            Text(
                text = model.toast.orEmpty(),
                color = theme.secondaryText,
                fontSize = 12.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.fillMaxWidth()
            )
        }

        AnimatedVisibility(visible = model.toast == null, enter = fadeIn(), exit = fadeOut()) {
            if (model.isSecureField) {
                Text(
                    text = strings[R.string.kb_secure_field],
                    color = theme.secondaryText,
                    fontSize = 12.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            } else {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    model.chips.forEach { chip ->
                        Pill(
                            theme = theme,
                            onClick = { actions.onSelectTemplate(chip.id) }
                        ) {
                            Text(
                                text = chip.names[model.chipLanguageCode] ?: chip.id,
                                fontSize = 13.5.sp,
                                fontWeight = FontWeight.Medium,
                                color = theme.primaryText,
                                maxLines = 1
                            )
                        }
                    }
                    Pill(
                        theme = theme,
                        width = 40.dp,
                        contentDescriptionText = strings[R.string.kb_add_template],
                        onClick = actions.onAddTemplate
                    ) {
                        Icon(
                            Icons.Filled.Add,
                            contentDescription = null,
                            tint = theme.primaryText,
                            modifier = Modifier.size(16.dp)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun Pill(
    theme: KeyboardTheme,
    width: Dp? = null,
    contentDescriptionText: String? = null,
    onClick: () -> Unit,
    content: @Composable () -> Unit
) {
    val base = Modifier
        .height(28.dp)
        .clip(RoundedCornerShape(14.dp))
        .background(theme.letterKey)
        .clickable(onClick = onClick)
        .padding(horizontal = if (width == null) 13.dp else 0.dp)

    Box(
        modifier = (if (width != null) base.width(width) else base).then(
            if (contentDescriptionText != null) {
                Modifier.describedAs(contentDescriptionText)
            } else {
                Modifier
            }
        ),
        contentAlignment = Alignment.Center
    ) { content() }
}

/** Shorthand for the one accessibility property every tappable pill needs. */
private fun Modifier.describedAs(label: String): Modifier =
    this.semantics { contentDescription = label }

// --------------------------------------------------------------- composer

@Composable
private fun Composer(
    model: ReplyPanelModel,
    actions: ReplyPanelActions,
    strings: AppStrings,
    theme: KeyboardTheme
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 6.dp, vertical = 2.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(theme.panelBackground)
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Header(model, actions, strings, theme)
        SourceMessage(model, actions, theme)

        when (model.stage) {
            ReplyStage.READY -> InstructionArea(model, actions, strings, theme)
            ReplyStage.GENERATING -> GeneratingRow(strings, theme)
            ReplyStage.RESULT -> DraftArea(model, actions, strings, theme)
            ReplyStage.CONFLICT -> ConflictArea(actions, strings, theme)
            ReplyStage.IDLE -> Unit
        }
    }
}

@Composable
private fun Header(
    model: ReplyPanelModel,
    actions: ReplyPanelActions,
    strings: AppStrings,
    theme: KeyboardTheme
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        // The collapsed template selector. Tapping it closes the composer and
        // returns to the chip row, so the user is never locked into a template
        // they picked by mistake.
        Row(
            modifier = Modifier
                .height(24.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(theme.letterKey)
                .clickable(onClick = actions.onClose)
                .padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp)
        ) {
            Text(
                text = model.selectedTemplateName,
                fontSize = 12.5.sp,
                fontWeight = FontWeight.SemiBold,
                color = theme.primaryText,
                maxLines = 1
            )
            Icon(
                Icons.Filled.Close,
                contentDescription = strings[R.string.kb_close],
                tint = theme.primaryText,
                modifier = Modifier.size(11.dp)
            )
        }

        Spacer(Modifier.weight(1f))

        if (model.stage == ReplyStage.RESULT) {
            IconPill(
                theme = theme,
                icon = Icons.Filled.Refresh,
                contentDescriptionText = strings[R.string.kb_regenerate],
                onClick = actions.onRegenerate
            )
            ActionPill(
                label = strings[R.string.kb_insert],
                enabled = !model.draft.isBlank,
                theme = theme,
                modifier = Modifier,
                onClick = actions.onInsert
            )
        }
    }
}

@Composable
private fun SourceMessage(
    model: ReplyPanelModel,
    actions: ReplyPanelActions,
    theme: KeyboardTheme
) {
    Text(
        text = model.sourceMessage,
        fontSize = 12.5.sp,
        color = theme.secondaryText,
        maxLines = if (model.sourceExpanded) 4 else 2,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = actions.onToggleSource)
    )
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(0.5.dp)
            .background(theme.divider)
    )
}

@Composable
private fun InstructionArea(
    model: ReplyPanelModel,
    actions: ReplyPanelActions,
    strings: AppStrings,
    theme: KeyboardTheme
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        KeyboardTextField(
            state = model.instruction,
            placeholder = strings[R.string.kb_instruction_placeholder],
            textStyle = TextStyle(fontSize = 14.sp),
            textColor = theme.primaryText,
            placeholderColor = theme.secondaryText,
            caretColor = theme.accent,
            isActive = model.focus == PanelFocus.INSTRUCTION,
            onTap = { offset ->
                actions.onFocus(PanelFocus.INSTRUCTION)
                actions.onCaret(PanelFocus.INSTRUCTION, offset)
            },
            accessibilityLabel = strings[R.string.kb_instruction_label],
            modifier = Modifier
                .weight(1f)
                .heightIn(min = 34.dp, max = 56.dp)
        )

        MicButton(model.voice, strings, theme, actions.onMic)

        ActionPill(
            label = strings[R.string.kb_generate],
            enabled = true,
            theme = theme,
            modifier = Modifier,
            onClick = actions.onGenerate
        )
    }

    VoiceStatusLine(model.voice, strings, theme)
}

@Composable
private fun DraftArea(
    model: ReplyPanelModel,
    actions: ReplyPanelActions,
    strings: AppStrings,
    theme: KeyboardTheme
) {
    KeyboardTextField(
        state = model.draft,
        placeholder = strings[R.string.kb_draft_title],
        textStyle = TextStyle(fontSize = 15.sp),
        textColor = theme.primaryText,
        placeholderColor = theme.secondaryText,
        caretColor = theme.accent,
        isActive = model.focus == PanelFocus.DRAFT,
        onTap = { offset ->
            actions.onFocus(PanelFocus.DRAFT)
            actions.onCaret(PanelFocus.DRAFT, offset)
        },
        accessibilityLabel = strings[R.string.kb_draft_title],
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 36.dp, max = 92.dp)
    )
}

@Composable
private fun GeneratingRow(strings: AppStrings, theme: KeyboardTheme) {
    Row(
        modifier = Modifier.fillMaxWidth().height(36.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        CircularProgressIndicator(
            modifier = Modifier.size(16.dp),
            strokeWidth = 2.dp,
            color = theme.secondaryText
        )
        Text(strings[R.string.kb_generating], fontSize = 13.sp, color = theme.secondaryText)
    }
}

@Composable
private fun ConflictArea(
    actions: ReplyPanelActions,
    strings: AppStrings,
    theme: KeyboardTheme
) {
    Text(
        text = strings[R.string.kb_host_field_not_empty],
        fontSize = 12.sp,
        fontWeight = FontWeight.Medium,
        color = theme.primaryText,
        maxLines = 2
    )
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        ActionPill(strings[R.string.kb_replace_existing], true, theme, Modifier.weight(1f)) {
            actions.onConflict(ConflictChoice.REPLACE)
        }
        ActionPill(strings[R.string.kb_append_existing], true, theme, Modifier.weight(1f)) {
            actions.onConflict(ConflictChoice.APPEND)
        }
        ActionPill(strings[R.string.kb_keep_typing], true, theme, Modifier.weight(1f), quiet = true) {
            actions.onConflict(ConflictChoice.CANCEL)
        }
    }
}

// ------------------------------------------------------------------ voice

@Composable
private fun MicButton(
    voice: VoiceState,
    strings: AppStrings,
    theme: KeyboardTheme,
    onClick: () -> Unit
) {
    val listening = voice is VoiceState.Listening || voice is VoiceState.Starting
    val processing = voice is VoiceState.Processing

    Box(
        modifier = Modifier
            .size(34.dp)
            .clip(RoundedCornerShape(17.dp))
            .background(if (listening) theme.accent else theme.letterKey)
            .clickable(onClick = onClick)
            .describedAs(
                if (listening) strings[R.string.voice_kb_stop] else strings[R.string.voice_kb_start]
            ),
        contentAlignment = Alignment.Center
    ) {
        when {
            processing -> CircularProgressIndicator(
                modifier = Modifier.size(15.dp),
                strokeWidth = 2.dp,
                color = theme.secondaryText
            )
            listening -> Icon(
                Icons.Filled.Stop,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(16.dp)
            )
            else -> Icon(
                Icons.Filled.Mic,
                contentDescription = null,
                tint = theme.primaryText,
                modifier = Modifier.size(17.dp)
            )
        }
    }
}

/**
 * One line under the instruction field. It is the only place the microphone's
 * state is described in words, and it is always present while the microphone is
 * doing anything — the product rule is that the user must never be uncertain
 * whether they are being recorded.
 */
@Composable
private fun VoiceStatusLine(voice: VoiceState, strings: AppStrings, theme: KeyboardTheme) {
    val message = when (voice) {
        is VoiceState.Starting -> strings[R.string.voice_kb_listening]
        is VoiceState.Listening -> voice.partial.ifBlank { strings[R.string.voice_kb_listening] }
        is VoiceState.Processing -> strings[R.string.voice_kb_processing]
        is VoiceState.PermissionRequired -> strings[R.string.voice_kb_permission_needed]
        is VoiceState.PermissionDenied -> strings[R.string.voice_kb_permission_denied]
        is VoiceState.Failed -> when (voice.reason) {
            VoiceFailure.NO_SPEECH -> strings[R.string.voice_kb_no_speech]
            VoiceFailure.NETWORK -> strings[R.string.kb_err_offline]
            VoiceFailure.LANGUAGE_UNAVAILABLE -> strings[R.string.voice_kb_unavailable]
            VoiceFailure.UNAVAILABLE -> strings[R.string.voice_kb_unavailable]
            VoiceFailure.GENERIC -> strings[R.string.voice_kb_failed]
        }
        else -> null
    } ?: return

    Text(
        text = message,
        fontSize = 11.5.sp,
        color = if (voice is VoiceState.Listening) theme.primaryText else theme.secondaryText,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier.fillMaxWidth()
    )
}

// ------------------------------------------------------------------ pills

@Composable
private fun ActionPill(
    label: String,
    enabled: Boolean,
    theme: KeyboardTheme,
    modifier: Modifier = Modifier,
    quiet: Boolean = false,
    onClick: () -> Unit
) {
    val background = when {
        quiet -> theme.letterKey
        enabled -> theme.accent
        else -> theme.accent.copy(alpha = 0.30f)
    }
    Box(
        modifier = modifier
            .height(28.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(background)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = label,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (quiet) theme.primaryText else Color.White,
            maxLines = 1
        )
    }
}

@Composable
private fun IconPill(
    theme: KeyboardTheme,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    contentDescriptionText: String,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .size(width = 30.dp, height = 26.dp)
            .clip(RoundedCornerShape(13.dp))
            .background(theme.letterKey)
            .clickable(onClick = onClick)
            .describedAs(contentDescriptionText),
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, contentDescription = null, tint = theme.primaryText, modifier = Modifier.size(15.dp))
    }
}

private val IDLE_HEIGHT = 40.dp
