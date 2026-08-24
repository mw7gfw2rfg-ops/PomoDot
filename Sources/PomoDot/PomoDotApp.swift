import AppKit
import SwiftUI
import PomoDotKit

/// Entry point. Not a SwiftUI `App` scene: this app has no windows in the SwiftUI sense,
/// only a status item and a panel it owns directly, so an `NSApplicationDelegate` is the
/// honest shape for it.
@main
enum PomoDotMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // .accessory = no Dock icon, no ⌘-Tab entry (ISA ISC-13). Info.plist's LSUIElement
        // covers this too; setting it here means it holds even when run from the CLI.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let engine = TimerEngine()
    private var statusItem: NSStatusItem!
    private var panel: GlassPanel?
    private var ticker: Timer?
    private var clickMonitor: Any?
    private var napSuppression: NSObjectProtocol?

    /// Frames the status item pulse after a phase ends, so the menu bar nags gently.
    private var pulseFramesRemaining = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        restoreSettings()
        installStatusItem()

        engine.onPhaseCompleted = { [weak self] finished in
            self?.handlePhaseCompleted(finished)
        }

        // 1 Hz is enough: `remaining` is derived from a deadline, so this timer only
        // exists to notice the zero-crossing and to prompt a redraw. Missing a tick
        // (during sleep, say) costs nothing — the next one reads the correct time.
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        ticker?.tolerance = 0.15
        // .common mode, or the menu bar countdown visibly stalls whenever a menu is being
        // tracked and then jumps several seconds when it closes. The deadline math stays
        // correct either way — this is purely about the redraw.
        RunLoop.main.add(ticker!, forMode: .common)

        // App Nap will throttle a background accessory app's timers. The phase length is
        // still correct on wake (it's read from a clock), but the visible countdown freezes,
        // which reads as a broken app.
        napSuppression = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Pomodoro countdown must keep redrawing"
        )
        refreshStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        persistSettings()
        ticker?.invalidate()
        removeClickMonitor()
        if let napSuppression { ProcessInfo.processInfo.endActivity(napSuppression) }
    }

    // MARK: - Status item

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "PomoDot"
    }

    private func refreshStatusItem() {
        let dimmed = pulseFramesRemaining > 0 && pulseFramesRemaining % 2 == 0
        statusItem.button?.image = StatusItemRenderer.image(
            clock: engine.clockText,
            progress: engine.progress,
            running: engine.state == .running,
            dimmed: dimmed
        )
    }

    @objc private func statusItemClicked() {
        pulseFramesRemaining = 0
        panel?.isVisible == true ? hidePanel() : showPanel()
    }

    // MARK: - Tick

    private func tick() {
        engine.tick()
        if pulseFramesRemaining > 0 { pulseFramesRemaining -= 1 }
        refreshStatusItem()
    }

    private func handlePhaseCompleted(_ finished: Phase) {
        // Deliberately not UNUserNotificationCenter: that requires a signed, notarised
        // bundle and fails silently otherwise. A sound plus a pulsing menu bar item plus
        // opening the panel always works, on any build (ISA § Decisions).
        NSSound(named: finished == .focus ? "Glass" : "Submarine")?.play()
        pulseFramesRemaining = 8
        showPanel()
    }

    // MARK: - Panel

    private func showPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel

        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let frameOnScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        panel.position(below: frameOnScreen, on: buttonWindow.screen)

        panel.orderFrontRegardless()
        installClickMonitor()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        removeClickMonitor()
    }

    private func makePanel() -> GlassPanel {
        let root = PanelView(engine: engine, onQuit: { NSApp.terminate(nil) })
        let hosting = NSHostingView(rootView: MaterialisingPanel { root })
        // .intrinsicContentSize is what makes the hosting view report a real
        // intrinsicContentSize; .preferredContentSize alone only drives the window and
        // leaves both size queries at zero.
        hosting.sizingOptions = [.intrinsicContentSize, .preferredContentSize]
        // Give SwiftUI a layout pass now, so the panel has a real size the first time it's
        // positioned rather than on the second open.
        hosting.layoutSubtreeIfNeeded()
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        return GlassPanel(contentView: hosting)
    }

    /// Dismiss on a click anywhere outside the panel. The global monitor catches clicks in
    /// other apps; the local one catches clicks in our own status item area.
    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    // MARK: - Persistence
    //
    // UserDefaults, because the entire state worth saving is three integers. A file format
    // would be machinery nobody asked for.

    private func restoreSettings() {
        let defaults = UserDefaults.standard
        var durations = Durations.standard
        if defaults.object(forKey: "focus") != nil {
            durations.focus = defaults.integer(forKey: "focus")
            durations.shortBreak = defaults.integer(forKey: "shortBreak")
            durations.longBreak = defaults.integer(forKey: "longBreak")
        }
        engine.durations = durations
        engine.reset()
    }

    private func persistSettings() {
        let defaults = UserDefaults.standard
        defaults.set(engine.durations.focus, forKey: "focus")
        defaults.set(engine.durations.shortBreak, forKey: "shortBreak")
        defaults.set(engine.durations.longBreak, forKey: "longBreak")
    }
}

/// Wraps the panel so it *materialises* rather than fading.
///
/// apple-design § 12: "animate blur radius and scale together on enter/exit, so the surface
/// reads as a real material arriving rather than a plain opacity fade" (ISA ISC-40).
struct MaterialisingPanel<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .scaleEffect(appeared ? 1 : 0.94, anchor: .top)
            .blur(radius: appeared ? 0 : 6)
            .opacity(appeared ? 1 : 0)
            .padding(12)  // room for the shadow, and for the scale-up not to clip
            .onAppear {
                guard !reduceMotion else { appeared = true; return }
                withAnimation(Theme.springPanel) { appeared = true }
            }
    }
}
