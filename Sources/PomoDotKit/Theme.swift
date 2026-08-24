import SwiftUI

/// Design tokens. Every value here is a deliberate choice with a reason, per the
/// apple-design "Craft" principle — nothing is a round number picked at random.
public enum Theme {

    // MARK: - Colour
    //
    // Two references, one rule. Teenage Engineering is black/white plus a single orange
    // hit; Nothing is monochrome plus a single red. Both are "neutral + one accent",
    // so the palette is: neutral everything, orange for focus, red for overrun, and
    // *nothing at all* for breaks. A break is the absence of the accent, which is
    // conceptually right — the colour is what tells you to work.

    /// Teenage Engineering orange. Focus, and only focus.
    public static let focusAccent = Color(red: 1.00, green: 0.35, blue: 0.12)
    /// Nothing red. Reserved for the overrun/attention state.
    public static let alertAccent = Color(red: 0.84, green: 0.10, blue: 0.13)

    /// Break phases resolve to a neutral. This is the single accent rule (ISA ISC-31/32).
    public static func accent(for phase: Phase) -> Color {
        phase.isBreak ? Color.primary.opacity(0.82) : focusAccent
    }

    /// Unlit dot-matrix cells. Low enough to read as "off", present enough to form the
    /// local scrim that lets us sit on clear glass without a background plate.
    public static let dotOff = 0.16
    /// Unlit cells in the menu bar, where the template renderer has less contrast to play with.
    public static let dotOffStatusItem = 0.22

    // MARK: - Typography
    //
    // Teenage Engineering uses monospaced type *exclusively* — it reads as precision
    // without having to say "precision". So: every glyph in this app is either a drawn
    // dot, or monospaced. There is no proportional text anywhere (ISA ISC-27/28).

    /// Micro-caps legend — the small uppercase labels beside controls, TE-style.
    /// Positive tracking, because small text needs letters pushed apart to stay legible,
    /// and doubly so over translucency (apple-design § 15, § 12 vibrancy).
    public static func legend(_ size: CGFloat = 9) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    /// Numeric legends on the dial — TE's little printed numbers beside controls.
    public static func numeral(_ size: CGFloat = 8) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }

    /// Tracking is size-specific, never one value for everything (apple-design § 15).
    /// Small caps get pushed apart; nothing here is large enough to want negative tracking.
    public static let legendTracking: CGFloat = 1.6
    public static let numeralTracking: CGFloat = 0.8

    // MARK: - Geometry

    public static let panelWidth: CGFloat = 268
    public static let panelCornerRadius: CGFloat = 26
    /// Gap between the menu bar and the top of the panel.
    public static let panelTopInset: CGFloat = 6

    public static let dialSize: CGFloat = 158
    public static let dialTickCount = 60
    /// Every 5th tick is emphasised — the TE convention of a coarse scale over a fine one.
    public static let dialMajorTickEvery = 5

    // MARK: - Motion
    //
    // apple-design § 4: default to critically damped; spend bounce only where the
    // gesture itself carried momentum.

    /// Default UI spring — no overshoot, graceful, non-distracting.
    public static let springDefault = Animation.spring(response: 0.38, dampingFraction: 1.0)
    /// For state the user *committed* to (start/skip) — a touch of overshoot as reward.
    public static let springCommit = Animation.spring(response: 0.34, dampingFraction: 0.78)
    /// Panel materialise/dematerialise.
    public static let springPanel = Animation.spring(response: 0.32, dampingFraction: 0.86)
}

/// A reusable micro-caps legend, so the tracking rule can't drift between call sites.
public struct Legend: View {
    private let text: String
    private let size: CGFloat
    private let opacity: Double

    public init(_ text: String, size: CGFloat = 9, opacity: Double = 0.55) {
        self.text = text
        self.size = size
        self.opacity = opacity
    }

    public var body: some View {
        Text(text.uppercased())
            .font(Theme.legend(size))
            .tracking(Theme.legendTracking)
            .foregroundStyle(.primary.opacity(opacity))
    }
}
