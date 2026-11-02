import Foundation
import Testing

@testable import DianaCore

struct VoiceSchedulingTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Colombo")!
        return c
    }
    private func date(_ day: Int = 2, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    @Test func exampleCreatesOnlyADraftBeforeExplicitConfirmation() throws {
        var flow = VoiceConversation()
        #expect(flow.wake() == .prompt("Yep, how can I help you?"))
        let action = flow.receive(
            "Schedule a meeting with my client at 5 PM", now: date(), calendar: calendar)
        guard case .prompt(let readback) = action else {
            Issue.record("Expected read-back")
            return
        }
        #expect(readback.contains("Monday, November 2 at 5:00 PM"))
        #expect(flow.draft?.title == "Meeting with my client")
        #expect(flow.draft?.kind == .meeting)
        #expect(flow.phase == .confirming)
        #expect(flow.receive("maybe", now: date(), calendar: calendar) != .commit(flow.draft!))
        guard case .commit(let saved) = flow.receive("Yes, save it", now: date(), calendar: calendar) else {
            Issue.record("Expected commit after yes")
            return
        }
        #expect(saved.startsAt == date(hour: 17))
        #expect(flow.receive("yes", now: date(), calendar: calendar) == .ignore)
    }
    @Test func omittedPastClockUsesTomorrowAndSaysTheDate() throws {
        let reminder = try VoiceScheduleParser.parse(
            "schedule a meeting at five PM", now: date(hour: 18), calendar: calendar)
        #expect(reminder.startsAt == date(3, hour: 17))
        let spoken = try VoiceScheduleParser.parse(
            "schedule a call tomorrow at five thirty PM", now: date(), calendar: calendar)
        #expect(spoken.startsAt == date(3, hour: 17, minute: 30))
    }
    @Test func needsMeridiemAndClarifiesWithoutSaving() {
        var flow = VoiceConversation()
        _ = flow.wake()
        #expect(
            flow.receive("schedule a meeting with my client at five", now: date(), calendar: calendar)
                == .prompt(VoiceScheduleError.ambiguousTime.localizedDescription))
        #expect(flow.draft == nil)
        _ = flow.receive("PM", now: date(), calendar: calendar)
        #expect(flow.draft?.startsAt == date(hour: 17))
        #expect(flow.phase == .confirming)
    }
    @Test func cancelAndUnclearAffirmationsNeverCommit() {
        for answer in ["cancel", "no", "don't save", "stop"] {
            var flow = VoiceConversation()
            _ = flow.wake()
            _ = flow.receive("schedule a meeting at 5 PM", now: date(), calendar: calendar)
            #expect(
                flow.receive(answer, now: date(), calendar: calendar) == .finish("Okay, nothing was saved."))
            #expect(flow.receive("yes", now: date(), calendar: calendar) == .ignore)
        }
        var flow = VoiceConversation()
        _ = flow.wake()
        _ = flow.receive("schedule a meeting at 5 PM", now: date(), calendar: calendar)
        guard case .prompt = flow.receive("yes but I am not sure", now: date(), calendar: calendar) else {
            Issue.record("Unclear reply committed")
            return
        }
        #expect(flow.phase == .confirming)
    }
    @Test func correctionsRequireASecondReadBackAndConfirmation() {
        var flow = VoiceConversation()
        _ = flow.wake()
        _ = flow.receive("schedule a meeting with my client at 5 PM", now: date(), calendar: calendar)
        guard case .prompt(let text) = flow.receive("No, change it to 6 PM", now: date(), calendar: calendar)
        else {
            Issue.record("Correction must be read back")
            return
        }
        #expect(text.contains("6:00 PM"))
        #expect(flow.draft?.title == "Meeting with my client")
        #expect(flow.phase == .confirming)
        guard case .commit(let value) = flow.receive("yep", now: date(), calendar: calendar) else {
            Issue.record("Expected corrected commit")
            return
        }
        #expect(value.startsAt == date(hour: 18))
    }
    @Test func expiryAndExplicitPastDatesNeverSave() {
        var flow = VoiceConversation()
        _ = flow.wake()
        _ = flow.receive("schedule a meeting at 5 PM", now: date(), calendar: calendar)
        guard case .finish = flow.receive("yes", now: date().addingTimeInterval(121), calendar: calendar)
        else {
            Issue.record("Expired confirmation committed")
            return
        }
        #expect(throws: VoiceScheduleError.pastDate) {
            try VoiceScheduleParser.parse(
                "schedule a meeting today at 5 PM", now: date(hour: 18), calendar: calendar)
        }
    }
    @Test func unsupportedMultipleClocksAndNumericDatesRequireClarification() {
        for request in [
            "schedule a meeting from 5 PM to 6 PM", "schedule a meeting on 2026-11-05 at 5 PM",
            "schedule a meeting yesterday at 5 PM",
        ] {
            #expect(throws: VoiceScheduleError.unsupported) {
                try VoiceScheduleParser.parse(request, now: date(), calendar: calendar)
            }
        }
    }
    @Test func timeOnlyCorrectionNeverCountsAsConsent() {
        var flow = VoiceConversation()
        _ = flow.wake()
        _ = flow.receive("schedule a client meeting at 5 PM", now: date(), calendar: calendar)
        guard case .prompt = flow.receive("6 PM", now: date(), calendar: calendar) else {
            Issue.record("Correction committed")
            return
        }
        #expect(flow.draft?.startsAt == date(hour: 18))
        #expect(flow.draft?.title == "Client meeting")
        #expect(flow.phase == .confirming)
    }
    @Test func weekdaysRelativeTimesAndWakePhrase() throws {
        #expect(VoiceScheduleParser.wakeSuffix(in: "Hey Diana") == "")
        #expect(
            VoiceScheduleParser.wakeSuffix(in: "hey Diana, schedule a meeting at 5 PM")
                == "schedule a meeting at 5 PM")
        #expect(VoiceScheduleParser.wakeSuffix(in: "the Diana project") == nil)
        #expect(
            try VoiceScheduleParser.parse(
                "schedule a client meeting Friday at 5 PM", now: date(), calendar: calendar
            ).startsAt == date(6, hour: 17))
        #expect(
            try VoiceScheduleParser.parse(
                "remind me to drink water in twenty minutes", now: date(), calendar: calendar
            ).startsAt == date(minute: 20))
        #expect(throws: VoiceScheduleError.unsupported) {
            try VoiceScheduleParser.parse(
                "schedule a meeting every day at 5 PM", now: date(), calendar: calendar)
        }
    }
}
