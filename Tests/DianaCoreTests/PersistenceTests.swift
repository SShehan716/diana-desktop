import Foundation
import Testing

@testable import DianaCore

struct PersistenceTests {
    @Test func roundTripKeepsOccurrenceIdentityAndCompletion() throws {
        var data = AppData()
        let reminder = Reminder(title: "Meeting", startsAt: Date(timeIntervalSince1970: 1_790_000_059.85))
        data.reminders = [reminder]
        let occurrence = Occurrence(reminderID: reminder.id, dueAt: reminder.startsAt)
        var record = OccurrenceRecord(occurrence: occurrence)
        record.completedAt = .now
        data.records[occurrence.id] = record
        let decoded = try DataRepository.decode(DataRepository.encode(data))
        let restored = Occurrence(reminderID: decoded.reminders[0].id, dueAt: decoded.reminders[0].startsAt)
        #expect(restored.id == occurrence.id)
        #expect(decoded.records[restored.id]?.completedAt != nil)
    }

    @Test func atomicRepositoryPersistsChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = DataRepository(directory: directory)
        #expect(try repository.load().reminders.isEmpty)
        var data = AppData()
        data.reminders = [Reminder(title: "Water", repeatRule: .daily)]
        try repository.save(data)
        let restored = try repository.load()
        #expect(restored.reminders.first?.title == "Water")
        data.preferences.accent = .teal
        try repository.save(data)
        #expect(try repository.load().preferences.accent == .teal)
    }

    @Test func rejectsCorruptUnsupportedAndDuplicateData() throws {
        #expect(throws: (any Error).self) { try DataRepository.decode(Data("not json".utf8)) }
        var data = AppData()
        data.version = 9
        #expect(throws: (any Error).self) { try DataRepository.decode(DataRepository.encode(data)) }
        data.version = 1
        let reminder = Reminder(title: "Task")
        data.reminders = [reminder, reminder]
        #expect(throws: (any Error).self) { try DataRepository.decode(DataRepository.encode(data)) }
    }

    @Test func rejectsInvalidRenderingPreferences() throws {
        var data = AppData()
        data.preferences.companionHeight = 100_000
        #expect(throws: (any Error).self) { try DataRepository.decode(DataRepository.encode(data)) }
    }

    @Test func readingCorruptionPreservesOriginalBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = DataRepository(directory: directory)
        let bytes = Data("preserve this broken data".utf8)
        try bytes.write(to: repository.file)
        #expect(throws: (any Error).self) { try repository.load() }
        #expect(try Data(contentsOf: repository.file) == bytes)
    }
}
