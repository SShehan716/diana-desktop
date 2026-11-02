import AVFoundation
import Speech

private final class SpeechBufferSink: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    func append(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }
}

@MainActor final class MicrophoneRecognizer {
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var tapInstalled = false
    private var sessionID = UUID()
    init() { recognizer?.queue = .main }
    var onText: ((String, Bool) -> Void)?
    var onError: ((String) -> Void)?
    var usesOnDeviceRecognition: Bool { recognizer?.supportsOnDeviceRecognition == true }
    var hasPermissions: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            && SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func requestPermissions() async -> Bool {
        if hasPermissions { return true }
        let microphone: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphone = true
        case .notDetermined: microphone = await AVCaptureDevice.requestAccess(for: .audio)
        default: microphone = false
        }
        guard microphone else { return false }
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else { return false }
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable result in
                continuation.resume(returning: result)
            }
        }
        return authorization == .authorized
    }
    func start() throws {
        stop()
        guard hasPermissions else { throw VoiceCaptureError.permission }
        guard let recognizer, recognizer.isAvailable else { throw VoiceCaptureError.unavailable }
        let session = UUID()
        sessionID = session
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = ["Hey Diana", "schedule a meeting", "yes save it", "cancel"]
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let message = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == session else { return }
                if let text, !text.isEmpty { self.onText?(text, final) }
                if let message, self.sessionID == session { self.onError?(message) }
            }
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            stop()
            throw VoiceCaptureError.noMicrophone
        }
        let sink = SpeechBufferSink(request)
        let audioCallback: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, _ in
            sink.append(buffer)
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: audioCallback)
        tapInstalled = true
        engine.prepare()
        do { try engine.start() } catch {
            stop()
            throw error
        }
    }
    func stop() {
        sessionID = UUID()
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }
}

enum VoiceCaptureError: LocalizedError {
    case permission, unavailable, noMicrophone
    var errorDescription: String? {
        switch self {
        case .permission:
            "Allow Microphone and Speech Recognition for Diana in System Settings → Privacy & Security."
        case .unavailable:
            "English speech recognition is unavailable. Check your connection or downloaded speech resources, then try again."
        case .noMicrophone: "No working microphone was found. Check your Mac’s input device."
        }
    }
}
