import Testing
import Foundation
@testable import PomoDotKit

/// Every test writes to its own throwaway directory. The real log at
/// `~/Library/Application Support/PomoDot` must never be touched by a test run (ISC-59).
private func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("PomoDotTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A fixed calendar so day-bucketing assertions don't drift with the machine's locale.
private var testCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    calendar.firstWeekday = 1   // Sunday, matching GitHub
    return calendar
}

// MARK: - Persistence

@Test @MainActor
func logSurvivesAReopen() {
    // ISC-51. The whole point of a log is that it outlives the process.
    let directory = tempDirectory()
    let first = FocusLog(directory: directory, calendar: testCalendar)
    first.record(seconds: 1500)
    first.record(seconds: 900)

    let reopened = FocusLog(directory: directory, calendar: testCalendar)
    #expect(reopened.entries.count == 2)
    #expect(reopened.totalSeconds == 2400)
}

@Test @MainActor
func storeIsAppendOnlyJSONLWithOneObjectPerLine() {
    // ISC-50.
    let directory = tempDirectory()
    let log = FocusLog(directory: directory, calendar: testCalendar)
    log.record(seconds: 1500)
    log.record(seconds: 600)

    let text = try! String(contentsOf: directory.appendingPathComponent("focus-log.jsonl"),
                           encoding: .utf8)
    let lines = text.split(separator: "\n")
    #expect(lines.count == 2)
    for line in lines {
        #expect(line.hasPrefix("{") && line.hasSuffix("}"), "each line must stand alone")
    }
}

@Test @MainActor
func corruptLineIsSkippedNotFatal() {
    // ISC-57. A half-written final line (power loss mid-append) must cost one session,
    // not the entire history.
    let directory = tempDirectory()
    let file = directory.appendingPathComponent("focus-log.jsonl")
    let good = #"{"start":"2026-08-20T09:00:00Z","seconds":1500}"#
    try! (good + "\n" + #"{"start":"2026-08-2"# + "\n").write(to: file, atomically: true, encoding: .utf8)

    let log = FocusLog(directory: directory, calendar: testCalendar)
    #expect(log.entries.count == 1)
    #expect(log.totalSeconds == 1500)
}

@Test @MainActor
func shortSessionsAreNotLogged() {
    // ISC-55. A stray start-then-stop shouldn't stain a day on the heatmap.
    let directory = tempDirectory()
    let log = FocusLog(directory: directory, calendar: testCalendar)

    #expect(log.record(seconds: 59) == false)
    #expect(log.record(seconds: 60) == true)
    #expect(log.entries.count == 1)
}

// MARK: - Aggregation

@Test @MainActor
func dailyTotalsBucketByLocalCalendarDay() {
    // ISC-56. A session at 23:30 local belongs to that local day, not to the UTC day.
    // Under BST this is the case that would silently shift sessions to tomorrow.
    let directory = tempDirectory()
    let calendar = testCalendar
    let log = FocusLog(directory: directory, calendar: calendar)

    // 2026-08-20 23:30 BST == 22:30 UTC — same local day, and the naive UTC read agrees.
    // 2026-08-20 00:30 BST == 2026-08-19 23:30 UTC — here UTC would put it on the 19th.
    let lateEvening = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 23, minute: 30))!
    let earlyMorning = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 0, minute: 30))!
    log.record(seconds: 1500, start: lateEvening)
    log.record(seconds: 900, start: earlyMorning)

    #expect(log.dailyTotals()["2026-08-20"] == 2400, "both sessions fall on the same local day")
    #expect(log.seconds(on: earlyMorning) == 2400)
}

@Test @MainActor
func rollingWindowCountsWholeLocalDaysIncludingToday() {
    let directory = tempDirectory()
    let calendar = testCalendar
    let log = FocusLog(directory: directory, calendar: calendar)
    let now = Date()

    log.record(seconds: 600, start: now)
    log.record(seconds: 600, start: calendar.date(byAdding: .day, value: -3, to: now)!)
    log.record(seconds: 600, start: calendar.date(byAdding: .day, value: -30, to: now)!)

    #expect(log.secondsInLast(days: 7, relativeTo: now) == 1200)
    #expect(log.totalSeconds == 1800)
}

@Test
func durationsFormatTersely() {
    // ISC-62.
    #expect(DurationText.short(0) == "0m")
    #expect(DurationText.short(59) == "0m")
    #expect(DurationText.short(60) == "1m")
    #expect(DurationText.short(1500) == "25m")
    #expect(DurationText.short(3600) == "1h 0m")
    #expect(DurationText.short(15900) == "4h 25m")
}

// MARK: - Engine → log integration

/// A controllable clock, so "focused for 10 minutes" can be asserted without waiting.
@MainActor
private final class TestClock {
    var now = ContinuousClock.now
    func advance(_ seconds: Double) { now = now.advanced(by: .seconds(seconds)) }
    var provider: @Sendable () -> ContinuousClock.Instant {
        let box = self
        return { MainActor.assumeIsolated { box.now } }
    }
}

@Test @MainActor
func abandoningAFocusLogsOnlyTheTimeActuallyFocused() {
    // ISC-52. The heatmap must not flatter you — skipping at 10 minutes logs 10, not 25.
    var logged: [(seconds: Int, start: Date)] = []
    let clock = TestClock()
    let engine = TimerEngine(now: clock.provider)
    engine.onFocusEnded = { seconds, start in logged.append((seconds, start)) }

    engine.start()
    clock.advance(10 * 60)
    engine.skip()

    #expect(logged.count == 1)
    #expect(logged.first?.seconds == 10 * 60, "logged time is elapsed, not the phase length")
}

@Test @MainActor
func pausedTimeIsNotCountedAsFocusedTime() {
    // ISC-53. Ten minutes focused, an hour paused, then skip → ten minutes logged.
    var logged: [Int] = []
    let clock = TestClock()
    let engine = TimerEngine(now: clock.provider)
    engine.onFocusEnded = { seconds, _ in logged.append(seconds) }

    engine.start()
    clock.advance(10 * 60)
    engine.pause()
    clock.advance(60 * 60)
    engine.skip()

    #expect(logged == [10 * 60])
}

@Test @MainActor
func completedFocusLogsTheFullPhaseLength() {
    var logged: [Int] = []
    let clock = TestClock()
    let engine = TimerEngine(now: clock.provider)
    engine.onFocusEnded = { seconds, _ in logged.append(seconds) }

    engine.start()
    clock.advance(25 * 60)
    engine.tick()

    #expect(logged == [25 * 60])
    #expect(engine.phase == .shortBreak)
}

@Test @MainActor
func breakPhasesNeverReachTheFocusLog() {
    // ISC-54.
    var callbacks = 0
    let clock = TestClock()
    let engine = TimerEngine(now: clock.provider)
    engine.onFocusEnded = { _, _ in callbacks += 1 }

    engine.start()
    clock.advance(5 * 60)
    engine.skip()                   // focus -> break, one focus ended
    #expect(callbacks == 1)

    engine.start()
    clock.advance(5 * 60)
    engine.skip()                   // break -> focus, must NOT fire
    #expect(callbacks == 1, "leaving a break is not focused time")
}

@Test @MainActor
func theSameFocusStretchIsNeverLoggedTwice() {
    // Reset then skip must not double-count: the start stamp is cleared on report.
    var logged: [Int] = []
    let clock = TestClock()
    let engine = TimerEngine(now: clock.provider)
    engine.onFocusEnded = { seconds, _ in logged.append(seconds) }

    engine.start()
    clock.advance(3 * 60)
    engine.reset()
    engine.skip()

    #expect(logged == [3 * 60])
}

@Test @MainActor
func resumingAfterAPauseKeepsTheOriginalStartInstant() {
    // The session is attributed to the day it *began*, so a pause across midnight can't
    // silently move it to tomorrow.
    var starts: [Date] = []
    let clock = TestClock()
    let engine = TimerEngine(now: clock.provider)
    engine.onFocusEnded = { _, start in starts.append(start) }

    engine.start()
    let began = Date()
    clock.advance(60)
    engine.pause()
    engine.start()
    clock.advance(60)
    engine.skip()

    #expect(starts.count == 1)
    #expect(abs(starts[0].timeIntervalSince(began)) < 2)
}

// MARK: - Transport sequence matrix
//
// The invariant: every accrued second is flushed exactly once. These are the orderings where
// a stale start-stamp or an unconditional log would double-count or lose time.

/// One step in a transport sequence. `wait` advances the injected clock.
private enum Step { case start, pause, skip, reset, tick, quit, wait(Double) }

@MainActor
private func runSequence(_ steps: [Step]) -> [Int] {
    var logged: [Int] = []
    let clock = TestClock()
    let engine = TimerEngine(now: clock.provider)
    engine.onFocusEnded = { seconds, _ in logged.append(seconds) }

    for step in steps {
        switch step {
        case .start: engine.start()
        case .pause: engine.pause()
        case .skip: engine.skip()
        case .reset: engine.reset()
        case .tick: engine.tick()
        case .quit: engine.flushFocusForShutdown()
        case .wait(let seconds): clock.advance(seconds)
        }
    }
    return logged
}

@Test @MainActor
func transportSequencesFlushEachSecondExactlyOnce() {
    // Each case: sequence → the focus durations that should be logged, in order.
    let cases: [(name: String, steps: [Step], expected: [Int])] = [
        ("skip then reset while idle",
         [.start, .wait(120), .skip, .reset], [120]),

        ("pause then reset",
         [.start, .wait(120), .pause, .wait(9999), .reset], [120]),

        ("pause, skip, new focus, reset — no stale stamp leaks forward",
         [.start, .wait(120), .pause, .skip,          // focus #1 ends at 120
          .start, .wait(60), .skip,                   // that's a BREAK, logs nothing
          .start, .wait(90), .reset],                 // focus #2 ends at 90
         [120, 90]),

        ("natural completion then a manual skip in the same turn",
         [.start, .wait(25 * 60), .tick, .skip], [25 * 60]),

        ("complete, then reset during the break",
         [.start, .wait(25 * 60), .tick, .reset], [25 * 60]),

        ("skip during a break logs nothing",
         [.start, .wait(60), .skip, .start, .wait(60), .skip], [60]),

        ("quit mid-focus banks the time",
         [.start, .wait(300), .quit], [300]),

        ("quit twice does not double-log",
         [.start, .wait(300), .quit, .quit], [300]),

        ("quit while idle logs nothing",
         [.quit], []),

        ("reset before ever starting logs nothing",
         [.reset, .reset], []),
    ]

    for testCase in cases {
        let logged = runSequence(testCase.steps)
        #expect(logged == testCase.expected, "\(testCase.name): got \(logged)")
    }
}

@Test @MainActor
func sleepingThroughAPhaseCannotLogMoreThanThePhaseLength() {
    // The lid-closed-for-hours case. Because elapsed is `phaseLength - remaining` and
    // `remaining` floors at zero, an absurd wall-clock jump can't produce an absurd entry.
    let logged = runSequence([.start, .wait(4 * 60 * 60), .skip])
    #expect(logged == [25 * 60])
}

// MARK: - Durability

@Test @MainActor
func appendRepairsAMissingTrailingNewline() {
    // A truncated previous write leaves no newline. Without repair the next record
    // concatenates onto the partial line and corrupts two entries instead of one.
    let directory = tempDirectory()
    let file = directory.appendingPathComponent("focus-log.jsonl")
    try! #"{"start":"2026-08-20T09:00:00Z","seconds":1500,"day":"2026-08-20"}"#
        .write(to: file, atomically: true, encoding: .utf8)   // deliberately no "\n"

    let log = FocusLog(directory: directory, calendar: testCalendar)
    log.record(seconds: 600)

    let lines = try! String(contentsOf: file, encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: true)
    #expect(lines.count == 2, "the new record must not fuse onto the unterminated line")

    let reopened = FocusLog(directory: directory, calendar: testCalendar)
    #expect(reopened.entries.count == 2)
    #expect(reopened.totalSeconds == 2100)
}

@Test @MainActor
func concurrentWritersDoNotClobberEachOther() {
    // Two instances is not hypothetical — it's what happens when a new build is launched
    // before the old one is quit. O_APPEND makes each write atomic at the kernel level.
    let directory = tempDirectory()
    let first = FocusLog(directory: directory, calendar: testCalendar)
    let second = FocusLog(directory: directory, calendar: testCalendar)

    for _ in 0..<20 {
        first.record(seconds: 300)
        second.record(seconds: 600)
    }

    let reopened = FocusLog(directory: directory, calendar: testCalendar)
    #expect(reopened.entries.count == 40, "no line was lost or overwritten")
    #expect(reopened.totalSeconds == 20 * 300 + 20 * 600)
}

@Test @MainActor
func theStoredLocalDayIsUsedInsteadOfRederivingIt() {
    // A record carries the day it was actually logged on. Re-deriving from the epoch under a
    // different timezone would silently re-bucket history; the stored value must win.
    let directory = tempDirectory()
    let file = directory.appendingPathComponent("focus-log.jsonl")
    // 00:30 UTC would re-derive to the 21st in London (BST, +1), but the record says the 20th.
    try! (#"{"start":"2026-08-21T00:30:00Z","seconds":1500,"day":"2026-08-20"}"# + "\n")
        .write(to: file, atomically: true, encoding: .utf8)

    let log = FocusLog(directory: directory, calendar: testCalendar)
    #expect(log.dailyTotals()["2026-08-20"] == 1500)
    #expect(log.dailyTotals()["2026-08-21"] == nil)
}

@Test @MainActor
func entriesWrittenBeforeTheDayFieldExistedStillAggregate() {
    // Backward compatibility with logs written by v1.1's first build.
    let directory = tempDirectory()
    let file = directory.appendingPathComponent("focus-log.jsonl")
    try! (#"{"start":"2026-08-20T09:00:00Z","seconds":1500}"# + "\n")
        .write(to: file, atomically: true, encoding: .utf8)

    let log = FocusLog(directory: directory, calendar: testCalendar)
    #expect(log.totalSeconds == 1500)
    #expect(log.dailyTotals()["2026-08-20"] == 1500, "day falls back to being derived from start")
}

@Test @MainActor
func transportEmitsDistinctCues() {
    // ISC-43.
    var cues: [Cue] = []
    let engine = TimerEngine()
    engine.onCue = { cues.append($0) }

    engine.start()
    engine.pause()
    engine.reset()
    engine.skip()

    #expect(cues == [.start, .pause, .reset, .skip])
}

@Test @MainActor
func completingAPhaseEmitsThePhaseSpecificCue() {
    let clock = TestClock()
    let engine = TimerEngine(now: clock.provider)
    var cues: [Cue] = []
    engine.onCue = { cues.append($0) }

    engine.start()
    clock.advance(25 * 60)
    engine.tick()
    #expect(cues.contains(.focusEnded))

    engine.start()
    clock.advance(5 * 60)
    engine.tick()
    #expect(cues.contains(.breakEnded))
}
