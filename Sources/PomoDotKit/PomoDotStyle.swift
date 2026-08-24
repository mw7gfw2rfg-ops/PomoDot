import SwiftUI
import GlassKit

/// The parts of PomoDot's look that are *about pomodoros* rather than about glass.
///
/// GlassKit owns the design tokens — colour, type, tracking, motion. What lives here is
/// composition: how wide this particular panel is, how big its dial is, and what the accent
/// means in this app's vocabulary. Those are decisions, not tokens, so they don't belong in
/// a shared package where a second app would inherit them by accident.
public enum Layout {
    public static let panelWidth: CGFloat = 268
    public static let dialSize: CGFloat = 158
}

public extension Theme {
    /// Break phases resolve to neutral — colour exists only while you're actually focusing.
    ///
    /// This is GlassKit's "colour marks a state, never a surface" rule spent on the one state
    /// this app has. A different app spends it on something else; that's why the mapping is
    /// here and the ramp is there.
    static func accent(for phase: Phase) -> Color {
        phase.isBreak ? neutralAccent : focusAccent
    }
}

/// The three running totals, in monospaced numerals under micro-caps labels.
public struct StatsRow: View {
    private let today: Int
    private let week: Int
    private let total: Int

    public init(todaySeconds: Int, weekSeconds: Int, totalSeconds: Int) {
        self.today = todaySeconds
        self.week = weekSeconds
        self.total = totalSeconds
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            stat("TODAY", today)
            Spacer(minLength: 0)
            stat("7 DAYS", week)
            Spacer(minLength: 0)
            stat("TOTAL", total)
        }
    }

    private func stat(_ label: String, _ seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Legend(label, size: 8, opacity: 0.34)
            Text(DurationText.short(seconds))
                .font(Theme.numeral(12))
                .tracking(Theme.numeralTracking)
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(0.9))
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(label): \(DurationText.short(seconds))"))
    }
}
