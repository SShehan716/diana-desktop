import Foundation

public struct ScheduleConflict: Equatable, Identifiable, Sendable {
    public var reminderID: UUID
    public var title: String
    public var dueAt: Date
    public var id: String { "\(reminderID.uuidString)|\(Int(floor(dueAt.timeIntervalSince1970 / 60)))" }
}

public enum ScheduleConflicts {

    public static func find(for candidate: Reminder, in data: AppData, calendar: Calendar = .current)
        -> [ScheduleConflict]
    {
        guard candidate.isEnabled else { return [] }
        let start = Date(timeIntervalSince1970: floor(candidate.startsAt.timeIntervalSince1970 / 60) * 60)
        let range = start..<start.addingTimeInterval(60)
        return data.reminders.filter { $0.id != candidate.id && $0.isEnabled }.flatMap { other in
            ScheduleEngine.occurrences(for: other, in: range, calendar: calendar).filter {
                data.records[$0.id]?.isFinished != true
            }.map { ScheduleConflict(reminderID: other.id, title: other.title, dueAt: $0.dueAt) }
        }.sorted { $0.id < $1.id }
    }
    public static func warning(_ conflicts: [ScheduleConflict]) -> String {
        let titles = conflicts.prefix(2).map(\.title).joined(separator: " and ")
        let rest = conflicts.count > 2 ? " and \(conflicts.count - 2) more" : ""
        return
            "You already have \(titles)\(rest) scheduled at that time. Choose another time, say cancel, or say save anyway to use this time."
    }
}
