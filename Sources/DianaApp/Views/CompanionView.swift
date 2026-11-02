import AppKit
import DianaCore
import SwiftUI

struct CompanionStudio: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dianaTheme) private var theme
    var compact = false
    @State private var loaded = false
    @State private var yaw = -0.12
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your companion").font(.system(size: 11)).foregroundStyle(theme.muted)
                    Text(model.preferences.companionName.isEmpty ? "Diana" : model.preferences.companionName)
                        .font(.system(size: 22, weight: .semibold, design: .rounded)).tracking(-0.3)
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(theme.success).frame(width: 5, height: 5)
                    Text("Here for you").font(.system(size: 10, weight: .medium))
                }.foregroundStyle(theme.muted).padding(.top, 8)
            }
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 18).fill(theme.stage)
                GeometryReader { geometry in
                    Path { path in
                        let x = geometry.size.width / 2
                        path.move(to: CGPoint(x: x, y: 35))
                        path.addLine(to: CGPoint(x: x, y: geometry.size.height - 35))
                        path.move(to: CGPoint(x: 25, y: geometry.size.height - 45))
                        path.addLine(to: CGPoint(x: geometry.size.width - 25, y: geometry.size.height - 45))
                    }.stroke(theme.accent.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                }.accessibilityHidden(true)
                Ellipse().stroke(theme.accent.opacity(0.13), lineWidth: 1).frame(width: 150, height: 24)
                    .padding(.bottom, 33).accessibilityHidden(true)
                DianaScene(
                    motion: model.previewMotion, replay: model.previewReplay,
                    reducedMotion: model.effectiveReducedMotion, lowPower: model.preferences.lowPower,
                    speed: model.preferences.animationSpeed, yaw: yaw, onReady: { loaded = true },
                    onError: { model.modelError = $0 }
                ).accessibilityLabel("Live 3D preview of Diana")
                if !loaded && model.modelError == nil {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("Getting Diana ready…").font(.system(size: 11)).foregroundStyle(theme.muted)
                    }.frame(maxHeight: .infinity)
                }
                if let error = model.modelError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").font(.title2)
                        Text("Diana couldn’t load").font(.system(size: 13, weight: .semibold))
                        Text(error).font(.system(size: 11)).multilineTextAlignment(.center)
                    }.padding(24).frame(maxHeight: .infinity).foregroundStyle(theme.muted)
                }
                HStack {
                    Button {
                        yaw -= 0.25
                    } label: {
                        Image(systemName: "arrow.counterclockwise").frame(width: 28, height: 28)
                    }.help("Rotate left")
                    Spacer()
                    Text("\(model.effectiveReducedMotion ? "Still" : "Live") preview").font(
                        .system(size: 10, weight: .medium))
                    Spacer()
                    Button {
                        yaw += 0.25
                    } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
                    }.help("Rotate right")
                }.font(.system(size: 11)).foregroundStyle(theme.muted).buttonStyle(.plain).padding(12)
            }.frame(height: compact ? 346 : 410).clipShape(RoundedRectangle(cornerRadius: 18))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(PetMotion.allCases) { motion in
                    Button {
                        model.previewMotion = motion
                        model.previewReplay += 1
                    } label: {
                        Label(motion.title, systemImage: motion.symbol).font(
                            .system(size: 11, weight: .medium)
                        ).frame(maxWidth: .infinity).padding(.vertical, 9).foregroundStyle(
                            model.previewMotion == motion ? theme.accent : theme.muted
                        ).background(
                            model.previewMotion == motion ? theme.background : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).disabled(model.effectiveReducedMotion && motion != .idle)
                }
            }.padding(4).background(theme.surface, in: RoundedRectangle(cornerRadius: 11))
            Text("A little company for whatever’s next.").font(.system(size: 12)).foregroundStyle(theme.muted)
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Button {
                    model.sayHello()
                } label: {
                    Label("Say hello", systemImage: "hand.wave")
                }.buttonStyle(QuietButtonStyle())

                    .disabled(!model.preferences.companionVisible || model.effectiveReducedMotion)
            }.frame(maxWidth: .infinity)
            if compact {
                Button {
                    model.page = .companion
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text("Make Diana yours")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }.font(.system(size: 11, weight: .medium)).foregroundStyle(theme.accent)
                }.buttonStyle(.plain).padding(.top, 6)
            }
        }.task(id: model.previewMotion) {
            guard model.previewMotion == .wave else { return }
            try? await Task.sleep(for: .seconds(3.2 / model.preferences.animationSpeed))
            if !Task.isCancelled { model.previewMotion = .idle }
        }
    }
}

struct CompanionSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dianaTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Meet your companion.").font(.system(size: 28, weight: .semibold)).tracking(-0.7)
                Text("A familiar face. A little encouragement. All yours.").font(.system(size: 13))
                    .foregroundStyle(theme.muted)
            }
            HStack(alignment: .top, spacing: 28) {
                CompanionStudio().frame(width: 300)
                VStack(alignment: .leading, spacing: 24) {
                    LocalAssistantView()
                    SectionTitle(
                        title: "Make yourself at home",
                        subtitle: "Your desktop companion updates as you make changes.")
                    Surface {
                        VStack(alignment: .leading, spacing: 20) {
                            settingToggle(
                                "Reminder visits", "Diana appears for reminders, then leaves with a kiss.",
                                key: \.companionVisible)
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Companion name").font(.system(size: 12, weight: .medium))
                                TextField(
                                    "Diana",
                                    text: Binding(
                                        get: { model.preferences.companionName },
                                        set: { model.preferences.companionName = String($0.prefix(24)) })
                                ).textFieldStyle(.roundedBorder).font(.system(size: 13))
                            }
                            slider("Desktop size", value: \.companionHeight, range: 180...380, suffix: "pt")
                            slider(
                                "Opacity", value: \.companionOpacity, range: 0.4...1, suffix: "%",
                                multiplier: 100)
                            VStack(alignment: .leading, spacing: 9) {
                                Text("First entrance").font(.system(size: 12, weight: .medium))
                                HStack {
                                    cornerButton("Bottom left", corner: "left", symbol: "arrow.down.left")
                                    cornerButton("Bottom right", corner: "right", symbol: "arrow.down.right")
                                }
                                Button("Reset position") { model.onReposition?() }.font(.system(size: 11))
                                    .buttonStyle(.plain).foregroundStyle(theme.accent)
                            }
                        }
                    }
                    Surface {
                        VStack(alignment: .leading, spacing: 19) {
                            SectionTitle(title: "A rhythm that suits you")
                            slider(
                                "Animation speed", value: \.animationSpeed, range: 0.5...1.5, suffix: "×",
                                decimals: true)
                            Text(
                                "Visits alternate sides: run in, share the reminder, blow a kiss, and run out. Diana rests offscreen between visits."
                            ).font(.system(size: 12)).foregroundStyle(theme.muted)
                            settingToggle(
                                "Gentle on your battery", "8 fps at rest; 15 during actions instead of 30.",
                                key: \.lowPower)
                            settingToggle(
                                "Reduce motion", "Keep Diana still and prevent desktop travel.",
                                key: \.reducedMotion)
                            settingToggle(
                                "Across your desktops", "Show Diana on every Space.", key: \.allSpaces)
                            settingToggle(
                                "Let clicks pass through", "Use the menu bar to move or hide Diana.",
                                key: \.clickThrough)
                        }
                    }
                }.frame(minWidth: 350, maxWidth: .infinity)
            }
        }
    }
    private func settingToggle(_ title: String, _ subtitle: String, key: WritableKeyPath<Preferences, Bool>)
        -> some View
    {
        Toggle(
            isOn: Binding(
                get: { model.preferences[keyPath: key] }, set: { model.preferences[keyPath: key] = $0 })
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(
                    horizontal: false, vertical: true)
            }
        }.toggleStyle(.switch).controlSize(.small).accessibilityLabel(title).accessibilityHint(subtitle)
    }
    private func slider(
        _ title: String, value: WritableKeyPath<Preferences, Double>, range: ClosedRange<Double>,
        suffix: String, multiplier: Double = 1, decimals: Bool = false
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                let number = model.preferences[keyPath: value] * multiplier
                Text(decimals ? String(format: "%.1f%@", number, suffix) : "\(Int(number))\(suffix)").font(
                    .system(size: 11)
                ).monospacedDigit().foregroundStyle(theme.muted)
            }
            Slider(
                value: Binding(
                    get: { model.preferences[keyPath: value] },
                    set: { model.preferences[keyPath: value] = $0 }), in: range
            ).accessibilityLabel(title)
        }
    }
    private func cornerButton(_ title: String, corner: String, symbol: String) -> some View {
        Button {
            model.preferences.corner = corner
            model.onReposition?()
        } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity)
        }.buttonStyle(QuietButtonStyle()).overlay(
            RoundedRectangle(cornerRadius: 9).stroke(
                model.preferences.corner == corner ? theme.accent : .clear, lineWidth: 1))
    }
}
