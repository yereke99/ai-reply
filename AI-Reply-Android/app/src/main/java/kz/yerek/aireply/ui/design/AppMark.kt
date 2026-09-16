package kz.yerek.aireply.ui.design

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * The app's mark, drawn rather than loaded from a drawable.
 *
 * Same geometry as the launcher icon and as the iOS `AppMarkView`: a rounded
 * square with the brand gradient, a reply arrow, and a spark. Drawing it means
 * it is crisp at any size and needs no asset per density, which is exactly the
 * reason the iOS version draws it too.
 */
@Composable
fun AppMark(size: Dp = 64.dp, modifier: Modifier = Modifier) {
    Canvas(
        modifier = modifier
            .size(size)
            // Purely decorative: the screen around it already says what the app
            // is, and announcing "logo" adds nothing for a screen-reader user.
            .clearAndSetSemantics { }
    ) {
        val side = this.size.minDimension
        val corner = side * 0.225f

        drawRoundRect(
            brush = Brush.verticalGradient(
                listOf(AppColors.MarkGradientTop, AppColors.MarkGradientBottom)
            ),
            size = Size(side, side),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(corner, corner)
        )

        fun p(x: Float, y: Float) = Offset(x / 108f * side, y / 108f * side)

        val arrow = Path().apply {
            moveTo(p(28f, 52f).x, p(28f, 52f).y)
            lineTo(p(48f, 34f).x, p(48f, 34f).y)
            lineTo(p(48f, 44f).x, p(48f, 44f).y)
            cubicTo(
                p(66f, 45.5f).x, p(66f, 45.5f).y,
                p(78f, 56.5f).x, p(78f, 56.5f).y,
                p(80.5f, 77f).x, p(80.5f, 77f).y
            )
            cubicTo(
                p(72f, 62.5f).x, p(72f, 62.5f).y,
                p(62f, 57.5f).x, p(62f, 57.5f).y,
                p(48f, 57.5f).x, p(48f, 57.5f).y
            )
            lineTo(p(48f, 68f).x, p(48f, 68f).y)
            close()
        }
        drawPath(arrow, Color.White)

        val spark = Path().apply {
            moveTo(p(78f, 22f).x, p(78f, 22f).y)
            lineTo(p(80.6f, 29.4f).x, p(80.6f, 29.4f).y)
            lineTo(p(88f, 32f).x, p(88f, 32f).y)
            lineTo(p(80.6f, 34.6f).x, p(80.6f, 34.6f).y)
            lineTo(p(78f, 42f).x, p(78f, 42f).y)
            lineTo(p(75.4f, 34.6f).x, p(75.4f, 34.6f).y)
            lineTo(p(68f, 32f).x, p(68f, 32f).y)
            lineTo(p(75.4f, 29.4f).x, p(75.4f, 29.4f).y)
            close()
        }
        drawPath(spark, Color.White.copy(alpha = 0.95f))
    }
}
