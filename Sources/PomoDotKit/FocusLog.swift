import Foundation
import Observation

/// One completed stretch of focus. Immutable — a fact about a moment.
public struct FocusEntry: Codable, Sendable, Equatable {
    /// When the focus started. The heatmap attributes a session to the local calendar day
    /// of this instant, so a session spanning midnight belongs to the day it began.
    public let start: Date
    /// Seconds actually focused — paused time excluded, and never the nominal phase length.
    public let seconds: Int
    /// The local calendar day the session began, as `yyyy-MM-dd`, recorded at write time.
    ///
    /// Redundant with `start` *today*, and deliberately so. Bucketing purely at read time
    /// means a DST change or a trip to another timezone silently re-buckets history under
    /// you — a session logged at 23:40 can slide to the previous day months later. The
    /// local day is a fact about the moment and can't be recovered from the epoch once the
    /// rule has changed, so it's stored rather than derived. `start` is kept so bugs in the
    /// day computation remain fixable.
    ///
    /// Optional for backward compatibility: entries written before this field existed decode
    /// with `day == nil` and fall back to computing it from `start`.
    public let day: String?

    public init(start: Date, seconds: Int, day: String? = nil) {
        self.start = start
        self.seconds = seconds
        self.day = day
    }

    /// `yyyy-MM-dd` in the given calendar's timezone.
    public static func dayString(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The stored day if present, otherwise derived from `start`.
    func resolvedDay(calendar: Calendar) -> String {
        day ?? FocusEntry.dayString(for: start, calendar: calendar)
    }
}

/// Durable, append-only record of focused time.
///
/// **Append-only JSONL, and aggregation is always derived.** Each line is a self-contained
/// fact; nothing is ever rewritten. That means changing the heatmap's intensity thresholds
/// later can't corrupt history, a partially-written final line costs one session rather than
/// the file, and the whole thing stays greppable. A database would be machinery nobody asked
/// for — this is a few hundred lines a year.
@Observable
@MainActor
public final class FocusLog {

    /// Sessions below this are dropped. A stray start-then-stop shouldn't stain a day.
    public static let minimumLoggedSeconds = 60

    public private(set) var entries: [FocusEntry] = []

    private let fileURL: URL
    private let calendar: Calendar

    /// - Parameter directory: where `focus-log.jsonl` lives. Injected so tests and
    ///   screenshot fixtures can never touch the real log (ISC-59).
    public init(directory: URL? = nil, calendar: Calendar = .current) {
        let base = directory ?? FocusLog.defaultDirectory()
        self.fileURL = base.appendingPathComponent("focus-log.jsonl")
        self.calendar = calendar
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        load()
    }

    /// `~/Library/Application Support/PomoDot`, overridable by `POMODOT_LOG_DIR` so a test
    /// or a screenshot run can point at a fixture directory.
    ///
    /// Note for future signing work: enabling App Sandbox silently redirects this to the
    /// app's container, at which point existing history becomes invisible rather than
    /// deleted. If the sandbox is ever turned on, migrate the file across explicitly.
    public static func defaultDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["POMODOT_LOG_DIR"] {
            return URL(fileURLWithPath: override)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return support.appendingPathComponent("PomoDot")
    }

    // MARK: - Writing

    /// Records focused time. Returns false if it was below the floor and dropped.
    @discardableResult
    public func record(seconds: Int, start: Date = Date()) -> Bool {
        guard seconds >= FocusLog.minimumLoggedSeconds else { return false }
        let entry = FocusEntry(start: start,
                               seconds: seconds,
                               day: FocusEntry.dayString(for: start, calendar: calendar))
        entries.append(entry)
        append(entry)
        return true
    }

    /// Appends one line using a real `O_APPEND` descriptor.
    ///
    /// Not `FileHandle.seekToEnd()` + `write`: each handle caches its own offset, so two
    /// running instances — which is exactly what happens when a new build is launched before
    /// the old one is quit — clobber each other's bytes and produce garbage rather than
    /// interleaved lines. `O_APPEND` makes the seek-and-write atomic in the kernel per
    /// `write(2)`, which removes the whole class of problem for the cost of one flag.
    ///
    /// There is also deliberately **no** rewrite path here. The previous version fell back to
    /// `write(to:atomically:)` when opening failed, which on an existing-but-unopenable file
    /// would have replaced the entire history with a single line. Append-only means the file
    /// is never opened for anything but appending.
    private func append(_ entry: FocusEntry) {
        guard let line = Self.encode(entry),
              var data = (line + "\n").data(using: .utf8) else { return }

        let descriptor = open(fileURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }

        // If a previous append was truncated mid-line (power loss), the file won't end in a
        // newline. Without this, the next record concatenates onto the partial one and
        // corrupts two entries instead of one.
        if needsLeadingNewline(descriptor: descriptor) {
            data = Data("\n".utf8) + data
        }

        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = write(descriptor, base, buffer.count)
        }
    }

    private func needsLeadingNewline(descriptor: Int32) -> Bool {
        let end = lseek(descriptor, 0, SEEK_END)
        guard end > 0 else { return false }   // empty file needs nothing

        // O_WRONLY can't read, so check the tail through a separate read-only descriptor.
        let reader = open(fileURL.path, O_RDONLY)
        guard reader >= 0 else { return false }
        defer { close(reader) }

        var lastByte: UInt8 = 0
        guard pread(reader, &lastByte, 1, off_t(end - 1)) == 1 else { return false }
        return lastByte != UInt8(ascii: "\n")
    }

    // MARK: - Reading

    private func load() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        entries = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            // A truncated final line (power loss mid-write) decodes to nil and is dropped.
            // One lost session is the right price for never failing to open the log at all.
            .compactMap { Self.decode(String($0)) }
    }

    private static func encode(_ entry: FocusEntry) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entry) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decode(_ line: String) -> FocusEntry? {
        guard let data = line.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(FocusEntry.self, from: data)
    }

    // MARK: - Aggregation
    //
    // All derived, never stored.

    /// Seconds focused on the local calendar day containing `date`.
    public func seconds(on date: Date) -> Int {
        let day = FocusEntry.dayString(for: date, calendar: calendar)
        return entries
            .filter { $0.resolvedDay(calendar: calendar) == day }
            .reduce(0) { $0 + $1.seconds }
    }

    /// Seconds focused across the last `days` local days, today inclusive.
    public func secondsInLast(days: Int, relativeTo now: Date = Date()) -> Int {
        guard let cutoff = calendar.date(byAdding: .day, value: -(days - 1),
                                         to: calendar.startOfDay(for: now)) else { return 0 }
        return entries
            .filter { $0.start >= cutoff }
            .reduce(0) { $0 + $1.seconds }
    }

    public var totalSeconds: Int {
        entries.reduce(0) { $0 + $1.seconds }
    }

    /// Seconds focused per local calendar day, keyed by the `yyyy-MM-dd` day string.
    ///
    /// Keyed by string rather than by `Date` so the key matches what was *recorded*, not what
    /// re-deriving start-of-day would produce today under a possibly different timezone.
    public func dailyTotals() -> [String: Int] {
        var totals: [String: Int] = [:]
        for entry in entries {
            totals[entry.resolvedDay(calendar: calendar), default: 0] += entry.seconds
        }
        return totals
    }
}

/// Formats a duration the way the rest of the app formats everything: terse and monospaced.
public enum DurationText {
    /// `0m`, `47m`, `4h 25m`. Never `04h`, because a leading zero on hours reads as a clock.
    public static func short(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }
}
