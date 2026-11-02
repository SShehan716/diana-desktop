import AVFoundation
import NaturalLanguage

@MainActor enum DianaSpeech {
    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted {
            if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
            if $0.language != $1.language { return $0.language < $1.language }
            return $0.name < $1.name
        }
    }
    static func voice(preferredID: String?, text: String) -> AVSpeechSynthesisVoice? {
        if let preferredID, let explicit = AVSpeechSynthesisVoice(identifier: preferredID) { return explicit }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let language = recognizer.dominantLanguage?.rawValue ?? "en"
        let voices = availableVoices
        var candidates = voices.filter { $0.language.hasPrefix(language + "-") || $0.language == language }
        if candidates.isEmpty { candidates = voices.filter { $0.language.hasPrefix("en-") } }
        let conversational = candidates.filter {
            !$0.identifier.contains(".eloquence.") && !$0.identifier.contains(".speech.synthesis.voice.")
        }
        if !conversational.isEmpty { candidates = conversational }
        let preferredLanguage = AVSpeechSynthesisVoice.currentLanguageCode()
        func score(_ voice: AVSpeechSynthesisVoice) -> Int {
            voice.quality.rawValue * 100 + (voice.gender == .female ? 10 : 0)
                + (voice.language == preferredLanguage ? 5 : 0)
        }
        return candidates.max { score($0) < score($1) } ?? AVSpeechSynthesisVoice(language: preferredLanguage)
    }
    static func label(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality =
            voice.quality == .premium ? "Premium" : voice.quality == .enhanced ? "Enhanced" : "Standard"
        return "\(voice.name) · \(voice.language) · \(quality)"
    }
}
