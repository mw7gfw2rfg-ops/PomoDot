import Foundation
import Observation

/// The Pomodoro phases. Break phases deliberately carry no accent colour —
/// colour exists only during focus, so it reads as a signal rather than decoration
/// (ISA § Principles, "restraint carries the meaning").
public enum Phase: String, Sendable, CaseIterable {
    case focus
    case shortBreak
    case longBreak

    public var legend: String {
        switch self {
        case .focus: "FOCUS"
        case .shortBreak: "BREAK"
        case .longBreak: "LONG BREAK"
        }
    }

    public var isBreak: Bool { self != .focus }
}

public enum RunState: Sendable, Equatable {
    case idle
    case running
    case paused
}

/// User-tunable phase lengths, in seconds.
public struct Durations: Sendable, Equatable {
    public var focus: Int
    public var shortBreak: Int
    public var longBreak: Int
    /// How many focus phases complete before a long break is served.
    public var longBreakEvery: Int

    public static let standard = Durations(focus: 25 * 60,
                                           shortBreak: 5 * 60,
                                           longBreak: 15 * 60,
                                           longBreakEvery: 4)

    public init(focus: Int, shortBreak: Int, longBreak: Int, longBreakEvery: Int) {
        self.focus = focus
        self.shortBreak = shortBreak
        self.longBreak = longBreak
        self.longBreakEvery = longBreakEvery
    }

    public func length(of phase: Phase) -> Int {
        switch phase {
        case .focus: focus
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }
}

/// The Pomodoro state machine.
///
/// **Time is read from a clock, never accumulated.** While running, the engine stores an
/// absolute `deadline` and derives remaining time by subtracting `now` from it. This is
/// the difference between a timer that survives a closed lid and one that silently loses
/// however long the machine was asleep — a decrementing tick counter stops being ticked
/// when the process is suspended, and comes back wrong. It also makes the display
/// completely independent of tick frequency (ISA ISC-33, ISC-37).
@Observable
@MainActor
public final class TimerEngine {

    public private(set) var phase: Phase = .focus
    public private(set) var state: RunState = .idle
    /// Focus phases completed since the last long break. Drives the session pips.
    public private(set) var completedFocusRuns: Int = 0
    /// Focus phases completed in total, across all cycles.
    public private(set) var totalFocusRuns: Int = 0

    public var durations: Durations {
        didSet {
            if state == .idle { remainingWhenIdle = durations.length(of: phase) }
            publish()
        }
    }

    /// Observable snapshots of `remaining` / `progress`, republished on every `tick()`.
    ///
    /// `remaining` is derived from a wall clock, and the observation system cannot see a
    /// clock advance — nothing it tracks changes, so a SwiftUI view bound to `remaining`
    /// renders once and then sits frozen while the menu bar (which re-reads by hand every
    /// second) counts down correctly. These stored mirrors are what views bind to.
    /// `remaining` stays the source of truth; these are a view of it.
    public private(set) var displayRemaining: Int
    public private(set) var displayProgress: Double = 0

    /// Instant the current phase ends. Only meaningful while running.
    ///
    /// `ContinuousClock`, not `Date`: `Date` is a wall clock, so an NTP correction or a DST
    /// change jumps the deadline and the phase ends early or late for no reason the user can
    /// see. `ContinuousClock` is monotonic — immune to clock adjustment — and, unlike
    /// `SuspendingClock`, it keeps counting while the machine is asleep, which is what a
    /// Pomodoro should do: 25 minutes means 25 minutes of real elapsed time.
    private var deadline: ContinuousClock.Instant?
    /// Remaining seconds while idle or paused — the only time we store a duration.
    private var remainingWhenIdle: Int

    /// Injected so tests can control time without sleeping.
    private let now: @Sendable () -> ContinuousClock.Instant

    /// Fired when a phase reaches zero, with the phase that just ended.
    public var onPhaseCompleted: ((Phase) -> Void)?

    /// Fired whenever a focus phase ends by any route — completed, skipped or reset — with
    /// the seconds *actually* focused and the instant the focus began.
    ///
    /// Actual elapsed, not the nominal phase length: logging 25 minutes for a session
    /// abandoned at 3 would make the heatmap flatter you, and a log that flatters you is one
    /// you stop trusting. Paused time is already excluded because `remaining` doesn't move
    /// while paused.
    public var onFocusEnded: ((_ seconds: Int, _ start: Date) -> Void)?

    /// Wall-clock instant the current focus phase began, for attributing it to a calendar
    /// day. Separate from `deadline`, which is monotonic and has no calendar meaning.
    private var focusStartedAt: Date?

    /// Fired for each transport action so the app can play a cue.
    public var onCue: ((Cue) -> Void)?

    public init(durations: Durations = .standard,
                now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.durations = durations
        self.now = now
        self.remainingWhenIdle = durations.length(of: .focus)
        self.displayRemaining = durations.length(of: .focus)
    }

    /// Republishes the observable snapshots from the clock-derived source of truth.
    /// Called from every transport method and from `tick()`.
    private func publish() {
        displayRemaining = remaining
        displayProgress = progress
    }

    // MARK: - Derived state

    /// Seconds left in the current phase, floored at zero.
    public var remaining: Int {
        switch state {
        case .running:
            guard let deadline else { return 0 }
            let left = now().duration(to: deadline)
            let seconds = Double(left.components.seconds)
                + Double(left.components.attoseconds) / 1e18
            return max(0, Int(seconds.rounded(.up)))
        case .idle, .paused:
            return remainingWhenIdle
        }
    }

    /// 0...1 through the current phase. Used by the tick ring and the status item arc.
    public var progress: Double {
        let total = durations.length(of: phase)
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(total - remaining) / Double(total)))
    }

    public var clockText: String { DotMatrix.clockString(remaining) }

    // MARK: - Transport

    public func start() {
        guard state != .running else { return }
        deadline = now().advanced(by: .seconds(remainingWhenIdle))
        // Stamp the calendar instant only on the *first* start of a focus phase, so
        // pause/resume doesn't re-attribute the session to a later day.
        if phase == .focus, focusStartedAt == nil { focusStartedAt = Date() }
        state = .running
        publish()
        onCue?(.start)
    }

    public func pause() {
        guard state == .running else { return }
        remainingWhenIdle = remaining
        deadline = nil
        state = .paused
        publish()
        onCue?(.pause)
    }

    public func toggle() {
        state == .running ? pause() : start()
    }

    /// Returns the current phase to its full length without changing which phase we're in.
    public func reset() {
        // Restarting a focus phase still banks whatever was focused before the restart.
        reportFocusEnded()
        state = .idle
        deadline = nil
        remainingWhenIdle = durations.length(of: phase)
        publish()
        onCue?(.reset)
    }

    /// Abandons the current phase and moves to the next one, stopped.
    /// A skipped focus phase does NOT count as completed — you don't earn a pip for
    /// work you didn't do. It *does* still log the minutes actually focused; pips count
    /// finished pomodoros, the log counts time, and they answer different questions.
    public func skip() {
        advance(countingCompletion: false)
        onCue?(.skip)
    }

    /// Banks any in-progress focus time at shutdown, so quitting mid-session doesn't discard
    /// the minutes already worked. Idempotent — the start stamp is cleared on report.
    public func flushFocusForShutdown() {
        reportFocusEnded()
    }

    /// Emits the focus time accrued so far, if we're in a focus phase that has started.
    /// Clears the stamp so the same stretch can never be reported twice.
    private func reportFocusEnded() {
        guard phase == .focus, let startedAt = focusStartedAt else { return }
        let elapsed = durations.focus - remaining
        focusStartedAt = nil
        guard elapsed > 0 else { return }
        onFocusEnded?(elapsed, startedAt)
    }

    /// Drives the clock. Call at ~1 Hz. Safe to call at any frequency, or not at all:
    /// `remaining` is derived from the deadline, so this only exists to notice the
    /// zero-crossing and to prompt a redraw.
    public func tick() {
        guard state == .running else { return }
        publish()
        guard remaining == 0 else { return }
        let finished = phase
        advance(countingCompletion: true)
        onCue?(finished == .focus ? .focusEnded : .breakEnded)
        onPhaseCompleted?(finished)
    }

    // MARK: - Phase advance

    private func advance(countingCompletion: Bool) {
        // Must run before `remaining` is reset by the phase change.
        reportFocusEnded()
        if phase == .focus && countingCompletion {
            completedFocusRuns += 1
            totalFocusRuns += 1
        }
        phase = nextPhase(after: phase, countingCompletion: countingCompletion)
        state = .idle
        deadline = nil
        remainingWhenIdle = durations.length(of: phase)
        publish()
    }

    private func nextPhase(after current: Phase, countingCompletion: Bool) -> Phase {
        switch current {
        case .focus:
            // A long break is earned by the Nth completed focus run, not the Nth attempt.
            let runs = countingCompletion ? completedFocusRuns : completedFocusRuns + 1
            let earnedLongBreak = countingCompletion
                && durations.longBreakEvery > 0
                && runs % durations.longBreakEvery == 0
            return earnedLongBreak ? .longBreak : .shortBreak
        case .shortBreak:
            return .focus
        case .longBreak:
            // A long break closes the cycle — the pips reset.
            completedFocusRuns = 0
            return .focus
        }
    }

    /// Number of pips to show filled in the current cycle.
    public var pipsFilled: Int { completedFocusRuns }
    public var pipsTotal: Int { max(1, durations.longBreakEvery) }
}
