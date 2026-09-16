package kz.yerek.aireply.keyboard.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import kz.yerek.aireply.ai.AppStrings
import kz.yerek.aireply.keyboard.KeyboardKey
import kz.yerek.aireply.keyboard.KeyboardMetrics
import kz.yerek.aireply.keyboard.KeyboardTheme

/**
 * The whole keyboard: the reply panel, then the keys.
 *
 * The ordering of these two is the product's central layout guarantee. The panel
 * is laid out first and takes whatever height it needs; the grid is sized from
 * [KeyboardMetrics] alone and is never asked to give any of it back. So the
 * keyboard window grows when a reply is being composed, and typing feels the
 * same in every state.
 */
@Composable
fun KeyboardRoot(
    gridState: KeyGridState,
    gridLabels: KeyGridLabels,
    panelModel: ReplyPanelModel,
    panelActions: ReplyPanelActions,
    strings: AppStrings,
    theme: KeyboardTheme,
    metrics: KeyboardMetrics,
    onKey: (KeyboardKey) -> Unit,
    onGlobeLongPress: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(theme.background)
            // Sits above the gesture bar rather than under it, so the bottom row
            // of keys is not half-covered on a gesture-navigation device.
            .navigationBarsPadding()
    ) {
        ReplyPanel(
            model = panelModel,
            actions = panelActions,
            strings = strings,
            theme = theme,
            // The panel may grow, but never past the point where it would hide
            // the conversation the user is replying to.
            maxHeight = metrics.availableHeight * 0.42f
        )

        Spacer(Modifier.height(metrics.actionBarGap + metrics.topPadding))

        KeyGrid(
            state = gridState,
            labels = gridLabels,
            theme = theme,
            metrics = metrics,
            onKey = onKey,
            onGlobeLongPress = onGlobeLongPress
        )

        Spacer(Modifier.height(metrics.bottomPadding))
    }
}
