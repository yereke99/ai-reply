package kz.yerek.aireply.ui.design

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * Type scale matched to the iOS text styles.
 *
 * SF Pro is not shipped: it is Apple-licensed, and a 4 MB font that renders
 * Kazakh slightly differently from the system one is a bad trade for a
 * similarity nobody will notice. What carries across is the PROPORTION — the
 * step sizes and weights, which are what makes a screen feel like the same
 * screen — rendered in the platform's own family.
 *
 * Sizes are in sp, so the user's font-size setting is respected everywhere in
 * the app. The one place it is deliberately pinned is the keyboard's key grid,
 * where a 2x accessibility scale would make the keys unlayoutable rather than
 * more readable.
 */
private val Default = FontFamily.Default

val AppTypography = Typography(
    // iOS .largeTitle 34
    displaySmall = TextStyle(fontFamily = Default, fontSize = 32.sp, lineHeight = 38.sp, fontWeight = FontWeight.SemiBold),
    // iOS .title 28
    headlineLarge = TextStyle(fontFamily = Default, fontSize = 26.sp, lineHeight = 32.sp, fontWeight = FontWeight.SemiBold),
    // iOS .title2 22
    headlineMedium = TextStyle(fontFamily = Default, fontSize = 21.sp, lineHeight = 27.sp, fontWeight = FontWeight.SemiBold),
    // iOS .headline 17 semibold
    titleLarge = TextStyle(fontFamily = Default, fontSize = 17.sp, lineHeight = 23.sp, fontWeight = FontWeight.SemiBold),
    titleMedium = TextStyle(fontFamily = Default, fontSize = 16.sp, lineHeight = 22.sp, fontWeight = FontWeight.Medium),
    // iOS .subheadline 15
    titleSmall = TextStyle(fontFamily = Default, fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold),
    // iOS .body 17
    bodyLarge = TextStyle(fontFamily = Default, fontSize = 16.sp, lineHeight = 23.sp, fontWeight = FontWeight.Normal),
    // iOS .callout 16
    bodyMedium = TextStyle(fontFamily = Default, fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.Normal),
    // iOS .footnote 13
    bodySmall = TextStyle(fontFamily = Default, fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Normal),
    labelLarge = TextStyle(fontFamily = Default, fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold),
    labelMedium = TextStyle(fontFamily = Default, fontSize = 13.sp, lineHeight = 17.sp, fontWeight = FontWeight.Medium),
    // iOS .caption 12
    labelSmall = TextStyle(fontFamily = Default, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Normal)
)
