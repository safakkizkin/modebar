import SwiftUI

/// Two italic bars — an equals sign with a rightward shear. Template-friendly.
struct ModeBarMark: Shape {
    /// Horizontal shear as dx/dy (≈ tan 22°).
    var shear: CGFloat = 0.40

    func path(in rect: CGRect) -> Path {
        let barH = rect.height * 0.20
        let gap = rect.height * 0.18
        let contentH = barH * 2 + gap
        let y0 = rect.midY - contentH / 2
        let insetX = rect.width * 0.10
        let span = rect.width - insetX * 2 - abs(shear) * contentH * 0.5
        let half = span / 2

        var path = Path()
        for top in [y0, y0 + barH + gap] {
            path.addPath(parallelogram(
                centerX: rect.midX,
                halfWidth: half,
                top: top,
                bottom: top + barH,
                yRef: rect.midY,
                shear: shear
            ))
        }
        return path
    }

    private func parallelogram(
        centerX: CGFloat,
        halfWidth: CGFloat,
        top: CGFloat,
        bottom: CGFloat,
        yRef: CGFloat,
        shear: CGFloat
    ) -> Path {
        let shiftTop = shear * (top - yRef)
        let shiftBot = shear * (bottom - yRef)
        var p = Path()
        p.move(to: CGPoint(x: centerX - halfWidth + shiftTop, y: top))
        p.addLine(to: CGPoint(x: centerX + halfWidth + shiftTop, y: top))
        p.addLine(to: CGPoint(x: centerX + halfWidth + shiftBot, y: bottom))
        p.addLine(to: CGPoint(x: centerX - halfWidth + shiftBot, y: bottom))
        p.closeSubpath()
        return p
    }
}

struct ModeBarMarkLabel: View {
    var dimmed: Bool = false

    var body: some View {
        ModeBarMark()
            .fill(Color.primary.opacity(dimmed ? 0.45 : 1))
            .frame(width: 16, height: 16)
            .accessibilityLabel("ModeBar")
    }
}
