import AVFoundation
import AppKit
import DianaCore
import ServiceManagement
import SwiftUI

struct AppSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dianaTheme) private var theme
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Make it yours.").font(.system(size: 28, weight: .semibold)).tracking(-0.7)
                Text("A few thoughtful details. A companion that fits your day.").font(.system(size: 13))
                    .foregroundStyle(theme.muted)
            }
            Surface {
                VStack(alignment: .leading, spacing: 23) {
                    SectionTitle(
                        title: "Look & feel", subtitle: "Choose the atmosphere that feels right for you.")
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Button {
                                model.preferences.appearance = appearance
                            } label: {
                                VStack(alignment: .leading, spacing: 11) {
                                    appearancePreview(appearance)
                                    HStack {
                                        Text(appearance.title).font(.system(size: 12, weight: .medium))
                                        Spacer()
                                        if model.preferences.appearance == appearance {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(
                                                theme.accent)
                                        }
                                    }
                                }.padding(12).background(
                                    theme.background, in: RoundedRectangle(cornerRadius: 12)
                                ).overlay(
                                    RoundedRectangle(cornerRadius: 12).stroke(
                                        model.preferences.appearance == appearance
                                            ? theme.accent : theme.line, lineWidth: 1))
                            }.buttonStyle(.plain).accessibilityLabel("\(appearance.title) appearance").frame(
                                maxWidth: .infinity)
                        }
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Your color").font(.system(size: 12, weight: .medium))
                            Text("A little personality, throughout the app.").font(.system(size: 11))
                                .foregroundStyle(theme.muted)
                        }
                        Spacer()
                        ForEach(Accent.allCases) { accent in
                            let sample = DianaTheme(selectedAccent: accent)
                            Button {
                                model.preferences.accent = accent
                            } label: {
                                Circle().fill(sample.button).frame(width: 27, height: 27).overlay {
                                    if model.preferences.accent == accent {
                                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }.padding(4).overlay(
                                    Circle().stroke(
                                        model.preferences.accent == accent ? sample.button : .clear,
                                        lineWidth: 1))
                            }.buttonStyle(.plain).help(accent.title).accessibilityLabel(
                                "\(accent.title) accent")
                        }
                    }
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 21) {
                    SectionTitle(
                        title: "The gentlest nudge", subtitle: "You choose how Diana gets your attention.")
                    Toggle(
                        isOn: Binding(
                            get: { model.preferences.notificationsEnabled },
                            set: { value in
                                if value {
                                    Task { await model.enableNotifications() }
                                } else {
                                    model.preferences.notificationsEnabled = false
                                }
                            })
                    ) { settingsLabel("macOS notifications", "Banners alongside your desktop companion.") }
                    .toggleStyle(.switch).controlSize(.small)
                    HStack {
                        Label(
                            notificationLabel,
                            systemImage: model.notificationState == .authorized
                                ? "checkmark.circle" : "bell.badge"
                        ).font(.system(size: 11)).foregroundStyle(theme.muted)
                        Spacer()
                        Button(model.notificationState == .notDetermined ? "Enable" : "Manage") {
                            if model.notificationState == .notDetermined {
                                Task { await model.enableNotifications() }
                            } else {
                                openNotificationSettings()
                            }
                        }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(
                            theme.accent)
                    }
                    if let problem = model.notificationProblem {
                        Text(problem).font(.system(size: 11)).foregroundStyle(theme.muted)
                    }
                    Divider()
                    preferenceToggle("A soft sound", "A small chime when a reminder arrives.", key: \.sounds)
                    preferenceToggle(
                        "Say it out loud", "Speak reminders and AI replies using a voice on your Mac.",
                        key: \.voice)
                    if model.preferences.voice {
                        Picker(
                            "Voice",
                            selection: Binding(
                                get: { model.preferences.voiceIdentifier ?? "" },
                                set: { model.preferences.voiceIdentifier = $0.isEmpty ? nil : $0 })
                        ) {
                            Text("Automatic · best installed voice").tag("")
                            ForEach(DianaSpeech.availableVoices, id: \.identifier) { voice in
                                Text(DianaSpeech.label(voice)).tag(voice.identifier)
                            }
                        }.font(.system(size: 12))
                        if let voice = DianaSpeech.voice(
                            preferredID: model.preferences.voiceIdentifier,
                            text: "Hello, it’s time for a short break.")
                        {
                            Text("Using " + DianaSpeech.label(voice)).font(.system(size: 11)).foregroundStyle(
                                theme.muted)
                        }
                        HStack(spacing: 12) {
                            Text("Speaking speed").font(.system(size: 12))
                            Slider(
                                value: Binding(
                                    get: { model.preferences.speechRate ?? 1 },
                                    set: { model.preferences.speechRate = $0 }), in: 0.8...1.2, step: 0.05
                            ).accessibilityLabel("Speaking speed")
                            Text(String(format: "%.2f×", model.preferences.speechRate ?? 1)).font(
                                .system(size: 11)
                            ).monospacedDigit().frame(width: 42)
                        }
                        HStack(spacing: 12) {

                            Button("Stop voice") { model.stopSpeaking() }.disabled(!model.isSpeaking)
                            if model.isSpeaking {
                                Label("Speaking", systemImage: "speaker.wave.2").font(.system(size: 11))
                                    .foregroundStyle(theme.muted)
                            }
                        }.buttonStyle(QuietButtonStyle())
                    }
                    Divider()
                    VoiceControlSettings()
                    Divider()
                    preferenceToggle(
                        "Quiet hours", "Keep both banners and Diana’s nudges quiet.", key: \.quietHoursEnabled
                    )
                    if model.preferences.quietHoursEnabled {
                        HStack(spacing: 20) {
                            Picker("From", selection: preference(\.quietStartHour)) {
                                ForEach(0..<24) { Text(hour($0)).tag($0) }
                            }
                            Picker("Until", selection: preference(\.quietEndHour)) {
                                ForEach(0..<24) { Text(hour($0)).tag($0) }
                            }
                        }.font(.system(size: 12))
                        if model.preferences.quietStartHour == model.preferences.quietEndHour {
                            Text("Choose different start and end times to create a quiet period.").font(
                                .system(size: 11)
                            ).foregroundStyle(theme.muted)
                        }
                    }

                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 20) {
                    SectionTitle(title: "At home on your Mac")
                    Toggle(isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)) {
                        settingsLabel("Start with your Mac", "Have Diana ready when you sign in.")
                    }.toggleStyle(.switch).controlSize(.small)
                    Divider()
                    HStack(alignment: .top) {
                        settingsLabel(
                            "Your reminders, kept close",
                            "Stored on this Mac. No account or cloud connection needed.")
                        Spacer()
                        Image(systemName: "internaldrive").foregroundStyle(theme.muted)
                    }
                    HStack(spacing: 9) {
                        Button {
                            model.exportBackup()
                        } label: {
                            Label("Export backup", systemImage: "square.and.arrow.up")
                        }.buttonStyle(QuietButtonStyle())
                        Button {
                            model.importBackup()
                        } label: {
                            Label("Import reminders", systemImage: "square.and.arrow.down")
                        }.buttonStyle(QuietButtonStyle()).disabled(model.storageFailure != nil)
                        Spacer()
                    }
                    Text(
                        "Imports add new reminders without replacing your current tasks. Keep Diana running in the menu bar for continuous scheduling."
                    ).font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(
                        horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                BrandMark(size: 23)
                Text("Diana 1.0").font(.system(size: 11, weight: .medium))
                Text("A little company. A clearer day.").font(.system(size: 11)).foregroundStyle(theme.muted)
            }.padding(.vertical, 4)
        }.frame(maxWidth: 820, alignment: .leading)
    }
    private var notificationLabel: String {
        switch model.notificationState {
        case .authorized, .provisional: "Notifications are allowed by macOS"
        case .denied: "Notifications are off in System Settings"
        default: "Notification permission hasn’t been requested"
        }
    }
    private func settingsLabel(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .medium))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(
                horizontal: false, vertical: true)
        }
    }
    private func preferenceToggle(
        _ title: String, _ subtitle: String, key: WritableKeyPath<Preferences, Bool>
    ) -> some View {
        Toggle(isOn: preference(key)) { settingsLabel(title, subtitle) }.toggleStyle(.switch).controlSize(
            .small
        ).accessibilityLabel(title).accessibilityHint(subtitle)
    }
    private func preference<Value>(_ key: WritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(get: { model.preferences[keyPath: key] }, set: { model.preferences[keyPath: key] = $0 })
    }
    private func hour(_ value: Int) -> String {
        (Calendar.current.date(bySettingHour: value, minute: 0, second: 0, of: .now) ?? .now).formatted(
            date: .omitted, time: .shortened)
    }
    private func setLaunchAtLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            model.errorMessage = "Couldn’t change login behavior. \(error.localizedDescription)"
        }
    }
    private func appearancePreview(_ appearance: AppAppearance) -> some View {
        let dark = appearance == .dark
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(theme.button.opacity(0.7)).frame(width: 18, height: 5)
                RoundedRectangle(cornerRadius: 2).fill(theme.button.opacity(0.15)).frame(width: 22, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(theme.button.opacity(0.15)).frame(width: 16, height: 4)
                Spacer(minLength: 0)
            }.padding(9).frame(width: 42).background(Color(oklch: dark ? 0.25 : 0.95))
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 2).fill(Color(oklch: dark ? 0.70 : 0.55)).frame(
                    width: 42, height: 5)
                RoundedRectangle(cornerRadius: 3).fill(theme.button.opacity(0.14)).frame(height: 14)
                RoundedRectangle(cornerRadius: 2).fill(Color(oklch: dark ? 0.40 : 0.88)).frame(height: 4)
                Spacer(minLength: 0)
            }.padding(11).frame(maxWidth: .infinity).background(Color(oklch: dark ? 0.19 : 1))
        }.frame(height: 76).clipShape(RoundedRectangle(cornerRadius: 7)).overlay(alignment: .bottomTrailing) {
            if appearance == .system {
                Image(systemName: "circle.lefthalf.filled").font(.system(size: 16)).foregroundStyle(
                    theme.muted
                ).padding(7)
            }
        }
    }
}
