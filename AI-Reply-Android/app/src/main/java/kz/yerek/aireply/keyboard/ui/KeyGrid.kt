package kz.yerek.aireply.keyboard.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Backspace
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.KeyboardCapslock
import androidx.compose.material.icons.filled.Language
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kz.yerek.aireply.core.lang.KeyboardLanguage
import kz.yerek.aireply.core.lang.KeyboardPlane
import kz.yerek.aireply.keyboard.KeyFontStyle
import kz.yerek.aireply.keyboard.KeyVisualStyle
import kz.yerek.aireply.keyboard.KeyboardKey
import kz.yerek.aireply.keyboard.KeyboardMetrics
import kz.yerek.aireply.keyboard.KeyboardTheme
import kz.yerek.aireply.keyboard.title
import kotlin.math.max

/** Everything the grid needs to draw itself. Nothing in it changes per keystroke. */
data class KeyGridState(
    val language: KeyboardLanguage,
    val plane: KeyboardPlane,
    val isShifted: Boolean,
    val isCapsLocked: Boolean,
    val showsGlobeKey: Boolean,
    val layoutBadge: String,
    val spaceLabel: String,
    val returnLabel: String,
    val returnIsProminent: Boolean
)

/** Accessibility labels, resolved by the caller so this file holds no strings. */
data class KeyGridLabels(
    val shift: String,
    val backspace: String,
    val switchKeyboard: String,
    val switchLayout: String
)

/**
 * The typing area.
 *
 * WHAT MAKES THIS FAST. The grid reads only [state] and [metrics]; neither
 * changes while the user types, so a keystroke recomposes nothing here at all.
 * A shift tap changes one boolean and relabels the letter keys, which is the
 * only per-tap recomposition in the keyboard. The reply panel's state is held
 * separately and read only by the panel, so a generation in flight — spinner,
 * partial voice transcript, growing draft — never touches the keys.
 *
 * That is the same conclusion the iOS build reaches with its page cache and its
 * "nothing in the typing path touches UserDefaults" rule, expressed in the way
 * Compose expresses it: keep the state a view reads as small as what it draws.
 */
@Composable
fun KeyGrid(
    state: KeyGridState,
    labels: KeyGridLabels,
    theme: KeyboardTheme,
    metrics: KeyboardMetrics,
    onKey: (KeyboardKey) -> Unit,
    onGlobeLongPress: () -> Unit,
    modifier: Modifier = Modifier
) {
    val density = LocalDensity.current

    // Key captions must not scale with the user's font-size setting. At 1.3x a
    // Cyrillic layout already starts clipping, and at 2x the keys would be
    // unusable rather than more readable. The rest of the app respects the
    // setting; this one grid is sized in physical space on purpose.
    CompositionLocalProvider(
        LocalDensity provides Density(density.density, fontScale = 1f)
    ) {
        Column(
            modifier = modifier
                .fillMaxWidth()
                .padding(horizontal = metrics.sidePadding),
            verticalArrangement = Arrangement.spacedBy(metrics.rowGap)
        ) {
            if (state.plane == KeyboardPlane.LETTERS) {
                LetterRows(state, labels, theme, metrics, onKey)
            } else {
                PlaneRows(state, labels, theme, metrics, onKey)
            }
            BottomRow(state, labels, theme, metrics, onKey, onGlobeLongPress)
        }
    }
}

@Composable
private fun LetterRows(
    state: KeyGridState,
    labels: KeyGridLabels,
    theme: KeyboardTheme,
    metrics: KeyboardMetrics,
    onKey: (KeyboardKey) -> Unit
) {
    val rows = state.language.letterRows
    val columns = state.language.gridColumns
    val unit = metrics.unitWidth(columns)

    rows.forEachIndexed { index, row ->
        val keys = row.map { KeyboardKey.Character(it) }
        when {
            state.language.rowFillsWidth(index) ->
                EvenRow(keys, state, labels, theme, metrics, columns, onKey)
            index == rows.lastIndex ->
                ShiftedRow(keys, unit, state, labels, theme, metrics, columns, onKey)
            else ->
                GridRow(keys, unit, columns, state, labels, theme, metrics, columns, onKey)
        }
    }
}

@Composable
private fun PlaneRows(
    state: KeyGridState,
    labels: KeyGridLabels,
    theme: KeyboardTheme,
    metrics: KeyboardMetrics,
    onKey: (KeyboardKey) -> Unit
) {
    val rows = state.plane.rows
    val columns = state.plane.gridColumns
    val unit = metrics.unitWidth(columns)

    rows.forEachIndexed { index, row ->
        val keys = row.map { KeyboardKey.Character(it) }
        if (index == rows.lastIndex) {
            val alternate = if (state.plane == KeyboardPlane.NUMBERS) {
                KeyboardPlane.SYMBOLS
            } else {
                KeyboardPlane.NUMBERS
            }
            val full = listOf(KeyboardKey.Plane(alternate)) + keys + listOf(KeyboardKey.Backspace)
            EvenRow(full, state, labels, theme, metrics, columns, onKey)
        } else {
            GridRow(keys, unit, columns, state, labels, theme, metrics, columns, onKey)
        }
    }
}

/** Row whose keys sit on the shared grid, centred when it holds fewer than [columns]. */
@Composable
private fun GridRow(
    keys: List<KeyboardKey>,
    unit: Dp,
    columns: Int,
    state: KeyGridState,
    labels: KeyGridLabels,
    theme: KeyboardTheme,
    metrics: KeyboardMetrics,
    gridColumns: Int,
    onKey: (KeyboardKey) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(metrics.columnGap)
    ) {
        val needsPadding = keys.size < columns
        if (needsPadding) Spacer(Modifier.weight(1f))
        keys.forEach { key -> Key(key, unit, state, labels, theme, metrics, gridColumns, onKey) }
        if (needsPadding) Spacer(Modifier.weight(1f))
    }
}

/**
 * Last letter row: shift, the letters, delete. Shift and delete absorb the
 * leftover width so they stay comfortably wide instead of shrinking to letter
 * size on a 12-column Cyrillic layout.
 */
@Composable
private fun ShiftedRow(
    keys: List<KeyboardKey>,
    unit: Dp,
    state: KeyGridState,
    labels: KeyGridLabels,
    theme: KeyboardTheme,
    metrics: KeyboardMetrics,
    gridColumns: Int,
    onKey: (KeyboardKey) -> Unit
) {
    val slots = keys.size + 2
    val gaps = metrics.columnGap.value * (slots - 1)
    val leftover = metrics.availableRowWidth.value - gaps - keys.size * unit.value
    val sideWidth = max(unit.value, leftover / 2f).dp

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(metrics.columnGap)
    ) {
        Key(KeyboardKey.Shift, sideWidth, state, labels, theme, metrics, gridColumns, onKey)
        keys.forEach { key -> Key(key, unit, state, labels, theme, metrics, gridColumns, onKey) }
        Key(KeyboardKey.Backspace, sideWidth, state, labels, theme, metrics, gridColumns, onKey)
    }
}

/** Row that spreads its keys edge to edge (Kazakh letter row, symbol rows). */
@Composable
private fun EvenRow(
    keys: List<KeyboardKey>,
    state: KeyGridState,
    labels: KeyGridLabels,
    theme: KeyboardTheme,
    metrics: KeyboardMetrics,
    gridColumns: Int,
    onKey: (KeyboardKey) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(metrics.columnGap)
    ) {
        keys.forEach { key ->
            Key(key, null, state, labels, theme, metrics, gridColumns, onKey, Modifier.weight(1f))
        }
    }
}

@Composable
private fun BottomRow(
    state: KeyGridState,
    labels: KeyGridLabels,
    theme: KeyboardTheme,
    metrics: KeyboardMetrics,
    onKey: (KeyboardKey) -> Unit,
    onGlobeLongPress: () -> Unit
) {
    val planeTarget = if (state.plane == KeyboardPlane.LETTERS) {
        KeyboardPlane.NUMBERS
    } else {
        KeyboardPlane.LETTERS
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(metrics.columnGap)
    ) {
        Key(KeyboardKey.Plane(planeTarget), metrics.controlKeyWidth, state, labels, theme, metrics, 10, onKey)

        // Shown only when the system says another input method is available to
        // switch to, exactly as iOS shows the globe only when needed.
        if (state.showsGlobeKey) {
            Key(
                KeyboardKey.Globe, metrics.controlKeyWidth, state, labels, theme, metrics, 10, onKey,
                onLongPress = onGlobeLongPress
            )
        }

        Key(KeyboardKey.Layout, metrics.controlKeyWidth, state, labels, theme, metrics, 10, onKey)
        Key(KeyboardKey.Space, null, state, labels, theme, metrics, 10, onKey, Modifier.weight(1f))
        Key(KeyboardKey.Return, metrics.returnKeyWidth, state, labels, theme, metrics, 10, onKey)
    }
}

// ----------------------------------------------------------------- one key

@Composable
private fun RowScope.Key(
    key: KeyboardKey,
    width: Dp?,
    state: KeyGridState,
    labels: KeyGridLabels,
    theme: KeyboardTheme,
    metrics: KeyboardMetrics,
    gridColumns: Int,
    onKey: (KeyboardKey) -> Unit,
    modifier: Modifier = Modifier,
    onLongPress: (() -> Unit)? = null
) {
    val style = visualStyle(key, state)
    val background = when (style) {
        KeyVisualStyle.LETTER -> theme.letterKey
        KeyVisualStyle.SPECIAL -> theme.specialKey
        KeyVisualStyle.ENGAGED -> theme.engagedKey
        KeyVisualStyle.PROMINENT -> theme.accent
    }
    val pressedBackground = when (style) {
        KeyVisualStyle.LETTER -> theme.letterKeyPressed
        KeyVisualStyle.SPECIAL -> theme.specialKeyPressed
        KeyVisualStyle.ENGAGED -> theme.engagedKey
        KeyVisualStyle.PROMINENT -> theme.accent.copy(alpha = 0.72f)
    }
    val contentColor = when (style) {
        KeyVisualStyle.LETTER, KeyVisualStyle.SPECIAL -> theme.primaryText
        KeyVisualStyle.ENGAGED -> theme.engagedKeyGlyph
        KeyVisualStyle.PROMINENT -> Color.White
    }

    KeyButton(
        width = width,
        height = metrics.keyHeight,
        cornerRadius = metrics.cornerRadius,
        background = background,
        pressedBackground = pressedBackground,
        contentColor = contentColor,
        shadow = theme.keyShadow,
        modifier = modifier,
        firesOnPress = key.firesOnPress,
        repeatWhileHeld = key is KeyboardKey.Backspace,
        contentDescriptionText = contentDescription(key, labels),
        onLongPress = onLongPress,
        onActivate = { onKey(key) }
    ) {
        when (key) {
            is KeyboardKey.Character -> {
                val label = if (state.plane == KeyboardPlane.LETTERS) displayed(key.value, state) else key.value
                val compact = metrics.unitWidth(gridColumns) < 30.dp
                KeyLabel(
                    label,
                    metrics.fontSize(
                        if (compact) KeyFontStyle.COMPACT_CHARACTER else KeyFontStyle.CHARACTER
                    )
                )
            }
            KeyboardKey.Shift -> KeyIcon(
                if (state.isCapsLocked) Icons.Filled.KeyboardCapslock else Icons.Filled.ArrowUpward,
                20.dp
            )
            KeyboardKey.Backspace -> KeyIcon(Icons.AutoMirrored.Filled.Backspace, 21.dp)
            is KeyboardKey.Plane -> KeyLabel(key.target.title, metrics.fontSize(KeyFontStyle.CONTROL))
            KeyboardKey.Globe -> KeyIcon(Icons.Filled.Language, 20.dp)
            KeyboardKey.Layout -> KeyLabel(state.layoutBadge, 13f, FontWeight.SemiBold)
            KeyboardKey.Space -> KeyLabel(state.spaceLabel, metrics.fontSize(KeyFontStyle.SPACE))
            KeyboardKey.Return -> KeyLabel(state.returnLabel, metrics.fontSize(KeyFontStyle.CONTROL))
        }
    }
}

private fun visualStyle(key: KeyboardKey, state: KeyGridState): KeyVisualStyle = when (key) {
    is KeyboardKey.Character, KeyboardKey.Space -> KeyVisualStyle.LETTER
    KeyboardKey.Shift ->
        if (state.isShifted || state.isCapsLocked) KeyVisualStyle.ENGAGED else KeyVisualStyle.SPECIAL
    KeyboardKey.Return ->
        if (state.returnIsProminent) KeyVisualStyle.PROMINENT else KeyVisualStyle.SPECIAL
    else -> KeyVisualStyle.SPECIAL
}

private fun displayed(value: String, state: KeyGridState): String =
    if (state.isShifted || state.isCapsLocked) value.uppercase() else value

private fun contentDescription(key: KeyboardKey, labels: KeyGridLabels): String? = when (key) {
    KeyboardKey.Shift -> labels.shift
    KeyboardKey.Backspace -> labels.backspace
    KeyboardKey.Globe -> labels.switchKeyboard
    KeyboardKey.Layout -> labels.switchLayout
    else -> null
}
