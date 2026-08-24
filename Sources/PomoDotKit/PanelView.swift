import SwiftUI
import GlassKit

/// The Liquid Glass panel.
///
/// There is exactly one glass surface in this hierarchy (ISA ISC-18). apple-design § 12 is
/// explicit that stacking a light translucent surface on another collapses legibility, and
/// it's also just wrong materially — real glass on glass is two panes, not one. So: one
/// `.glassEffect` on the root, and every child draws with strokes and dots directly onto it.
/// No child sets a fill.
public struct PanelView: View {
    @Bindable private var engine: TimerEngine
    @Bindable private var log: FocusLog
    private let sound: SoundEngine
    private let onQuit: () -> Void

    /// Mirrors `sound.isMuted` so the chip re-renders on toggle — `SoundEngine` owns audio
    /// resources and isn't an observable model.
    @State private var isMuted: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The focus presets offered as TE-style numeric chips.
    private let presets = [15, 25, 50]

    public init(engine: TimerEngine,
                log: FocusLog,
                sound: SoundEngine,
                onQuit: @escaping () -> Void) {
        self.engine = engine
        self.log = log
        self.sound = sound
        self.onQuit = onQuit
        self._isMuted = State(initialValue: sound.isMuted)
    }

    private var accent: Color { Theme.accent(for: engine.phase) }

    /// `Glass.clear` is the transparent variant — it transmits the backdrop without running
    /// the adaptive dimming that `.regular` applies. We can afford it because the unlit
    /// dot-matrix acts as a local scrim behind the numerals (see ISA § Decisions).
    /// When the user has asked the system for less transparency, we hand that back and
    /// use `.regular`, which does adapt (ISC-41).
    public var body: some View {
        VStack(spacing: 0) {
            header
            dial
            pips
            transport
            footer
            record
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(width: Layout.panelWidth)
        .glassSurface()
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
        .frame(width: Layout.dialSize, height: Layout.dialSize)
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
                PresetChip("\(minutes)",
                           isSelected: engine.durations.focus == minutes * 60,
                           accent: accent) {
                    engine.durations.focus = minutes * 60
                    if engine.phase == .focus { engine.reset() }
                }
            }

            Spacer()

            // Mute. A struck-through note glyph would need an icon font; the legend reading
            // SND / MUTE says the state in words, which is the monospace-only rule anyway.
            Button {
                sound.isMuted.toggle()
                isMuted = sound.isMuted
                // Confirm un-muting audibly — the one case where the cue *is* the feedback.
                if !isMuted { sound.play(.skip) }
            } label: {
                Legend(isMuted ? "MUTE" : "SND", size: 8, opacity: isMuted ? 0.7 : 0.34)
                    .modifier(HitTarget())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isMuted ? "Sound muted, tap to unmute" : "Sound on, tap to mute"))

            Button(action: onQuit) {
                Legend("QUIT", size: 8, opacity: 0.34)
                    .modifier(HitTarget())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Quit PomoDot"))
        }
        .padding(.top, 14)
    }

    // MARK: - Record
    //
    // Separated from the timer above by a hairline: the top of the panel is *now*, this is
    // *history*. They're different kinds of information and shouldn't read as one block.

    private var record: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle()
                .fill(.primary.opacity(0.12))
                .frame(height: 1)

            StatsRow(todaySeconds: log.seconds(on: Date()),
                     weekSeconds: log.secondsInLast(days: 7),
                     totalSeconds: log.totalSeconds)

            // The accent is used here even during a break, when it's otherwise suppressed.
            // Deliberate: the restraint rule says colour marks *focus*, and this whole
            // section is a record of focus. Suppressing it on breaks would make your history
            // flicker for a reason that has nothing to do with your history.
            HeatmapView(dailySeconds: log.dailyTotals(), accent: Theme.focusAccent)
        }
        .padding(.top, 14)
    }
}
