import DianaCore
import SwiftUI

struct LocalAssistantView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dianaTheme) private var theme
    @State private var draft = ""
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    SectionTitle(
                        title: "A little conversation",
                        subtitle: "Ask Diana for a plan, a pep talk, or a fresh perspective.")
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(theme.accent)
                }
                Toggle(
                    "Use local AI with Ollama",
                    isOn: Binding(
                        get: { model.preferences.ollamaEnabled == true },
                        set: { value in
                            model.preferences.ollamaEnabled = value
                            if value { Task { await model.connectAI() } } else { model.cancelAI() }
                        })
                ).toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
                Text(
                    "Chats stay in this session. Diana sends messages to Ollama on this Mac. Schedules are changed through the reminder editor."
                ).font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(
                    horizontal: false, vertical: true)
                if model.preferences.ollamaEnabled == true {
                    HStack {
                        Text(model.aiStatus).font(.system(size: 11)).foregroundStyle(theme.muted)
                        Spacer()
                        Button {
                            Task { await model.connectAI() }
                        } label: {
                            Label(
                                model.isConnectingAI ? "Connecting…" : "Reconnect",
                                systemImage: "arrow.clockwise")
                        }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(theme.accent).disabled(
                            model.isConnectingAI)
                    }
                    if !model.aiModels.isEmpty {
                        Picker(
                            "Model",
                            selection: Binding(
                                get: { model.preferences.ollamaModel ?? "" },
                                set: { model.preferences.ollamaModel = $0 })
                        ) {
                            ForEach(model.aiModels) { item in
                                Text("\(item.name) · \(item.sizeLabel)").tag(item.name)
                            }
                        }.font(.system(size: 12)).disabled(model.isAITyping)
                        Toggle(
                            "Personalize reminder messages",
                            isOn: Binding(
                                get: { model.preferences.aiReminderMessages == true },
                                set: { model.preferences.aiReminderMessages = $0 })
                        ).toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
                        Text(
                            "The original reminder always appears immediately. An optional short AI message is added if it arrives during the visit."
                        ).font(.system(size: 11)).foregroundStyle(theme.muted)
                    }
                    if !model.chatMessages.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 13) {
                                    ForEach(Array(model.chatMessages.enumerated()), id: \.offset) {
                                        index, item in
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(
                                                item.role == "user" ? "You" : model.preferences.companionName
                                            ).font(.system(size: 10, weight: .semibold)).foregroundStyle(
                                                theme.muted)
                                            Text(item.content).font(.system(size: 13)).foregroundStyle(
                                                theme.ink
                                            ).textSelection(.enabled).fixedSize(
                                                horizontal: false, vertical: true)
                                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                            .background(
                                                item.role == "user" ? theme.stage : theme.background,
                                                in: RoundedRectangle(cornerRadius: 10)
                                            ).id(index)
                                    }
                                }
                            }.frame(height: 230).onChange(of: model.chatMessages.count) { _, _ in
                                proxy.scrollTo(model.chatMessages.count - 1, anchor: .bottom)
                            }
                        }
                    }
                    if let error = model.aiError {
                        Text(error).font(.system(size: 12)).foregroundStyle(theme.muted).fixedSize(
                            horizontal: false, vertical: true)
                    }
                    if model.isAITyping {
                        HStack(spacing: 9) {
                            ProgressView().controlSize(.small)
                            Text("Diana is thinking locally…").font(.system(size: 11)).foregroundStyle(
                                theme.muted)
                            Spacer()
                            Button("Stop") { model.cancelAI() }.font(.system(size: 11)).buttonStyle(.plain)
                        }
                    }
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("Ask Diana…", text: $draft, axis: .vertical).lineLimit(1...4)
                            .textFieldStyle(.roundedBorder).font(.system(size: 13)).onSubmit(send)
                            .accessibilityIdentifier("askDianaInput")
                        Button(action: send) { Image(systemName: "arrow.up").frame(width: 17, height: 17) }
                            .buttonStyle(.borderedProminent).help("Send message").accessibilityLabel(
                                "Send message"
                            ).disabled(
                                model.isAITyping
                                    || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || model.preferences.ollamaModel == nil)
                    }
                    if !model.chatMessages.isEmpty {
                        HStack {
                            Button("Clear conversation") { model.clearChat() }
                            Spacer()
                            Button("Stop voice") { model.stopSpeaking() }
                        }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(theme.muted)
                    }
                }
            }
        }.task { if model.preferences.ollamaEnabled == true { await model.connectAI() } }
    }
    private func send() {
        guard !model.isAITyping, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        model.askDiana(draft)
        draft = ""
    }
}
