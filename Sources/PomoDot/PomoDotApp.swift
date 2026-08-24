import AppKit
import SwiftUI
import GlassKit
import PomoDotKit

/// Entry point.
///
/// Everything about *being a menu bar app* — status item, transparent panel, click-outside
/// dismissal, screen anchoring, the redraw tick, App Nap suppression — now lives in
/// GlassKit. What's left is the wiring that's actually about pomodoros.
@main
enum PomoDotMain {
    static func main() {
        MenuBarAppDelegate.run(AppDelegate())
    }
}

@MainActor
final class AppDelegate: MenuBarAppDelegate {

    private let engine = TimerEngine()
    private let log = FocusLog()
    private let sound = SoundEngine()

    /// Frames the status item pulse after a phase ends, so the menu bar nags gently.
    private var pulseFramesRemaining = 0

    override var napReason: String { "Pomodoro countdown must keep redrawing" }

    override func makeController() -> MenuBarController {
        restoreSettings()

        let controller = MenuBarController(
            statusItem: { [unowned self] in
                let dimmed = pulseFramesRemaining > 0 && pulseFramesRemaining % 2 == 0
                return StatusItemRenderer.image(text: engine.clockText,
                                                progress: engine.progress,
                                                running: engine.state == .running,
                                                dimmed: dimmed)
            },
            panel: { [unowned self] in
                AnyView(PanelView(engine: engine,
                                  log: log,
                                  sound: sound,
                                  onQuit: { NSApp.terminate(nil) }))
            }
        )

        controller.onTick = { [unowned self] in
            engine.tick()
            if pulseFramesRemaining > 0 { pulseFramesRemaining -= 1 }
        }

        engine.onPhaseCompleted = { [weak self, weak controller] _ in
            // The cue itself is played by `onCue`, which fires for every transport event;
            // this handler owns only the visual half. Deliberately not
            // UNUserNotificationCenter — that needs a signed, notarised bundle and fails
            // silently otherwise, whereas a sound plus a pulse plus opening the panel works
            // on any build.
            self?.pulseFramesRemaining = 8
            controller?.showPanel()
        }
        engine.onCue = { [weak self] cue in self?.sound.play(cue) }
        engine.onFocusEnded = { [weak self] seconds, start in
            self?.log.record(seconds: seconds, start: start)
        }

        return controller
    }

    override func applicationIsTerminating() {
        // Bank any focus accrued but not yet ended. Quitting 20 minutes into a session and
        // losing all 20 is the kind of silent loss that makes a tracker untrustworthy.
        engine.flushFocusForShutdown()
        persistSettings()
    }

    // MARK: - Persistence
    //
    // UserDefaults, because the entire state worth saving is three integers.

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
