import SwiftUI

/// The Teenage Engineering tick-ring: a fine 60-tick scale with every 5th emphasised,
/// and a progress arc riding just inside it. TE's visual grammar is a coarse scale drawn
/// over a fine one — it reads as an instrument rather than a graphic (ISA ISC-30).
public struct TickRing: View {
    private let progress: Double
    private let accent: Color
    private let isActive: Bool

    public init(progress: Double, accent: Color, isActive: Bool) {
        self.progress = progress
        self.accent = accent
        self.isActive = isActive
    }

    public var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let radius = size / 2
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                Canvas { context, _ in
                    for index in 0..<Theme.dialTickCount {
                        let isMajor = index % Theme.dialMajorTickEvery == 0
                        let angle = Angle.degrees(Double(index) / Double(Theme.dialTickCount) * 360 - 90)

                        let outer = radius
                        let inner = radius - (isMajor ? 8 : 4)
                        let start = point(center: center, radius: inner, angle: angle)
                        let end = point(center: center, radius: outer, angle: angle)

                        // Ticks the progress has already swept past take the accent.
                        let swept = Double(index) / Double(Theme.dialTickCount) <= progress
                        let color: Color = swept && isActive
                            ? accent
                            : Color.primary.opacity(isMajor ? 0.34 : 0.16)

                        var path = Path()
                        path.move(to: start)
                        path.addLine(to: end)
                        context.stroke(path,
                                       with: .color(color),
                                       style: StrokeStyle(lineWidth: isMajor ? 1.4 : 1,
                                                          lineCap: .round))
                    }
                }

                // The progress arc sits inside the tick scale so the two never collide.
                // Hidden entirely at zero — a round line cap on a zero-length trim still
                // paints a stray dot, which reads as a rendering glitch on an idle timer.
                if progress > 0 {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(accent.opacity(isActive ? 0.9 : 0.35),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(14)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle.radians),
                y: center.y + radius * sin(angle.radians))
    }
}

/// Session pips — how many focus runs are banked in this cycle. Four small squares,
/// because a filled square is the most legible tiny state indicator over glass, and
/// because round pips would read as more dots and compete with the matrix.
public struct SessionPips: View {
    private let filled: Int
    private let total: Int
    private let accent: Color

    public init(filled: Int, total: Int, accent: Color) {
        self.filled = filled
        self.total = total
        self.accent = accent
    }

    public var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { index in
                Rectangle()
                    .fill(index < filled ? accent : Color.primary.opacity(0.22))
                    .frame(width: 12, height: 3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(filled) of \(total) sessions complete"))
    }
}
