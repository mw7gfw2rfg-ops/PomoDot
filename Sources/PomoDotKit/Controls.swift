import SwiftUI

/// Transport buttons.
///
/// apple-design § 1: feedback lives on the *press*, not on the release. `configuration
/// .isPressed` is bound to the pressed state, so the scale change happens on pointer-down
/// while the action still fires on pointer-up — which is also what lets you slide off a
/// button to cancel (ISA ISC-39).
public struct TransportButtonStyle: ButtonStyle {
    private let accent: Color
    private let prominent: Bool

    public init(accent: Color, prominent: Bool = false) {
        self.accent = accent
        self.prominent = prominent
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Labels are always `.primary`, never the accent.
            //
            // Over translucency the backdrop can be any colour, so a fixed accent hue is a
            // coin flip: orange text over a warm wallpaper disappears. `.primary` resolves
            // against the material and stays legible whatever is behind. The accent still
            // marks the prominent button — via the stroke, which only has to be *noticed*,
            // not *read*. (apple-design § 12: put colour on a layer, not on the
            // translucent foreground.)
            .foregroundStyle(.primary.opacity(prominent ? 0.95 : 0.62))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background {
                // A hairline outline rather than a filled plate — filling it would put an
                // opaque surface on the glass, which the whole design forbids (ISC-21).
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        (prominent ? accent : Color.primary)
                            .opacity(configuration.isPressed ? 0.75 : (prominent ? 0.55 : 0.22)),
                        lineWidth: prominent ? 1.5 : 1
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.springDefault, value: configuration.isPressed)
    }
}

/// A small monospaced preset chip — TE's printed numeric legends, made tappable.
public struct PresetChip: View {
    private let minutes: Int
    private let isSelected: Bool
    private let accent: Color
    private let action: () -> Void

    public init(minutes: Int, isSelected: Bool, accent: Color, action: @escaping () -> Void) {
        self.minutes = minutes
        self.isSelected = isSelected
        self.accent = accent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text("\(minutes)")
                .font(Theme.numeral(10))
                .tracking(Theme.numeralTracking)
                .monospacedDigit()
                // Same rule as the transport labels: selection is carried by the stroke,
                // legibility by `.primary`.
                .foregroundStyle(.primary.opacity(isSelected ? 0.95 : 0.45))
                .frame(width: 26, height: 18)
                .contentShape(Rectangle())
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder((isSelected ? accent : Color.primary).opacity(isSelected ? 0.55 : 0.18),
                                      lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(minutes) minute focus"))
    }
}
