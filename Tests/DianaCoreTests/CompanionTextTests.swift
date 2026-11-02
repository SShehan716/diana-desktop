import Foundation
import Testing

@testable import DianaCore

struct CompanionTextTests {
    @Test func removesEmojiSequencesWithoutDroppingRealNumbers() {
        #expect(
            CompanionText.generated("Hi 😊! Drink water 💧 and stretch 🧘🏽‍♀️.") == "Hi! Drink water and stretch.")
        #expect(CompanionText.generated("Family 👩‍👩‍👧‍👦 flag 🇱🇰 heart ❤️ end") == "Family flag heart end")
        #expect(
            CompanionText.generated("At 10:30, bring 2 cups; #1 costs $5. C++ © 2026.")
                == "At 10:30, bring 2 cups; #1 costs $5. C++ © 2026.")
        #expect(CompanionText.generated("Drink 1️⃣ cup of water.") == "Drink 1 cup of water.")
    }
    @Test func cleansModelRoleplayAndFormattingBeforeDisplay() {
        #expect(
            CompanionText.generated(
                "*smiles warmly* **Take a break** 😊.\n- Stretch\n- [Drink water](https://example.com)")
                == "Take a break.\nStretch\nDrink water")
        #expect(
            CompanionText.spoken("[chuckles] Focus on *one task*. :) You’ve got this!!!")
                == "Focus on one task. You’ve got this.")
        #expect(CompanionText.spoken("Meet at 10:30 for C++.") == "Meet at 10:30 for C++.")
    }
    @Test func preservesNonEnglishAndAccentedText() {
        let text = "ආයුබෝවන්. Café, mañana, 日本語."
        #expect(CompanionText.spoken(text + " 😊") == text)
        #expect(CompanionText.generated(CompanionText.generated(text + " 😊")) == text)
    }
    @Test func emojiOnlyGenerationDoesNotBecomeASpokenReply() {
        #expect(CompanionText.spoken("😊💧🇱🇰") == "")
        let bytes = Data(#"{"message":{"role":"assistant","content":"😊💧"}}"#.utf8)
        #expect(throws: (any Error).self) { try OllamaClient.decodeReply(bytes) }
    }
    @Test func sanitizesEvenWhenOllamaIgnoresInstructions() throws {
        let bytes = Data(#"{"message":{"role":"assistant","content":"*smiles* Take a break 😊!"}}"#.utf8)
        #expect(try OllamaClient.decodeReply(bytes) == "Take a break!")
    }
    @Test func truncatesSpeechAtAWholeWordOrSentence() {
        let text = String(repeating: "A short complete sentence. ", count: 100)
        let spoken = CompanionText.spoken(text)
        #expect(spoken.count <= 1500)
        #expect(spoken.hasSuffix("."))
    }
    @Test func speechPreferencesRemainCompatibleAndValidated() throws {
        var data = AppData()
        data.preferences.speechRate = 0.9
        #expect(try DataRepository.decode(DataRepository.encode(data)).preferences.speechRate == 0.9)
        data.preferences.speechRate = 9
        #expect(throws: (any Error).self) { try DataRepository.decode(DataRepository.encode(data)) }
    }
}
