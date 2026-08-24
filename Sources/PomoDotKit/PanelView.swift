import SwiftUI

/// The Liquid Glass panel.
///
/// There is exactly one glass surface in this hierarchy (ISA ISC-18). apple-design § 12 is
/// explicit that stacking a light translucent surface on another collapses legibility, and
/// it's also just wrong materially — real glass on glass is two panes, not one. So: one
/// `.glassEffect` on the root, and every child draws with strokes and dots directly onto it.
/// No child sets a fill.
public struct PanelView: View {
    @Bindable private var engine: TimerEngine
    private let onQuit: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The focus presets offered as TE-style numeric chips.
    private let presets = [15, 25, 50]

    public init(engine: TimerEngine, onQuit: @escaping () -> Void) {
        self.engine = engine
        self.onQuit = onQuit
    }

    private var accent: Color { Theme.accent(for: engine.phase) }

    /// `Glass.clear` is the transparent variant — it transmits the backdrop without running
    /// the adaptive dimming that `.regular` applies. We can afford it because the unlit
    /// dot-matrix acts as a local scrim behind the numerals (see ISA § Decisions).
    /// When the user has asked the system for less transparency, we hand that back and
    /// use `.regular`, which does adapt (ISC-41).
    /// A/B'd `.clear` against `.regular` over identical saturated backdrops: on macOS 27
    /// they render near-identically here, so `.clear` costs nothing and is the literal
    /// reading of "purely transparent". `.regular` is kept for Reduce Transparency, where
    /// its adaptive dimming is the point.
    private var glass: Glass {
        reduceTransparency ? .regular : .clear
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            dial
            pips
            transport
            footer
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(width: Theme.panelWidth)
        .glassEffect(glass, in: .rect(cornerRadius: Theme.panelCornerRadius))
        .animation(reduceMotion ? nil : Theme.springDefault, value: engine.phase)
        .animation(reduceMotion ? nil : Theme.springDefault, value: engine.state)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 7) {
            // A status LED beside a monochrome label, rather than a coloured label.
            // Nothing's glyph interface in miniature — and it means the phase colour
            // survives any backdrop, because a filled dot only has to be seen, not read.
            Circle()
                .fill(accent)
                .frame(width: 5, height: 5)
                .opacity(engine.state == .running ? 1 : 0.45)

            Legend(engine.phase.legend, opacity: 0.9)
            Spacer()
            Legend(stateLegend, opacity: 0.42)
        }
        .padding(.bottom, 12)
    }

    private var stateLegend: String {
        switch engine.state {
        case .running: "RUN"
        case .paused: "HOLD"
        case .idle: "READY"
        }
    }

    // MARK: - Dial + matrix

    private var dial: some View {
        ZStack {
            // Bound to the published snapshots, not to `progress`/`clockText`: those read a
            // wall clock, which the observation system can't see advance.
            TickRing(progress: engine.displayProgress,
                     accent: accent,
                     isActive: engine.state == .running)

            // The countdown itself. Always `.primary` — never the accent. This is the one
            // element whose entire job is to be read at a glance, so it gets the colour
            // that can't lose a fight with the wallpaper. The accent is carried by the LED,
            // the swept ticks, the arc, the pips and the button strokes instead.
            //
            // Pitch 4.6 puts a 25-column MM:SS at ~113pt, which clears the 158pt ring with
            // ~22pt of air each side. At pitch 6 the digits collided with the tick scale.
            DotMatrixView(DotMatrix.clockString(engine.displayRemaining),
                          dotSize: 3,
                          dotSpacing: 1.6,
                          litColor: .primary.opacity(engine.state == .running ? 0.95 : 0.8),
                          unlitOpacity: reduceTransparency ? 0.10 : Theme.dotOff)
                .animation(nil, value: engine.displayRemaining)  // digits swap, they don't slide
        }
        .frame(width: Theme.dialSize, height: Theme.dialSize)
        .frame(maxWidth: .infinity)
    }

    private var pips: some View {
        SessionPips(filled: engine.pipsFilled, total: engine.pipsTotal, accent: accent)
            .padding(.top, 10)
            .padding(.bottom, 14)
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 8) {
            Button(engine.state == .running ? "PAUSE" : "START") {
                withAnimation(reduceMotion ? nil : Theme.springCommit) { engine.toggle() }
            }
            .buttonStyle(TransportButtonStyle(accent: accent, prominent: true))
            .font(Theme.legend(9))

            Button("SKIP") {
                withAnimation(reduceMotion ? nil : Theme.springCommit) { engine.skip() }
            }
            .buttonStyle(TransportButtonStyle(accent: accent))
            .font(Theme.legend(9))

            Button("RESET") {
                withAnimation(reduceMotion ? nil : Theme.springDefault) { engine.reset() }
            }
            .buttonStyle(TransportButtonStyle(accent: accent))
            .font(Theme.legend(9))
        }
        .textCase(.uppercase)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Legend("MIN", size: 8, opacity: 0.34)

            ForEach(presets, id: \.self) { minutes in
                PresetChip(minutes: minutes,
                           isSelected: engine.durations.focus == minutes * 60,
                           accent: accent) {
                    engine.durations.focus = minutes * 60
                    if engine.phase == .focus { engine.reset() }
                }
            }

            Spacer()

            Button(action: onQuit) {
                Legend("QUIT", size: 8, opacity: 0.34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Quit PomoDot"))
        }
        .padding(.top, 14)
    }
}
