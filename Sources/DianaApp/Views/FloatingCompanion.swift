import DianaCore
import SwiftUI

struct FloatingCompanion: View {
    @Environment(AppModel.self) private var model
    var onDragEnd: () -> Void
    @State private var hovering = false
    var body: some View {
        VStack(spacing: 0) {
            if model.visitPhase.showsBubble {
                VStack(alignment: .leading, spacing: 8) {
                    if model.voiceAssistant.isActive {
                        HStack {
                            Image(
                                systemName: model.voiceAssistant.status == .speaking
                                    ? "speaker.wave.2" : "mic.fill")
                            Text(model.preferences.companionName).fontWeight(.semibold)
                            Spacer()
                            Button {
                                model.voiceAssistant.cancel()
                            } label: {
                                Image(systemName: "xmark")
                            }.buttonStyle(.plain).help("Cancel voice request")
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(model.voiceAssistant.prompt).font(.system(size: 13, weight: .medium)).lineLimit(
                            8)
                        if !model.voiceAssistant.transcript.isEmpty {
                            Text("Heard: " + model.voiceAssistant.transcript).font(.system(size: 10))
                                .foregroundStyle(.secondary).lineLimit(2)
                        }
                        Text(model.voiceAssistant.statusLabel).font(.system(size: 10)).foregroundStyle(
                            .secondary)
                    } else if let occurrence = model.activeReminder,
                        let reminder = model.reminder(for: occurrence)
                    {
                        HStack {
                            Image(systemName: reminder.kind.symbol)
                            Text(model.preferences.companionName).fontWeight(.semibold)
                            Spacer()
                            Button {
                                model.dismiss(occurrence)
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                            }.buttonStyle(.plain).help("Dismiss this reminder")
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(reminder.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                        if let aside = model.reminderAside {
                            Text(aside).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        }
                        HStack {
                            Button("Done") { model.complete(occurrence) }.buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            Button("10 min later") { model.snooze(occurrence) }.buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    } else if let greeting = model.petGreeting {
                        Text(greeting).font(.system(size: 13, weight: .medium)).fixedSize(
                            horizontal: false, vertical: true)
                    }
                }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).shadow(
                    color: .black.opacity(0.10), radius: 10, y: 4
                ).frame(height: model.voiceAssistant.isActive ? 240 : 160, alignment: .bottom).padding(
                    .horizontal, 4)
            } else {
                Color.clear.frame(height: model.voiceAssistant.isActive ? 240 : 160).allowsHitTesting(false)
            }
            DianaScene(
                motion: model.petMotion, replay: model.petReplay, reducedMotion: model.effectiveReducedMotion,
                lowPower: model.preferences.lowPower, speed: model.preferences.animationSpeed,
                yaw: model.petYaw, draggable: true, onDragEnd: onDragEnd, onError: { model.modelError = $0 }
            ).frame(height: model.preferences.companionHeight).opacity(model.preferences.companionOpacity)
                .accessibilityLabel(
                    "\(model.preferences.companionName), your desktop companion. Drag to move."
                ).contextMenu {
                    Button("Open Diana") { model.onRevealWindow?() }
                    Button("Say hello") { model.sayHello() }

                    Divider()
                    Button("Hide companion") { model.preferences.companionVisible = false }
                }
            HStack(spacing: 6) {
                Image(systemName: "hand.draw").font(.system(size: 10))
                Text("Drag to move").font(.system(size: 10, weight: .medium))
            }.padding(.horizontal, 10).padding(.vertical, 4).background(.regularMaterial, in: Capsule())
                .opacity(hovering ? 1 : 0).allowsHitTesting(false)
        }.padding(.bottom, 6).onHover { hovering = $0 }.tint(
            DianaTheme(selectedAccent: model.preferences.accent).button)
    }
}
