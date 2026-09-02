import Foundation

/// The app's time and count strings (spec §2.4.5). Every string is built here so screens agree.
public enum DurationFormatter {
    /// Totals: "6h 20m", "42m", "2h", "0m"; `~` prefix while the total is an estimate (spec §3.3).
    public static func long(_ seconds: TimeInterval, approximate: Bool = false) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded(.toNearestOrAwayFromZero))
        let h = minutes / 60, m = minutes % 60
        let body: String
        if h == 0 { body = "\(m)m" } else if m == 0 { body = "\(h)h" } else { body = "\(h)h \(m)m" }
        return approximate ? "~" + body : body
    }

    /// Remaining time on a Play pill: "~12m", "1h 5m", "<1m".
    public static func remaining(_ seconds: TimeInterval, approximate: Bool) -> String {
        if seconds < 60 { return "<1m" }
        return long(seconds, approximate: approximate)
    }

    /// Player clock: "0:42", "12:05", "1:02:33".
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Added-age in the row meta line: "now", "5m", "3h", "2d", "3w", "4mo", "1y".
    public static func age(of date: Date, now: Date = Date()) -> String {
        let s = now.timeIntervalSince(date)
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        if s < 7 * 86_400 { return "\(Int(s / 86_400))d" }
        if s < 30 * 86_400 { return "\(Int(s / (7 * 86_400)))w" }
        if s < 365 * 86_400 { return "\(Int(s / (30 * 86_400)))mo" }
        return "\(Int(s / (365 * 86_400)))y"
    }

    public static func items(_ count: Int) -> String { count == 1 ? "1 item" : "\(count) items" }
}
