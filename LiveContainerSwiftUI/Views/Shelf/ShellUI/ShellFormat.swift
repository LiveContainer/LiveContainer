import Foundation

/// The wording of the version and last-played line, shared by every view and by the host and the demo that fill it:
/// "Version 1.0.0", "Played today", "Played yesterday", "Played 3 days ago", joined as "Version 1.0.0 · Played today".
public enum ShellFormat {
    /// "Version 1.0.0", empty for an empty version.
    public static func version(_ version: String) -> String {
        version.isEmpty ? "" : ShellStrings.text("Version \(version)")
    }

    /// "Played today", "Played yesterday" or "Played <relative date>", by calendar days, not by 24 hour spans.
    public static func played(_ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return ShellStrings.text("Played today")
        case 1: return ShellStrings.text("Played yesterday")
        default:
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.unitsStyle = .full
            formatter.dateTimeStyle = .numeric
            let relative = formatter.localizedString(for: calendar.startOfDay(for: date), relativeTo: calendar.startOfDay(for: now))
            return ShellStrings.text("Played \(relative)")
        }
    }

    /// The parts that are not empty, joined by a middle dot.
    public static func metaLine(_ parts: String?...) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "Version 1.0.0 · Played today": the version line with the last-played date when there is one.
    public static func versionLine(version v: String, lastPlayed: Date?, now: Date = Date(), calendar: Calendar = .current,
                                   locale: Locale = .current) -> String {
        metaLine(version(v), lastPlayed.map { played($0, now: now, calendar: calendar, locale: locale) })
    }
}
