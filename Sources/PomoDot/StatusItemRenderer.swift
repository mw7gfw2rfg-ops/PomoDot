import AppKit
import PomoDotKit

/// Draws the menu bar label as a template `NSImage`.
///
/// Template images are the most literal reading of "blend in with Apple UI": macOS tints
/// them itself for light menu bars, dark menu bars, tinted menu bars and the highlighted
/// state, so the item is always exactly the colour every other menu bar item is. Nothing's
/// palette is monochrome anyway, so we lose nothing by giving up colour here — and the
/// accent still lives in the panel (ISA ISC-10).
enum StatusItemRenderer {

    /// Menu bar items get ~24pt of usable height; the 7-row matrix at a 1.7pt dot on a
    /// 2.5pt pitch is ~16.7pt tall — legible without crowding its neighbours.
    private static let dotSize: CGFloat = 1.7
    private static let dotSpacing: CGFloat = 0.8
    private static var pitch: CGFloat { dotSize + dotSpacing }

    /// Width of the progress bar drawn under the digits.
    private static let barHeight: CGFloat = 1.0
    private static let barGap: CGFloat = 2.0

    /// Renders `MM:SS` as dots, with a hairline progress bar beneath.
    /// - Parameter dimmed: draw at reduced alpha, used to pulse the item when a phase ends.
    static func image(clock: String, progress: Double, running: Bool, dimmed: Bool = false) -> NSImage {
        let layout = DotMatrix.layout(clock)
        let matrixWidth = max(0, CGFloat(layout.width) * pitch - dotSpacing)
        let matrixHeight = max(0, CGFloat(DotMatrix.height) * pitch - dotSpacing)
        let totalHeight = matrixHeight + barGap + barHeight

        let image = NSImage(size: NSSize(width: matrixWidth, height: totalHeight),
                            flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return true }

            let litAlpha: CGFloat = dimmed ? 0.35 : 1.0

            // Lit dots only — no unlit grid here.
            //
            // The panel draws the full matrix because the unlit dots are what make it read
            // as a display, and they double as a local scrim over clear glass. Neither
            // reason survives at menu bar scale: a 1.7pt unlit dot sits too close to its lit
            // neighbour to be told apart, so the whole block smears into a grey rectangle,
            // and a template image has nothing to be legible *against* anyway — macOS
            // guarantees its contrast. Tried it at 0.22 alpha, measured it, removed it.
            for (row, cells) in layout.cells.enumerated() {
                for (column, isLit) in cells.enumerated() where isLit {
                    let x = CGFloat(column) * pitch
                    // The glyph table is top-down; the image is bottom-up. Flip y.
                    let y = totalHeight - matrixHeight + CGFloat(DotMatrix.height - 1 - row) * pitch
                    let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                    context.setFillColor(gray: 0, alpha: litAlpha)
                    context.fillEllipse(in: rect)
                }
            }

            // Progress hairline. Full-width track at low alpha, swept portion at full.
            let trackRect = CGRect(x: 0, y: 0, width: matrixWidth, height: barHeight)
            context.setFillColor(gray: 0, alpha: dimmed ? 0.08 : 0.18)
            context.fill(trackRect)

            if running || progress > 0 {
                let sweep = max(0, min(1, progress))
                context.setFillColor(gray: 0, alpha: litAlpha)
                context.fill(CGRect(x: 0, y: 0, width: matrixWidth * sweep, height: barHeight))
            }

            return true
        }

        // The critical line: template mode hands tinting to macOS.
        image.isTemplate = true
        return image
    }
}
