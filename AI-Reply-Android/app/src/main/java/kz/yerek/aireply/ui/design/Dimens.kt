package kz.yerek.aireply.ui.design

import androidx.compose.ui.unit.dp

/**
 * A deliberately small set of spatial decisions, ported one-to-one from the iOS
 * `DS` enum. An iOS point and an Android dp are the same size on screen, so
 * these numbers transfer without translation and the two apps share a rhythm
 * rather than merely a colour.
 */
object Spacing {
    val xxs = 4.dp
    val xs = 8.dp
    val s = 12.dp
    val m = 16.dp
    val l = 24.dp
    val xl = 32.dp
}

object Radius {
    val small = 8.dp
    val medium = 12.dp
    val large = 16.dp
}

object Layout {
    /**
     * Text stops growing past this width so lines stay readable on a tablet or
     * an unfolded foldable the same way they do on a small phone.
     */
    val readableWidth = 560.dp

    /**
     * Android's minimum comfortable hit target. iOS uses 44pt; 48dp is the
     * Android guideline, and the four extra dp are not worth a worse tap target
     * for the sake of matching a number nobody can see.
     */
    val minimumTouchTarget = 48.dp
}
