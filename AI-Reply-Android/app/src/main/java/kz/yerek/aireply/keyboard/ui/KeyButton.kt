package kz.yerek.aireply.keyboard.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * One key.
 *
 * PRESS TIMING matches the system keyboard and the iOS build: keys that only
 * type fire on PRESS, so typing feels instant; keys that rebuild the whole grid
 * (plane switch, layout switch, globe) fire on RELEASE, so the key is never torn
 * out from under the finger mid-touch.
 *
 * THE SHADOW is a hard 1dp bottom edge, not a blur — the same weight the iOS
 * keys get from a zero-radius shadow offset one point down. It is drawn as a
 * second rounded rectangle behind the key rather than with `Modifier.shadow`,
 * which would produce a soft Material elevation shadow and, more to the point,
 * an offscreen rendering pass per key on every frame.
 *
 * REPEAT lives here rather than on the service because it is a property of
 * holding this key down, and because a coroutine tied to the composition is
 * cancelled automatically when the keyboard goes away — which a timer owned by
 * the service would not be.
 */
@Composable
fun KeyButton(
    width: Dp?,
    height: Dp,
    cornerRadius: Dp,
    background: Color,
    pressedBackground: Color,
    contentColor: Color,
    shadow: Color,
    modifier: Modifier = Modifier,
    firesOnPress: Boolean = true,
    repeatWhileHeld: Boolean = false,
    contentDescriptionText: String? = null,
    onLongPress: (() -> Unit)? = null,
    onActivate: () -> Unit,
    content: @Composable () -> Unit
) {
    var pressed by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    val sized = if (width != null) modifier.width(width) else modifier

    Box(
        modifier = sized
            .height(height)
            .then(
                if (contentDescriptionText != null) {
                    Modifier.semantics { contentDescription = contentDescriptionText }
                } else {
                    Modifier
                }
            )
            .clip(RoundedCornerShape(cornerRadius))
            .background(shadow)
            .pointerInput(firesOnPress, repeatWhileHeld, onActivate, onLongPress) {
                detectTapGestures(
                    onPress = {
                        pressed = true
                        if (firesOnPress) onActivate()

                        val repeatJob = if (repeatWhileHeld) {
                            scope.launch {
                                delay(REPEAT_DELAY_MS)
                                while (isActive) {
                                    onActivate()
                                    delay(REPEAT_INTERVAL_MS)
                                }
                            }
                        } else {
                            null
                        }

                        val releasedInside = tryAwaitRelease()
                        repeatJob?.cancel()
                        pressed = false
                        if (!firesOnPress && releasedInside) onActivate()
                    },
                    onLongPress = onLongPress?.let { action -> { action() } }
                )
            }
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(bottom = 1.dp)
                .clip(RoundedCornerShape(cornerRadius))
                .background(if (pressed) pressedBackground else background),
            contentAlignment = Alignment.Center
        ) {
            CompositionLocalProvider(LocalContentColor provides contentColor) {
                content()
            }
        }
    }
}

/**
 * Key captions are sized in sp but rendered inside a density whose font scale is
 * pinned to 1 (see [KeyGrid]), so a 2x accessibility font setting cannot push
 * the letters out of their keys.
 */
@Composable
fun KeyLabel(text: String, fontSize: Float, weight: FontWeight = FontWeight.Normal) {
    Text(
        text = text,
        fontSize = fontSize.sp,
        fontWeight = weight,
        textAlign = TextAlign.Center,
        maxLines = 1,
        modifier = Modifier.clearAndSetSemantics { }
    )
}

@Composable
fun KeyIcon(icon: ImageVector, size: Dp = 22.dp) {
    Icon(imageVector = icon, contentDescription = null, modifier = Modifier.size(size))
}

private const val REPEAT_DELAY_MS = 450L
private const val REPEAT_INTERVAL_MS = 85L
