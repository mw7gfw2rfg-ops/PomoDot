import SwiftUI
import GlassKit

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
