import Foundation
import Testing

@testable import DianaApp

@MainActor struct VoiceLifecycleTests {
    @Test func idleAndExternalSpeechNeverStartTheMicrophone() async throws {
        let harness = VoiceHarness()
        #expect(harness.assistant.status == .off)
        harness.input.onText?("Hey Diana", true)
        harness.assistant.pauseRecognition()
        try await Task.sleep(for: .milliseconds(400))
        #expect(harness.input.starts == 0)
        #expect(!harness.assistant.isActive)
    }

    @Test(arguments: ["bye", "cancel", "stop"]) func farewellAndCancellationReleaseTheMicrophone(
        answer: String
    ) async throws {
        let harness = VoiceHarness()
        try await harness.beginListening()
        harness.input.onText?(answer, true)
        try await waitUntil { harness.assistant.status == .speaking }
        #expect(!harness.input.capturing)
        #expect(harness.commits == 0)
        harness.completeSpeech()
        #expect(harness.assistant.status == .off)
        try await Task.sleep(for: .milliseconds(400))
        #expect(harness.input.starts == 1)
    }

    @Test func aConfirmedReminderEndsTheSessionWithoutResumingWakeListening() async throws {
        let harness = VoiceHarness()
        try await harness.beginListening()
        harness.input.onText?("Schedule a meeting with my client in twenty minutes", true)
        try await waitUntil { harness.assistant.status == .speaking }
        #expect(harness.commits == 0)
        #expect(!harness.input.capturing)
        harness.completeSpeech()
        try await waitUntil { harness.input.capturing }
        #expect(harness.assistant.status == .confirming)
        harness.input.onText?("Yes, save it", true)
        try await waitUntil { harness.commits == 1 }
        #expect(!harness.input.capturing)
        harness.completeSpeech()
        #expect(harness.assistant.status == .off)
        try await Task.sleep(for: .milliseconds(400))
        #expect(harness.input.starts == 2)
    }

    @Test func silenceReleasesCaptureAndSavesNothing() async throws {
        let harness = VoiceHarness(replyTimeout: .milliseconds(80))
        try await harness.beginListening()
        try await waitUntil { harness.assistant.status == .speaking }
        #expect(!harness.input.capturing)
        #expect(harness.commits == 0)
        harness.completeSpeech()
        #expect(harness.assistant.status == .off)
    }

    @Test func recognitionFailureStopsCaptureWithoutAnAutomaticRetry() async throws {
        let harness = VoiceHarness()
        try await harness.beginListening()
        harness.input.onError?("Microphone disconnected")
        #expect(!harness.input.capturing)
        #expect(harness.commits == 0)
        harness.completeSpeech()
        try await Task.sleep(for: .milliseconds(400))
        #expect(harness.assistant.status == .off)
        #expect(harness.input.starts == 1)
    }

    @Test func cancellationInvalidatesDelayedSpeechCompletions() async throws {
        let harness = VoiceHarness()
        await harness.assistant.beginConversation()
        harness.assistant.didArrive()
        let staleCompletion = harness.speechCompletion
        harness.assistant.endSession()
        staleCompletion?()
        try await Task.sleep(for: .milliseconds(400))
        #expect(harness.input.starts == 0)
        #expect(harness.assistant.status == .off)
    }

    @Test func cancellingDuringPermissionRequestCannotOpenTheMicrophoneLater() async throws {
        let harness = VoiceHarness()
        harness.input.deferPermission = true
        let start = Task { await harness.assistant.beginConversation() }
        try await waitUntil { harness.input.permissionReply != nil }
        harness.assistant.endSession()
        harness.input.permissionReply?.resume(returning: true)
        await start.value
        harness.assistant.didArrive()
        #expect(harness.input.starts == 0)
        #expect(!harness.assistant.isActive)
        #expect(harness.assistant.status == .off)
    }

    @Test func repeatedInvocationsDoNotRestartAnActiveDraft() async throws {
        let harness = VoiceHarness()
        try await harness.beginListening()
        await harness.assistant.beginConversation()
        #expect(harness.input.starts == 1)
        #expect(harness.assistant.status == .listening)
        harness.assistant.endSession()
        #expect(!harness.input.capturing)
    }

    @Test func wakePhraseStartsAVisitAndGoodbyeResumesWakeListening() async throws {
        let harness = VoiceHarness()
        await harness.assistant.enable(requestPermission: true)
        #expect(harness.assistant.status == .waiting)
        #expect(harness.input.capturing)
        harness.input.onText?("The weather is nice", true)
        #expect(!harness.assistant.isActive)
        harness.input.onText?("Hey Diana", true)
        #expect(harness.assistant.status == .arriving)
        #expect(!harness.input.capturing)
        harness.assistant.didArrive()
        #expect(harness.assistant.prompt == "Yep, how can I help you?")
        #expect(!harness.input.capturing)
        harness.completeSpeech()
        try await waitUntil { harness.input.capturing }
        harness.input.onText?("Bye Diana", true)
        try await waitUntil { harness.assistant.status == .speaking }
        #expect(!harness.input.capturing)
        harness.completeSpeech()
        #expect(harness.assistant.status == .waiting)
        #expect(!harness.assistant.isActive)
        #expect(harness.input.capturing)
        #expect(harness.commits == 0)
        harness.assistant.disable()
        #expect(!harness.input.capturing)
        #expect(harness.assistant.status == .off)
    }

    @Test func disablingWakeListeningPreventsSpeechCompletionFromReopeningCapture() async throws {
        let harness = VoiceHarness()
        await harness.assistant.enable(requestPermission: true)
        harness.assistant.pauseForSpeech()
        #expect(!harness.input.capturing)
        harness.assistant.resumeAfterExternalSpeech()
        #expect(harness.input.capturing)
        harness.assistant.disable()
        let starts = harness.input.starts
        harness.assistant.resumeAfterExternalSpeech()
        harness.input.onText?("Hey Diana", true)
        #expect(!harness.input.capturing)
        #expect(!harness.assistant.isActive)
        #expect(harness.input.starts == starts)
    }

    @Test func disablingDuringWakePermissionRequestCannotStartCapture() async throws {
        let harness = VoiceHarness()
        harness.input.deferPermission = true
        let start = Task { await harness.assistant.enable(requestPermission: true) }
        try await waitUntil { harness.input.permissionReply != nil }
        harness.assistant.disable()
        harness.input.permissionReply?.resume(returning: true)
        await start.value
        #expect(!harness.assistant.isEnabled)
        #expect(!harness.input.capturing)
        #expect(harness.assistant.status == .off)
        #expect(harness.input.starts == 0)
    }

    @Test func startupWithoutPermissionDoesNotCaptureOrPrompt() async {
        let harness = VoiceHarness()
        harness.input.hasPermissions = false
        await harness.assistant.enable(requestPermission: false)
        #expect(harness.input.permissionRequests == 0)
        #expect(harness.input.starts == 0)
        #expect(!harness.assistant.isEnabled)
        #expect(harness.assistant.status == .error)
    }

    @Test func anEmptyListeningTurnReturnsToWakeModeWithoutSaving() async throws {
        let harness = VoiceHarness(replyTimeout: .milliseconds(80))
        await harness.assistant.enable(requestPermission: true)
        harness.input.onText?("Hey Diana", true)
        harness.assistant.didArrive()
        harness.completeSpeech()
        try await waitUntil { harness.assistant.status == .speaking }
        #expect(!harness.input.capturing)
        harness.completeSpeech()
        #expect(harness.assistant.status == .waiting)
        #expect(harness.input.capturing)
        #expect(harness.commits == 0)
        harness.assistant.disable()
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }
}

@MainActor private final class VoiceHarness {
    let input = FakeVoiceInput()
    let assistant: VoiceAssistant
    var speechCompletion: (() -> Void)?
    var commits = 0

    init(replyTimeout: Duration = .seconds(25)) {
        assistant = VoiceAssistant(microphone: input, replyTimeout: replyTimeout)
        assistant.configure()
        assistant.onSpeak = { [weak self] _, completion in self?.speechCompletion = completion }
        assistant.onCommit = { [weak self] _, _ in
            self?.commits += 1
            return true
        }
    }

    func completeSpeech() {
        let completion = speechCompletion
        speechCompletion = nil
        completion?()
    }

    func beginListening() async throws {
        await assistant.beginConversation()
        #expect(!input.capturing)
        assistant.didArrive()
        #expect(!input.capturing)
        completeSpeech()
        for _ in 0..<200 {
            if input.capturing { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(input.capturing)
    }
}

@MainActor private final class FakeVoiceInput: VoiceInput {
    var onText: ((String, Bool) -> Void)?
    var onError: ((String) -> Void)?
    var usesOnDeviceRecognition = true
    var hasPermissions = true
    var permissionRequests = 0
    var capturing = false
    var starts = 0
    var deferPermission = false
    var permissionReply: CheckedContinuation<Bool, Never>?

    func requestPermissions() async -> Bool {
        permissionRequests += 1
        if deferPermission { return await withCheckedContinuation { permissionReply = $0 } }
        return hasPermissions
    }
    func start() {
        starts += 1
        capturing = true
    }
    func stop() { capturing = false }
}
