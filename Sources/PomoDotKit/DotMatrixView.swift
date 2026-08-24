import SwiftUI

/// Renders a string as a dot-matrix display.
///
/// The unlit dots are drawn, not skipped. That is the whole point: it's what makes this
/// read as a matrix *display* rather than as a stylised font, and it's what gives the lit
/// dots a field to sit against so the panel can be genuinely transparent behind them
/// (ISA ISC-24). Dots are circles, per NDot's rounded-dot construction (ISC-25).
public struct DotMatrixView: View {
    private let text: String
    private let dotSize: CGFloat
    private let dotSpacing: CGFloat
    private let litColor: Color
    private let unlitOpacity: Double

    public init(_ text: String,
                dotSize: CGFloat = 6,
                dotSpacing: CGFloat = 3,
                litColor: Color = .primary,
                unlitOpacity: Double = Theme.dotOff) {
        self.text = text
        self.dotSize = dotSize
        self.dotSpacing = dotSpacing
        self.litColor = litColor
        self.unlitOpacity = unlitOpacity
    }

    private var pitch: CGFloat { dotSize + dotSpacing }

    public var body: some View {
        let layout = DotMatrix.layout(text)
        Canvas { context, _ in
            for (y, row) in layout.cells.enumerated() {
                for (x, isLit) in row.enumerated() {
                    let rect = CGRect(x: CGFloat(x) * pitch,
                                      y: CGFloat(y) * pitch,
                                      width: dotSize,
                                      height: dotSize)
                    // Unlit cells are a faint version of the lit colour — NOT a dark
                    // substrate, even though a physical matrix display has one.
                    //
                    // Tried the dark-substrate version and screenshotted it: over a
                    // mid-tone backdrop the dark unlit cells contrast *with the backdrop*,
                    // so lit and unlit dots compete and the digits collapse into
                    // high-frequency noise. The governing rule is that unlit cells must sit
                    // close to the backdrop so only the lit ones pop — which is what
                    // dimming the lit colour does, in either appearance.
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(isLit ? litColor : litColor.opacity(unlitOpacity))
                    )
                }
            }
        }
        .frame(
            width: max(0, CGFloat(layout.width) * pitch - dotSpacing),
            height: max(0, CGFloat(DotMatrix.height) * pitch - dotSpacing)
        )
        // The matrix is a display of a value, not decoration — expose the value, not the dots.
        .accessibilityElement()
        .accessibilityLabel(Text(text))
    }
}
