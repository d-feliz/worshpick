import Foundation

public enum ServiceUsageWindow {
    /// Songs used on or after this date count as "used in the last N Sundays".
    public static func cutoffDate(sundayCount: Int, relativeTo today: Date, calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: today)
        return calendar.date(byAdding: .day, value: -7 * sundayCount, to: startOfToday) ?? startOfToday
    }
}
