import Foundation

public struct AssistantMessage: Codable, Sendable, Equatable {
    public var role: String
    public var content: String
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}
public struct OllamaModel: Decodable, Identifiable, Sendable {
    public var name: String
    public var size: Int64?
    public var remoteHost: String?
    private enum CodingKeys: String, CodingKey {
        case name, size
        case remoteHost = "remote_host"
    }
    public var id: String { name }
    public var sizeLabel: String {
        size.map { String(format: "%.1f GB", Double($0) / 1_000_000_000) } ?? "Local model"
    }
}
public enum LocalAssistantError: LocalizedError {
    case unavailable, noModel, emptyReply
    case server(String)
    case invalidResponse
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Ollama isn’t available. Open Ollama on your Mac, then reconnect."
        case .noModel: "Choose an installed Ollama model first."
        case .emptyReply: "The model returned an empty reply. Try again."
        case .server(let message): "Ollama: \(String(message.prefix(240)))"
        case .invalidResponse: "Ollama returned an unreadable response."
        }
    }
}

public actor OllamaClient {
    private let base = URL(string: "http://127.0.0.1:11434/api/")!
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 110
        configuration.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: configuration)
    }
    public func models() async throws -> [OllamaModel] {
        var request = URLRequest(url: base.appendingPathComponent("tags"))
        request.timeoutInterval = 4
        let bytes = try await send(request)
        struct List: Decodable { var models: [OllamaModel] }
        guard let list = try? JSONDecoder().decode(List.self, from: bytes) else {
            throw LocalAssistantError.invalidResponse
        }
        return list.models.filter {
            $0.remoteHost == nil && !($0.name.hasSuffix(":cloud") || $0.name.hasSuffix("-cloud"))
        }.sorted { $0.name < $1.name }
    }
    public func reply(model: String, messages: [AssistantMessage], short: Bool = false) async throws -> String
    {
        guard !model.isEmpty, try await models().contains(where: { $0.name == model }) else {
            throw LocalAssistantError.noModel
        }
        struct Options: Encodable {
            var numPredict: Int
            var numContext = 2048
            var temperature = 0.65
            private enum CodingKeys: String, CodingKey {
                case numPredict = "num_predict"
                case numContext = "num_ctx"
                case temperature
            }
        }
        struct Body: Encodable {
            var model: String
            var messages: [AssistantMessage]
            var stream = false
            var keepAlive = "1m"
            var options: Options
            private enum CodingKeys: String, CodingKey {
                case model, messages, stream, options
                case keepAlive = "keep_alive"
            }
        }
        var conversation = messages
        if conversation.first?.role == "system" {
            conversation[0].content += " " + CompanionText.generationInstruction
        } else {
            conversation.insert(
                AssistantMessage(role: "system", content: CompanionText.generationInstruction), at: 0)
        }
        var request = URLRequest(url: base.appendingPathComponent("chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            Body(model: model, messages: conversation, options: Options(numPredict: short ? 48 : 160)))
        return try Self.decodeReply(await send(request))
    }
    public static func decodeReply(_ bytes: Data) throws -> String {
        struct Reply: Decodable {
            var message: AssistantMessage
            var doneReason: String?
            private enum CodingKeys: String, CodingKey {
                case message
                case doneReason = "done_reason"
            }
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: bytes),
            reply.message.role == "assistant"
        else { throw LocalAssistantError.invalidResponse }
        let value = CompanionText.generated(reply.message.content)
        guard !value.isEmpty else { throw LocalAssistantError.emptyReply }
        let limited = String(value.prefix(4000))
        if reply.doneReason == "length" || value.count > 4000 {
            if let end = limited.lastIndex(where: { ".!?".contains($0) }),
                limited.distance(from: limited.startIndex, to: end) > 12
            {
                return String(limited[...end])
            }
            return limited + "…"
        }
        return limited
    }
    private func send(_ request: URLRequest) async throws -> Data {
        do {
            let (bytes, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw LocalAssistantError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                struct Failure: Decodable { var error: String }
                let message =
                    (try? JSONDecoder().decode(Failure.self, from: bytes))?.error
                    ?? "Request failed (\(http.statusCode))."
                throw LocalAssistantError.server(message)
            }
            return bytes
        } catch is CancellationError { throw CancellationError() } catch let error as LocalAssistantError {
            throw error
        } catch let error as URLError where error.code == .cancelled { throw CancellationError() } catch {
            throw LocalAssistantError.unavailable
        }
    }
}
