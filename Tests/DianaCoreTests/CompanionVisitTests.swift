import Testing

@testable import DianaCore

struct CompanionVisitTests {
    @Test func staysHiddenUntilReminderArrives() {
        #expect(CompanionVisitPhase.hidden.intent(hasContent: false, enabled: true) == .hide)
        #expect(CompanionVisitPhase.hidden.intent(hasContent: true, enabled: true) == .enter)
    }
    @Test func queuedRemindersKeepOneVisit() {
        #expect(CompanionVisitPhase.entering.intent(hasContent: true, enabled: true) == .keep)
        #expect(CompanionVisitPhase.presenting.intent(hasContent: true, enabled: true) == .keep)
        #expect(CompanionVisitPhase.presenting.intent(hasContent: false, enabled: true) == .depart)
    }
    @Test func arrivalsInterruptDeparture() {
        for phase in [CompanionVisitPhase.kissing, .exiting] {
            #expect(phase.intent(hasContent: true, enabled: true) == .enter)
            #expect(phase.intent(hasContent: false, enabled: true) == .keep)
        }
    }
    @Test func disableAlwaysHidesAndOnlyPresentationShowsBubble() {
        for phase in [CompanionVisitPhase.hidden, .entering, .presenting, .kissing, .exiting] {
            #expect(phase.intent(hasContent: true, enabled: false) == .hide)
            #expect(phase.showsBubble == (phase == .presenting))
        }
    }
}
