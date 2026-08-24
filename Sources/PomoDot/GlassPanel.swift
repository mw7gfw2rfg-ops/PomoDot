import AppKit
import SwiftUI

/// A borderless, genuinely non-opaque panel.
///
/// This is why the app doesn't use `MenuBarExtra(.window)`: that scene's hosting window
/// supplies its own material with no documented hook to clear it, and "purely transparent"
/// is the primary requirement here. Owning the `NSPanel` costs ~60 lines and buys direct
/// control over `isOpaque` and `backgroundColor` (ISA ISC-14, ISC-15).
final class GlassPanel: NSPanel {

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            // .nonactivatingPanel keeps the frontmost app frontmost — clicking the timer
            // shouldn't steal focus from whatever the user is actually working on.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // The transparency floor. Without these, macOS composites an opaque surface
        // beneath the content and no material can undo it.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        isFloatingPanel = true
        // .popUpMenu rather than .statusBar: this behaves like a menu, so it should sit
        // above other status windows rather than competing with them for order.
        level = .popUpMenu
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        self.contentView = contentView
        // The hosting view must be clear too — a white NSView here would defeat everything.
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = .clear
    }

    // Borderless panels are not key by default, but the panel holds buttons.
    override var canBecomeKey: Bool { true }

    /// Positions the panel under a status item, clamped to the visible screen.
    ///
    /// apple-design § 7: anchor interactions to their source. The panel emerges from the
    /// menu bar item that opened it, not from the middle of the screen (ISA ISC-19).
    func position(below statusItemFrame: NSRect, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main, let content = contentView else { return }
        let visible = screen.visibleFrame
        let size = measuredContentSize(of: content)

        // Centre horizontally on the status item, then keep it fully on screen.
        var x = statusItemFrame.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)

        // Clamp vertically too. In a full-screen app the menu bar auto-hides and the status
        // item's window frame can sit above the visible area, which would otherwise place
        // the panel off the top of the screen where it silently can't be seen.
        var y = statusItemFrame.minY - size.height - PanelMetrics.topInset
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - PanelMetrics.topInset)

        setContentSize(size)
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// `NSHostingView.fittingSize` reports zero until SwiftUI has run a layout pass, and a
    /// window sized 0x0 orders front perfectly happily — it's just invisible, with no error
    /// anywhere. Force the pass, then fall back to the known design size if it still
    /// measures empty, so the panel can never be silently sized out of existence.
    private func measuredContentSize(of content: NSView) -> NSSize {
        content.layoutSubtreeIfNeeded()
        // intrinsicContentSize is the one NSHostingView actually populates from the SwiftUI
        // root's ideal size; fittingSize stays zero until the view is in a window.
        for candidate in [content.intrinsicContentSize, content.fittingSize]
        where candidate.width >= 1 && candidate.height >= 1 {
            return candidate
        }
        return PanelMetrics.fallbackSize
    }
}

enum PanelMetrics {
    static let topInset: CGFloat = 6
    /// Panel width plus the shadow padding in `MaterialisingPanel`, and a generous height.
    static let fallbackSize = NSSize(width: 268 + 24, height: 400)
}
