import SwiftUI

/// The app's mark, drawn rather than loaded from the asset catalog.
///
/// Same geometry as the app icon: a keyboard keycap, a reply arrow cut through
/// it, and two sparks. Drawing it means it scales cleanly at any size, follows
/// the accent colour, and does not need its own image asset for every place the
/// onboarding shows it.
struct AppMarkView: View {

    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.357, green: 0.294, blue: 0.910),
                                 Color(red: 0.122, green: 0.435, blue: 0.922)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(.white)
                .offset(x: -size * 0.045, y: size * 0.01)

            Image(systemName: "sparkle")
                .font(.system(size: size * 0.22, weight: .semibold))
                .foregroundStyle(.white)
                .offset(x: size * 0.27, y: -size * 0.25)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 20) {
        AppMarkView(size: 120)
        AppMarkView(size: 64)
        AppMarkView(size: 32)
    }
    .padding()
}
