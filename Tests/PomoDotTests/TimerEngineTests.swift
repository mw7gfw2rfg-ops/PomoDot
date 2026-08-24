import Testing
import Foundation
@testable import PomoDotKit
import GlassKit

/// A controllable clock, so tests assert on time arithmetic rather than on sleeping.
@MainActor
private final class FakeClock {
    var now = ContinuousClock.now
    func advance(_ seconds: Double) { now = now.advanced(by: .seconds(seconds)) }
    var provider: @Sendable () -> ContinuousClock.Instant {
        // Captured by reference through a box so `advance` is visible to the engine.
        let box = self
        return { MainActor.assumeIsolated { box.now } }
    }
}

@MainActor
private func makeEngine(_ durations: Durations = .standard) -> (TimerEngine, FakeClock) {
    let clock = FakeClock()
    let engine = TimerEngine(durations: durations, now: clock.provider)
    return (engine, clock)
}

// MARK: - Deadline arithmetic

@Test @MainActor
func remainingIsDerivedFromDeadlineNotFromTickCount() {
    // ISA ISC-37. The engine must report the same remaining time whether it was ticked
    // once, a hundred times, or not at all — because it reads a clock rather than
    // accumulating. This is the property that makes it survive system sleep.
    let (engine, clock) = makeEngine()
    engine.start()

    clock.advance(60)
    let withoutTicks = engine.remaining

    let (other, otherClock) = makeEngine()
    other.start()
    otherClock.advance(60)
    for _ in 0..<60 { other.tick() }

    #expect(withoutTicks == other.remaining)
    #expect(withoutTicks == 24 * 60)
}

@Test @MainActor
func remainingSurvivesAJumpLongerThanThePhase() {
    // The closed-lid case: the process is suspended for longer than the phase lasts.
    // A decrementing counter would come back with a stale positive value; a deadline
    // clamps to zero and the next tick completes the phase.
    let (engine, clock) = makeEngine()
    engine.start()
    clock.advance(60 * 60 * 3)

    #expect(engine.remaining == 0)
    engine.tick()
    #expect(engine.phase == .shortBreak)
}

@Test @MainActor
func remainingNeverGoesNegative() {
    let (engine, clock) = makeEngine()
    engine.start()
    clock.advance(25 * 60 + 500)
    #expect(engine.remaining == 0)
}

@Test @MainActor
func tickRepublishesTheObservableSnapshots() {
    // Regression: the panel once rendered a frozen 25:00 while the menu bar counted down
    // correctly. `remaining` is derived from a clock, and SwiftUI's observation system
    // can't see a clock advance — so nothing it tracked ever changed and the view never
    // re-rendered. `displayRemaining`/`displayProgress` are the stored mirrors that fix it,
    // and this asserts `tick()` actually republishes them.
    let (engine, clock) = makeEngine()
    engine.start()
    #expect(engine.displayRemaining == 25 * 60)

    clock.advance(30)
    #expect(engine.displayRemaining == 25 * 60, "no tick yet, so the snapshot is still stale")

    engine.tick()
    #expect(engine.displayRemaining == 24 * 60 + 30)
    #expect(engine.displayRemaining == engine.remaining)
    #expect(abs(engine.displayProgress - engine.progress) < 0.0001)
}

@Test @MainActor
func transportMethodsRepublishSnapshotsImmediately() {
    // Every transport action must leave the snapshot correct without waiting for a tick,
    // otherwise the panel shows the previous phase's time for up to a second after a skip.
    let (engine, clock) = makeEngine()

    engine.start()
    clock.advance(60)
    engine.pause()
    #expect(engine.displayRemaining == 24 * 60)

    engine.reset()
    #expect(engine.displayRemaining == 25 * 60)

    engine.skip()
    #expect(engine.displayRemaining == 5 * 60, "snapshot must follow the phase change at once")

    engine.durations.shortBreak = 7 * 60
    #expect(engine.displayRemaining == 7 * 60)
}

// MARK: - Phase cadence

@Test @MainActor
func fourthCompletedFocusYieldsLongBreak() {
    // ISA ISC-36. The headline cadence rule: three short breaks, then a long one.
    let (engine, clock) = makeEngine()

    for cycle in 1...4 {
        #expect(engine.phase == .focus)
        engine.start()
        clock.advance(Double(engine.durations.focus))
        engine.tick()

        if cycle < 4 {
            #expect(engine.phase == .shortBreak, "cycle \(cycle) should give a short break")
            engine.start()
            clock.advance(Double(engine.durations.shortBreak))
            engine.tick()
        } else {
            #expect(engine.phase == .longBreak, "the 4th focus should earn the long break")
        }
    }
}

@Test @MainActor
func longBreakResetsThePipCycle() {
    let (engine, clock) = makeEngine()
    for _ in 1...4 {
        engine.start()
        clock.advance(Double(engine.durations.focus))
        engine.tick()
        if engine.phase != .longBreak {
            engine.start()
            clock.advance(Double(engine.durations.shortBreak))
            engine.tick()
        }
    }
    #expect(engine.phase == .longBreak)
    #expect(engine.pipsFilled == 4)

    engine.start()
    clock.advance(Double(engine.durations.longBreak))
    engine.tick()

    #expect(engine.phase == .focus)
    #expect(engine.pipsFilled == 0, "the cycle closes when the long break is taken")
}

@Test @MainActor
func skippingFocusDoesNotEarnAPip() {
    // You don't get credit for work you skipped — and a skipped run must not push you
    // toward a long break either.
    let (engine, _) = makeEngine()
    engine.start()
    engine.skip()

    #expect(engine.phase == .shortBreak)
    #expect(engine.pipsFilled == 0)
    #expect(engine.totalFocusRuns == 0)
}

@Test @MainActor
func skippingFourFocusRunsNeverReachesLongBreak() {
    let (engine, _) = makeEngine()
    for _ in 1...4 {
        engine.skip()               // focus -> short break
        #expect(engine.phase == .shortBreak)
        engine.skip()               // short break -> focus
    }
    #expect(engine.pipsFilled == 0)
}

// MARK: - Transport

@Test @MainActor
func pauseStoresRemainingAndResumeRecomputesAFreshDeadline() {
    // ISA ISC-35. Paused time must not count down.
    let (engine, clock) = makeEngine()
    engine.start()
    clock.advance(5 * 60)
    engine.pause()

    let atPause = engine.remaining
    clock.advance(60 * 60)                    // an hour goes by while paused
    #expect(engine.remaining == atPause, "a paused timer must not lose time")

    engine.start()
    clock.advance(60)
    #expect(engine.remaining == atPause - 60)
}

@Test @MainActor
func resetRestoresThePhaseWithoutChangingIt() {
    let (engine, clock) = makeEngine()
    engine.start()
    clock.advance(10 * 60)
    engine.reset()

    #expect(engine.phase == .focus)
    #expect(engine.state == .idle)
    #expect(engine.remaining == 25 * 60)
}

@Test @MainActor
func changingFocusDurationWhileIdleUpdatesRemaining() {
    let (engine, _) = makeEngine()
    engine.durations.focus = 50 * 60
    #expect(engine.remaining == 50 * 60)
}

@Test @MainActor
func progressRunsZeroToOne() {
    let (engine, clock) = makeEngine()
    #expect(engine.progress == 0)
    engine.start()
    clock.advance(Double(25 * 60 / 2))
    #expect(abs(engine.progress - 0.5) < 0.01)
    clock.advance(Double(25 * 60))
    #expect(engine.progress == 1)
}
