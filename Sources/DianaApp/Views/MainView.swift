import AppKit
import DianaCore
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.openWindow) private var openWindow
    private var scheme: ColorScheme? {
        switch model.preferences.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    private var theme: DianaTheme {
        DianaTheme(dark: (scheme ?? systemScheme) == .dark, selectedAccent: model.preferences.accent)
    }
    var body: some View {
        @Bindable var model = model
        GeometryReader { geometry in
            HStack(spacing: 0) {
                SidebarView().frame(width: 218)
                Rectangle().fill(theme.line).frame(width: 1)
                VStack(spacing: 0) {
                    header
                    Rectangle().fill(theme.line.opacity(0.7)).frame(height: 1)
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 26) {
                                if let failure = model.storageFailure { errorBanner(failure) }
                                switch model.page {
                                case .today: TodayView()
                                case .schedule: ScheduleView()
                                case .companion: CompanionSettingsView()
                                case .settings: AppSettingsView()
                                }
                            }.padding(30).frame(maxWidth: .infinity, alignment: .topLeading)
                        }.scrollIndicators(.hidden)
                        if model.page == .today && geometry.size.width >= 1160 {
                            Rectangle().fill(theme.line.opacity(0.7)).frame(width: 1)
                            ScrollView { CompanionStudio(compact: true).padding(20) }.scrollIndicators(
                                .hidden
                            ).frame(width: 342)
                        }
                    }
                }
            }.background(theme.background)
        }.frame(minWidth: 980, minHeight: 680).environment(\.dianaTheme, theme).foregroundStyle(theme.ink)
            .tint(theme.accent).preferredColorScheme(scheme).sheet(item: $model.editor) { reminder in
                ReminderEditor(initial: reminder).environment(model).environment(\.dianaTheme, theme)
                    .preferredColorScheme(scheme)
            }.alert(
                "Something needs attention",
                isPresented: Binding(
                    get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }.overlay(alignment: .bottom) {
                if let toast = model.toast {
                    Label(toast, systemImage: "checkmark.circle.fill").font(
                        .system(size: 12, weight: .medium)
                    ).padding(.horizontal, 18).padding(.vertical, 12).background(theme.ink, in: Capsule())
                        .foregroundStyle(theme.background).shadow(
                            color: .black.opacity(0.12), radius: 14, y: 6
                        ).padding(.bottom, 22).transition(.opacity)
                }
            }.animation(model.effectiveReducedMotion ? nil : .easeOut(duration: 0.18), value: model.toast)
            .onAppear {
                model.onRevealWindow = {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                if let window = NSApp.windows.first(where: { $0.title == "Diana" }) {
                    window.backgroundColor = NSColor(theme.background)
                    window.titlebarAppearsTransparent = true
                }
            }.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
        { _ in Task { await model.refreshNotificationStatus() } }
    }
    private var header: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: model.page.symbol).foregroundStyle(theme.accent)
                Text(model.page.title).font(.system(size: 13, weight: .semibold))
            }
            Spacer()
            if model.page == .today || model.page == .schedule {
                @Bindable var model = model
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.muted)
                    TextField(
                        "Find a reminder", text: $model.query,
                        prompt: Text("Find a reminder").foregroundStyle(theme.muted)
                    ).textFieldStyle(.plain).font(.system(size: 12)).accessibilityIdentifier("reminderSearch")
                    if !model.query.isEmpty {
                        Button {
                            model.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }.buttonStyle(.plain).help("Clear search")
                    }
                }.padding(.horizontal, 11).padding(.vertical, 9).frame(width: 195).background(
                    theme.surface, in: RoundedRectangle(cornerRadius: 9))
            }
            Button {
                model.showEditor()
            } label: {
                Label("New reminder", systemImage: "plus")
            }.buttonStyle(PrimaryButtonStyle()).disabled(model.storageFailure != nil).accessibilityIdentifier(
                "newReminder")
        }.padding(.horizontal, 28).frame(height: 77)
    }
    private func errorBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Saved data needs attention", systemImage: "exclamationmark.triangle").fontWeight(.semibold)
            Text(text)
            Button("Open data folder") { NSWorkspace.shared.open(model.repository.directory) }.buttonStyle(
                QuietButtonStyle())
        }.font(.system(size: 12)).padding(18).background(
            theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dianaTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 34)
                Text("diana").font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-0.6)
            }.padding(.top, 48).padding(.bottom, 8)
            Text("In good company.").font(.system(size: 12)).foregroundStyle(theme.muted).padding(.bottom, 35)
            VStack(spacing: 6) {
                ForEach(Array(AppPage.allCases.enumerated()), id: \.element.id) { index, page in
                    Button {
                        model.page = page
                        if page == .today { model.selectedDate = .now }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: page.symbol).font(.system(size: 16)).frame(width: 20)
                            Text(page.title).font(
                                .system(size: 13, weight: model.page == page ? .semibold : .medium))
                            Spacer()
                            if page == .today {
                                let count = model.todayOccurrences.filter {
                                    model.data.records[$0.id]?.isFinished != true
                                }.count
                                if count > 0 {
                                    Text("\(count)").font(.system(size: 11, weight: .semibold)).padding(
                                        .horizontal, 7
                                    ).padding(.vertical, 3).background(
                                        theme.background.opacity(0.7), in: Capsule())
                                }
                            }
                        }.foregroundStyle(model.page == page ? theme.accent : theme.muted).padding(
                            .horizontal, 12
                        ).padding(.vertical, 12).background(
                            model.page == page ? theme.paleAccent : .clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        ).contentShape(RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).keyboardShortcut(
                        KeyEquivalent(Character("\(index + 1)")), modifiers: .command
                    ).accessibilityIdentifier("nav-\(page.rawValue)")
                }
            }
            Spacer(minLength: 25)
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Circle().fill(model.preferences.companionVisible ? theme.success : theme.muted).frame(
                        width: 6, height: 6)
                    Text(model.preferences.companionVisible ? "Ready for reminders" : "Visits paused").font(
                        .system(size: 12, weight: .semibold))
                }
                Text(
                    model.preferences.companionVisible
                        ? "\(model.preferences.companionName) appears when a reminder is due."
                        : "Enable visits to bring Diana back for reminders."
                ).font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(
                    horizontal: false, vertical: true)
                Toggle(
                    "Reminder visits",
                    isOn: Binding(
                        get: { model.preferences.companionVisible },
                        set: { model.preferences.companionVisible = $0 })
                ).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11)).padding(.top, 6)
                    .accessibilityIdentifier("sidebarCompanionToggle")
            }.padding(14).background(theme.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 13))
            HStack(spacing: 6) {
                Image(systemName: "internaldrive").font(.system(size: 10))
                Text("Made for your Mac").font(.system(size: 10))
            }.foregroundStyle(theme.muted).padding(.top, 19).padding(.bottom, 18)
        }.padding(.horizontal, 20).background(theme.sidebar)
    }
}
