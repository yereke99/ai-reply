package kz.yerek.aireply.keyboard

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * All keyboard geometry, derived from the live width and the number of rows the
 * current layout needs.
 *
 * Nothing here is a hard-coded frame, which is what lets one set of numbers
 * serve a 5" phone, a foldable's cover screen, and the 5-row Kazakh layout —
 * and what lets the iOS formulas port across unchanged, since an iOS point and
 * an Android dp are the same size on screen.
 *
 * ONE ANDROID ADDITION: [availableHeight]. iOS is portrait-locked, so its
 * keyboard can never be asked to fit into 380dp of screen. Android can, every
 * time someone turns their phone sideways, so the key height is scaled down
 * when the rows would otherwise eat the whole display.
 */
data class KeyboardMetrics(
    val width: Dp,
    /** Letter/number rows, excluding the bottom control row. */
    val contentRowCount: Int,
    val availableHeight: Dp
) {

    val rowCount: Int get() = contentRowCount + 1

    val sidePadding: Dp get() = 3.dp
    val topPadding: Dp get() = 5.dp
    val bottomPadding: Dp get() = 5.dp

    val columnGap: Dp get() = if (width >= 375.dp) 6.dp else 5.dp
    val rowGap: Dp get() = if (rowCount >= 5) 8.dp else 11.dp

    /**
     * Native portrait keys are ~42-46dp tall. We stay in that band, compress
     * for the taller 5-row Kazakh layout, and compress again if the screen is
     * too short to give the rows their preferred height.
     */
    val keyHeight: Dp
        get() {
            val base = when {
                width >= 410.dp -> 48f
                width >= 375.dp -> 46f
                else -> 43f
            }
            val forRows = if (rowCount >= 5) (base * 0.855f).roundToInt().toFloat() else base

            // The rows may use at most this much of the screen. The reply panel
            // and the host app's own content need the rest, and a keyboard that
            // fills a landscape display is unusable whatever its key size.
            val budget = availableHeight.value * 0.52f
            val needed = rowCount * forRows + (rowCount - 1) * rowGap.value +
                topPadding.value + bottomPadding.value
            if (availableHeight.value <= 0f || needed <= budget) return forRows.dp

            val slack = budget - (rowCount - 1) * rowGap.value - topPadding.value - bottomPadding.value
            // Never below a thumb-sized key; a cramped keyboard beats an
            // untappable one, and anything smaller means the device is too
            // short for a keyboard at all.
            return max(30f, slack / rowCount).dp
        }

    val typingHeight: Dp
        get() = topPadding + keyHeight * rowCount + rowGap * (rowCount - 1) + bottomPadding

    /** Height of the idle chip row. The panel grows past this; the keys never shrink for it. */
    val actionBarHeight: Dp get() = 42.dp
    val actionBarGap: Dp get() = 3.dp

    val cornerRadius: Dp get() = if (keyHeight >= 44.dp) 6.dp else 5.dp

    val availableRowWidth: Dp get() = width - sidePadding * 2

    /** Width of a single key on a row that spans [columns] evenly spaced slots. */
    fun unitWidth(columns: Int): Dp {
        if (columns <= 0) return 0.dp
        val gaps = columnGap * (columns - 1)
        return max(1f, (availableRowWidth - gaps).value / columns).dp
    }

    /** Fixed-size keys on the bottom row: plane switch, globe, language. */
    val controlKeyWidth: Dp
        get() = min(52f, max(38f, (width.value * 0.108f).roundToInt().toFloat())).dp

    val returnKeyWidth: Dp get() = (controlKeyWidth.value * 1.55f).roundToInt().dp

    fun fontSize(style: KeyFontStyle): Float = when (style) {
        KeyFontStyle.CHARACTER -> if (keyHeight >= 44.dp) 23f else 21f
        KeyFontStyle.COMPACT_CHARACTER -> if (keyHeight >= 44.dp) 20f else 18f
        KeyFontStyle.CONTROL -> 15f
        KeyFontStyle.SPACE -> 15f
    }
}

enum class KeyFontStyle { CHARACTER, COMPACT_CHARACTER, CONTROL, SPACE }
