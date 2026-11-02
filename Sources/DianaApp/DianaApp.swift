import AppKit
import DianaCore
import SwiftUI

@main struct DianaApp: App {
    @NSApplicationDelegateAdaptor(DianaAppDelegate.self) private var delegate
    @State private var model: AppModel
    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        // Notification actions can arrive before the main window opens.
        model.start()
    }
    var body: some Scene {
        Window("Diana", id: "main") {
            MainView().environment(model).onAppear { delegate.configure(model: model) }
        }.windowStyle(.hiddenTitleBar).defaultSize(width: 1260, height: 840).defaultPosition(.center)
            .windowResizability(.contentMinSize).commands {
                CommandGroup(replacing: .newItem) {
                    Button("New Reminder") {
                        model.onRevealWindow?()
                        model.showEditor()
                    }.keyboardShortcut("n")
                }
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") {
                        model.page = .settings
                        model.onRevealWindow?()
                    }.keyboardShortcut(",")
                }
                CommandMenu("Companion") {
                    Toggle(
                        "Reminder Visits",
                        isOn: Binding(
                            get: { model.preferences.companionVisible },
                            set: { model.preferences.companionVisible = $0 }))
                    Button("Say Hello") { model.sayHello() }
                    Button("Talk to Diana") { model.startVoiceConversation() }.keyboardShortcut(
                        "t", modifiers: [.command, .shift])
                    Toggle(
                        "Listen for Hey Diana",
                        isOn: Binding(
                            get: { model.voiceAssistant.isEnabled },
                            set: { model.setVoiceAssistantEnabled($0) }))
                    Button("End Conversation") { model.stopSpeaking() }.disabled(
                        !model.voiceAssistant.isActive && model.voiceAssistant.status != .enabling)
                    Button("Focus Desktop Companion") { model.onFocusPet?() }.keyboardShortcut(
                        "d", modifiers: [.command, .shift])

                    Button("Return to Corner") { model.onReposition?() }
                }
            }
        MenuBarExtra("Diana", systemImage: "sparkles") {
            Text("Diana · in good company")
            if let next = model.nextOccurrence, let reminder = model.reminder(for: next) {
                Text("Next: \(reminder.title) · \(next.dueAt.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("A little room in your day.")
            }
            Divider()
            Button("Open Diana") { model.onRevealWindow?() }.keyboardShortcut("o")
            Button("New Reminder…") {
                model.onRevealWindow?()
                model.showEditor()
            }
            Button("Water Reminder…") {
                model.onRevealWindow?()
                model.showEditor(kind: .water)
            }
            Divider()
            Toggle(
                "Reminder Visits",
                isOn: Binding(
                    get: { model.preferences.companionVisible },
                    set: { model.preferences.companionVisible = $0 }))
            Button("Say Hello") { model.sayHello() }
            Button("Talk to Diana") { model.startVoiceConversation() }
            Toggle(
                "Listen for Hey Diana",
                isOn: Binding(
                    get: { model.voiceAssistant.isEnabled }, set: { model.setVoiceAssistantEnabled($0) }))
            Button("End Conversation") { model.stopSpeaking() }.disabled(
                !model.voiceAssistant.isActive && model.voiceAssistant.status != .enabling)
            Button("Return to Corner") { model.onReposition?() }
            Divider()
            Button("Quit Diana") {
                model.flush()
                NSApp.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
}

@MainActor final class DianaAppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var panel: CompanionPanel?
    private var visitTask: Task<Void, Never>?
    private var contentTask: Task<Void, Never>?
    private var visitScreen: NSScreen?
    private var travelsLeft = true
    private var nextFromRight: Bool?
    private var presentedID: String?
    private var voiceVisit = false
    private var placed = false
    private var lastCorner = "right"
    func configure(model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        model.onPreferencesChanged = { [weak self] in self?.updatePanel() }
        model.onCompanionContentChanged = { [weak self] in
            // Coalesce queue changes before deciding whether to dismiss the panel.
            self?.contentTask?.cancel()
            self?.contentTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled else { return }
                self?.updatePanel()
            }
        }
        model.onReposition = { [weak self] in self?.positionPanel(reset: true) }
        model.onFocusPet = { [weak self] in
            guard let self else { return }
            model.preferences.companionVisible = true
            NSApp.activate(ignoringOtherApps: true)
            if model.visitPhase.isVisible { self.panel?.makeKeyAndOrderFront(nil) } else { model.sayHello() }
        }
        model.start()
        Task { @MainActor in
            for motion in [PetMotion.run, .kiss] {
                _ = try? await DianaAssetLibrary.shared.instance(for: motion)
            }
        }
        updatePanel()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.model?.resumeAfterWake() } }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.positionPanel(reset: false) } }
    }
    func updatePanel() {
        guard let model else { return }
        if panel == nil {
            let panel = CompanionPanel(
                contentRect: NSRect(x: 0, y: 0, width: 240, height: 360),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.isReleasedWhenClosed = false
            panel.title = "Diana Companion"
            let host = NSHostingView(
                rootView: FloatingCompanion(onDragEnd: { [weak self] in self?.savePosition() }).environment(
                    model))
            host.sizingOptions = []
            panel.contentView = host
            self.panel = panel
        }
        guard let panel else { return }
        let p = model.preferences
        panel.collectionBehavior =
            p.allSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            : [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.alphaValue = 1
        panel.appearance =
            p.appearance == .system ? nil : NSAppearance(named: p.appearance == .dark ? .darkAqua : .aqua)
        let hasContent =
            model.activeReminder != nil || model.petGreeting != nil || model.voiceAssistant.isActive
        panel.ignoresMouseEvents = p.clickThrough && !hasContent
        let width = max(260, p.companionHeight * 0.65)
        let height = p.companionHeight + (model.voiceAssistant.isActive ? 266 : 186)
        let origin = panel.frame.origin
        panel.setContentSize(NSSize(width: width, height: height))
        panel.setFrameOrigin(origin)
        if !model.visitPhase.isVisible { positionPanel(reset: lastCorner != p.corner) }
        lastCorner = p.corner
        if model.effectiveReducedMotion {
            if model.visitPhase == .entering {
                visitTask?.cancel()
                positionPanel(reset: true)
                model.visitPhase = .presenting
                schedulePresentation()
                return
            } else if model.visitPhase == .kissing || model.visitPhase == .exiting {
                visitTask?.cancel()
                model.visitPhase = .hidden
                panel.orderOut(nil)
                return
            }
        }
        switch model.visitPhase.intent(
            hasContent: hasContent, enabled: p.companionVisible || model.voiceAssistant.isActive)
        {
        case .hide:
            visitTask?.cancel()
            presentedID = nil
            model.visitPhase = .hidden
            panel.orderOut(nil)
        case .enter: beginVisit()
        case .depart: depart()
        case .keep: if model.visitPhase == .presenting { schedulePresentation() }
        }
    }

    func positionPanel(reset: Bool) {
        guard let panel, let model, let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 18, dy: 10)
        var position = panel.frame.origin
        if reset || !placed {
            if !reset, let x = model.preferences.petX, let y = model.preferences.petY {
                position = NSPoint(x: x, y: y)
            } else {
                position = NSPoint(
                    x: model.preferences.corner == "left" ? visible.minX : visible.maxX - panel.frame.width,
                    y: visible.minY)
            }
        }
        position.x = min(max(position.x, visible.minX), max(visible.minX, visible.maxX - panel.frame.width))
        position.y = min(max(position.y, visible.minY), max(visible.minY, visible.maxY - panel.frame.height))
        panel.setFrameOrigin(position)
        placed = true
        if reset { savePosition() }
    }
    func savePosition() {
        guard let panel, let model else { return }
        var preferences = model.preferences
        preferences.petX = panel.frame.minX
        preferences.petY = panel.frame.minY
        model.data.preferences = preferences
        model.saveSoon()
    }

    private func setMotion(_ motion: PetMotion, yaw: Double = 0) {
        model?.petYaw = yaw
        model?.petMotion = motion
        model?.petReplay += 1
    }
    private func travel(to x: CGFloat, duration: Double) async {
        guard let panel else { return }
        let start = panel.frame.origin
        let began = ProcessInfo.processInfo.systemUptime
        while !Task.isCancelled {
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - began) / max(duration, 0.001))
            panel.setFrameOrigin(NSPoint(x: start.x + (x - start.x) * progress, y: start.y))
            if progress >= 1 { return }
            try? await Task.sleep(for: .milliseconds(33))
        }
    }
    private func beginVisit() {
        guard let model, let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        visitTask?.cancel()
        presentedID = nil
        visitScreen = screen
        voiceVisit = model.voiceAssistant.isActive
        travelsLeft =
            voiceVisit
            ? model.preferences.corner == "right" : (nextFromRight ?? (model.preferences.corner == "right"))
        if !voiceVisit { nextFromRight = !travelsLeft }
        model.visitPhase = .entering
        let visible = screen.visibleFrame
        let destination =
            voiceVisit
            ? (travelsLeft ? visible.maxX - panel.frame.width - 18 : visible.minX + 18)
            : (travelsLeft ? visible.minX + 18 : visible.maxX - panel.frame.width - 18)
        panel.setFrameOrigin(
            NSPoint(
                x: model.effectiveReducedMotion
                    ? destination : (travelsLeft ? visible.maxX : visible.minX - panel.frame.width),
                y: visible.minY + 10))
        setMotion(model.effectiveReducedMotion ? .idle : .run, yaw: travelsLeft ? -.pi / 2 : .pi / 2)
        panel.orderFrontRegardless()
        let duration =
            model.effectiveReducedMotion
            ? 0
            : abs(panel.frame.minX - destination)
                / (model.preferences.companionHeight * 0.70 * model.preferences.animationSpeed)
        visitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if duration > 0 { await self.travel(to: destination, duration: duration) }
            guard !Task.isCancelled, model.visitPhase == .entering else { return }
            model.visitPhase = .presenting
            self.schedulePresentation()
        }
    }
    private func schedulePresentation() {
        guard let model else { return }
        let id =
            model.voiceAssistant.isActive
            ? "voice-session" : (model.activeReminder?.id ?? model.petGreeting ?? "")
        guard id != presentedID else { return }
        presentedID = id
        visitTask?.cancel()
        setMotion(
            model.effectiveReducedMotion
                ? .idle
                : (model.voiceAssistant.isActive || model.activeReminder == nil
                    ? .wave : (travelsLeft ? .portrait : .hip)))
        if model.voiceAssistant.isActive {
            model.voiceAssistant.didArrive()
            return
        }
        visitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5.1 / model.preferences.animationSpeed))
            guard !Task.isCancelled else { return }
            self?.setMotion(.idle)
            try? await Task.sleep(for: .seconds(13))
            guard !Task.isCancelled else { return }
            model.finishVisit()
            if model.activeReminder == nil { model.petGreeting = nil }
        }
    }
    private func depart() {
        guard let model, let panel, let screen = visitScreen ?? panel.screen else { return }
        visitTask?.cancel()
        presentedID = nil
        if model.effectiveReducedMotion {
            model.visitPhase = .hidden
            panel.orderOut(nil)
            return
        }
        model.visitPhase = .kissing
        setMotion(.kiss)
        visitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.25 / model.preferences.animationSpeed))
            guard !Task.isCancelled, let self else { return }
            model.visitPhase = .exiting
            let exitsLeft = self.voiceVisit ? !self.travelsLeft : self.travelsLeft
            self.setMotion(.run, yaw: exitsLeft ? -.pi / 2 : .pi / 2)
            let destination =
                exitsLeft ? screen.visibleFrame.minX - panel.frame.width : screen.visibleFrame.maxX
            let duration =
                abs(destination - panel.frame.minX)
                / (model.preferences.companionHeight * 0.70 * model.preferences.animationSpeed)
            await self.travel(to: destination, duration: duration)
            guard !Task.isCancelled else { return }
            model.visitPhase = .hidden
            panel.orderOut(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.onRevealWindow?()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        model?.voiceAssistant.pauseRecognition()
        model?.flush()
    }
}

final class CompanionPanel: NSPanel { override var canBecomeKey: Bool { true } }
