import SwiftUI

/// The grid geometry behind the heatmap, kept free of SwiftUI so the date arithmetic —
/// the part that's actually easy to get wrong — can be unit-tested directly.
public enum HeatmapGrid {

    /// How far back the heatmap looks. 26 weeks is what fits the panel's 228pt of usable
    /// width at a legible cell size, and it's a meaningful span for a student: roughly
    /// one academic term and a bit.
    public static let weeks = 26
    public static let daysPerWeek = 7

    /// The days shown, ordered as `columns[week][weekday]`, oldest week first.
    ///
    /// The grid always *ends* on today, so the bottom-right region is the current week and
    /// trailing cells after today are still present (as future days with no data) — same as
    /// GitHub, which keeps the week columns intact rather than ragged.
    public static func columns(endingOn today: Date,
                               calendar: Calendar = .current) -> [[Date]] {
        let startOfToday = calendar.startOfDay(for: today)

        // Walk back to the first day of this week, then back `weeks - 1` further weeks.
        let weekdayIndex = calendar.component(.weekday, from: startOfToday) - calendar.firstWeekday
        let normalisedIndex = (weekdayIndex + daysPerWeek) % daysPerWeek
        guard let startOfThisWeek = calendar.date(byAdding: .day,
                                                  value: -normalisedIndex,
                                                  to: startOfToday),
              let firstDay = calendar.date(byAdding: .day,
                                           value: -(weeks - 1) * daysPerWeek,
                                           to: startOfThisWeek)
        else { return [] }

        return (0..<weeks).map { week in
            (0..<daysPerWeek).compactMap { day in
                calendar.date(byAdding: .day, value: week * daysPerWeek + day, to: firstDay)
            }
        }
    }

    /// Intensity level 0-4 for a day's focus, GitHub-style.
    ///
    /// Fixed thresholds rather than quartiles of your own data: quartiles are self-relative,
    /// so a light week would light up as brightly as a heavy one and the colour would stop
    /// meaning anything. These are anchored to pomodoros — roughly one, two, four, six —
    /// so a bright square always means the same amount of work.
    public static func level(forSeconds seconds: Int) -> Int {
        // Explicit returns: the `let` above makes this a switch *statement*, not an
        // expression, so implicit returns would silently evaluate and discard the literals.
        let minutes = seconds / 60
        switch minutes {
        case 0: return 0
        case ..<26: return 1
        case ..<51: return 2
        case ..<101: return 3
        default: return 4
        }
    }
}

/// GitHub-contributions-style heatmap of focused time.
///
/// Squares, not circles — the panel already has a dot-matrix, and round cells here would
/// read as more dots and compete with it (ISC-70). No `.glassEffect` anywhere in this view:
/// the panel's single glass surface stays single (ISC-69).
public struct HeatmapView: View {
    /// Keyed by `yyyy-MM-dd`, matching what `FocusLog` recorded.
    private let dailySeconds: [String: Int]
    private let accent: Color
    private let today: Date
    /// Row order follows `Calendar.current.firstWeekday` deliberately: GitHub starts weeks on
    /// Sunday, but a UK user's week starts on Monday and the grid should match the week they
    /// actually live in, not GitHub's.
    private let calendar: Calendar

    // Sized so 26 columns exactly span the panel's 228pt of usable width:
    // 26 * 7 + 25 * 1.8 = 227. A narrower grid leaves the legend row spanning wider than
    // the thing it describes, which reads as a layout bug.
    private let cell: CGFloat = 7
    private let gap: CGFloat = 1.8

    public init(dailySeconds: [String: Int],
                accent: Color,
                today: Date = Date(),
                calendar: Calendar = .current) {
        self.dailySeconds = dailySeconds
        self.accent = accent
        self.today = today
        self.calendar = calendar
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            grid
            legend
        }
    }

    private var grid: some View {
        let columns = HeatmapGrid.columns(endingOn: today, calendar: calendar)
        let startOfToday = calendar.startOfDay(for: today)

        return HStack(spacing: gap) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                VStack(spacing: gap) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        let isFuture = day > startOfToday
                        Rectangle()
                            .fill(colour(for: day, isFuture: isFuture))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Focus heatmap, last \(HeatmapGrid.weeks) weeks"))
    }

    private func colour(for day: Date, isFuture: Bool) -> Color {
        // Days that haven't happened are dimmer than days you simply didn't focus — an empty
        // past day is information, a future day isn't.
        guard !isFuture else { return .primary.opacity(0.04) }

        let seconds = dailySeconds[FocusEntry.dayString(for: day, calendar: calendar)] ?? 0
        let level = HeatmapGrid.level(forSeconds: seconds)
        return Self.colour(level: level, accent: accent)
    }

    /// Level 0 is a faint neutral, not a pale accent: an empty day should read as *absent*,
    /// not as a tiny amount of focus. Levels 1-4 climb in accent opacity.
    static func colour(level: Int, accent: Color) -> Color {
        switch level {
        case 0: .primary.opacity(0.10)
        case 1: accent.opacity(0.30)
        case 2: accent.opacity(0.52)
        case 3: accent.opacity(0.76)
        default: accent
        }
    }

    private var legend: some View {
        HStack(spacing: 5) {
            Legend("LAST \(HeatmapGrid.weeks) WEEKS", size: 8, opacity: 0.34)
            Spacer()
            Legend("LESS", size: 8, opacity: 0.34)
            HStack(spacing: gap) {
                ForEach(0..<5, id: \.self) { level in
                    Rectangle()
                        .fill(Self.colour(level: level, accent: accent))
                        .frame(width: cell, height: cell)
                }
            }
            Legend("MORE", size: 8, opacity: 0.34)
        }
    }
}

/// The three running totals, in monospaced numerals under micro-caps labels.
public struct StatsRow: View {
    private let today: Int
    private let week: Int
    private let total: Int

    public init(todaySeconds: Int, weekSeconds: Int, totalSeconds: Int) {
        self.today = todaySeconds
        self.week = weekSeconds
        self.total = totalSeconds
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            stat("TODAY", today)
            Spacer(minLength: 0)
            stat("7 DAYS", week)
            Spacer(minLength: 0)
            stat("TOTAL", total)
        }
    }

    private func stat(_ label: String, _ seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Legend(label, size: 8, opacity: 0.34)
            Text(DurationText.short(seconds))
                .font(Theme.numeral(12))
                .tracking(Theme.numeralTracking)
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(0.9))
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(label): \(DurationText.short(seconds))"))
    }
}
