import Foundation
import Testing

@testable import DianaCore

struct ScheduleConflictTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Colombo")!
        return c
    }
    func date(_ day: Int = 2, _ hour: Int = 19, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, second: second))!
    }
    @Test func sameMinuteDifferentTitlesConflictButAnotherDayDoesNot() {
        var data = AppData()
        let existing = Reminder(title: "Meeting with Kasun", kind: .meeting, startsAt: date(second: 12))
        data.reminders = [existing]
        var candidate = Reminder(title: "Meeting with Mina", kind: .meeting, startsAt: date(second: 48))
        #expect(
            ScheduleConflicts.find(for: candidate, in: data, calendar: calendar).map(\.title) == [
                existing.title
            ])
        candidate.startsAt = date(3)
        #expect(ScheduleConflicts.find(for: candidate, in: data, calendar: calendar).isEmpty)
        candidate.startsAt = date(2, 20)
        #expect(ScheduleConflicts.find(for: candidate, in: data, calendar: calendar).isEmpty)
    }
    @Test func selfPausedAndFinishedOccurrencesDoNotConflict() {
        var data = AppData()
        var existing = Reminder(title: "Existing", startsAt: date())
        data.reminders = [existing]
        #expect(ScheduleConflicts.find(for: existing, in: data, calendar: calendar).isEmpty)
        let candidate = Reminder(title: "Candidate", startsAt: date())
        existing.isEnabled = false
        data.reminders = [existing]
        #expect(ScheduleConflicts.find(for: candidate, in: data, calendar: calendar).isEmpty)
        existing.isEnabled = true
        data.reminders = [existing]
        let occurrence = Occurrence(reminderID: existing.id, dueAt: existing.startsAt)
        var record = OccurrenceRecord(occurrence: occurrence)
        record.completedAt = date()
        data.records[occurrence.id] = record
        #expect(ScheduleConflicts.find(for: candidate, in: data, calendar: calendar).isEmpty)
    }
    @Test func recurringOccurrencesUseTheSelectedDayAndIgnoreNotificationLead() {
        var data = AppData()
        let existing = Reminder(
            title: "Weekday standup", kind: .meeting, startsAt: date(), repeatRule: .weekdays, leadMinutes: 15
        )
        data.reminders = [existing]
        let tuesday = Reminder(title: "Client meeting", startsAt: date(3))
        #expect(ScheduleConflicts.find(for: tuesday, in: data, calendar: calendar).count == 1)
        let saturday = Reminder(title: "Client meeting", startsAt: date(7))
        #expect(ScheduleConflicts.find(for: saturday, in: data, calendar: calendar).isEmpty)
    }
    @Test func occupiedTimeRequiresExplicitOverrideOrACorrection() {
        let now = date(2, 12)
        var data = AppData()
        data.reminders = [Reminder(title: "Meeting with Kasun", startsAt: date())]
        var flow = VoiceConversation()
        _ = flow.wake()
        let action = flow.receive(
            "schedule a meeting with Mina at 7 PM", now: now, calendar: calendar, schedules: data)
        guard case .prompt(let warning) = action else {
            Issue.record("Missing conflict warning")
            return
        }
        #expect(warning.contains("Meeting with Kasun"))
        #expect(warning.contains("save anyway"))
        guard
            case .prompt(let unclear) = flow.receive(
                "okay maybe", now: now, calendar: calendar, schedules: data)
        else {
            Issue.record("Unclear reply committed")
            return
        }
        #expect(unclear.contains("save anyway"))
        guard case .prompt = flow.receive("yes", now: now, calendar: calendar, schedules: data) else {
            Issue.record("Generic yes bypassed conflict")
            return
        }
        guard case .commit = flow.receive("save anyway", now: now, calendar: calendar, schedules: data) else {
            Issue.record("Explicit override was rejected")
            return
        }
        #expect(flow.approvedConflictIDs.count == 1)
        #expect(flow.receive("save anyway", now: now, calendar: calendar, schedules: data) == .ignore)
        _ = flow.wake()
        _ = flow.receive("schedule a meeting at 7 PM", now: now, calendar: calendar, schedules: data)
        _ = flow.receive("change it to 8 PM", now: now, calendar: calendar, schedules: data)
        guard case .commit = flow.receive("yes", now: now, calendar: calendar, schedules: data) else {
            Issue.record("Conflict-free correction did not save")
            return
        }
        #expect(flow.approvedConflictIDs.isEmpty)
    }
    @Test func aConflictAddedAfterReadBackRequiresANewWarning() {
        let now = date(2, 12)
        var data = AppData()
        var flow = VoiceConversation()
        _ = flow.wake()
        _ = flow.receive("schedule a meeting at 7 PM", now: now, calendar: calendar, schedules: data)
        data.reminders.append(Reminder(title: "Newly scheduled meeting", startsAt: date()))
        guard case .prompt(let warning) = flow.receive("yes", now: now, calendar: calendar, schedules: data)
        else {
            Issue.record("Late conflict bypassed warning")
            return
        }
        #expect(warning.contains("Newly scheduled meeting"))
        data.reminders.append(Reminder(title: "Another new conflict", startsAt: date()))
        guard case .prompt = flow.receive("save anyway", now: now, calendar: calendar, schedules: data) else {
            Issue.record("Unseen conflict was overridden")
            return
        }
    }
    @Test func byeCancelsAnyUnconfirmedDraft() {
        for text in ["bye", "Bye Diana!", "Goodbye", "bye-bye", "Thanks, bye", "see you later"] {
            #expect(VoiceScheduleParser.isFarewell(text))
            var flow = VoiceConversation()
            _ = flow.wake()
            _ = flow.receive("schedule a meeting at 7 PM", now: date(2, 12), calendar: calendar)
            #expect(flow.receive(text, now: date(2, 12), calendar: calendar) == .finish("Bye. See you soon."))
            #expect(flow.draft == nil)
            #expect(flow.receive("yes", now: date(2, 12), calendar: calendar) == .ignore)
        }
        #expect(!VoiceScheduleParser.isFarewell("schedule a meeting with Goodbye Labs at 7 PM"))
        #expect(!VoiceScheduleParser.isFarewell("buy a book"))
        #expect(VoiceScheduleParser.endsWithFarewell("We are done now, bye Diana"))
        #expect(!VoiceScheduleParser.endsWithFarewell("Schedule a meeting with Goodbye Labs"))
    }
}
