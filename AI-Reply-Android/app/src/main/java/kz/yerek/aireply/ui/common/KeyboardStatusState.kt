package kz.yerek.aireply.ui.common

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import kz.yerek.aireply.keyboard.input.KeyboardStatus

/**
 * Whether the keyboard is enabled and selected, refreshed whenever the screen
 * comes back to the foreground.
 *
 * Read on resume rather than polled: the two values can only change in system
 * Settings or the input-method picker, both of which take the user out of this
 * app and bring them back.
 */
@Composable
fun rememberKeyboardStatus(): State<KeyboardStatus.Snapshot> {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val state = remember { mutableStateOf(KeyboardStatus.current(context)) }

    DisposableEffect(owner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                state.value = KeyboardStatus.current(context)
            }
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer) }
    }

    return state
}
