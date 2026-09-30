import Foundation

public enum AlarmSchedule {
    /// When the light for the next occurrence starts (alarm time − lead), strictly after `now`.
    /// Days refer to the alarm time: a Monday 00:05 alarm starts its light on Sunday night.
    public static func nextFire(for alarm: Alarm, after now: Date, calendar: Calendar = .current) -> Date? {
        nextAlarmTime(for: alarm, after: now.addingTimeInterval(alarm.leadSeconds), calendar: calendar)
            .map { $0.addingTimeInterval(-alarm.leadSeconds) }
    }

    /// The next wake-up time itself (hour:minute on a selected day), strictly after `now`.
    public static func nextAlarmTime(for alarm: Alarm, after now: Date, calendar: Calendar = .current) -> Date? {
        guard alarm.enabled else { return nil }
        let today = calendar.startOfDay(for: now)
        for offset in 0...7 {
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: today),
                let fire = calendar.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: day),
                fire > now
            else { continue }
            if alarm.isOnce { return fire }
            if alarm.days[mondayIndex(of: fire, calendar: calendar)] { return fire }
        }
        return nil
    }

    /// The earliest upcoming light start across a list of alarms (disabled ones are skipped).
    public static func next(in alarms: [Alarm], after now: Date, calendar: Calendar = .current) -> (alarm: Alarm, date: Date)? {
        alarms
            .compactMap { a in nextFire(for: a, after: now, calendar: calendar).map { (alarm: a, date: $0) } }
            .min { $0.date < $1.date }
    }

    /// "Today 07:00", "Tomorrow 07:00", or "Tue 07:00" (within a week).
    public static func label(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let time = TimeText.hhmm(c.hour ?? 0, c.minute ?? 0)
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow \(time)"
        }
        return "\(DaysLabel.short[mondayIndex(of: date, calendar: calendar)]) \(time)"
    }

    /// 0 = Monday … 6 = Sunday (Calendar's weekday is 1 = Sunday).
    static func mondayIndex(of date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }
}
