package kz.yerek.aireply.keyboard.ui

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kz.yerek.aireply.keyboard.input.KeyboardTextFieldState

/**
 * A text field the keyboard itself edits.
 *
 * WHY NOT `BasicTextField`. A normal text field asks the system for focus and
 * then expects an input method to serve it. Inside an input method that is
 * circular: there is no second keyboard, and requesting focus from an IME
 * window behaves differently across OEM builds. So this renders the text, draws
 * its own caret, and takes edits from the key grid through
 * [KeyboardTextFieldState]. Tapping still moves the caret, because the text
 * layout can be asked which offset a point corresponds to.
 *
 * iOS arrives at the same design from the other end: it asks for first responder
 * as a bonus, and implements the storage-based path anyway so that editing
 * behaves identically when the system refuses. Here that path is the only one,
 * which removes the class of bugs where the two disagree.
 */
@Composable
fun KeyboardTextField(
    state: KeyboardTextFieldState,
    placeholder: String,
    textStyle: TextStyle,
    textColor: Color,
    placeholderColor: Color,
    caretColor: Color,
    isActive: Boolean,
    onTap: (Int) -> Unit,
    modifier: Modifier = Modifier,
    accessibilityLabel: String? = null
) {
    var layout by remember { mutableStateOf<TextLayoutResult?>(null) }
    var caretVisible by remember { mutableStateOf(true) }
    val scroll = rememberScrollState()

    // Blink only while this field is the one being typed into. A caret blinking
    // in a field the keys are not routed to is a lie about where text will go.
    LaunchedEffect(isActive, state.cursor, state.text) {
        if (!isActive) {
            caretVisible = false
            return@LaunchedEffect
        }
        // Restart solid after every edit, so the caret is never invisible at the
        // moment the user is looking for it.
        caretVisible = true
        while (true) {
            delay(BLINK_MS)
            caretVisible = !caretVisible
        }
    }

    val showPlaceholder = state.text.isEmpty()

    Box(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(scroll)
            .then(
                if (accessibilityLabel != null) {
                    Modifier.semantics {
                        contentDescription =
                            if (showPlaceholder) accessibilityLabel else state.text
                    }
                } else {
                    Modifier
                }
            )
            .pointerInput(state) {
                detectTapGestures { position ->
                    val result = layout
                    val offset = if (result == null) {
                        state.text.length
                    } else {
                        result.getOffsetForPosition(position)
                    }
                    onTap(offset)
                }
            }
    ) {
        BasicText(
            text = state.text.ifEmpty { placeholder },
            style = textStyle.copy(color = if (showPlaceholder) placeholderColor else textColor),
            onTextLayout = { layout = it },
            modifier = Modifier
                .fillMaxWidth()
                .drawWithContent {
                    drawContent()
                    if (!isActive || !caretVisible || showPlaceholder) return@drawWithContent
                    val result = layout ?: return@drawWithContent
                    val cursor = state.cursor.coerceIn(0, state.text.length)
                    val rect = runCatching { result.getCursorRect(cursor) }.getOrNull()
                        ?: return@drawWithContent
                    drawRect(
                        color = caretColor,
                        topLeft = Offset(rect.left, rect.top),
                        size = Size(CARET_WIDTH.toPx(), rect.height)
                    )
                }
        )

        // An empty field still needs a caret, and there is no glyph to hang one
        // off, so it is drawn at the origin instead of from the layout result.
        if (isActive && caretVisible && showPlaceholder) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .drawWithContent {
                        drawContent()
                        drawRect(
                            color = caretColor,
                            topLeft = Offset.Zero,
                            size = Size(CARET_WIDTH.toPx(), (textStyle.fontSize.value * 1.25f) * density)
                        )
                    }
            )
        }
    }
}

private val CARET_WIDTH = 2.dp
private const val BLINK_MS = 550L
