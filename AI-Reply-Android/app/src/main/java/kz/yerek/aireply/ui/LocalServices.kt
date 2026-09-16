package kz.yerek.aireply.ui

import androidx.compose.runtime.staticCompositionLocalOf
import kz.yerek.aireply.ServiceLocator

/**
 * The object graph, available to any screen.
 *
 * WHY NOT A ViewModel PER SCREEN. Almost every screen here is a settings form
 * over one shared, synchronously-readable configuration object; a ViewModel for
 * each would be a layer that forwards calls and owns no state of its own. The
 * two screens with real asynchronous work — "Try a reply" and dictation — do
 * hold their own state objects, which is where that machinery belongs.
 *
 * `staticCompositionLocalOf` rather than `compositionLocalOf` because this never
 * changes for the life of the process, so reads should not be tracked.
 */
val LocalServices = staticCompositionLocalOf<ServiceLocator> {
    error("LocalServices was read outside of the app's CompositionLocalProvider")
}
