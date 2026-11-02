import Foundation
import Testing

@testable import DianaCore

struct ScheduleEngineTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, calendar: Calendar? = nil) -> Date {
        (calendar ?? utc).date(
            from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func oneTimeReminderRespectsHalfOpenRange() {
        let reminder = Reminder(title: "Meeting", startsAt: date(2, 14, 30))
        #expect(ScheduleEngine.occurrences(for: reminder, in: date(2)..<date(3), calendar: utc).count == 1)
        #expect(
            ScheduleEngine.occurrences(for: reminder, in: date(1)..<reminder.startsAt, calendar: utc).isEmpty)
    }

    @Test func weekdaysSkipSaturdayAndSunday() {
        let reminder = Reminder(title: "Stand-up", startsAt: date(6, 9), repeatRule: .weekdays)
        let result = ScheduleEngine.occurrences(for: reminder, in: date(6)..<date(10), calendar: utc)
        #expect(result.map(\.dueAt) == [date(6, 9), date(9, 9)])
    }

    @Test func weeklyUsesChosenWeekday() {
        let reminder = Reminder(title: "Weekly review", startsAt: date(2, 15), repeatRule: .weekly)
        let result = ScheduleEngine.occurrences(for: reminder, in: date(2)..<date(17), calendar: utc)
        #expect(result.map(\.dueAt) == [date(2, 15), date(9, 15), date(16, 15)])
    }

    @Test func dailyKeepsWallClockTimeAcrossDST() {
        var calendar = utc
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let reminder = Reminder(
            title: "Morning water", startsAt: date(1, 9, 30, calendar: calendar), repeatRule: .daily)
        let start = date(1, calendar: calendar)
        let end = date(4, calendar: calendar)
        let result = ScheduleEngine.occurrences(for: reminder, in: start..<end, calendar: calendar)
        #expect(result.count == 3)
        #expect(
            result.allSatisfy {
                calendar.component(.hour, from: $0.dueAt) == 9
                    && calendar.component(.minute, from: $0.dueAt) == 30
            })
    }

    @Test func repeatedHourDoesNotDuplicateAnOccurrence() {
        var calendar = utc
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 1, minute: 30))!
        let reminder = Reminder(title: "Daily", startsAt: start, repeatRule: .daily)
        let result = ScheduleEngine.occurrences(
            for: reminder, in: date(1, calendar: calendar)..<date(2, calendar: calendar), calendar: calendar)
        #expect(result.count == 1)
    }

    @Test func intervalHonorsActiveHoursAndRestartsEachDay() {
        let reminder = Reminder(
            title: "Water", startsAt: date(2, 9), repeatRule: .interval, intervalMinutes: 60)
        let result = ScheduleEngine.occurrences(for: reminder, in: date(2)..<date(4), calendar: utc)
        #expect(result.count == 18)
        #expect(result.first?.dueAt == date(2, 9))
        #expect(result.last?.dueAt == date(3, 17))
        #expect(!result.contains { utc.component(.hour, from: $0.dueAt) == 18 })
    }

    @Test func intervalDoesNotScheduleBeforeStart() {
        let reminder = Reminder(title: "Water", startsAt: date(2, 10, 17), repeatRule: .interval)
        let result = ScheduleEngine.occurrences(for: reminder, in: date(2)..<date(3), calendar: utc)
        #expect(result.first?.dueAt == date(2, 11))
    }

    @Test func disabledAndInvalidRemindersDoNotSchedule() {
        var reminder = Reminder(title: "Paused", startsAt: date(2, 9), repeatRule: .daily, isEnabled: false)
        #expect(ScheduleEngine.occurrences(for: reminder, in: date(2)..<date(3), calendar: utc).isEmpty)
        reminder.isEnabled = true
        reminder.title = "   "
        #expect(ScheduleEngine.occurrences(for: reminder, in: date(2)..<date(3), calendar: utc).isEmpty)
    }

    @Test func completingOneRepeatLeavesFutureOccurrences() {
        var data = AppData()
        let reminder = Reminder(title: "Water", startsAt: date(2, 9), repeatRule: .daily)
        data.reminders = [reminder]
        let occurrence = Occurrence(reminderID: reminder.id, dueAt: date(2, 9))
        var record = OccurrenceRecord(occurrence: occurrence)
        record.completedAt = date(2, 8)
        data.records[occurrence.id] = record
        let plan = ScheduleEngine.upcoming(in: data, after: date(2, 8), calendar: utc)
        #expect(plan.first?.0.dueAt == date(3, 9))
    }

    @Test func snoozeOverridesOriginalNotificationTime() {
        var data = AppData()
        let reminder = Reminder(title: "Meeting", startsAt: date(2, 9))
        data.reminders = [reminder]
        let occurrence = Occurrence(reminderID: reminder.id, dueAt: reminder.startsAt)
        var record = OccurrenceRecord(occurrence: occurrence)
        record.snoozedUntil = date(2, 9, 15)
        data.records[occurrence.id] = record
        let plan = ScheduleEngine.upcoming(in: data, after: date(2, 9, 5), calendar: utc)
        #expect(plan.count == 1)
        #expect(plan.first?.1 == date(2, 9, 15))
    }

    @Test func olderSnoozedOccurrenceSurvivesEnumerationWindow() {
        var data = AppData()
        let reminder = Reminder(title: "An older task", startsAt: date(1, 9))
        data.reminders = [reminder]
        let occurrence = Occurrence(reminderID: reminder.id, dueAt: reminder.startsAt)
        var record = OccurrenceRecord(occurrence: occurrence)
        record.snoozedUntil = date(5, 10)
        data.records[occurrence.id] = record
        #expect(ScheduleEngine.upcoming(in: data, after: date(5, 9), calendar: utc).first?.1 == date(5, 10))
    }

    @Test func leadTimesAndNotificationLimit() {
        var data = AppData()
        data.reminders = [
            Reminder(title: "Meeting", startsAt: date(2, 10), leadMinutes: 5),
            Reminder(title: "Water", startsAt: date(2, 9), repeatRule: .interval, intervalMinutes: 5),
        ]
        let plan = ScheduleEngine.upcoming(in: data, after: date(2, 8), limit: 60, calendar: utc)
        #expect(plan.count == 60)
        #expect(plan.contains { $0.1 == date(2, 9, 55) && $0.0.reminderID == data.reminders[0].id })
        #expect(plan.map { $0.1 } == plan.map { $0.1 }.sorted())
    }

    @Test func quietHoursCrossMidnightAndSuppressPlans() {
        var data = AppData()
        data.preferences.quietHoursEnabled = true
        #expect(data.preferences.isQuiet(at: date(2, 23), calendar: utc))
        #expect(data.preferences.isQuiet(at: date(2, 7), calendar: utc))
        #expect(!data.preferences.isQuiet(at: date(2, 12), calendar: utc))
        data.reminders = [Reminder(title: "Late task", startsAt: date(2, 23))]
        #expect(ScheduleEngine.upcoming(in: data, after: date(2, 12), calendar: utc).isEmpty)
    }

    @Test func fullHourLeadFiresOnTheExactBoundary() {
        var data = AppData()
        let reminder = Reminder(title: "Meeting", startsAt: date(2, 10), leadMinutes: 60)
        data.reminders = [reminder]
        let due = ScheduleEngine.due(
            in: data, after: date(2, 9).addingTimeInterval(-5), through: date(2, 9), calendar: utc)
        #expect(due.count == 1)
        #expect(due.first?.dueAt == date(2, 10))
    }

    @Test func simultaneousRemindersAreAllReturnedAndAnnouncedOnlyOnce() {
        var data = AppData()
        data.reminders = [
            Reminder(title: "First", startsAt: date(2, 9)), Reminder(title: "Second", startsAt: date(2, 9)),
        ]
        let due = ScheduleEngine.due(
            in: data, after: date(2, 9).addingTimeInterval(-5), through: date(2, 9), calendar: utc)
        #expect(due.count == 2)
        for occurrence in due {
            var record = OccurrenceRecord(occurrence: occurrence)
            record.announcedAt = date(2, 9)
            data.records[occurrence.id] = record
        }
        #expect(
            ScheduleEngine.due(
                in: data, after: date(2, 9).addingTimeInterval(-5), through: date(2, 9, 1), calendar: utc
            ).isEmpty)
    }

    @Test func dueSnoozeUsesTheNewFireTime() {
        var data = AppData()
        let reminder = Reminder(title: "Task", startsAt: date(1, 9))
        data.reminders = [reminder]
        let occurrence = Occurrence(reminderID: reminder.id, dueAt: reminder.startsAt)
        var record = OccurrenceRecord(occurrence: occurrence)
        record.snoozedUntil = date(5, 10)
        data.records[occurrence.id] = record
        let due = ScheduleEngine.due(
            in: data, after: date(5, 10).addingTimeInterval(-5), through: date(5, 10), calendar: utc)
        #expect(due.count == 1)
        #expect(due.first?.id == occurrence.id)
    }
}
