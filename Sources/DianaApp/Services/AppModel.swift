import AVFoundation
import AppKit
import DianaCore
import Observation
import SwiftUI
import UserNotifications

enum AppPage: String, CaseIterable, Identifiable {
    case today, schedule, companion, settings
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .schedule: "calendar"
        case .companion: "sparkles"
        case .settings: "slider.horizontal.3"
        }
    }
}

enum PetMotion: String, CaseIterable, Identifiable {
    case idle, run, wave, kiss, portrait, hip
    var id: String { rawValue }
    var title: String {
        switch self {
        case .idle: "Relax"
        case .run: "Run"
        case .wave: "Wave"
        case .kiss: "Kiss"
        case .portrait: "Portrait"
        case .hip: "Hip pose"
        }
    }
    var symbol: String {
        switch self {
        case .idle: "figure.stand"
        case .run: "figure.run"
        case .wave: "hand.wave"
        case .kiss: "heart"
        case .portrait: "person.crop.square"
        case .hip: "figure.stand"
        }
    }
}

@Observable @MainActor final class AppModel {
    var data: AppData
    var page: AppPage = .today
    var selectedDate = Date.now
    var query = ""
    var showCompleted = false
    var editor: Reminder?
    var errorMessage: String?
    var storageFailure: String?
    var notificationState: UNAuthorizationStatus = .notDetermined
    var notificationProblem: String?
    var now = Date.now
    var activeReminder: Occurrence? { didSet { onCompanionContentChanged?() } }
    var previewMotion: PetMotion = .idle
    var petMotion: PetMotion = .idle
    var petYaw = 0.0
    var visitPhase: CompanionVisitPhase = .hidden
    var petReplay = 0
    var previewReplay = 0
    var petGreeting: String? { didSet { onCompanionContentChanged?() } }
    var chatMessages: [AssistantMessage] = []
    var isAITyping = false
    var aiModels: [OllamaModel] = []
    var aiStatus = "Connect to the Ollama running on this Mac."
    var aiError: String?
    var isConnectingAI = false
    var reminderAside: String?
    var isSpeaking = false
    let voiceAssistant = VoiceAssistant()
    @ObservationIgnored private let localAI = OllamaClient()
    @ObservationIgnored private var chatRequestID = UUID()
    @ObservationIgnored private var chatTask: Task<Void, Never>?
    @ObservationIgnored private var reminderAITask: Task<Void, Never>?
    var modelError: String?
    var toast: String?
    @ObservationIgnored let repository: DataRepository
    @ObservationIgnored var notificationService: NotificationService?
    @ObservationIgnored var onPreferencesChanged: (() -> Void)?
    @ObservationIgnored var onRevealWindow: (() -> Void)?
    @ObservationIgnored var onReposition: (() -> Void)?
    @ObservationIgnored var onFocusPet: (() -> Void)?
    @ObservationIgnored var onCompanionContentChanged: (() -> Void)?
    @ObservationIgnored private var presentationQueue: [Occurrence] = []
    @ObservationIgnored private var clock: Timer?
    @ObservationIgnored private var lastTick = Date.now.addingTimeInterval(-10 * 60)
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var greetingTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private let speech = AVSpeechSynthesizer()
    @ObservationIgnored private let speechObserver = SpeechObserver()
    @ObservationIgnored private var spokenUtteranceID: ObjectIdentifier?
    @ObservationIgnored private var speechCompletion: (() -> Void)?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        repository = DataRepository(directory: support.appendingPathComponent("Diana", isDirectory: true))
        do { data = try repository.load() } catch {
            data = AppData()
            storageFailure =
                "Your saved reminders could not be read. The original file is preserved. \(error.localizedDescription)"
        }
        voiceAssistant.configure()
        voiceAssistant.onChange = { [weak self] in self?.onCompanionContentChanged?() }
        voiceAssistant.onSpeak = { [weak self] text, completion in
            self?.performSpeech(text, completion: completion)
        }
        voiceAssistant.onCommit = { [weak self] reminder, approved in
            self?.commitVoiceReminder(reminder, approvedConflicts: approved) == true
        }
        voiceAssistant.onSchedules = { [weak self] in self?.data ?? AppData() }
        voiceAssistant.onCompanionVisible = { [weak self] in
            self?.visitPhase == .entering || self?.visitPhase == .presenting
        }
        voiceAssistant.onFarewell = { [weak self] in
            guard let self else { return }
            self.greetingTask?.cancel()
            self.reminderAITask?.cancel()
            self.presentationQueue = []
            self.activeReminder = nil
            self.petGreeting = nil
            self.reminderAside = nil
        }
        voiceAssistant.onEnabledChanged = { [weak self] value in
            self?.preferences.voiceAssistantEnabled = value
        }
        speechObserver.onFinished = { [weak self] id in
            guard let self, self.spokenUtteranceID == id else { return }
            self.spokenUtteranceID = nil
            self.isSpeaking = false
            let completion = self.speechCompletion
            self.speechCompletion = nil
            if let completion { completion() } else { self.voiceAssistant.resumeAfterExternalSpeech() }
        }
        speech.delegate = speechObserver
        speechObserver.onChange = { [weak self] in
            guard let self else { return }
            self.isSpeaking = self.speech.isSpeaking
        }
    }

    var preferences: Preferences {
        get { data.preferences }
        set {
            let old = data.preferences
            data.preferences = newValue
            saveSoon()
            onPreferencesChanged?()
            if old.ollamaEnabled == true && newValue.ollamaEnabled != true {
                cancelAI()
                reminderAITask?.cancel()
            }
            if old.voice && !newValue.voice { stopSpeaking() }
            if old.sounds != newValue.sounds || old.notificationsEnabled != newValue.notificationsEnabled
                || old.quietHoursEnabled != newValue.quietHoursEnabled
                || old.quietStartHour != newValue.quietStartHour || old.quietEndHour != newValue.quietEndHour
            {
                reconcileNotifications()
            }
        }
    }

    var effectiveReducedMotion: Bool {
        preferences.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    var nextOccurrence: Occurrence? { ScheduleEngine.upcoming(in: data, after: now, limit: 1).first?.0 }
    var selectedDayOccurrences: [Occurrence] { occurrences(on: selectedDate) }
    var todayOccurrences: [Occurrence] { occurrences(on: now) }
    func occurrences(on date: Date) -> [Occurrence] {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let generated = data.reminders.flatMap { ScheduleEngine.occurrences(for: $0, in: start..<end) }
        return generated.sorted { $0.dueAt < $1.dueAt }
    }
    var visibleOccurrences: [Occurrence] {
        selectedDayOccurrences.filter { occurrence in
            guard let reminder = reminder(for: occurrence) else { return false }
            let matches =
                query.isEmpty || reminder.title.localizedCaseInsensitiveContains(query)
                || reminder.notes.localizedCaseInsensitiveContains(query)
            return matches && (showCompleted || data.records[occurrence.id]?.isFinished != true)
        }
    }
    var completedToday: Int {
        selectedDayOccurrences.filter { data.records[$0.id]?.completedAt != nil }.count
    }
    var overdue: [Occurrence] {
        data.reminders.filter {
            $0.isEnabled && $0.repeatRule == .once && $0.startsAt < Calendar.current.startOfDay(for: now)
        }.map { Occurrence(reminderID: $0.id, dueAt: $0.startsAt, leadMinutes: $0.leadMinutes) }.filter {
            data.records[$0.id]?.isFinished != true
        }.sorted { $0.dueAt < $1.dueAt }
    }

    func reminder(for occurrence: Occurrence) -> Reminder? {
        data.reminders.first { $0.id == occurrence.reminderID }
    }
    func start() {
        guard notificationService == nil else { return }
        if preferences.voiceAssistantEnabled == true {
            Task { await voiceAssistant.enable(requestPermission: false) }
        }
        let service = NotificationService(model: self)
        notificationService = service
        service.configure()
        Task {
            await refreshNotificationStatus()
            reconcileNotifications()
        }
        clock = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func refreshNotificationStatus() async {
        notificationState = await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus
    }
    func enableNotifications() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await refreshNotificationStatus()
            preferences.notificationsEnabled = true
            reconcileNotifications()
        } catch { errorMessage = "Notifications could not be enabled: \(error.localizedDescription)" }
    }
    func reconcileNotifications() { notificationService?.reconcile(data: data) }
    func conflicts(for reminder: Reminder) -> [ScheduleConflict] {
        ScheduleConflicts.find(for: reminder, in: data)
    }
    func hasConflict(_ occurrence: Occurrence) -> Bool {
        guard data.records[occurrence.id]?.isFinished != true, var reminder = reminder(for: occurrence) else {
            return false
        }
        reminder.startsAt = occurrence.dueAt
        return !conflicts(for: reminder).isEmpty
    }
    func showEditor(kind: ReminderKind = .task) {
        var date = now.addingTimeInterval(30 * 60)
        if page == .today && !Calendar.current.isDateInToday(selectedDate) {
            date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? date
        }
        let title = kind == .water ? "Drink a glass of water" : kind == .rest ? "Take a little break" : ""
        editor = Reminder(
            title: title, kind: kind, startsAt: date, repeatRule: kind == .water ? .interval : .once,
            leadMinutes: kind == .meeting ? 5 : 0)
    }
    func saveReminder(_ reminder: Reminder, approvedConflicts: Set<String> = []) {
        guard storageFailure == nil else { return }
        if let error = reminder.validationError {
            errorMessage = error
            return
        }
        var cleaned = reminder
        cleaned.title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.startsAt = Date(
            timeIntervalSince1970: floor(reminder.startsAt.timeIntervalSince1970 / 60) * 60)
        let conflicts = ScheduleConflicts.find(for: cleaned, in: data)
        guard Set(conflicts.map(\.id)).isSubset(of: approvedConflicts) else {
            showToast("That time is already in use. Review the conflict before saving.")
            return
        }
        if let index = data.reminders.firstIndex(where: { $0.id == reminder.id }) {
            let old = data.reminders[index]
            data.reminders[index] = cleaned
            if old.startsAt != cleaned.startsAt || old.repeatRule != cleaned.repeatRule
                || old.intervalMinutes != cleaned.intervalMinutes || old.windowStart != cleaned.windowStart
                || old.windowEnd != cleaned.windowEnd
            {
                data.records = data.records.filter {
                    $0.value.reminderID != reminder.id || $0.value.completedAt != nil
                }
            }
        } else {
            guard data.reminders.count < 2000 else {
                errorMessage =
                    "Diana supports up to 2,000 reminders. Export a backup before removing older tasks."
                return
            }
            data.reminders.append(cleaned)
        }
        editor = nil
        guard flush() else { return }
        reconcileNotifications()
        showToast("Reminder saved. Diana will take it from here.")
    }
    func removeReminder(_ reminder: Reminder) {
        data.reminders.removeAll { $0.id == reminder.id }
        data.records = data.records.filter { $0.value.reminderID != reminder.id }
        presentationQueue.removeAll { $0.reminderID == reminder.id }
        if activeReminder?.reminderID == reminder.id { advanceReminder() }
        flush()
        reconcileNotifications()
    }
    func toggleEnabled(_ reminder: Reminder) {
        guard let index = data.reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        data.reminders[index].isEnabled.toggle()
        if !data.reminders[index].isEnabled {
            presentationQueue.removeAll { $0.reminderID == reminder.id }
            if activeReminder?.reminderID == reminder.id { advanceReminder() }
        }
        flush()
        reconcileNotifications()
    }
    func complete(_ occurrence: Occurrence) {
        var record = data.records[occurrence.id] ?? OccurrenceRecord(occurrence: occurrence)
        if record.completedAt != nil {
            record.completedAt = nil
        } else {
            record.completedAt = Date.now
            record.dismissedAt = nil
            record.snoozedUntil = nil
        }
        data.records[occurrence.id] = record
        if activeReminder?.id == occurrence.id { advanceReminder() }
        flush()
        reconcileNotifications()
    }
    func snooze(_ occurrence: Occurrence, minutes: Int = 10) {
        var record = data.records[occurrence.id] ?? OccurrenceRecord(occurrence: occurrence)
        record.snoozedUntil = Date.now.addingTimeInterval(Double(minutes) * 60)
        record.announcedAt = nil
        record.dismissedAt = nil
        data.records[occurrence.id] = record
        if activeReminder?.id == occurrence.id { advanceReminder() }
        flush()
        reconcileNotifications()
        showToast("Snoozed for \(minutes) minutes.")
    }
    func dismiss(_ occurrence: Occurrence) {
        var record = data.records[occurrence.id] ?? OccurrenceRecord(occurrence: occurrence)
        record.dismissedAt = Date.now
        record.snoozedUntil = nil
        data.records[occurrence.id] = record
        if activeReminder?.id == occurrence.id { advanceReminder() }
        flush()
        reconcileNotifications()
    }

    func tick() {
        let current = Date.now
        if Calendar.current.isDate(selectedDate, inSameDayAs: now)
            && !Calendar.current.isDate(now, inSameDayAs: current)
        {
            selectedDate = current
        }
        now = current
        let lower = max(lastTick, current.addingTimeInterval(-10 * 60))
        lastTick = current
        let candidates = ScheduleEngine.due(in: data, after: lower, through: current)
        for occurrence in candidates {
            var record = data.records[occurrence.id] ?? OccurrenceRecord(occurrence: occurrence)
            record.announcedAt = current
            data.records[occurrence.id] = record
            if !preferences.isQuiet(at: current) { enqueueReminder(occurrence) }
        }
        if !candidates.isEmpty { flush() }
        if Int(current.timeIntervalSince1970) % 60 < 5 { reconcileNotifications() }
    }

    func presentReminder(_ occurrence: Occurrence) {
        guard let reminder = reminder(for: occurrence) else { return }
        if let active = activeReminder, active.id != occurrence.id,
            !presentationQueue.contains(where: { $0.id == active.id })
        {
            presentationQueue.insert(active, at: 0)
        }
        presentationQueue.removeAll { $0.id == occurrence.id }
        reminderAITask?.cancel()
        reminderAside = nil
        activeReminder = occurrence
        if preferences.ollamaEnabled == true, preferences.aiReminderMessages == true,
            let selected = preferences.ollamaModel
        {
            reminderAITask = Task { @MainActor [weak self] in
                guard let self else { return }
                let messages = [
                    AssistantMessage(
                        role: "system",
                        content:
                            "You are Diana, a friendly desktop companion. Write one warm reminder sentence under 16 words. No preamble, quotes, or scheduling claims."
                    ), AssistantMessage(role: "user", content: "Remind me about: " + reminder.title),
                ]
                if let reply = try? await self.localAI.reply(
                    model: selected, messages: messages, short: true), !Task.isCancelled,
                    self.activeReminder?.id == occurrence.id,
                    self.visitPhase == .entering || self.visitPhase == .presenting
                {
                    self.reminderAside = String(reply.prefix(160))
                }
            }
        }
        if preferences.sounds
            && (NSApp.isActive || !preferences.notificationsEnabled || notificationState != .authorized)
        {
            NSSound(named: "Glass")?.play()
        }
        if preferences.voice { speak(reminder.title) }
    }

    func sayHello() {
        greetingTask?.cancel()
        petGreeting = "A little company for whatever’s next."
        previewMotion = .wave
        previewReplay += 1
        greetingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            self?.petGreeting = nil
            self?.previewMotion = .idle
        }
    }
    private func enqueueReminder(_ occurrence: Occurrence) {
        if activeReminder == nil {
            presentReminder(occurrence)
        } else if activeReminder?.id != occurrence.id
            && !presentationQueue.contains(where: { $0.id == occurrence.id })
        {
            presentationQueue.append(occurrence)
        }
    }
    func finishVisit() { advanceReminder() }
    private func advanceReminder() {
        reminderAITask?.cancel()
        reminderAside = nil
        activeReminder = nil
        petMotion = .idle
        while !presentationQueue.isEmpty {
            let next = presentationQueue.removeFirst()
            guard data.records[next.id]?.isFinished != true,
                (data.records[next.id]?.snoozedUntil ?? .distantPast) <= .now,
                reminder(for: next)?.isEnabled == true
            else { continue }
            presentReminder(next)
            break
        }
    }
    func connectAI() async {
        guard !isConnectingAI else { return }
        isConnectingAI = true
        aiError = nil
        defer { isConnectingAI = false }
        do {
            aiModels = try await localAI.models()
            if !aiModels.contains(where: { $0.name == preferences.ollamaModel }) {
                preferences.ollamaModel = aiModels.first?.name
            }
            aiStatus =
                aiModels.isEmpty
                ? "Ollama is running. Install a local model to begin."
                : "Connected · \(aiModels.count) local model\(aiModels.count == 1 ? "" : "s")"
        } catch {
            aiModels = []
            aiError = error.localizedDescription
            aiStatus = "Ollama is offline"
        }
    }
    func askDiana(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isAITyping, preferences.ollamaEnabled == true else { return }
        guard let selected = preferences.ollamaModel else {
            aiError = LocalAssistantError.noModel.localizedDescription
            return
        }
        aiError = nil
        isAITyping = true
        let requestID = UUID()
        chatRequestID = requestID
        chatMessages.append(AssistantMessage(role: "user", content: String(prompt.prefix(1000))))
        if chatMessages.count > 11 { chatMessages.removeFirst(chatMessages.count - 11) }
        let messages =
            [
                AssistantMessage(
                    role: "system",
                    content:
                        "You are Diana, a warm desktop companion. Give practical, friendly answers in at most 60 words. You cannot change schedules, create tasks, access calendars, or use tools. Never claim you performed those actions. Help the user plan. Only if they ask you to create or change a reminder, explain that they can save it with New Reminder."
                )
            ] + chatMessages
        chatTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.chatRequestID == requestID { self.isAITyping = false } }
            do {
                let reply = try await self.localAI.reply(model: selected, messages: messages)
                guard !Task.isCancelled else { return }
                self.chatMessages.append(AssistantMessage(role: "assistant", content: reply))
                self.previewMotion = .wave
                self.previewReplay += 1
                if self.preferences.voice { self.speak(reply) }
            } catch is CancellationError {} catch { self.aiError = error.localizedDescription }
        }
    }
    func cancelAI() {
        chatTask?.cancel()
        chatRequestID = UUID()
        isAITyping = false
    }
    func clearChat() {
        cancelAI()
        chatMessages = []
        aiError = nil
        stopSpeaking()
    }
    func speak(_ text: String) {
        guard !voiceAssistant.isActive else { return }
        performSpeech(text, completion: nil)
    }
    private func performSpeech(_ text: String, completion: (() -> Void)?) {
        let cleanText = CompanionText.spoken(text)
        guard !cleanText.isEmpty else {
            completion?()
            return
        }
        voiceAssistant.pauseForSpeech()
        spokenUtteranceID = nil
        speechCompletion = nil
        speech.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: cleanText)
        spokenUtteranceID = ObjectIdentifier(utterance)
        speechCompletion = completion
        utterance.voice = DianaSpeech.voice(preferredID: preferences.voiceIdentifier, text: cleanText)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(preferences.speechRate ?? 1)
        utterance.pitchMultiplier = 1
        utterance.preUtteranceDelay = 0.08
        utterance.postUtteranceDelay = 0.15
        speech.speak(utterance)
    }
    func stopSpeaking() {
        if voiceAssistant.isActive { voiceAssistant.endSession() }
        speech.stopSpeaking(at: .immediate)
    }
    func setVoiceAssistantEnabled(_ enabled: Bool) {
        if enabled {
            Task { await voiceAssistant.enable(requestPermission: true) }
        } else {
            voiceAssistant.disable()
            speechCompletion = nil
            spokenUtteranceID = nil
            speech.stopSpeaking(at: .immediate)
        }
    }
    private func commitVoiceReminder(_ reminder: Reminder, approvedConflicts: Set<String>) -> Bool {
        guard storageFailure == nil, data.reminders.count < 2000,
            !data.reminders.contains(where: { $0.id == reminder.id }), reminder.validationError == nil
        else { return false }
        var cleaned = reminder
        cleaned.startsAt = Date(
            timeIntervalSince1970: floor(reminder.startsAt.timeIntervalSince1970 / 60) * 60)
        guard cleaned.startsAt > .now else { return false }
        guard Set(ScheduleConflicts.find(for: cleaned, in: data).map(\.id)).isSubset(of: approvedConflicts)
        else { return false }
        var updated = data
        updated.reminders.append(cleaned)
        do {
            try repository.save(updated)
            data = updated
            reconcileNotifications()
            showToast("Voice reminder saved.")
            return true
        } catch {
            errorMessage = "The voice reminder could not be saved. " + error.localizedDescription
            return false
        }
    }
    func resumeAfterWake() {
        tick()
        reconcileNotifications()
        onPreferencesChanged?()
    }
    func showToast(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            if !Task.isCancelled { self?.toast = nil }
        }
    }
    func saveSoon() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            if !Task.isCancelled { self?.flush() }
        }
    }
    @discardableResult func flush() -> Bool {
        guard storageFailure == nil else { return false }
        do {
            try repository.save(data)
            return true
        } catch {
            errorMessage = "Your latest changes could not be saved. \(error.localizedDescription)"
            return false
        }
    }
    func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Diana-backup.json"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try DataRepository.encode(data).write(to: url, options: .atomic)
                showToast("Backup exported.")
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let backup = try DataRepository.decode(Data(contentsOf: url))
            let existing = Set(data.reminders.map(\.id))
            let additions = backup.reminders.filter { !existing.contains($0.id) }
            guard data.reminders.count + additions.count <= 2000 else {
                throw RepositoryError.invalid("The combined backup would exceed 2,000 reminders.")
            }
            data.reminders += additions
            let addedIDs = Set(additions.map(\.id))
            for (id, record) in backup.records where addedIDs.contains(record.reminderID) {
                data.records[id] = record
            }
            flush()
            reconcileNotifications()
            showToast("Imported \(additions.count) reminders. Existing tasks were kept.")
        } catch { errorMessage = "This backup could not be imported. \(error.localizedDescription)" }
    }

}
