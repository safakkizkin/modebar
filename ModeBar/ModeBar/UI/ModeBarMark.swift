import AppKit
import SwiftUI

/// Two italic bars drawn into a template `NSImage` at 1x/2x/3x so the menu bar stays sharp.
enum ModeBarMarkImage {
    static func template(pointSize: CGFloat = 16) -> NSImage {
        let scales: [CGFloat] = [1, 2, 3]
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        for scale in scales {
            let px = Int((pointSize * scale).rounded())
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: px,
                pixelsHigh: px,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else { continue }
            rep.size = NSSize(width: pointSize, height: pointSize)
            NSGraphicsContext.saveGraphicsState()
            if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = ctx
                ctx.imageInterpolation = .none
                ctx.shouldAntialias = true
                drawBars(in: NSRect(x: 0, y: 0, width: pointSize, height: pointSize), scale: scale)
            }
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }
        image.isTemplate = true
        return image
    }

    private static func drawBars(in rect: NSRect, scale: CGFloat) {
        NSColor.black.setFill()
        let shear: CGFloat = 0.36
        let barH = max(2 / scale, rect.height * 0.22)
        let gap = max(1.5 / scale, rect.height * 0.16)
        let contentH = barH * 2 + gap
        let y0 = rect.midY - contentH / 2
        let inset: CGFloat = rect.width * 0.08
        let span = rect.width - inset * 2 - abs(shear) * contentH * 0.35
        let half = span / 2
        let yRef = rect.midY

        for top in [y0, y0 + barH + gap] {
            let bottom = top + barH
            let shiftTop = shear * (top - yRef)
            let shiftBot = shear * (bottom - yRef)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.midX - half + shiftTop, y: top))
            path.line(to: NSPoint(x: rect.midX + half + shiftTop, y: top))
            path.line(to: NSPoint(x: rect.midX + half + shiftBot, y: bottom))
            path.line(to: NSPoint(x: rect.midX - half + shiftBot, y: bottom))
            path.close()
            path.fill()
        }
    }
}

struct ModeBarMarkLabel: View {
    var dimmed: Bool = false

    var body: some View {
        Image(nsImage: ModeBarMarkImage.template())
            .renderingMode(.template)
            .opacity(dimmed ? 0.55 : 1)
            .frame(width: 16, height: 16)
            .accessibilityLabel("ModeBar")
    }
}
