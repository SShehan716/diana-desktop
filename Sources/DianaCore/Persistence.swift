import Foundation

public struct DataRepository: Sendable {
    public let directory: URL
    public var file: URL { directory.appendingPathComponent("reminders.json") }
    public init(directory: URL) { self.directory = directory }

    public func load() throws -> AppData {
        guard FileManager.default.fileExists(atPath: file.path) else { return AppData() }
        return try Self.decode(Data(contentsOf: file))
    }

    public func save(_ value: AppData) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encode(value)
        guard data.count <= 10_000_000 else {
            throw RepositoryError.invalid(
                "Your reminder history is too large to save. Export a backup before removing old reminders.")
        }
        _ = try Self.decode(data)
        try data.write(to: file, options: .atomic)
    }

    public static func encode(_ value: AppData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    public static func decode(_ data: Data) throws -> AppData {
        guard data.count <= 10_000_000 else {
            throw RepositoryError.invalid("This backup is larger than 10 MB.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(AppData.self, from: data)
        guard value.version == 1 else {
            throw RepositoryError.invalid("This backup uses an unsupported data version.")
        }
        guard value.reminders.count <= 2000, Set(value.reminders.map(\.id)).count == value.reminders.count,
            value.reminders.allSatisfy({ $0.validationError == nil })
        else { throw RepositoryError.invalid("This backup contains invalid or duplicate reminders.") }
        let p = value.preferences
        let speechRate = p.speechRate ?? 1
        guard p.companionName.count <= 24, ["left", "right"].contains(p.corner), p.companionHeight.isFinite,
            (160...420).contains(p.companionHeight), p.companionOpacity.isFinite,
            (0.3...1).contains(p.companionOpacity), p.animationSpeed.isFinite,
            (0.5...1.5).contains(p.animationSpeed), (0...23).contains(p.quietStartHour),
            (0...23).contains(p.quietEndHour), speechRate.isFinite, (0.8...1.2).contains(speechRate),
            p.petX?.isFinite != false, p.petY?.isFinite != false
        else { throw RepositoryError.invalid("This backup contains invalid preferences.") }
        return value
    }
}

public enum RepositoryError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
}
