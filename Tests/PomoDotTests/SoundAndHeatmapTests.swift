import Testing
import Foundation
@testable import PomoDotKit

// MARK: - Sound synthesis
//
// Tests the sample generation, not playback — the synthesis is deliberately nonisolated and
// device-free so it can be asserted on in CI or on a machine with no audio output.

@Test
func everyCueGeneratesSamples() {
    // ISC-43.
    for cue in Cue.allCases {
        let samples = SoundEngine.render(cue: cue)
        #expect(!samples.isEmpty, "\(cue) produced no audio")
    }
}

@Test
func everyCueStartsAndEndsSilent() {
    // ISC-44/45. A waveform that begins or ends mid-cycle is a step discontinuity, which is
    // heard as a click on every single press. The envelope must pin both ends to zero.
    for cue in Cue.allCases {
        let samples = SoundEngine.render(cue: cue)
        #expect(abs(samples.first ?? 1) < 1e-9, "\(cue) starts with a click")
        #expect(abs(samples.last ?? 1) < 1e-9, "\(cue) ends with a click")
    }
}

@Test
func cuesNeverClip() {
    // Sample values outside ±1 wrap or distort in the output stage.
    for cue in Cue.allCases {
        let peak = SoundEngine.render(cue: cue).map(abs).max() ?? 0
        #expect(peak <= 1.0, "\(cue) clips at \(peak)")
        #expect(peak > 0.01, "\(cue) is effectively silent")
    }
}

@Test
func envelopeIsZeroAtBothEndsAndPositiveInside() {
    #expect(SoundEngine.envelope(0) == 0)
    #expect(SoundEngine.envelope(1) == 0)
    #expect(SoundEngine.envelope(0.5) > 0)
}

@Test
func cuesAreDistinguishableFromEachOther() {
    // Six events that all sounded the same would carry no information.
    let rendered = Cue.allCases.map { SoundEngine.render(cue: $0) }
    for i in rendered.indices {
        for j in rendered.indices where j > i {
            #expect(rendered[i] != rendered[j],
                    "\(Cue.allCases[i]) and \(Cue.allCases[j]) are identical")
        }
    }
}

// MARK: - Heatmap geometry

private var gridCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    calendar.firstWeekday = 1
    return calendar
}

@Test
func gridIsSevenRowsByTheConfiguredNumberOfWeeks() {
    // ISC-63/72.
    let columns = HeatmapGrid.columns(endingOn: Date(), calendar: gridCalendar)
    #expect(columns.count == HeatmapGrid.weeks)
    for week in columns {
        #expect(week.count == HeatmapGrid.daysPerWeek)
    }
}

@Test
func todayFallsInTheLastColumn() {
    // ISC-65. The grid must end at the present, or the heatmap is showing history that
    // stops somewhere arbitrary.
    let calendar = gridCalendar
    let today = calendar.startOfDay(for: Date())
    let columns = HeatmapGrid.columns(endingOn: today, calendar: calendar)
    let lastWeek = columns.last!.map { calendar.startOfDay(for: $0) }
    #expect(lastWeek.contains(today))
}

@Test
func eachColumnIsOneCalendarWeekInWeekdayOrder() {
    // ISC-64. Rows must be weekdays, so a horizontal read is "same weekday over time".
    let calendar = gridCalendar
    let columns = HeatmapGrid.columns(endingOn: Date(), calendar: calendar)

    for week in columns {
        // Days within a column advance by exactly one day.
        for index in 1..<week.count {
            let gap = calendar.dateComponents([.day], from: week[index - 1], to: week[index]).day
            #expect(gap == 1)
        }
    }
    // The same row across adjacent columns is the same weekday, 7 days apart.
    for row in 0..<HeatmapGrid.daysPerWeek {
        let first = calendar.component(.weekday, from: columns[0][row])
        let second = calendar.component(.weekday, from: columns[1][row])
        #expect(first == second)
    }
}

@Test
func gridIsContiguousAcrossWeekBoundaries() {
    let calendar = gridCalendar
    let columns = HeatmapGrid.columns(endingOn: Date(), calendar: calendar)
    for index in 1..<columns.count {
        let previousLast = columns[index - 1].last!
        let currentFirst = columns[index].first!
        let gap = calendar.dateComponents([.day], from: previousLast, to: currentFirst).day
        #expect(gap == 1, "week \(index) does not follow directly from week \(index - 1)")
    }
}

@Test
func intensityLevelsAreAnchoredToPomodoroCounts() {
    // ISC-66. Fixed thresholds, not quartiles — a bright square must always mean the same
    // amount of work, regardless of how the rest of the window went.
    #expect(HeatmapGrid.level(forSeconds: 0) == 0)
    #expect(HeatmapGrid.level(forSeconds: 25 * 60) == 1)
    #expect(HeatmapGrid.level(forSeconds: 50 * 60) == 2)
    #expect(HeatmapGrid.level(forSeconds: 100 * 60) == 3)
    #expect(HeatmapGrid.level(forSeconds: 101 * 60) == 4)
    #expect(HeatmapGrid.level(forSeconds: 10 * 3600) == 4, "levels cap rather than overflow")
}

@Test
func emptyLogProducesAFullGridOfLevelZero() {
    // ISC-71. Day one must render a deliberate empty instrument, not a blank space.
    let columns = HeatmapGrid.columns(endingOn: Date(), calendar: gridCalendar)
    let totals: [Date: Int] = [:]
    let cells = columns.flatMap { $0 }
    #expect(cells.count == HeatmapGrid.weeks * HeatmapGrid.daysPerWeek)
    for day in cells {
        #expect(HeatmapGrid.level(forSeconds: totals[day] ?? 0) == 0)
    }
}
