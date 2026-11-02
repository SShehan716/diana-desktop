import DianaCore
import Foundation
import Observation

@Observable @MainActor final class VoiceAssistant {
    enum Status: String {
        case off, enabling, waiting, arriving, speaking, listening, confirming, saving, error
    }
    var status: Status = .off
    var isEnabled = false
    var isActive = false
    var prompt = ""
    var transcript = ""
    var problem: String?
    var usesOnDeviceRecognition = false
    private var conversation = VoiceConversation()
    @ObservationIgnored private let microphone = MicrophoneRecognizer()
    @ObservationIgnored private var silenceTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var rotationTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var turnID = UUID()
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var failedStarts = 0
    @ObservationIgnored private var wakeCommand = ""
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onSpeak: ((String, @escaping () -> Void) -> Void)?
    @ObservationIgnored var onCommit: ((Reminder, Set<String>) -> Bool)?
    @ObservationIgnored var onSchedules: (() -> AppData)?
    @ObservationIgnored var onFarewell: (() -> Void)?
    @ObservationIgnored var onCompanionVisible: (() -> Bool)?
    @ObservationIgnored var onEnabledChanged: ((Bool) -> Void)?
    var statusLabel: String {
        switch status {
        case .off: "Voice control is off"
        case .enabling: "Requesting microphone and speech access…"
        case .waiting: "Listening for Hey Diana"
        case .arriving: "Diana is on her way"
        case .speaking: "Diana is speaking"
        case .listening: "Listening for your request"
        case .confirming: "Listening for yes, a correction, or cancel"
        case .saving: "Saving your confirmed reminder"
        case .error: "Voice control needs attention"
        }
    }
    func configure() {
        microphone.onText = { [weak self] text, final in self?.receive(text, final: final) }
        microphone.onError = { [weak self] error in self?.recognitionFailed(error) }
    }
    func enable(requestPermission: Bool) async {
        guard !isEnabled && status != .enabling else { return }
        status = .enabling
        problem = nil
        let allowed = requestPermission ? await microphone.requestPermissions() : microphone.hasPermissions
        guard allowed else {
            status = .error
            problem = VoiceCaptureError.permission.localizedDescription
            onEnabledChanged?(false)
            return
        }
        isEnabled = true
        usesOnDeviceRecognition = microphone.usesOnDeviceRecognition
        onEnabledChanged?(true)
        startWakeListening()
    }
    func disable() {
        isEnabled = false
        endSession()
        microphone.stop()
        retryTask?.cancel()
        status = .off
        problem = nil
        onEnabledChanged?(false)
    }
    func pauseRecognition() {
        turnID = UUID()
        microphone.stop()
        silenceTask?.cancel()
        timeoutTask?.cancel()
        rotationTask?.cancel()
        retryTask?.cancel()
    }
    func pauseForSpeech() {
        pauseRecognition()
        if isEnabled && !isActive { status = .speaking }
    }
    func resumeAfterExternalSpeech() {
        guard isEnabled && !isActive else { return }
        startWakeListening()
    }
    private func startWakeListening() {
        guard isEnabled && !isActive else { return }
        pauseRecognition()
        status = .waiting
        transcript = ""
        do {
            try microphone.start()
            rotationTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled else { return }
                self?.startWakeListening()
            }
        } catch { recognitionFailed(error.localizedDescription) }
    }
    private func receive(_ text: String, final: Bool) {
        guard isEnabled else { return }
        if status == .waiting {
            failedStarts = 0
            if VoiceScheduleParser.endsWithFarewell(text) {
                if onCompanionVisible?() == true {
                    pauseRecognition()
                    sessionID = UUID()
                    isActive = true
                    onFarewell?()
                    finish("Bye. See you soon.")
                } else {
                    startWakeListening()
                }
            } else if let suffix = VoiceScheduleParser.wakeSuffix(in: text) {
                activate(suffix: suffix)
            } else if final {
                startWakeListening()
            }
            return
        }
        guard status == .listening || status == .confirming else { return }
        transcript = text
        silenceTask?.cancel()
        let turn = turnID
        silenceTask = Task { @MainActor [weak self] in
            if !final { try? await Task.sleep(for: .seconds(1.6)) }
            guard !Task.isCancelled, let self, self.turnID == turn else { return }
            self.acceptUtterance(text)
        }
    }
    private func activate(suffix: String) {
        pauseRecognition()
        sessionID = UUID()
        wakeCommand = suffix
        isActive = true
        status = .arriving
        transcript = ""
        problem = nil
        if case .prompt(let greeting) = conversation.wake() { prompt = greeting }
        onChange?()
    }
    func didArrive() {
        guard isActive && status == .arriving else { return }
        say(prompt) { [weak self] in
            guard let self else { return }
            if !self.wakeCommand.isEmpty {
                let command = self.wakeCommand
                self.wakeCommand = ""
                self.acceptUtterance(command)
            } else {
                self.listenForTurn()
            }
        }
    }
    private func listenForTurn() {
        guard isActive && isEnabled else { return }
        pauseRecognition()
        transcript = ""
        status = conversation.phase == .confirming ? .confirming : .listening
        let turn = turnID
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self, self.turnID == turn else { return }
            do { try self.microphone.start() } catch {
                self.recognitionFailed(error.localizedDescription)
                return
            }
            self.timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled, let self, self.turnID == turn else { return }
                self.finish("I didn’t hear a reply. Nothing was saved.")
            }
        }
        onChange?()
    }
    private func acceptUtterance(_ text: String) {
        guard isActive else { return }
        pauseRecognition()
        transcript = text
        if VoiceScheduleParser.isFarewell(text) { onFarewell?() }
        let action = conversation.receive(text, now: .now, schedules: onSchedules?() ?? AppData())
        switch action {
        case .prompt(let message): say(message) { [weak self] in self?.listenForTurn() }
        case .commit(let draft):
            status = .saving
            onChange?()
            let success = onCommit?(draft, conversation.approvedConflictIDs) == true
            finish(
                success
                    ? "All set. I’ve saved your reminder."
                    : "I couldn’t save that reminder. Nothing new was saved. Please check Diana’s settings.")
        case .finish(let message): finish(message)
        case .ignore: break
        }
    }
    private func say(_ text: String, then: @escaping () -> Void) {
        pauseRecognition()
        prompt = text
        status = .speaking
        onChange?()
        let session = sessionID
        onSpeak?(text) { [weak self] in
            guard let self, self.isActive, self.sessionID == session else { return }
            then()
        }
    }
    private func finish(_ message: String) {
        conversation.cancel()
        say(message) { [weak self] in
            self?.endSession()
            self?.startWakeListening()
        }
    }
    func cancel() {
        guard isActive else { return }
        finish("Okay, nothing else was saved.")
    }
    func endSession() {
        pauseRecognition()
        sessionID = UUID()
        conversation.cancel()
        isActive = false
        transcript = ""
        wakeCommand = ""
        onChange?()
    }
    private func recognitionFailed(_ message: String) {
        guard isEnabled else { return }
        if isActive {
            problem = message
            finish("I couldn’t hear that clearly. Nothing was saved. Please try again.")
        } else {
            pauseRecognition()
            failedStarts += 1
            guard failedStarts < 3 else {
                status = .error
                problem = message
                isEnabled = false
                onEnabledChanged?(false)
                return
            }
            retryTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled { self?.startWakeListening() }
            }
        }
    }
}
