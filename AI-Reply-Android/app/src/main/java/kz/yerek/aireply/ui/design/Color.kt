package kz.yerek.aireply.ui.design

import androidx.compose.ui.graphics.Color

/**
 * The palette, reverse-engineered from the iOS app.
 *
 * iOS spends most of its colour budget on semantic system colours
 * (`systemGroupedBackground`, `secondarySystemGroupedBackground`, `separator`),
 * which is why its design system file is so small. Those values are stable and
 * published, so they are written out here rather than approximated with
 * Material's generated tonal palettes — which would produce a different app
 * that happened to use the same accent.
 *
 * The accent is the app's own, from `AccentColor.colorset`, and dynamic colour
 * is deliberately off: the product has an identity, and inheriting the user's
 * wallpaper would erase the one thing that makes the two platforms recognisably
 * the same app.
 */
object AppColors {

    // Brand ------------------------------------------------------------------

    /** AccentColor, light appearance: sRGB 0.286 / 0.435 / 0.925. */
    val AccentLight = Color(0xFF496FEC)

    /** AccentColor, dark appearance: sRGB 0.404 / 0.545 / 1.000. */
    val AccentDark = Color(0xFF678BFF)

    /** The app mark's gradient, top and bottom. */
    val MarkGradientTop = Color(0xFF5B4BE8)
    val MarkGradientBottom = Color(0xFF1F6FEB)

    // Light ------------------------------------------------------------------

    /** systemGroupedBackground */
    val BackgroundLight = Color(0xFFF2F2F7)

    /** secondarySystemGroupedBackground — the raised card surface */
    val SurfaceLight = Color(0xFFFFFFFF)

    val SeparatorLight = Color(0xFFC6C6C8)
    val TextPrimaryLight = Color(0xFF000000)
    val TextSecondaryLight = Color(0xFF8A8A8E)
    val TextTertiaryLight = Color(0xFFC0C0C4)

    // Dark -------------------------------------------------------------------

    val BackgroundDark = Color(0xFF000000)
    val SurfaceDark = Color(0xFF1C1C1E)
    val SeparatorDark = Color(0xFF38383A)
    val TextPrimaryDark = Color(0xFFFFFFFF)
    val TextSecondaryDark = Color(0xFF98989F)
    val TextTertiaryDark = Color(0xFF636366)

    // Status -----------------------------------------------------------------

    val Success = Color(0xFF34C759)
    val Warning = Color(0xFFFF9500)
    val DangerLight = Color(0xFFFF3B30)
    val DangerDark = Color(0xFFFF453A)
}
