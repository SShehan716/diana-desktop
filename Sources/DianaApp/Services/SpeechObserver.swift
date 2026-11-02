import AVFoundation

private final class CompletedUtterance: @unchecked Sendable {
    let utterance: AVSpeechUtterance
    init(_ utterance: AVSpeechUtterance) { self.utterance = utterance }
    var id: ObjectIdentifier { ObjectIdentifier(utterance) }
}

@MainActor final class SpeechObserver: NSObject, AVSpeechSynthesizerDelegate {
    var onChange: (() -> Void)?
    var onFinished: ((ObjectIdentifier) -> Void)?
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance
    ) { Task { @MainActor [weak self] in self?.onChange?() } }
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        let completed = CompletedUtterance(utterance)
        Task { @MainActor [weak self] in
            self?.onChange?()
            self?.onFinished?(completed.id)
        }
    }
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        let completed = CompletedUtterance(utterance)
        Task { @MainActor [weak self] in
            self?.onChange?()
            self?.onFinished?(completed.id)
        }
    }
}
