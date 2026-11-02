import SwiftUI

struct VoiceControlSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dianaTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                "Listen for Hey Diana",
                isOn: Binding(
                    get: { model.voiceAssistant.isEnabled }, set: { model.setVoiceAssistantEnabled($0) })
            ).toggleStyle(.switch).controlSize(.small).font(.system(size: 12)).disabled(
                model.voiceAssistant.status == .enabling
                    || (model.voiceAssistant.isActive && !model.voiceAssistant.isEnabled))
            Text(
                "Say ‘Hey Diana’, then ‘Schedule a meeting with my client tomorrow at 5 PM’. Diana reads back the date and time and saves only after you say yes. Say bye to dismiss her or cancel to discard an unconfirmed reminder."
            ).font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(
                horizontal: false, vertical: true)
            HStack {
                Button("Talk to Diana", systemImage: "mic") { model.startVoiceConversation() }.buttonStyle(
                    QuietButtonStyle()
                ).disabled(model.voiceAssistant.isActive || model.voiceAssistant.status == .enabling)
                if model.voiceAssistant.isActive || model.voiceAssistant.status == .enabling {
                    Button("End conversation") { model.stopSpeaking() }.buttonStyle(QuietButtonStyle())
                }
            }
            Label(
                model.voiceAssistant.statusLabel,
                systemImage: model.voiceAssistant.status == .waiting
                    || model.voiceAssistant.status == .listening || model.voiceAssistant.status == .confirming
                    ? "mic.fill" : "mic.slash"
            ).font(.system(size: 11, weight: .medium)).foregroundStyle(theme.muted)
            if let problem = model.voiceAssistant.problem {
                Text(problem).font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(
                    horizontal: false, vertical: true)
            }
            Text(
                "Wake-word listening keeps the microphone active, so macOS shows its orange microphone indicator. Turn off Listen for Hey Diana to release it; you can still start a conversation with Talk to Diana. Recognition pauses while Diana speaks. After goodbye or a 25-second listening timeout, wake-word listening resumes if enabled."
            ).font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(
                horizontal: false, vertical: true)
            Text(
                "Requires microphone and Apple Speech Recognition access. English recognition runs on-device when available; otherwise Apple may process audio online. Audio is not sent to Ollama."
            ).font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(
                horizontal: false, vertical: true)
        }
    }
}
