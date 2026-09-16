package kz.yerek.aireply.ui.design

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import kz.yerek.aireply.data.settings.AppearancePreference

/**
 * Colours the app uses that Material's scheme has no slot for, kept beside it
 * rather than squeezed into `surfaceTint` and friends where the next reader
 * would have to guess what they meant.
 */
data class AppExtraColors(
    val separator: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val success: Color,
    val warning: Color
)

val LocalExtraColors = staticCompositionLocalOf {
    AppExtraColors(
        separator = AppColors.SeparatorLight,
        textSecondary = AppColors.TextSecondaryLight,
        textTertiary = AppColors.TextTertiaryLight,
        success = AppColors.Success,
        warning = AppColors.Warning
    )
}

private val LightScheme = lightColorScheme(
    primary = AppColors.AccentLight,
    onPrimary = Color.White,
    primaryContainer = AppColors.AccentLight.copy(alpha = 0.12f),
    onPrimaryContainer = AppColors.AccentLight,
    background = AppColors.BackgroundLight,
    onBackground = AppColors.TextPrimaryLight,
    surface = AppColors.SurfaceLight,
    onSurface = AppColors.TextPrimaryLight,
    surfaceVariant = AppColors.BackgroundLight,
    onSurfaceVariant = AppColors.TextSecondaryLight,
    outline = AppColors.SeparatorLight,
    outlineVariant = AppColors.SeparatorLight,
    error = AppColors.DangerLight,
    onError = Color.White
)

private val DarkScheme = darkColorScheme(
    primary = AppColors.AccentDark,
    onPrimary = Color.White,
    primaryContainer = AppColors.AccentDark.copy(alpha = 0.18f),
    onPrimaryContainer = AppColors.AccentDark,
    background = AppColors.BackgroundDark,
    onBackground = AppColors.TextPrimaryDark,
    surface = AppColors.SurfaceDark,
    onSurface = AppColors.TextPrimaryDark,
    surfaceVariant = AppColors.SurfaceDark,
    onSurfaceVariant = AppColors.TextSecondaryDark,
    outline = AppColors.SeparatorDark,
    outlineVariant = AppColors.SeparatorDark,
    error = AppColors.DangerDark,
    onError = Color.White
)

/**
 * @param appearance the user's explicit choice. [AppearancePreference.SYSTEM]
 *   hands the decision back to the device, which is what `nil` does in the iOS
 *   `colorScheme` property.
 */
@Composable
fun AIReplyTheme(
    appearance: AppearancePreference = AppearancePreference.SYSTEM,
    content: @Composable () -> Unit
) {
    val dark = when (appearance) {
        AppearancePreference.SYSTEM -> isSystemInDarkTheme()
        AppearancePreference.LIGHT -> false
        AppearancePreference.DARK -> true
    }

    val extras = if (dark) {
        AppExtraColors(
            separator = AppColors.SeparatorDark,
            textSecondary = AppColors.TextSecondaryDark,
            textTertiary = AppColors.TextTertiaryDark,
            success = AppColors.Success,
            warning = AppColors.Warning
        )
    } else {
        AppExtraColors(
            separator = AppColors.SeparatorLight,
            textSecondary = AppColors.TextSecondaryLight,
            textTertiary = AppColors.TextTertiaryLight,
            success = AppColors.Success,
            warning = AppColors.Warning
        )
    }

    CompositionLocalProvider(LocalExtraColors provides extras) {
        MaterialTheme(
            colorScheme = if (dark) DarkScheme else LightScheme,
            typography = AppTypography,
            content = content
        )
    }
}
