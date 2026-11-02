import Foundation

public enum ScheduleEngine {
    public static func due(
        in data: AppData, after lower: Date, through now: Date, calendar: Calendar = .current
    ) -> [Occurrence] {
        guard lower < now else { return [] }
        let start = calendar.startOfDay(for: lower.addingTimeInterval(-86400))
        // Include the maximum supported lead time, with a margin for half-open ranges.
        let end = now.addingTimeInterval(3660)
        var result: [(Occurrence, Date)] = []
        let enabled = Set(data.reminders.filter(\.isEnabled).map(\.id))
        for reminder in data.reminders where reminder.isEnabled {
            for occurrence in occurrences(for: reminder, in: start..<end, calendar: calendar) {
                let record = data.records[occurrence.id]
                guard record?.isFinished != true, record?.announcedAt == nil else { continue }
                let fire = record?.snoozedUntil ?? occurrence.notificationAt
                if fire > lower && fire <= now { result.append((occurrence, fire)) }
            }
        }
        let found = Set(result.map { $0.0.id })
        for (id, record) in data.records
        where !found.contains(id) && enabled.contains(record.reminderID) && !record.isFinished
            && record.announcedAt == nil
        {
            if let fire = record.snoozedUntil, fire > lower && fire <= now {
                result.append((Occurrence(reminderID: record.reminderID, dueAt: record.dueAt), fire))
            }
        }
        return result.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 < $1.1 }.map(\.0)
    }

    public static func occurrences(
        for reminder: Reminder, in range: Range<Date>, calendar: Calendar = .current
    ) -> [Occurrence] {
        guard reminder.isEnabled, reminder.validationError == nil, range.lowerBound < range.upperBound else {
            return []
        }
        if reminder.repeatRule == .once {
            return range.contains(reminder.startsAt)
                ? [
                    Occurrence(
                        reminderID: reminder.id, dueAt: reminder.startsAt, leadMinutes: reminder.leadMinutes)
                ] : []
        }
        var day = calendar.startOfDay(for: max(range.lowerBound, reminder.startsAt))
        let clock = calendar.dateComponents([.hour, .minute], from: reminder.startsAt)
        let weekday = calendar.component(.weekday, from: reminder.startsAt)
        var dates: [Date] = []
        // Bound enumeration for malformed imported data and unexpectedly broad queries.
        for _ in 0..<370 where day < range.upperBound {
            let currentWeekday = calendar.component(.weekday, from: day)
            let matches = reminder.repeatRule != .weekdays || (2...6).contains(currentWeekday)
            if matches && (reminder.repeatRule != .weekly || currentWeekday == weekday) {
                if reminder.repeatRule == .interval {
                    if let start = wallClock(minutes: reminder.windowStart, on: day, calendar: calendar),
                        let end = wallClock(minutes: reminder.windowEnd, on: day, calendar: calendar)
                    {
                        var date = start
                        for _ in 0..<288 where date < end {
                            if date >= reminder.startsAt && range.contains(date) { dates.append(date) }
                            date = date.addingTimeInterval(Double(reminder.intervalMinutes) * 60)
                        }
                    }
                } else if let date = calendar.nextDate(
                    after: day.addingTimeInterval(-1), matching: clock, matchingPolicy: .nextTime,
                    repeatedTimePolicy: .first, direction: .forward), calendar.isDate(date, inSameDayAs: day),
                    date >= reminder.startsAt, range.contains(date)
                {
                    dates.append(date)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return dates.map { Occurrence(reminderID: reminder.id, dueAt: $0, leadMinutes: reminder.leadMinutes) }
    }

    public static func wallClock(minutes: Int, on day: Date, calendar: Calendar = .current) -> Date? {
        if minutes == 1440 {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))
        }
        return calendar.nextDate(
            after: calendar.startOfDay(for: day).addingTimeInterval(-1),
            matching: DateComponents(hour: minutes / 60, minute: minutes % 60), matchingPolicy: .nextTime,
            repeatedTimePolicy: .first)
    }

    public static func upcoming(
        in data: AppData, after now: Date, limit: Int = 60, calendar: Calendar = .current
    ) -> [(Occurrence, Date)] {
        let end = calendar.date(byAdding: .day, value: 14, to: now) ?? now.addingTimeInterval(14 * 86400)
        let start = calendar.startOfDay(for: now.addingTimeInterval(-86400))
        var result: [(Occurrence, Date)] = []
        for reminder in data.reminders where reminder.isEnabled {
            let occurrences = occurrences(for: reminder, in: start..<end, calendar: calendar)
            for occurrence in occurrences {
                let record = data.records[occurrence.id]
                guard record?.isFinished != true else { continue }
                let fireAt = record?.snoozedUntil ?? occurrence.notificationAt
                if fireAt > now && !data.preferences.isQuiet(at: fireAt, calendar: calendar) {
                    result.append((occurrence, fireAt))
                }
            }
        }
        // A snoozed occurrence can outlive its original query window.
        let existingIDs = Set(result.map { $0.0.id })
        let enabled = Set(data.reminders.filter(\.isEnabled).map(\.id))
        for (id, record) in data.records
        where !existingIDs.contains(id) && !record.isFinished && enabled.contains(record.reminderID) {
            if let snoozed = record.snoozedUntil, snoozed > now,
                !data.preferences.isQuiet(at: snoozed, calendar: calendar)
            {
                result.append((Occurrence(reminderID: record.reminderID, dueAt: record.dueAt), snoozed))
            }
        }
        return Array(result.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 < $1.1 }.prefix(max(0, limit)))
    }
}
