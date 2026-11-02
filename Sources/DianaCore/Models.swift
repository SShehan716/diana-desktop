import Foundation

public enum ReminderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case task, meeting, water, rest
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .task: "Task"
        case .meeting: "Meeting"
        case .water: "Water"
        case .rest: "Break"
        }
    }
    public var symbol: String {
        switch self {
        case .task: "checklist"
        case .meeting: "video"
        case .water: "drop"
        case .rest: "leaf"
        }
    }
}

public enum RepeatRule: String, Codable, CaseIterable, Identifiable, Sendable {
    case once, daily, weekdays, weekly, interval
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .once: "Does not repeat"
        case .daily: "Every day"
        case .weekdays: "Weekdays"
        case .weekly: "Every week"
        case .interval: "At an interval"
        }
    }
}

public struct Reminder: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var kind: ReminderKind
    public var startsAt: Date
    public var repeatRule: RepeatRule
    public var intervalMinutes: Int
    public var windowStart: Int
    public var windowEnd: Int
    public var leadMinutes: Int
    public var isEnabled: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(), title: String = "", notes: String = "", kind: ReminderKind = .task,
        startsAt: Date = .now, repeatRule: RepeatRule = .once, intervalMinutes: Int = 60,
        windowStart: Int = 9 * 60, windowEnd: Int = 18 * 60, leadMinutes: Int = 0, isEnabled: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.kind = kind
        self.startsAt = startsAt
        self.repeatRule = repeatRule
        self.intervalMinutes = intervalMinutes
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.leadMinutes = leadMinutes
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    public var validationError: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Give this reminder a name."
        }
        if title.count > 160 { return "Keep the reminder name under 160 characters." }
        if notes.count > 4000 { return "Keep notes under 4,000 characters." }
        if !(0...60).contains(leadMinutes) { return "Choose a reminder lead time between 0 and 60 minutes." }
        if repeatRule == .interval {
            if !(5...720).contains(intervalMinutes) { return "Choose an interval from 5 to 720 minutes." }
            if !(0..<1440).contains(windowStart) || !(1...1440).contains(windowEnd)
                || windowStart >= windowEnd
            {
                return "The active-hours end must be after the start, on the same day."
            }
        }
        return nil
    }

    public var repetitionLabel: String {
        repeatRule == .interval
            ? "Every \(intervalMinutes) min" : repeatRule == .once ? "One time" : repeatRule.title
    }
}

public struct Occurrence: Identifiable, Hashable, Sendable {
    public var reminderID: UUID
    public var dueAt: Date
    public var leadMinutes: Int
    public var id: String { "\(reminderID.uuidString)|\(Int(dueAt.timeIntervalSince1970.rounded()))" }
    public var notificationAt: Date { dueAt.addingTimeInterval(-Double(leadMinutes) * 60) }
    public init(reminderID: UUID, dueAt: Date, leadMinutes: Int = 0) {
        self.reminderID = reminderID
        self.dueAt = dueAt
        self.leadMinutes = leadMinutes
    }
}

public struct OccurrenceRecord: Codable, Equatable, Sendable {
    public var reminderID: UUID
    public var dueAt: Date
    public var completedAt: Date?
    public var dismissedAt: Date?
    public var snoozedUntil: Date?
    public var announcedAt: Date?
    public init(occurrence: Occurrence) {
        reminderID = occurrence.reminderID
        dueAt = occurrence.dueAt
    }
    public var isFinished: Bool { completedAt != nil || dismissedAt != nil }
}

public enum AppAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum Accent: String, Codable, CaseIterable, Identifiable, Sendable {
    case blue, teal, coral, violet
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var companionName = "Diana"
    public var appearance: AppAppearance = .light
    public var accent: Accent = .blue
    public var companionVisible = true
    public var corner = "right"
    public var clickThrough = false
    public var companionHeight = 280.0
    public var companionOpacity = 1.0
    public var animationSpeed = 1.0
    public var reducedMotion = false
    public var lowPower = true
    public var roaming = false
    public var allSpaces = true
    public var sounds = false
    public var voice = false
    public var voiceIdentifier: String?
    public var speechRate: Double?
    public var voiceAssistantEnabled: Bool?
    public var ollamaEnabled: Bool?
    public var ollamaModel: String?
    public var aiReminderMessages: Bool?
    public var notificationsEnabled = true
    public var quietHoursEnabled = false
    public var quietStartHour = 22
    public var quietEndHour = 8
    public var petX: Double?
    public var petY: Double?
    public init() {}

    public func isQuiet(at date: Date, calendar: Calendar = .current) -> Bool {
        guard quietHoursEnabled else { return false }
        let hour = calendar.component(.hour, from: date)
        return quietStartHour > quietEndHour
            ? hour >= quietStartHour || hour < quietEndHour : hour >= quietStartHour && hour < quietEndHour
    }
}

public struct AppData: Codable, Equatable, Sendable {
    public var version = 1
    public var reminders: [Reminder] = []
    public var records: [String: OccurrenceRecord] = [:]
    public var preferences = Preferences()
    public init() {}
}
