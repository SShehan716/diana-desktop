import Foundation
import Testing

@testable import DianaCore

struct OllamaTests {
    @Test func decodesDocumentedChatResponse() throws {
        let bytes = Data(
            #"{"message":{"role":"assistant","content":"  Take a small break. \n"},"done":true}"#.utf8)
        #expect(try OllamaClient.decodeReply(bytes) == "Take a small break.")
    }
    @Test func rejectsMissingAndEmptyResponses() {
        for json in [
            #"{"error":"missing model"}"#, #"{"message":{"role":"assistant","content":"  "}}"#, "invalid",
        ] { #expect(throws: (any Error).self) { try OllamaClient.decodeReply(Data(json.utf8)) } }
    }
    @Test func unfinishedGenerationEndsAtACompleteSentence() throws {
        let bytes = Data(
            #"{"message":{"role":"assistant","content":"Hello, take a short break. Then do something you"},"done_reason":"length"}"#
                .utf8)
        #expect(try OllamaClient.decodeReply(bytes) == "Hello, take a short break.")
    }
    @Test func readsOldPreferencesWithoutAIFields() throws {
        let encoded = try DataRepository.encode(AppData())
        #expect(try DataRepository.decode(encoded).preferences.ollamaEnabled == nil)
        var data = AppData()
        data.preferences.ollamaEnabled = true
        data.preferences.ollamaModel = "llama2:latest"
        data.preferences.voiceIdentifier = "test.voice"
        let restored = try DataRepository.decode(DataRepository.encode(data))
        #expect(restored.preferences.ollamaModel == "llama2:latest")
        #expect(restored.preferences.voiceIdentifier == "test.voice")
    }
}
